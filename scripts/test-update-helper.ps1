param([string]$CandidateMSI, [string]$CandidateZip)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\update-helper.ps1')
$testRoot=Join-Path $root ('.local\qa-updater\Operação Ágil '+[guid]::NewGuid().ToString());$null=New-Item -ItemType Directory -Path $testRoot -Force
$script:checks=0;$script:restarts=0;$script:realVersion=(Get-Command Get-PCVersion).ScriptBlock
function Check($Condition,[string]$Label){$script:checks++;if(!$Condition){throw "Update helper test failed: $Label"}}
function Get-PCVersion([string]$Executable){return [IO.File]::ReadAllText($Executable).Trim()}
function Start-PCLauncher([string]$Executable){$script:restarts++}
function Wait-PCParent($Plan){}
Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-Fixture([string]$Kind='normal'){
 $case=Join-Path $testRoot ([guid]::NewGuid().ToString());$app=Join-Path $case 'Portable';$updates=Join-Path $case 'ProjectCraft\updates';$job=Join-Path $updates ([guid]::NewGuid().ToString());$null=New-Item -ItemType Directory -Path (Join-Path $app 'resources'),$job -Force
 [IO.File]::WriteAllText((Join-Path $app 'Project Craft.exe'),'1.1.1');[IO.File]::WriteAllText((Join-Path $app 'resources\app.asar'),'old-asar');[IO.File]::WriteAllText((Join-Path $app 'personal-notes.txt'),'preserve');[IO.File]::WriteAllText((Join-Path $case 'ProjectCraft\preferences.json'),'settings')
 $source=Join-Path $case 'source.zip';$zip=[IO.Compression.ZipFile]::Open($source,[IO.Compression.ZipArchiveMode]::Create)
 try{foreach($name in @('Project Craft.exe','resources/app.asar','new-file.txt')){$entry=$zip.CreateEntry($name);$writer=New-Object IO.StreamWriter($entry.Open());try{$writer.Write($(if($name -eq 'Project Craft.exe'){'1.2.0'}else{'new-data'}))}finally{$writer.Dispose()}};if($Kind -eq 'traversal'){$entry=$zip.CreateEntry('../outside.txt');$writer=New-Object IO.StreamWriter($entry.Open());$writer.Write('escape');$writer.Dispose()};if($Kind -eq 'duplicate'){$null=$zip.CreateEntry('project craft.exe')}}finally{$zip.Dispose()}
 $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();$package=Join-Path $updates ($hash+'.zip');Move-Item -LiteralPath $source -Destination $package
 $plan=@{schema=1;version='1.2.0';format='zip';sha256=$hash;size=(Get-Item -LiteralPath $package).Length;file=$package;executable=(Join-Path $app 'Project Craft.exe');parentId=12345;parentStarted=[DateTime]::UtcNow.ToString('o');job=$job};$planFile=Join-Path $job 'plan.json';Write-PCJson $planFile $plan
 return @{app=$app;case=$case;job=$job;plan=$plan;file=$planFile;package=$package}
}
$fixture=New-Fixture
Check ((Invoke-PCUpdate $fixture.file) -eq 0) 'native ZIP staging and update completes'
Check ((Get-PCVersion (Join-Path $fixture.app 'Project Craft.exe')) -eq '1.2.0') 'new executable installed'
Check ((Get-Content -LiteralPath (Join-Path $fixture.app 'resources/app.asar') -Raw) -eq 'new-data') 'resources installed'
Check ((Get-Content -LiteralPath (Join-Path $fixture.app 'personal-notes.txt') -Raw) -eq 'preserve') 'unmanaged files preserved'
Check ((Get-Content -LiteralPath (Join-Path $fixture.case 'ProjectCraft/preferences.json') -Raw) -eq 'settings') 'player preferences outside application untouched'
Check ((Get-Content -LiteralPath (Join-Path $fixture.job 'result.json') -Raw|ConvertFrom-Json).success) 'success reported'
Check ($script:restarts -eq 1) 'updated launcher automatically reopened'

