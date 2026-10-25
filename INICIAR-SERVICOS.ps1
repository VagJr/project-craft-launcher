$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'LIGAR-ATUALIZADOR.ps1')
& (Join-Path $PSScriptRoot '..\discord-bot\LIGAR-BOT.ps1')
