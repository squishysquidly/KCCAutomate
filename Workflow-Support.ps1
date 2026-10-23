# Shared queue reporting and maintenance. Loaded by the conversion worker.
$queueState = @{}
$queuePersistent = $false
$currentSource = $null
function Select-Conversion($File) {
    if (-not $config) { $script:activeProfile='KS'; $script:activeNaming='{name}'; return }
    $effective = $config | Select-Object *
    $relative = $File.FullName.Substring($incoming.Length).TrimStart('\')
    foreach ($rule in @($config.FolderRules)) {
        if ($rule.Pattern -and $relative -like $rule.Pattern) {
            foreach ($property in $rule.Options.PSObject.Properties) {
                if ($property.Name -in @('Profile','Format','Cropping','Splitter','MangaStyle','Upscale','Stretch','Autolevel','NoAutocontrast','ForceColor','ForcePng','Webtoon','Gamma','OutputNaming')) {
                    $effective | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
                }
            }
            break
        }
    }
    if ($effective.Profile -notmatch '^[A-Za-z0-9]+$' -or $effective.Format -notin @('MOBI','EPUB','PDF','CBZ') -or
        [int]$effective.Cropping -notin @(0,1,2) -or [int]$effective.Splitter -notin @(0,1,2)) { throw 'Invalid conversion preset.' }
    if ($effective.Profile -notmatch '^K(?!o)' -and $effective.Format -eq 'MOBI') { throw 'The folder preset selects MOBI for a non-Kindle profile.' }
    $script:activeProfile=$effective.Profile
    $script:activeNaming=if ($effective.OutputNaming) { $effective.OutputNaming } else { '{name}' }
    $script:outputExtension='.' + $effective.Format.ToLowerInvariant()
    $script:arguments=@('--profile',$effective.Profile,'--format',$effective.Format,'--cropping',[string]$effective.Cropping,'--splitter',[string]$effective.Splitter,'--tempdir')
    foreach ($setting in @(@('MangaStyle','--manga-style'),@('Upscale','--upscale'),@('Stretch','--stretch'),@('Autolevel','--autolevel'),@('NoAutocontrast','--noautocontrast'),@('ForceColor','--forcecolor'),@('ForcePng','--forcepng'),@('Webtoon','--webtoon'))) {
        if ($effective.($setting[0])) { $script:arguments += $setting[1] }
    }
    if ([double]$effective.Gamma -gt 0) { $script:arguments += @('--gamma',([double]$effective.Gamma).ToString([Globalization.CultureInfo]::InvariantCulture)) }
}
function Read-QueueHistory {
    $history = Join-Path $work 'queue.json'
    if (Test-Path -LiteralPath $history) {
        try {
            foreach ($row in (Get-Content -LiteralPath $history -Raw | ConvertFrom-Json)) {
                if ($row.SourcePath) { $queueState[$row.SourcePath] = $row }
            }
        } catch { Write-Host 'Queue history could not be read; conversion receipts are still retained.' }
    }
}
function Save-QueueHistory {
    if (-not $queuePersistent) { return }
    try {
        $recent = @($queueState.Values | Sort-Object UpdatedUtc -Descending | Select-Object -First 1000)
        $temp = Join-Path $work ('queue-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $recent -Depth 8))
        Move-Item -LiteralPath $temp -Destination (Join-Path $work 'queue.json') -Force
    } catch { Write-Host "Queue history could not be saved: $_" }
}
function Get-OutputName($File) {
    $template = '{name}'
    if ($activeNaming) { $template = $activeNaming }
    $name = $template.Replace('{name}', $File.BaseName).Replace('{format}', $outputExtension.TrimStart('.')).Replace('{profile}', $activeProfile)
    if (-not $name -or $name -match '[<>:"/\\|?*\x00-\x1f]' -or $name -match '[{}]' -or $name.EndsWith('.') -or $name.EndsWith(' ')) {
        throw 'Output naming must be a filename using {name}, {format} or {profile}; folders and invalid filename characters are not allowed.'
    }
    $name + $outputExtension
}
function Get-Advice([string]$Message) {
    switch -Regex ($Message) {
        'JXL|djxl' { return 'Check the JPEG XL decoder path and its log; retry this book after fixing it.' }
        'exists|same output|conflict' { return 'Review the conflicting filename. Rename the source or choose replacement of converted books.' }
        'KindleGen|MOBI|usable output' { return 'Open the KCC log. Check KindleGen, network access and the output path.' }
        'changed|recent|partial' { return 'Wait for the download to finish, then refresh or retry.' }
        'unavailable|network|access|denied' { return 'Check share permissions and connectivity for the Windows account running the task.' }
        default { return 'Open the working folder for the detailed converter log, correct the issue, then retry.' }
    }
}
function Set-QueueRecord([string]$Source, [string]$Status, [string]$Detail = '', [string]$Target = '') {
    if (-not $queueState.ContainsKey($Source)) {
        $relative = $Source.Substring($incoming.Length).TrimStart('\')
        $queueState[$Source] = [pscustomobject]@{
            SourcePath=$Source; Name=[IO.Path]::GetFileName($Source); Batch=($relative -split '\\')[0]
            Status='Waiting'; Detail=''; Advice=''; OutputPath=''; JxlPages=0; Fingerprint=''; UpdatedUtc=''
        }
    }
    $row = $queueState[$Source]
    $row.Status=$Status; $row.Detail=$Detail; $row.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
    $row.Advice = if ($Status -eq 'Failed' -or $Status -eq 'Conflict') { Get-Advice $Detail } else { '' }
    if ($Target) { $row.OutputPath=$Target }
    Write-Host ('@@MF:' + ($row | ConvertTo-Json -Compress -Depth 6))
    Save-QueueHistory
}
function Get-JobFolder($File) {
    Join-Path $work (Key ((Fingerprint $File) + ($arguments -join ' ') + '|jxl-preprocessing-v1|' + $output + '|' + (Get-OutputName $File)))
}
function Test-Receipt($File) {
    $receipt = Join-Path (Get-JobFolder $File) 'receipt.json'
    if (-not (Test-Path -LiteralPath $receipt)) { return $false }
    $items = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if (-not @($items).Count) { return $false }
    foreach ($item in $items) {
        if (-not (Test-Path -LiteralPath $item.Path) -or (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Hash) { return $false }
    }
    return $true
}
function Get-PreviewQueue {
    Read-QueueHistory
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($batch in @(Get-ChildItem -LiteralPath $incoming -Force | Where-Object { $_.Name -notlike 'KCC-*' })) {
        try {
            $files = @(BatchFiles $batch)
            $selected = @($files | Where-Object { $_.Extension.ToLowerInvariant() -in $inputExtensions })
            $recent = @($files | Where-Object { $_.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddMinutes(-$QuietMinutes) -or $_.Extension -in @('.part','.tmp','.crdownload','.download') }).Count
            $targets = @{}
            foreach ($file in $selected) {
                Select-Conversion $file
                $destinationFolder=Join-Path $output (Split-Path ($file.FullName.Substring($incoming.Length).TrimStart('\')) -Parent)
                $target = Join-Path $destinationFolder (Get-OutputName $file)
                if (-not $targets.ContainsKey($target)) { $targets[$target] = @() }
                $targets[$target] += $file.FullName
            }
            foreach ($file in $files) {
                $source = $file.FullName
                $old = $queueState[$source]
                if ($file.Extension.ToLowerInvariant() -notin $inputExtensions) {
                    Set-QueueRecord $source $(if ($batch.PSIsContainer -and $selected.Count) { 'Accompanying' } else { 'Ignored' }) 'Not converted; accompanies a successful folder into the archive.'
                    continue
                }
                Select-Conversion $file
                $destinationFolder=Join-Path $output (Split-Path ($source.Substring($incoming.Length).TrimStart('\')) -Parent)
                $target = Join-Path $destinationFolder (Get-OutputName $file)
                $fingerprint = Fingerprint $file
                $jxl = 0
                if ($file.Extension -eq '.cbz') {
                    $zip = [IO.Compression.ZipFile]::OpenRead($source)
                    try { $jxl = @($zip.Entries | Where-Object { $_.FullName -match '(?i)\.jxl$' }).Count } finally { $zip.Dispose() }
                }
                $state = 'Waiting'; $detail = 'Ready to convert.'
                if ($recent) { $state='Waiting for download'; $detail='Recent or partial files exist in this batch.' }
                elseif ($targets[$target].Count -gt 1) { $state='Conflict'; $detail='Multiple selected inputs would create the same output.' }
                elseif ($jxl -gt 0 -and (-not $convertJxl -or -not $DjxlExe -or -not (Test-Path -LiteralPath $DjxlExe))) { $state='Failed'; $detail='JXL pages require an enabled, installed djxl decoder.' }
                elseif ($old -and $old.Fingerprint -eq $fingerprint -and $old.Status -in @('Failed','Converted','Conflict')) { $state=$old.Status; $detail=$old.Detail }
                elseif ((Test-Path -LiteralPath $target) -and -not $overwriteConverted) { $state='Review existing output'; $detail='An output exists; conversion will verify its receipt or stop on different content.' }
                Set-QueueRecord $source $state $detail $target
                $queueState[$source].JxlPages=$jxl; $queueState[$source].Fingerprint=$fingerprint
            }
        } catch { Set-QueueRecord $batch.FullName 'Failed' ([string]$_) }
    }
    if ($ReportPath) {
        [IO.File]::WriteAllText($ReportPath, (ConvertTo-Json -InputObject @($queueState.Values | Sort-Object Batch,Name) -Depth 8))
    }
}
function Remove-ExpiredAttempts {
    if (-not $config -or -not $config.AutoCleanup) { return }
    $successDays=[int]$config.SuccessRetentionDays; $failureDays=[int]$config.FailureRetentionDays
    if ($successDays -lt 1 -or $failureDays -lt 1) { throw 'Retention periods must be at least one day.' }
    $rootPath=[IO.Path]::GetFullPath($work).TrimEnd('\') + '\'
    foreach ($jobDir in @(Get-ChildItem -LiteralPath $work -Directory -Force | Where-Object { $_.Name -match '^[A-F0-9]{64}$' })) {
        if ($jobDir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        foreach ($attemptDir in @(Get-ChildItem -LiteralPath $jobDir.FullName -Directory -Force | Where-Object { $_.Name -match '^[a-f0-9]{32}$' })) {
            $resultPath=Join-Path $attemptDir.FullName 'result.json'
            $succeeded=$false
            if (Test-Path -LiteralPath $resultPath) { try { $succeeded=[bool]((Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json).Succeeded) } catch { continue } }
            $days = if ($succeeded) { $successDays } else { $failureDays }
            if ($attemptDir.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddDays(-$days)) { continue }
            $resolved = [IO.Path]::GetFullPath($attemptDir.FullName)
            if (-not $resolved.StartsWith($rootPath,[StringComparison]::OrdinalIgnoreCase) -or
                ($attemptDir.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                @(Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { continue }
            Remove-Item -LiteralPath $resolved -Recurse -Force
            Log "CLEANED temporary attempt: $resolved"
        }
    }
}
