$ErrorActionPreference = 'Stop'
$launcherDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$startupScript = Join-Path $launcherDirectory 'INICIAR-SERVICOS.ps1'
$powershellExecutable = (Get-Command powershell.exe -ErrorAction Stop).Source
$startupAction = New-ScheduledTaskAction -Execute $powershellExecutable -Argument "-NoProfile -WindowStyle Hidden -File `"$startupScript`"" -WorkingDirectory $launcherDirectory
$startupTrigger = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$startupPrincipal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$startupSettings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'ProjectCraft-Servicos' -Action $startupAction -Trigger $startupTrigger -Principal $startupPrincipal -Settings $startupSettings -Description 'Inicia o atualizador de endereço/versões e o bot do Project Craft ao entrar no Windows.' -Force | Out-Null
Write-Output 'Serviços configurados para iniciar ao entrar no Windows.'
