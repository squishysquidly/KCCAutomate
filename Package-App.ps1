param([switch]$SkipBuild)
$ErrorActionPreference='Stop'
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'Build-App.ps1') }
$build=Join-Path $PSScriptRoot 'dist\KCCAutomate'
$stage=Join-Path $PSScriptRoot ('dist\package-'+[guid]::NewGuid().ToString('N'))
$payload=Join-Path $stage 'KCCAutomate'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
$files=@('KCCAutomate.exe','MainWindow.xaml','Convert-Manga.ps1','Workflow-Support.ps1','Manage-Schedule.ps1','Read-Log.ps1','Notify-Result.ps1','Apply-Update.ps1','Workspace-Info.ps1','README.md','portable.flag','license.txt')
foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $build $file) -Destination $payload }
$zip=Join-Path $PSScriptRoot 'dist\KCCAutomate-Windows.zip'
Compress-Archive -LiteralPath $payload -DestinationPath $zip -Force
$hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'dist\SHA256SUMS'), "$hash  KCCAutomate-Windows.zip`n")
Write-Output "Portable package: $zip"
