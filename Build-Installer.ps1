param([switch]$SkipPackage)
$ErrorActionPreference='Stop'
if(-not $SkipPackage){& (Join-Path $PSScriptRoot 'Package-App.ps1')}
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$compiler=Join-Path $framework 'csc.exe'
$dist=Join-Path $PSScriptRoot 'dist'
$references=@('System.dll','System.Core.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Web.Extensions.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll','Microsoft.CSharp.dll')|ForEach-Object{'/reference:'+(Join-Path $framework $_)}
$sources=@((Join-Path $PSScriptRoot 'installer\Setup.cs'),(Join-Path $PSScriptRoot 'app\Services.cs'))
$uninstaller=Join-Path $dist 'Uninstall-MangaFlow.exe'
& $compiler /nologo /target:winexe /optimize+ /define:UNINSTALL_BUILD @references "/win32manifest:$PSScriptRoot\app\app.manifest" "/out:$uninstaller" @sources
if($LASTEXITCODE){throw 'Uninstaller compilation failed.'}
$zip=Join-Path $dist 'MangaFlow-Windows.zip'
$digest=Join-Path $dist 'payload.sha256'
[IO.File]::WriteAllText($digest,(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant())
$setup=Join-Path $dist 'MangaFlow-Setup.exe'
& $compiler /nologo /target:winexe /optimize+ @references "/win32manifest:$PSScriptRoot\app\app.manifest" "/resource:$zip,MangaFlow.Payload.zip" "/resource:$digest,MangaFlow.Payload.sha256" "/resource:$uninstaller,MangaFlow.Uninstaller.exe" "/out:$setup" @sources
if($LASTEXITCODE){throw 'Installer compilation failed.'}
$sums=@($zip,$setup)|ForEach-Object{(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($_)}
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS'),$sums)
Write-Output "Built installer: $setup"
