$ErrorActionPreference = 'Stop'
$launcherDirectory = $PSScriptRoot
$stateDirectory = Join-Path $launcherDirectory '.local'
if (Test-Path -LiteralPath (Join-Path $stateDirectory 'distribution-suspended.json')) { Write-Output 'Atualizador suspenso enquanto o alerta do antivírus é analisado.'; exit 0 }
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$pidFile = Join-Path $stateDirectory 'watch.pid'
if (Test-Path -LiteralPath $pidFile) {
    $watchProcessId = [int](Get-Content -LiteralPath $pidFile)
    $existingProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $watchProcessId" -ErrorAction SilentlyContinue
    if ($existingProcess -and $existingProcess.CommandLine -like '*scripts/watch.cjs*') { Write-Output 'O atualizador já está ativo.'; exit 0 }
}
$nodeExecutable = (Get-Command node -ErrorAction Stop).Source
$watchProcess = Start-Process -FilePath $nodeExecutable -ArgumentList @('scripts/watch.cjs') -WorkingDirectory $launcherDirectory -WindowStyle Hidden -RedirectStandardOutput (Join-Path $stateDirectory 'watch.log') -RedirectStandardError (Join-Path $stateDirectory 'watch-error.log') -PassThru
Set-Content -LiteralPath $pidFile -Value $watchProcess.Id
Write-Output 'Atualizador ativo: conferência a cada cinco minutos.'
