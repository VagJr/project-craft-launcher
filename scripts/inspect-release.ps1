param([Parameter(Mandatory=$true)][string]$ReleaseDir,
      [Parameter(Mandatory=$true)][string]$OutputDir)
$ErrorActionPreference = 'Stop'
$ReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path
$null = New-Item -ItemType Directory -Path $OutputDir -Force
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
$provenance = Get-Content -LiteralPath (Join-Path $ReleaseDir 'BUILD-PROVENANCE.json') -Raw | ConvertFrom-Json
$version = $provenance.version
$scanner = 'C:\ProgramData\Microsoft\Windows Defender\Platform\CurrentVersion\MpCmdRun.exe'
if (!(Test-Path -LiteralPath $scanner)) { throw 'Microsoft Defender nao encontrado.' }
$status = Get-MpComputerStatus
$scans = @()
$signatures = @()
foreach ($artifact in $provenance.artifacts) {
    $file = Join-Path $ReleaseDir $artifact.file
    $digest = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($digest -ne $artifact.sha256) { throw 'Artefato alterado depois da compilacao.' }
    $log = Join-Path $OutputDir ($artifact.file + '.defender.txt')
    & $scanner -Scan -ScanType 3 -File $file -DisableRemediation *> $log
    $code = $LASTEXITCODE
    $clean = $code -eq 0 -and (Select-String -LiteralPath $log -SimpleMatch 'found no threats' -Quiet)
    $scans += [PSCustomObject]@{file=$artifact.file;sha256=$digest;exitCode=$code;clean=[bool]$clean}
    if ($file.EndsWith('.msi')) {
        $sig = Get-AuthenticodeSignature -LiteralPath $file
        $signatures += [PSCustomObject]@{file=$artifact.file;status=$sig.Status.ToString();subject=$sig.SignerCertificate.Subject;thumbprint=$sig.SignerCertificate.Thumbprint}
    }
}
$appDir = Join-Path $ReleaseDir 'win-unpacked'
$appLog = Join-Path $OutputDir "app-$version.defender.txt"
& $scanner -Scan -ScanType 3 -File $appDir -DisableRemediation *> $appLog
$appCode = $LASTEXITCODE
$appClean = $appCode -eq 0 -and (Select-String -LiteralPath $appLog -SimpleMatch 'found no threats' -Quiet)
$scans += [PSCustomObject]@{file='win-unpacked';exitCode=$appCode;clean=[bool]$appClean}
$appExe = Join-Path $appDir 'Project Craft.exe'
$sig = Get-AuthenticodeSignature -LiteralPath $appExe
$signatures += [PSCustomObject]@{file='win-unpacked/Project Craft.exe';status=$sig.Status.ToString();subject=$sig.SignerCertificate.Subject;thumbprint=$sig.SignerCertificate.Thumbprint}
$runtimeExe = Join-Path $provenance.work 'node_modules\electron\dist\electron.exe'
$runtimeSig = Get-AuthenticodeSignature -LiteralPath $runtimeExe
$files = @(Get-ChildItem -LiteralPath $appDir -Recurse -File | ForEach-Object {
    [PSCustomObject]@{file=$_.FullName.Substring($appDir.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$report = [PSCustomObject]@{
    schema=1;version=$version;checkedAt=[DateTime]::UtcNow.ToString('o')
    defender=[PSCustomObject]@{engine=$status.AMEngineVersion;platform=$status.AMProductVersion;definitions=$status.AntivirusSignatureVersion;definitionsUpdated=$status.AntivirusSignatureLastUpdated.ToUniversalTime().ToString('o');realTimeProtection=$status.RealTimeProtectionEnabled}
    scans=$scans;signatures=$signatures;files=$files
    upstreamRuntime=[PSCustomObject]@{status=$runtimeSig.Status.ToString();subject=$runtimeSig.SignerCertificate.Subject;sha256=(Get-FileHash -LiteralPath $runtimeExe -Algorithm SHA256).Hash.ToLowerInvariant()}
    localScanPassed=(@($scans | Where-Object { !$_.clean }).Count -eq 0)
    publicReady=(@($scans | Where-Object { !$_.clean }).Count -eq 0 -and @($signatures | Where-Object { $_.status -ne 'Valid' }).Count -eq 0)
    limitations=@('Local Defender scans do not guarantee every antivirus or cloud reputation result.','Ed25519 update signatures do not replace Windows publisher signing.','The old 1.0.1 installer remains withdrawn; false positive is not confirmed.')
}
$reportPath = Join-Path $OutputDir "release-$version.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
[PSCustomObject]@{report=$reportPath;localScanPassed=$report.localScanPassed;publicReady=$report.publicReady;signatures=$signatures;scans=$scans} | ConvertTo-Json -Depth 5
if (!$report.localScanPassed) { exit 2 }
