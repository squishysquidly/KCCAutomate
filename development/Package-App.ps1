param([switch]$SkipBuild)
$ErrorActionPreference='Stop'
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'Build-App.ps1') }
$build=Join-Path $PSScriptRoot 'dist\KCCAutomate'
$distRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'dist')).TrimEnd('\')
$stage=Join-Path $distRoot ('package-'+[guid]::NewGuid().ToString('N'))
$payload=Join-Path $stage 'KCCAutomate'
try {
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    $files=@('KCCAutomate.exe','MainWindow.xaml','Convert-Manga.ps1','Workflow-Support.ps1','Manage-Schedule.ps1','Read-Log.ps1','Notify-Result.ps1','Apply-Update.ps1','Workspace-Info.ps1','README.md','portable.flag','license.txt')
    foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $build $file) -Destination $payload }
    $zip=Join-Path $distRoot 'KCCAutomate-Windows.zip'
    Compress-Archive -LiteralPath $payload -DestinationPath $zip -Force
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $distRoot 'SHA256SUMS'), "$hash  KCCAutomate-Windows.zip`n")
    Write-Output "Portable package: $zip"
} finally {
    if(Test-Path -LiteralPath $stage){
        $resolved=[IO.Path]::GetFullPath($stage)
        if(-not $resolved.StartsWith($distRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolved) -notmatch '^package-[a-f0-9]{32}$') {throw 'Refusing to clean an unexpected package path.'}
        foreach($entry in @((Get-Item -LiteralPath $distRoot),(Get-Item -LiteralPath $resolved)) + @(Get-ChildItem -LiteralPath $resolved -Recurse -Force)){
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refusing to clean a linked package staging path.'}
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