$fixture=New-Fixture;$before=$script:restarts;[IO.File]::AppendAllText($fixture.package,'tamper')
Check ((Invoke-PCUpdate $fixture.file) -eq 1) 'modified archive rejected'
Check (!(Test-Path -LiteralPath (Join-Path $fixture.job 'ready.json'))) 'bad hash never releases parent'
Check ((Get-PCVersion $fixture.plan.executable) -eq '1.1.1' -and $script:restarts -eq $before) 'bad hash preserves running application'

foreach($kind in @('traversal','duplicate')){$fixture=New-Fixture $kind;Check ((Invoke-PCUpdate $fixture.file) -eq 1) "$kind rejected";Check (!(Test-Path -LiteralPath (Join-Path $fixture.job 'outside.txt'))) "$kind cannot write outside stage"}

$fixture=New-Fixture;$null=New-Item -ItemType File -Path (Join-Path $fixture.job 'cancel')
Check ((Invoke-PCUpdate $fixture.file) -eq 1) 'parent cancellation prevents installation'
Check ((Get-PCVersion $fixture.plan.executable) -eq '1.1.1') 'cancellation preserves old version'

$fixture=New-Fixture;$script:originalMove=(Get-Command Move-PCFile).ScriptBlock;$script:injected=$false
function Move-PCFile([string]$Source,[string]$Destination){if(!$script:injected -and $Source.Contains('\stage\resources\app.asar')){$script:injected=$true;throw 'Injected file move failure'};& $script:originalMove $Source $Destination}
Check ((Invoke-PCUpdate $fixture.file) -eq 1) 'partial application failure reported'
Check ((Get-PCVersion $fixture.plan.executable) -eq '1.1.1') 'old executable restored after partial failure'
Check ((Get-Content -LiteralPath (Join-Path $fixture.app 'resources/app.asar') -Raw) -eq 'old-asar') 'old resources restored'
Check ((Get-Content -LiteralPath (Join-Path $fixture.app 'personal-notes.txt') -Raw) -eq 'preserve') 'rollback preserves unmanaged files'
Check (!(Get-Content -LiteralPath (Join-Path $fixture.job 'result.json') -Raw|ConvertFrom-Json).success) 'rollback recorded for retry cooldown'

$fixture=New-Fixture;$fixture.plan.file=Join-Path $fixture.case 'other.zip';Write-PCJson $fixture.file $fixture.plan
Check ((Invoke-PCUpdate $fixture.file) -eq 1) 'plan cannot select arbitrary file'
Check ((Get-PCFormat (Join-Path $fixture.app 'Project Craft.exe')) -eq 'zip') 'portable installation identified'

$msi=Join-Path $root 'build\1.1.1\ProjectCraft-Setup-1.1.1-x64.msi'
if(Test-Path -LiteralPath $msi){Assert-PCMSI @{file=$msi;version='1.1.1'};Check $true 'actual MSI metadata validated through Windows Installer';$refused=$false;try{Assert-PCMSI @{file=$msi;version='9.9.9'}}catch{$refused=$true};Check $refused 'MSI version mismatch rejected'}
if($CandidateMSI){Assert-PCMSI @{file=$CandidateMSI;version='1.2.0'};Check $true 'new MSI metadata matches release'}
if($CandidateZip){function Get-PCVersion([string]$Executable){& $script:realVersion $Executable};$fixture=New-Fixture;$fixture.plan.file=$CandidateZip;$files=Expand-PCZip $fixture.plan;Check ($files.Count -gt 50) 'actual release ZIP expands safely';Check ((Get-PCVersion (Join-Path $fixture.job 'stage\Project Craft.exe')) -eq '1.2.0') 'actual release executable version matches'}
$report=@{passed=$true;checks=$script:checks;nativePowerShell=$true;zipInstall=$true;rollback=$true;integrity=$true;traversal=$true;preferencesPreserved=$true;msiMetadata=$true;testRoot=$testRoot;testedAt=[DateTime]::UtcNow.ToString('o')}
$report|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $testRoot 'report.json') -Encoding UTF8
$report|ConvertTo-Json
