param([string]$ConfigPath,[switch]$AvailabilityOnly)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$settings=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($AvailabilityOnly) {
    $errors=@()
    foreach ($pair in @(@('Incoming','WatchFolder'),@('Converted','ConvertedFolder'),@('Archive','ArchiveFolder'),@('Working','WorkFolder'))) {
        if($pair[1] -eq 'ArchiveFolder' -and $settings.OriginalsAction -eq 'Delete'){continue}
        $path=[string]$settings.($pair[1])
        try {
            if (-not $path -or -not [IO.Path]::IsPathRooted($path) -or -not [IO.Directory]::Exists($path)) { throw 'Folder is missing, disconnected, or not accessible.' }
            $iterator=[IO.Directory]::EnumerateFileSystemEntries($path).GetEnumerator()
            try { [void]$iterator.MoveNext() } finally { $iterator.Dispose() }
        } catch { $errors += $pair[0]+': '+$path+' - '+$_.Exception.Message }
    }
    [pscustomobject]@{Ready=($errors.Count -eq 0);Message=($errors -join "`n")}|ConvertTo-Json -Compress
    return
}
$work=$settings.WorkFolder
if (-not (Test-Path -LiteralPath $work -PathType Container)) { throw 'Working folder is unavailable or has not been created yet.' }
$files=@(Get-ChildItem -LiteralPath $work -File -Recurse -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
$bytes=($files | Measure-Object Length -Sum).Sum
$attempts=@(Get-ChildItem -LiteralPath $work -Directory -Recurse | Where-Object { $_.Name -match '^[a-f0-9]{32}$' }).Count
Write-Output ('@@SPACE:' + ('{0:N2} GB in {1} files; {2} attempt folders. Receipts and logs are kept.' -f ($bytes/1GB),$files.Count,$attempts))
