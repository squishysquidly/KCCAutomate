param(
    [Parameter(Mandatory=$true)][string]$TargetDirectory,
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [Parameter(Mandatory=$true)][string]$BackupDirectory,
    [string]$StageDirectory,
    [string]$ManifestHash,
    [int]$WaitProcessId=0,
    [switch]$Rollback,
    [switch]$NoRelaunch
)
$ErrorActionPreference='Stop'
$files=@('KCCAutomate.exe','MainWindow.xaml','Convert-Manga.ps1','Workflow-Support.ps1','Manage-Schedule.ps1','Read-Log.ps1','Notify-Result.ps1','Apply-Update.ps1','Workspace-Info.ps1','README.md')
$target=[IO.Path]::GetFullPath($TargetDirectory).TrimEnd('\')
$backup=[IO.Path]::GetFullPath($BackupDirectory).TrimEnd('\')
if ($target -eq [IO.Path]::GetPathRoot($target).TrimEnd('\') -or $target -eq $backup) { throw 'Invalid update or backup location.' }
$userDir=Split-Path $ConfigPath
$resultPath=Join-Path $userDir 'last-update.txt'
$lock=$null
$originals=@()
$created=@()
try {
    if ($WaitProcessId -gt 0) { Wait-Process -Id $WaitProcessId -Timeout 60 -ErrorAction SilentlyContinue }
    if ($WaitProcessId -gt 0 -and (Get-Process -Id $WaitProcessId -ErrorAction SilentlyContinue)) { throw 'KCCAutomate did not close; update canceled.' }
    $settings=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $work=[IO.Path]::GetFullPath($settings.WorkFolder)
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    # Same SMB lock as conversion. Never replace worker files during a conversion.
    $lock=[IO.File]::Open((Join-Path $work 'running.lock'),'OpenOrCreate','ReadWrite','None')
    if ($Rollback) {
        $metadata=Get-Content -LiteralPath (Join-Path $backup 'backup-info.json') -Raw | ConvertFrom-Json
        if ($metadata.Target -ne $target) { throw 'This backup belongs to a different installation.' }
        foreach ($item in $metadata.Files) {
            if ($item.Name -notin $files -or (Get-FileHash -LiteralPath (Join-Path $backup $item.Name)).Hash -ne $item.Hash) { throw 'The backup did not pass verification.' }
        }
        foreach ($item in $metadata.Files) { Copy-Item -LiteralPath (Join-Path $backup $item.Name) -Destination (Join-Path $target $item.Name) -Force }
        foreach ($name in $metadata.Created) {
            if ($name -notin $files) { throw 'Invalid rollback filename.' }
            $path=[IO.Path]::GetFullPath((Join-Path $target $name))
            if (-not $path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid rollback path.' }
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
        }
        [IO.File]::WriteAllText($resultPath,'The previous KCCAutomate version was restored. Your settings and schedule were retained.')
    } else {
        $manifestPath=Join-Path $StageDirectory 'verified-files.json'
        if ((Get-FileHash -LiteralPath $manifestPath).Hash -ne $ManifestHash) { throw 'The staged update manifest changed.' }
        $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if (@($manifest).Count -ne $files.Count -or @($manifest.Name | Sort-Object -Unique).Count -ne $files.Count) { throw 'Incomplete staged update.' }
        foreach ($item in $manifest) {
            if ($item.Name -notin $files -or (Get-FileHash -LiteralPath (Join-Path $StageDirectory $item.Name)).Hash -ne $item.Hash) { throw 'The staged update changed after verification.' }
        }
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        foreach ($name in $files) {
            $path=Join-Path $target $name
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Copy-Item -LiteralPath $path -Destination (Join-Path $backup $name)
                $originals += [pscustomobject]@{Name=$name;Hash=(Get-FileHash -LiteralPath (Join-Path $backup $name)).Hash}
            } else { $created += $name }
        }
        [pscustomobject]@{Target=$target;Files=$originals;Created=$created} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backup 'backup-info.json') -Encoding UTF8
        try {
            foreach ($name in $files) { Copy-Item -LiteralPath (Join-Path $StageDirectory $name) -Destination (Join-Path $target $name) -Force }
            foreach ($item in $manifest) { if ((Get-FileHash -LiteralPath (Join-Path $target $item.Name)).Hash -ne $item.Hash) { throw 'Installed file verification failed.' } }
        } catch {
            foreach ($item in $originals) { Copy-Item -LiteralPath (Join-Path $backup $item.Name) -Destination (Join-Path $target $item.Name) -Force }
            foreach ($name in $created) {
                $path=[IO.Path]::GetFullPath((Join-Path $target $name))
                if ($path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $path -PathType Leaf)) { Remove-Item -LiteralPath $path -Force }
            }
            throw
        }
        [IO.File]::WriteAllText($resultPath,'KCCAutomate was updated. Your settings, tool versions and schedule were retained. A rollback copy is available.')
    }
} catch {
    [IO.File]::WriteAllText($resultPath,"Update was not completed: $_. Check folder permissions and ensure no scheduled conversion is running.")
    Write-Error $_ -ErrorAction Continue
    $global:LASTEXITCODE=1
} finally {
    if ($lock) { $lock.Dispose() }
    if (-not $NoRelaunch) { Start-Process -FilePath (Join-Path $target 'KCCAutomate.exe') -WorkingDirectory $target }
}
if ($global:LASTEXITCODE -eq 1) { exit 1 }
