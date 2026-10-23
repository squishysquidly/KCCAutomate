param([string]$ConfigPath)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$settings=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$work=$settings.WorkFolder
if (-not (Test-Path -LiteralPath $work -PathType Container)) { throw 'Working folder is unavailable or has not been created yet.' }
$files=@(Get-ChildItem -LiteralPath $work -File -Recurse -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
$bytes=($files | Measure-Object Length -Sum).Sum
$attempts=@(Get-ChildItem -LiteralPath $work -Directory -Recurse | Where-Object { $_.Name -match '^[a-f0-9]{32}$' }).Count
Write-Output ('@@SPACE:' + ('{0:N2} GB in {1} files; {2} attempt folders. Receipts and logs are kept.' -f ($bytes/1GB),$files.Count,$attempts))
