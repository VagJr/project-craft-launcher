param([string]$PlanPath, [string]$ProbeExe, [string]$LaunchPlan)
$ErrorActionPreference = 'Stop'

function Assert-PCInside([string]$Root, [string]$Target) {
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Target)
    if (!$full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Caminho fora da pasta autorizada de atualização.' }
    return $full
}
function Assert-PCNoLinks([string]$Root, [string]$Target) {
    $full = Assert-PCInside $Root $Target
    $current = $full
    while ($current.Length -ge $Root.TrimEnd('\').Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links não são permitidos na atualização.' }
        }
        if ($current -eq $Root.TrimEnd('\')) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $full
}
function Write-PCJson([string]$File, $Value) {
    $temp = $File + '.tmp'
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $File -Force
}
function Get-PCFormat([string]$Executable) {
    $exe = [IO.Path]::GetFullPath($Executable)
    foreach ($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
            if ($entry.DisplayName -ne 'Project Craft') { continue }
            if ($entry.InstallLocation) {
                $installed = Join-Path $entry.InstallLocation 'Project Craft.exe'
                if ([IO.Path]::GetFullPath($installed).Equals($exe, [StringComparison]::OrdinalIgnoreCase)) { return 'msi' }
            }
            if ($entry.DisplayIcon -and $entry.DisplayIcon.Split(',')[0].Trim('"').Equals($exe, [StringComparison]::OrdinalIgnoreCase)) { return 'msi' }
        }
    }
    # Older MSI versions did not always publish InstallLocation. Resolve the registered main component instead.
    $installer=$null
    try {
        $installer=New-Object -ComObject WindowsInstaller.Installer
        foreach ($product in @($installer.RelatedProducts('{3CA07A52-26E6-5D36-905A-1C4CD09CFD5B}'))) {
            $cached=$installer.ProductInfo($product,'LocalPackage')
            if (!$cached -or !(Test-Path -LiteralPath $cached)) { continue }
            $database=$installer.OpenDatabase($cached,0)
            $view=$database.OpenView('SELECT `Component`.`ComponentId` FROM `Component`, `File` WHERE `File`.`Component_`=`Component`.`Component` AND `File`.`File`=''mainExecutable''')
            $null=$view.Execute();$record=$view.Fetch()
            if ($record) { $component=([string]$record.StringData(1)).Trim();$installed=$installer.ComponentPath($product,$component);if ($installed -and $installed.Equals($exe,[StringComparison]::OrdinalIgnoreCase)) { return 'msi' } }
            $null=[Runtime.InteropServices.Marshal]::ReleaseComObject($database)
        }
    } catch { # A non-MSI portable installation has no registered component.
    } finally { if ($installer) { $null=[Runtime.InteropServices.Marshal]::ReleaseComObject($installer) } }
    return 'zip'
}
function Get-PCVersion([string]$Executable) {
    $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($Executable).ProductVersion
    if ($version -notmatch '^(\d+)\.(\d+)\.(\d+)') { throw 'Executável sem versão Project Craft válida.' }
    return "$($Matches[1]).$($Matches[2]).$($Matches[3])"
}
function Test-PCParent($Plan) {
    $process = Get-Process -Id $Plan.parentId -ErrorAction SilentlyContinue
    if (!$process) { return $false }
    # A recycled PID must not block or terminate an unrelated process.
    if ([Math]::Abs(($process.StartTime.ToUniversalTime() - [DateTime]::Parse($Plan.parentStarted).ToUniversalTime()).TotalSeconds) -gt 5) { return $false }
    return $process.Path -and $process.Path.Equals($Plan.executable, [StringComparison]::OrdinalIgnoreCase)
}
function Wait-PCParent($Plan) {
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    while (Test-PCParent $Plan) {
        if ((Test-Path -LiteralPath (Join-Path $Plan.job 'cancel')) -or [DateTime]::UtcNow -gt $deadline) { throw 'O launcher não encerrou; a atualização foi cancelada.' }
        Start-Sleep -Milliseconds 250
    }
    # Let Chromium's child processes release DLLs and resources.
    Start-Sleep -Seconds 2
}
function Get-PCRelative([string]$Name) {
    $name = $Name.Replace('\', '/')
    if (!$name -or $name.StartsWith('/') -or $name.Contains(':') -or $name.Contains([char]0) -or ($name.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' })) { throw 'Caminho inválido no pacote portátil.' }
    return $name
}
function Expand-PCZip($Plan) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stage = Join-Path $Plan.job 'stage'; $null = New-Item -ItemType Directory -Path $stage -Force
    $zip = [IO.Compression.ZipFile]::OpenRead($Plan.file)
    try {
        $files = New-Object 'System.Collections.Generic.List[string]'; $seen = @{}; [long]$bytes = 0
        foreach ($entry in $zip.Entries) {
            $relative = Get-PCRelative $entry.FullName
            if ((($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw 'Link simbólico no pacote portátil.' }
            if ($entry.FullName.EndsWith('/')) { continue }
            if ($seen.ContainsKey($relative.ToLowerInvariant())) { throw 'Arquivo duplicado no pacote portátil.' }
            $seen[$relative.ToLowerInvariant()] = $true; $bytes += $entry.Length
            if ($files.Count -ge 2048 -or $bytes -gt 1073741824) { throw 'Limites do pacote portátil excedidos.' }
            $target = Assert-PCNoLinks $stage (Join-Path $stage $relative)
            $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
            $files.Add($relative)
        }
        if (!$seen.ContainsKey('project craft.exe') -or !$seen.ContainsKey('resources/app.asar')) { throw 'Pacote portátil incompleto.' }
        if ((Get-PCVersion (Join-Path $stage 'Project Craft.exe')) -ne $Plan.version) { throw 'Versão do executável portátil não corresponde ao canal.' }
        return ,$files.ToArray()
    } finally { $zip.Dispose() }
}
function Move-PCFile([string]$Source, [string]$Destination) {
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Destination)) -Force
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try { Move-Item -LiteralPath $Source -Destination $Destination -Force; return } catch { if ($attempt -eq 19) { throw }; Start-Sleep -Milliseconds 500 }
    }
}
function Install-PCZip($Plan, [string[]]$Files) {
    $root = [IO.Path]::GetDirectoryName($Plan.executable); $stage = Join-Path $Plan.job 'stage'; $backup = Join-Path $Plan.job 'rollback'
    $null = New-Item -ItemType Directory -Path $backup -Force
    $marker = '.project-craft-launcher-files.json'; $all = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $Files) { $all.Add($file) }
    $manifest = Join-Path $root $marker
    if (Test-Path -LiteralPath $manifest) {
        foreach ($file in @((Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).files)) { $file = Get-PCRelative $file; if (!$all.Contains($file)) { $all.Add($file) } }
    }
    Write-PCJson (Join-Path $stage $marker) @{version=$Plan.version;files=$Files}; $all.Add($marker)
    $changed = New-Object 'System.Collections.Generic.List[object]'
    try {
        foreach ($relative in $all) {
            $target = Assert-PCNoLinks $root (Join-Path $root $relative); $saved = Assert-PCNoLinks $backup (Join-Path $backup $relative)
            $source = Assert-PCNoLinks $stage (Join-Path $stage $relative)
            $row = @{relative=$relative;old=$false;installed=$false}; $changed.Add($row)
            if (Test-Path -LiteralPath $target) { if ((Get-Item -LiteralPath $target).PSIsContainer) { throw 'Uma pasta ocupa o destino de um arquivo.' }; Move-PCFile $target $saved; $row.old=$true }
            if (Test-Path -LiteralPath $source) { Move-PCFile $source $target; $row.installed=$true }
            Write-PCJson (Join-Path $Plan.job 'journal.json') @{files=$changed.ToArray()}
        }
        if ((Get-PCVersion $Plan.executable) -ne $Plan.version) { throw 'A versão instalada não corresponde ao pacote.' }
    } catch {
        $failure = $_
        for ($i=$changed.Count-1; $i -ge 0; $i--) {
            $row=$changed[$i]; $target=Assert-PCInside $root (Join-Path $root $row.relative); $saved=Assert-PCInside $backup (Join-Path $backup $row.relative)
            if ($row.installed -and (Test-Path -LiteralPath $target)) { Remove-Item -LiteralPath $target -Force }
            if ($row.old -and (Test-Path -LiteralPath $saved)) { Move-PCFile $saved $target }
        }
        throw $failure
    }
}
function Get-PCMSIProperty($Database, [string]$Name) {
    $view=$Database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$Name'"); $null=$view.Execute(); $record=$view.Fetch()
    if (!$record) { throw 'Metadados ausentes no MSI.' }; return ([string]$record.StringData(1)).Trim()
}
function Assert-PCMSI($Plan) {
    $installer=New-Object -ComObject WindowsInstaller.Installer; $database=$installer.OpenDatabase($Plan.file,0)
    $version=[version](Get-PCMSIProperty $database 'ProductVersion'); $canonical="$($version.Major).$($version.Minor).$($version.Build)"
    if ((Get-PCMSIProperty $database 'ProductName') -ne 'Project Craft' -or $canonical -ne $Plan.version -or (Get-PCMSIProperty $database 'UpgradeCode') -ne '{3CA07A52-26E6-5D36-905A-1C4CD09CFD5B}') { throw 'Produto ou versão do MSI não corresponde ao canal.' }
    $null=[Runtime.InteropServices.Marshal]::ReleaseComObject($database); $null=[Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
}
function Install-PCMSI($Plan) {
    $log=Join-Path $Plan.job 'installer.log'; $root=[IO.Path]::GetDirectoryName($Plan.executable)
    foreach ($value in @($Plan.file,$root,$log)) { if ($value.Contains('"') -or $value.Contains("`n") -or $value.Contains("`r")) { throw 'Argumento inválido para o instalador.' } }
    $arguments=@('/i',('"'+$Plan.file+'"'),'/quiet','/norestart','REBOOT=ReallySuppress',('APPLICATIONFOLDER="'+$root+'"'),'/l*v',('"'+$log+'"'))
    $process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw "O Windows Installer retornou $($process.ExitCode)." }
    if ((Get-PCVersion $Plan.executable) -ne $Plan.version) { throw 'O executável atualizado não foi encontrado na instalação.' }
}
function Start-PCLauncher([string]$Executable) { if (Test-Path -LiteralPath $Executable) { $null=Start-Process -FilePath $Executable -WorkingDirectory ([IO.Path]::GetDirectoryName($Executable)) } }
function Invoke-PCUpdate([string]$File) {
    $plan=$null; $package=$null; $parentExited=$false; $jobVerified=$false
    try {
        $plan=Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($plan.schema -ne 1 -or $plan.version -notmatch '^\d+\.\d+\.\d+$' -or $plan.format -notin @('msi','zip') -or $plan.sha256 -notmatch '^[a-f0-9]{64}$' -or $plan.size -le 0 -or $plan.size -gt 536870912 -or $plan.parentId -le 0) { throw 'Plano de atualização inválido.' }
        $job=[IO.Path]::GetFullPath($plan.job); $updates=[IO.Path]::GetDirectoryName($job)
        if ([IO.Path]::GetFileName($updates) -ne 'updates' -or [IO.Path]::GetFileName($job) -notmatch '^[a-f0-9-]{36}$' -or [IO.Path]::GetFullPath($File) -ne (Join-Path $job 'plan.json')) { throw 'Pasta do atualizador inválida.' }
        $null=Assert-PCNoLinks $updates $File; $jobVerified=$true
        $expected=Join-Path $updates ($plan.sha256+'.'+$plan.format)
        if ([IO.Path]::GetFullPath($plan.file) -ne $expected -or [IO.Path]::GetFileName($plan.executable) -ne 'Project Craft.exe') { throw 'Arquivo de atualização inválido.' }
        $null=Assert-PCNoLinks $updates $plan.file
        $null=Assert-PCNoLinks ([IO.Path]::GetDirectoryName($plan.executable)) $plan.executable
        $package=[IO.File]::Open($plan.file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $sha=[Security.Cryptography.SHA256]::Create(); try { $actual=([BitConverter]::ToString($sha.ComputeHash($package))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
        if ($actual -ne $plan.sha256 -or $package.Length -ne $plan.size) { throw 'O pacote não passou na conferência de integridade.' }
        $files=@(); if ($plan.format -eq 'zip') { $files=Expand-PCZip $plan } else { Assert-PCMSI $plan }
        if (Test-Path -LiteralPath (Join-Path $job 'cancel')) { throw 'Atualização cancelada antes da aplicação.' }
        Write-PCJson (Join-Path $job 'ready.json') @{ready=$true}
        Wait-PCParent $plan; $parentExited=$true
        if (Test-Path -LiteralPath (Join-Path $job 'cancel')) { throw 'Atualização cancelada.' }
        if ($plan.format -eq 'zip') { Install-PCZip $plan $files } else { Install-PCMSI $plan }
        $result=@{success=$true;version=$plan.version;format=$plan.format;finishedAt=[DateTime]::UtcNow.ToString('o')}
    } catch { $result=@{success=$false;message=$_.Exception.Message;finishedAt=[DateTime]::UtcNow.ToString('o')} }
    finally { if ($package) { $package.Dispose() } }
    if ($jobVerified -and (Test-Path -LiteralPath $job)) { Write-PCJson (Join-Path $job 'result.json') $result; Write-PCJson (Join-Path $updates 'result.json') $result }
    if ($parentExited) { Start-PCLauncher $plan.executable }
    if (!$result.success) { return 1 }; return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($ProbeExe) { Get-PCFormat $ProbeExe; exit 0 }
    if ($LaunchPlan) {
        foreach ($value in @($PSCommandPath,$LaunchPlan)) { if ($value.Contains('"') -or $value.Contains("`n") -or $value.Contains("`r")) { throw 'Caminho inválido para iniciar o atualizador.' } }
        $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',('"'+$PSCommandPath+'"'),'-PlanPath',('"'+$LaunchPlan+'"'))
        $worker=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $job=[IO.Path]::GetDirectoryName($LaunchPlan);$deadline=[DateTime]::UtcNow.AddSeconds(180)
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath (Join-Path $job 'ready.json')) { exit 0 }
            if (Test-Path -LiteralPath (Join-Path $job 'result.json')) { throw 'O pacote não pôde ser preparado. Consulte o resultado do atualizador.' }
            $worker.Refresh();if ($worker.HasExited) { throw 'O processo de atualização encerrou antes de confirmar a preparação.' }
            Start-Sleep -Milliseconds 250
        }
        [IO.File]::WriteAllText((Join-Path $job 'cancel'),'cancelled');throw 'O atualizador excedeu o tempo de preparação.'
    }

    if (!$PlanPath) { throw 'Plano de atualização ausente.' }
    exit (Invoke-PCUpdate $PlanPath)
}
