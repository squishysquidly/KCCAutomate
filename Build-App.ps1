param([string]$Destination = (Join-Path $PSScriptRoot 'dist\MangaFlow'))
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework compiler is unavailable.' }
$framework = Split-Path $compiler
$wpf = Join-Path $framework 'WPF'
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$references = @('System.dll','System.Core.dll','System.Xaml.dll','System.Web.Extensions.dll','System.Windows.Forms.dll','System.Drawing.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll') |
    ForEach-Object { '/reference:' + (Join-Path $framework $_) }
$references += @('PresentationFramework.dll','PresentationCore.dll','WindowsBase.dll') |
    ForEach-Object { '/reference:' + (Join-Path $wpf $_) }
$sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'app') -Filter '*.cs' | ForEach-Object FullName)
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ @references "/win32manifest:$PSScriptRoot\app\app.manifest" "/out:$Destination\MangaFlow.exe" @sources
if ($LASTEXITCODE -ne 0) { throw 'App compilation failed.' }
foreach ($file in @('Convert-Manga.ps1','Workflow-Support.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $Destination -Force }
foreach ($file in @('MainWindow.xaml','Manage-Schedule.ps1','Read-Log.ps1','Notify-Result.ps1','Apply-Update.ps1','Workspace-Info.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('app\' + $file)) -Destination $Destination -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $Destination -Force
Write-Output "Built portable app: $Destination\MangaFlow.exe"
