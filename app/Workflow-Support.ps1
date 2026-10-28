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
                if ($property.Name -in @('Profile','Format','Cropping','Splitter','MangaStyle','Upscale','Stretch','Autolevel','NoAutocontrast','ForceColor','ForcePng','Webtoon','Gamma','OutputNaming','ScribeCompatibility')) {
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
    if($null -ne $effective.ScribeCompatibility -and $effective.ScribeCompatibility -isnot [bool]){throw 'Scribe compatibility must be true or false.'}
    if($effective.ScribeCompatibility -eq $true -and $effective.Profile -eq 'KS' -and $effective.Format -in @('MOBI','EPUB')){
        $effective.Profile='KS1860';$effective.Cropping=0;$effective.ForcePng=$false
    }
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
            foreach ($row in (Get-Content -LiteralPath $history -Raw -Encoding UTF8 | ConvertFrom-Json)) {
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
    $name = $template.Replace('{name}', (Get-BookLabel $File)).Replace('{format}', $outputExtension.TrimStart('.')).Replace('{profile}', $activeProfile)
    if (-not $name -or $name -match '[<>:"/\\|?*\x00-\x1f]' -or $name -match '[{}]' -or $name.EndsWith('.') -or $name.EndsWith(' ')) {
        throw 'Output naming must be a filename using {name}, {format} or {profile}; folders and invalid filename characters are not allowed.'
    }
    $name + $outputExtension
}
function Get-Advice([string]$Message) {
    switch -Regex ($Message) {
        'Multiple inputs|Multiple selected inputs' { return 'Rename one input or put the inputs in separate folders. A replacement policy cannot resolve two source files targeting one book.' }
        'JXL|djxl' { return 'Check the JPEG XL decoder path and its log; retry this book after fixing it.' }
        'exists|same output|conflict|Previously published output' { return 'Review incoming and output paths. Choose Replace or Keep both in On retry, then retry the selected output conflict.' }
        'KindleGen|MOBI|usable output' { return 'Open the KCC log. Check KindleGen, network access and the output path.' }
        'changed|recent|partial' { return 'Wait for the download to finish, then refresh or retry.' }
        'unavailable|network|access|denied' { return 'Check that the local or remote folder is accessible to the Windows account running the task.' }
        default { return 'Open the working folder for the detailed converter log, correct the issue, then retry.' }
    }
}
function Get-ConflictKind([string]$Message) {
    if ($Message -match 'Multiple inputs|Multiple selected inputs') { return 'MultipleInputs' }
    if ($Message -match 'Different output already exists|Previously published output') { return 'ExistingOutput' }
    return ''
}
function Set-QueueRecord([string]$Source, [string]$Status, [string]$Detail = '', [string]$Target = '', [string]$ConflictKind = '') {
    if (-not $queueState.ContainsKey($Source)) {
        $relative = $Source.Substring($incoming.Length).TrimStart('\')
        $queueState[$Source] = [pscustomobject]@{
            SourcePath=$Source; Name=[IO.Path]::GetFileName($Source); Batch=($relative -split '\\')[0]
            Status='Waiting'; Detail=''; Advice=''; OutputPath=''; JxlPages=0; Fingerprint=''; UpdatedUtc=''
        }
    }
    $row = $queueState[$Source]
    $row | Add-Member -NotePropertyName ConflictKind -NotePropertyValue $ConflictKind -Force
    $row.Status=$Status; $row.Detail=$Detail; $row.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
    $row.Advice = if($Status -eq 'Stopped'){'Run now or retry this book to continue. Unconverted originals were retained.'}elseif ($Status -eq 'Failed' -or $Status -eq 'Conflict') { Get-Advice $Detail } else { '' }
    if ($Target) { $row.OutputPath=$Target }
    Write-Host ('@@MF:' + ($row | ConvertTo-Json -Compress -Depth 6))
    Save-QueueHistory
}
function Get-JobFolder($File) {
    Join-Path $work (Key ((Fingerprint $File) + ($arguments -join ' ') + '|jxl-preprocessing-v1|' + $output + '|' + (Get-OutputName $File) + (Get-BundleKey $File) + (Get-LabelKey) + (Get-OutputFolderKey $File)))
}
function Test-Receipt($File) {
    $receipt = Join-Path (Get-JobFolder $File) 'receipt.json'
    $chapterReceipt=@(Get-ChapterReceipt $File)
    if (-not $chapterReceipt.Count -and -not (Test-Path -LiteralPath $receipt)) { return $false }
    try {
        $items = if ($chapterReceipt.Count) { $chapterReceipt } else { Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json }
        if (-not $items -or -not @($items).Count) { return $false }
        foreach ($item in $items) {
            if (-not $item.Path -or -not $item.Hash -or -not (Test-Path -LiteralPath $item.Path -PathType Leaf) -or (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Hash) { return $false }
        }
    } catch { return $false }
    return $true
}
function Publish-ConvertedBooks($File, $Books, [string]$Destination, [string]$Policy) {
    $stem=[IO.Path]::GetFileNameWithoutExtension((Get-OutputName $File))
    $planned=@()
    foreach ($book in $Books) {
        if (-not $book.BaseName.StartsWith('book',[StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected KCC output filename: $($book.Name)" }
        $suffix=$book.BaseName.Substring(4)
        $target=Join-Path $Destination ($stem+$suffix+$outputExtension)
        if (Test-Path -LiteralPath $target -PathType Container) { throw "Output path is an existing folder: $target" }
        $exists=Test-Path -LiteralPath $target -PathType Leaf
        $hash=(Get-FileHash -LiteralPath $book.FullName -Algorithm SHA256).Hash
        $different=$exists -and (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash
        $planned += [pscustomobject]@{Source=$book.FullName;Suffix=$suffix;Target=$target;Hash=$hash;Exists=$exists;Different=$different}
    }
    if ($Policy -eq 'Skip' -and @($planned | Where-Object Exists).Count) {
        return [pscustomobject]@{Skipped=$true;Target=($planned | Where-Object Exists | Select-Object -First 1).Target;Receipt=@()}
    }
    $conflicts=@($planned | Where-Object Different)
    if ($conflicts.Count -and $Policy -eq 'Review') { throw "Different output already exists: $($conflicts[0].Target)" }
    if ($conflicts.Count -and $Policy -eq 'KeepBoth') {
        $number=1
        do {
            $number++
            if ($number -gt 9999) { throw 'No free numbered output name was found.' }
            $occupied=$false
            foreach ($item in $planned) {
                $item.Target=Join-Path $Destination ($stem+' ('+$number+')'+$item.Suffix+$outputExtension)
                if ((Test-Path -LiteralPath $item.Target) -or ($reservedOutputs -and $reservedOutputs.ContainsKey($item.Target))) { $occupied=$true }
            }
        } while ($occupied)
        foreach ($item in $planned) { $item.Exists=$false; $item.Different=$false }
    }
    $receipt=@()
    foreach ($item in $planned) {
        if (-not $item.Exists) {
            # Fail rather than overwrite if another writer created this name.
            [IO.File]::Copy($item.Source,$item.Target,$false)
        } elseif ($item.Different) {
            if ($Policy -ne 'Replace') { throw "Different output already exists: $($item.Target)" }
            [IO.File]::Copy($item.Source,$item.Target,$true)
        }
        if ((Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -ne $item.Hash) { throw "Output verification failed: $($item.Target)" }
        $receipt += [pscustomobject]@{Path=$item.Target;Hash=$item.Hash}
    }
    [pscustomobject]@{Skipped=$false;Target=$receipt[0].Path;Receipt=$receipt}
}
function Get-PreviewQueue {
    if ($bundleOptions.Enabled) { Get-ChapterPreview; return }
    Read-QueueHistory
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $batches=@(Get-ChildItem -LiteralPath $incoming -Force | Where-Object { $_.Name -notlike 'KCC-*' })
    $previewFiles=@{}; $targets=@{}
    foreach ($batch in $batches) {
        try {
            $previewFiles[$batch.FullName]=@(BatchFiles $batch)
            foreach ($file in @($previewFiles[$batch.FullName] | Where-Object { $_.Extension.ToLowerInvariant() -in $inputExtensions })) {
                Select-Conversion $file
                $folder=Get-OutputDirectory $file
                $target=Join-Path $folder (Get-OutputName $file)
                if (-not $targets.ContainsKey($target)) { $targets[$target]=@() }
                $targets[$target]+=$file.FullName
            }
        } catch { Set-QueueRecord $batch.FullName 'Failed' ([string]$_); $previewFiles[$batch.FullName]=@() }
    }
    foreach ($batch in $batches) {
        try {
            $files = @($previewFiles[$batch.FullName])
            $selected = @($files | Where-Object { $_.Extension.ToLowerInvariant() -in $inputExtensions })
            $recent = @($files | Where-Object { $_.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddMinutes(-$QuietMinutes) -or $_.Extension -in @('.part','.tmp','.crdownload','.download') }).Count
            foreach ($file in $files) {
                $source = $file.FullName
                $old = $queueState[$source]
                if ($file.Extension.ToLowerInvariant() -notin $inputExtensions) {
                    Set-QueueRecord $source $(if ($batch.PSIsContainer -and $selected.Count) { 'Accompanying' } else { 'Ignored' }) $(if($originalsAction -eq 'Delete'){'Not converted; retained in Incoming when converted originals are deleted.'}else{'Not converted; accompanies a successful folder into the archive.'})
                    continue
                }
                Select-Conversion $file
                $destinationFolder=Get-OutputDirectory $file
                $target = Join-Path $destinationFolder (Get-OutputName $file)
                $fingerprint = Fingerprint $file
                $jxl = 0
                if ($file.Extension -eq '.cbz') {
                    $zip = [IO.Compression.ZipFile]::OpenRead($source)
                    try { $jxl = @($zip.Entries | Where-Object { $_.FullName -match '(?i)\.jxl$' }).Count } finally { $zip.Dispose() }
                }
                $state = 'Waiting'; $detail = 'Ready to convert.'
                if ($recent) { $state='Waiting for download'; $detail='Recent or partial files exist in this batch.' }
                elseif ($targets[$target].Count -gt 1) { $state='Conflict'; $detail='Multiple selected inputs would create the same output. Rename one or use separate folders.' }
                elseif ($jxl -gt 0 -and (-not $convertJxl -or -not $DjxlExe -or -not (Test-Path -LiteralPath $DjxlExe))) { $state='Failed'; $detail='JXL pages require an enabled, installed djxl decoder.' }
                elseif (Test-Receipt $file) { $state='Converted'; $detail='Previously completed output verified.' }
                elseif (Test-Path -LiteralPath $target -PathType Leaf) {
                    if ($duplicateAction -eq 'Skip') { $state='Skipped existing output'; $detail='Existing output will be kept; incoming originals stay in place.' }
                    elseif ($duplicateAction -eq 'Replace') { $detail='Existing output will be replaced after conversion and verification.' }
                    elseif ($duplicateAction -eq 'KeepBoth') { $detail='Different output will be kept with a free numbered filename.' }
                    else { $state='Conflict'; $detail='Different output already exists or has not been verified. Conversion can compare it; choose a one-run action to replace or keep both.' }
                }
                elseif ($old -and $old.Fingerprint -eq $fingerprint -and $old.Status -eq 'Failed') { $state=$old.Status; $detail=$old.Detail }
                Set-QueueRecord $source $state $detail $target (Get-ConflictKind $detail)
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
