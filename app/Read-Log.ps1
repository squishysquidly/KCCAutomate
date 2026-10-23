param([string]$ConfigPath, [Parameter(Mandatory=$true)][string]$LogPath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
Get-Content -LiteralPath $LogPath -Tail 500
