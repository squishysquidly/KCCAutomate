param(
    [string]$KccExe = 'C:\kindletomanga\kcc-c2e.exe',
    [string]$DjxlExe = 'C:\Program Files\KindleComicConverter\jxl\djxl.exe',
    [int]$QuietMinutes = 30,
    [switch]$Preview,
    [string]$ConfigPath,
    [switch]$CheckSetup,
    [string]$StopFile,
    [string]$ReportPath,
    [string]$SelectionPath,
    [switch]$CleanupOnly,
    [ValidateSet('Review','Replace','KeepBoth','Skip')][string]$ExistingOutputAction
)

# Windows PowerShell 5.1. Each top-level folder is one archival batch.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$root = '\\192.168.7.223\mirror'
$incoming = Join-Path $root 'manga_downloaded'
$output = Join-Path $root 'manga_kindle'
$archive = Join-Path $root 'manga_sorted'
$work = Join-Path $root 'manga_automation_work'
$arguments = @('--profile','KS','--format','MOBI','--manga-style',
    '--upscale','--cropping','0','--splitter','0','--tempdir')
$inputExtensions = @('.cbz')
$outputExtension = '.mobi'
$overwriteConverted = $false
$duplicateAction = 'Review'
$convertJxl = $true
$kindlegenExe = ''
$sevenZipExe = ''
$approvedKccVersion = ''
if ($ConfigPath) {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $incoming = $config.WatchFolder
    $output = $config.ConvertedFolder
    $archive = $config.ArchiveFolder
    $work = $config.WorkFolder
    $KccExe = $config.KccExe
    $DjxlExe = $config.DjxlExe
    $kindlegenExe = $config.KindlegenExe
    $sevenZipExe = $config.SevenZipExe
    $approvedKccVersion = [string]$config.ApprovedKccVersion
    if ($approvedKccVersion -and $approvedKccVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid approved KCC version in settings. Save settings again in KCCAutomate.' }
    $QuietMinutes = [int]$config.QuietMinutes
    $inputExtensions = @($config.InputExtensions)
    $overwriteConverted = [bool]$config.OverwriteConverted
    $duplicateAction = if ($config.DuplicateAction) { [string]$config.DuplicateAction } elseif ($overwriteConverted) { 'Replace' } else { 'Review' }
    if ($duplicateAction -notin @('Review','Replace','KeepBoth','Skip')) { throw 'Choose a supported duplicate action.' }
    $convertJxl = [bool]$config.ConvertJxl
    if ($config.Profile -notmatch '^[A-Za-z0-9]+$') { throw 'Choose a valid device profile.' }
    if ($config.Format -notin @('MOBI','EPUB','CBZ','PDF')) { throw 'Unsupported output format.' }
    if ($config.Profile -notmatch '^K(?!o)' -and $config.Format -eq 'MOBI') { throw 'Choose EPUB, CBZ or PDF for a non-Kindle device.' }
    if ($QuietMinutes -lt 0 -or $QuietMinutes -gt 1440) { throw 'The quiet period must be between 0 and 1440 minutes.' }
    if (-not $inputExtensions.Count -or @($inputExtensions | Where-Object { $_ -notin @('.cbz','.pdf','.epub','.cbr','.cb7') }).Count) { throw 'Select supported input formats.' }
    if ([int]$config.Cropping -notin @(0,1,2) -or [int]$config.Splitter -notin @(0,1,2)) { throw 'Invalid cropping or spread setting.' }
    $outputExtension = '.' + $config.Format.ToLowerInvariant()
    $arguments = @('--profile', $config.Profile, '--format', $config.Format,
        '--cropping', [string]$config.Cropping, '--splitter', [string]$config.Splitter, '--tempdir')
    foreach ($setting in @(
        @('MangaStyle','--manga-style'), @('Upscale','--upscale'),
        @('Stretch','--stretch'), @('Autolevel','--autolevel'),
        @('NoAutocontrast','--noautocontrast'), @('ForceColor','--forcecolor'),
        @('ForcePng','--forcepng'), @('Webtoon','--webtoon')
    )) { if ($config.($setting[0])) { $arguments += $setting[1] } }
    if ([double]$config.Gamma -gt 0) { $arguments += @('--gamma', ([double]$config.Gamma).ToString([Globalization.CultureInfo]::InvariantCulture)) }
}
# Refuse overlapping locations before touching any files. UNC paths are supported.
$paths = @($incoming,$output,$archive,$work)
for ($i = 0; $i -lt $paths.Count; $i++) {
    if (-not $paths[$i] -or -not [IO.Path]::IsPathRooted($paths[$i])) { throw 'Select absolute folder paths.' }
    $paths[$i] = [IO.Path]::GetFullPath($paths[$i]).TrimEnd('\')
    if ($paths[$i] -eq [IO.Path]::GetPathRoot($paths[$i]).TrimEnd('\')) { throw 'Choose a subfolder, not the root of a drive or share.' }
}
for ($i = 0; $i -lt $paths.Count; $i++) {
    for ($j = $i + 1; $j -lt $paths.Count; $j++) {
        if ($paths[$i].Equals($paths[$j], [StringComparison]::OrdinalIgnoreCase) -or
            ($paths[$i] + '\').StartsWith($paths[$j] + '\', [StringComparison]::OrdinalIgnoreCase) -or
            ($paths[$j] + '\').StartsWith($paths[$i] + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Watch, converted, archive and working folders must be separate, with none inside another.'
        }
    }
}
$incoming,$output,$archive,$work = $paths
. (Join-Path $PSScriptRoot 'Workflow-Support.ps1')
$selectedPaths = $null
if ($SelectionPath) {
    $selectedPaths = Get-Content -LiteralPath $SelectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $selectedPaths -or -not @($selectedPaths).Count) { throw 'The selection file is empty. No inputs were processed.' }
    foreach ($selected in $selectedPaths) {
        if ($selected -isnot [string] -or -not [IO.Path]::IsPathRooted($selected) -or -not ([IO.Path]::GetFullPath($selected)).StartsWith($incoming+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Selected input paths must be files inside the watch folder.' }
    }
}
if ($ExistingOutputAction) {
    if (-not $selectedPaths -or -not @($selectedPaths).Count) { throw 'A one-run duplicate action requires a nonempty selection file.' }
    $duplicateAction = $ExistingOutputAction
}

function Fingerprint($File) {
    '{0}|{1}|{2}' -f $File.FullName, $File.Length, $File.LastWriteTimeUtc.Ticks
}
function BatchFiles($Batch) {
    if ($Batch.PSIsContainer) {
        @(Get-ChildItem -LiteralPath $Batch.FullName -File -Recurse -Force)
    } else { @($Batch) }
}
function Snapshot($Batch) {
    (@(BatchFiles $Batch | Sort-Object FullName | ForEach-Object { Fingerprint $_ }) -join "`n")
}
function Key($Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','') }
    finally { $sha.Dispose() }
}
function Log($Text) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text
    Write-Host $line
    Add-Content -LiteralPath (Join-Path $work 'automation.log') -Value $line
}

function Quote-NativeArgument([string]$Value) {
    # Quote for the Windows C runtime, including embedded quotes and final slashes.
    '"' + ([regex]::Replace(([regex]::Replace($Value, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
}
function Invoke-Converter([string]$Executable, [string[]]$Options, [string]$LogFile) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (@($Options | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $start.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    if ($sevenZipExe) {
        if (-not (Test-Path -LiteralPath $sevenZipExe -PathType Leaf)) { throw 'The selected 7-Zip executable is missing. Re-run guided setup.' }
        $start.EnvironmentVariables['PATH'] = (Split-Path $sevenZipExe -Parent) + ';' + $start.EnvironmentVariables['PATH']
    }
    if ($kindlegenExe -and $outputExtension -eq '.mobi') {
        if (-not (Test-Path -LiteralPath $kindlegenExe -PathType Leaf)) { throw 'The selected KindleGen executable is missing.' }
        $start.EnvironmentVariables['PATH'] = (Split-Path $kindlegenExe -Parent) + ';' + $start.EnvironmentVariables['PATH']
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Could not launch $Executable" }
        # Drain both streams concurrently. Decoder progress on stderr is normal.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text = $stdout.Result + "`r`n" + $stderr.Result
        if ($LogFile) { [IO.File]::WriteAllText($LogFile, $text) }
        [pscustomobject]@{ ExitCode=$process.ExitCode; Text=$text }
    } finally { $process.Dispose() }
}

function Prepare-Cbz([string]$Source, [string]$Attempt) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Source)
    try {
        $jxls = @($zip.Entries | Where-Object { $_.FullName -match '(?i)\.jxl$' })
        if (-not $jxls.Count) { return $Source }
        if (-not $convertJxl) { throw 'This CBZ contains JXL pages. Enable JPEG XL conversion to avoid losing pages.' }
        if (-not (Test-Path -LiteralPath $DjxlExe -PathType Leaf)) {
            throw "CBZ contains JPEG XL pages. Install djxl.exe at $DjxlExe or supply -DjxlExe."
        }
        Log "JXL: converting $($jxls.Count) pages in $Source"
        if ($currentSource) { $queueState[$currentSource].JxlPages=$jxls.Count; Set-QueueRecord $currentSource 'Decoding JXL' "$($jxls.Count) JXL pages are being decoded." }
        $prepared = Join-Path $Attempt 'prepared.cbz'
        $targetZip = [IO.Compression.ZipFile]::Open($prepared, 'Create')
        try {
            $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $zip.Entries) {
                if (-not $entry.Name) { continue }
                $name = $entry.FullName.Replace('\','/')
                $isJxl = $name -match '(?i)\.jxl$'
                if ($isJxl) { $name = $name.Substring(0, $name.Length - 4) + '.png' }
                if (-not $names.Add($name)) { throw "Duplicate page filename after JXL conversion: $name" }
                # Images are never extracted using archive-controlled paths.
                $pageInput = Join-Path $Attempt 'page.jxl'
                $pageOutput = Join-Path $Attempt 'page.png'
                if ($isJxl) {
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $pageInput, $true)
                    if (Test-Path -LiteralPath $pageOutput) { Remove-Item -LiteralPath $pageOutput -Force }
                    $decode = Invoke-Converter $DjxlExe @($pageInput,$pageOutput) (Join-Path $Attempt 'djxl.log')
                    if ($decode.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pageOutput)) {
                        throw "JXL decoding failed for $($entry.FullName); see $Attempt\djxl.log"
                    }
                    $stream = [IO.File]::OpenRead($pageOutput)
                    try {
                        $signature = New-Object byte[] 8
                        $read = $stream.Read($signature,0,8)
                        if ($read -ne 8 -or [BitConverter]::ToString($signature) -ne '89-50-4E-47-0D-0A-1A-0A') {
                            throw "Decoder produced no valid PNG header for $($entry.FullName)"
                        }
                    } finally { $stream.Dispose() }
                }
                $newEntry = $targetZip.CreateEntry($name, [IO.Compression.CompressionLevel]::NoCompression)
                $to = $newEntry.Open()
                $from = $null
                try {
                    if ($isJxl) { $from = [IO.File]::OpenRead($pageOutput) } else { $from = $entry.Open() }
                    $from.CopyTo($to)
                } finally { if ($from) { $from.Dispose() }; $to.Dispose() }
            }
        } finally { $targetZip.Dispose() }
        return $prepared
    } finally { $zip.Dispose() }
}

function Archive-Batch($Batch, [string]$Destination, [string]$ExpectedSnapshot) {
    $sourcePath = [IO.Path]::GetFullPath($Batch.FullName)
    $inputPrefix = [IO.Path]::GetFullPath($incoming).TrimEnd('\') + '\'
    if (-not $sourcePath.StartsWith($inputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a source outside Incoming: $sourcePath"
    }
    if ($Batch.PSIsContainer) {
        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            throw "Archive folder conflicts with an existing file: $Destination"
        }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        # Create empty directories too. Copy by explicit relative paths so that
        # an existing archive never gains an extra nested copy of the batch.
        foreach ($dir in @(Get-ChildItem -LiteralPath $sourcePath -Directory -Recurse -Force)) {
            $relative = $dir.FullName.Substring($sourcePath.Length).TrimStart('\')
            New-Item -ItemType Directory -Path (Join-Path $Destination $relative) -Force | Out-Null
        }
    } elseif (Test-Path -LiteralPath $Destination -PathType Container) {
        throw "Archive file conflicts with an existing folder: $Destination"
    }
    $copied = @()
    foreach ($file in @(BatchFiles $Batch)) {
        $target = $Destination
        if ($Batch.PSIsContainer) {
            $relative = $file.FullName.Substring($sourcePath.Length).TrimStart('\')
            $target = Join-Path $Destination $relative
        }
        if (Test-Path -LiteralPath $target -PathType Container) {
            throw "Archive file conflicts with an existing folder: $target"
        }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $copied += [pscustomobject]@{ Path=$target; Hash=$hash }
    }
    foreach ($item in $copied) {
        if ((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Hash) {
            throw "Archive verification failed; originals retained: $($item.Path)"
        }
    }
    if ((Snapshot $Batch) -ne $ExpectedSnapshot) {
        throw "Source changed while archiving; originals retained: $sourcePath"
    }
    # The absolute source was checked against Incoming above. Delete only after
    # every archive copy has been verified, leaving sources intact on copy errors.
    Remove-Item -LiteralPath $sourcePath -Recurse -Force
}

function Assert-ApprovedKcc($Check) {
    if (-not $approvedKccVersion) { return }
    $version = [regex]::Match($Check.Text, '(?im)^comic2ebook[^\r\n]*?v?(\d+\.\d+\.\d+)(?=\s|$)')
    if ($Check.ExitCode -ne 0 -or -not $version.Success -or $version.Groups[1].Value -ne $approvedKccVersion) {
        throw "This KCCAutomate release requires the approved KCC $approvedKccVersion c2e executable. Choose its Windows CLI download in guided setup. Newer KCC builds require maintainer testing and a KCCAutomate update. Originals were retained."
    }
}

if ($CheckSetup) {
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -PathType Container) { Write-Output "OK folder: $path" }
        else { Write-Output "Folder unavailable or not created yet: $path" }
    }
    if (-not (Test-Path -LiteralPath $KccExe -PathType Leaf)) { throw "Select the KCC command-line converter: $KccExe" }
    $check = Invoke-Converter $KccExe @('--help') ''
    Write-Output $check.Text
    Assert-ApprovedKcc $check
    if ($check.ExitCode -ne 0) { throw 'KCC could not start. Check its installation and dependencies above.' }
    if ($convertJxl) {
        if (-not (Test-Path -LiteralPath $DjxlExe -PathType Leaf)) { throw "Select djxl.exe to enable JPEG XL conversion: $DjxlExe" }
        $check = Invoke-Converter $DjxlExe @('--help') ''
        Write-Output $check.Text
        if ($check.ExitCode -ne 0) { throw 'The JPEG XL decoder could not start.' }
    }
    Write-Output 'Setup check finished. Run Preview next. MOBI conversion also requires KindleGen beside KCC or detectable by KCC.'
    return
}
if (-not (Test-Path -LiteralPath $incoming -PathType Container)) {
    Write-Host '@@FOLDERS:Watch folder is unavailable. Check the drive, connection and account permissions.'
    throw "Incoming folder is unavailable: $incoming"
}
Write-Host '@@FOLDERS:Watch folder is reachable. Output and archive folders are created on demand.'
if ($Preview) {
    Get-PreviewQueue
    return
}
if (-not $CleanupOnly -and -not (Test-Path -LiteralPath $KccExe -PathType Leaf)) {
    throw "KCC CLI not found: $KccExe. Install the c2e command-line build, or supply -KccExe with its actual path."
}
if (-not $CleanupOnly -and $approvedKccVersion) {
    $check = Invoke-Converter $KccExe @('--help') ''
    Assert-ApprovedKcc $check
}
foreach ($dir in @($output,$archive,$work)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
# Exclusive SMB file handle prevents simultaneous runs, including other PCs.
try { $lock = [IO.File]::Open((Join-Path $work 'running.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { throw "Cannot acquire workflow lock (another run may be active): $_" }
$failed = $false
try {
    Read-QueueHistory
    $queuePersistent = $true
    if ($CleanupOnly) { Remove-ExpiredAttempts; Log 'Workspace cleanup finished. Receipts and originals were retained.'; return }
    Log 'Starting scan.'
    $batches = @(Get-ChildItem -LiteralPath $incoming -Force |
        Where-Object { $_.Name -notlike 'KCC-*' -and ($_.PSIsContainer -or $_.Extension.ToLowerInvariant() -in $inputExtensions) })
    $plans = @()
    foreach ($batch in $batches) {
        $files=@()
        try {
            $files = @(BatchFiles $batch)
            if (($batch.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                @((Get-ChildItem -LiteralPath $batch.FullName -Recurse -Force -ErrorAction Stop) | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
                throw 'Linked files or folders are not processed. Use a regular folder.'
            }
            $cbzs = @($files | Where-Object { $_.Extension.ToLowerInvariant() -in $inputExtensions })
            if ($selectedPaths -and -not @($cbzs | Where-Object { $_.FullName -in $selectedPaths }).Count) { continue }
            if (-not $cbzs.Count) { Log "SKIP no selected input formats: $($batch.FullName)"; continue }
            if (@($files | Where-Object { $_.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddMinutes(-$QuietMinutes) -or $_.Extension -in @('.part','.tmp','.crdownload','.download') }).Count) {
                foreach ($file in $cbzs) { Set-QueueRecord $file.FullName 'Waiting for download' 'Recent or partial files exist in this batch.' }
                Log "WAIT recent or partial files: $($batch.FullName)"; continue
            }
            $before = Snapshot $batch
            $archivePath = Join-Path $archive $batch.Name
            # Probe exclusive access; this detects many, but not all, active downloads.
            foreach ($file in $files) {
                $handle = [IO.File]::Open($file.FullName,'Open','Read','None')
                $handle.Dispose()
            }
            $destinations = @{}
            foreach ($file in $cbzs) {
                Select-Conversion $file
                $name = Join-Path (Split-Path $file.FullName -Parent) (Get-OutputName $file)
                if ($destinations.ContainsKey($name)) { throw "Multiple inputs would create the same output: $name. Move them into separate folders." }
                $destinations[$name] = $true
                if (-not $selectedPaths -or $file.FullName -in $selectedPaths) { Set-QueueRecord $file.FullName 'Waiting' 'Queued for this run.' }
                elseif (-not $queueState.ContainsKey($file.FullName)) { Set-QueueRecord $file.FullName 'Waiting' 'Not selected for this retry.' }
                $queueState[$file.FullName].Fingerprint=Fingerprint $file
            }
            $plans += [pscustomobject]@{ Batch=$batch; Files=$cbzs; Before=$before; ArchivePath=$archivePath; Failed=$false }
        } catch { $failed = $true; Log "ERROR $($batch.Name): $_"; foreach ($file in @($files | Where-Object { $_.Extension.ToLowerInvariant() -in $inputExtensions })) { $kind=Get-ConflictKind ([string]$_); Set-QueueRecord $file.FullName $(if($kind){'Conflict'}else{'Failed'}) ([string]$_) '' $kind } }
    }
    # Reserve all planned names, including loose files in separate batches.
    $reservedOutputs=@{}
    foreach ($plan in $plans) {
        foreach ($file in $plan.Files) {
            Select-Conversion $file
            $relative=$file.FullName.Substring($incoming.Length).TrimStart('\')
            $target=Join-Path (Join-Path $output (Split-Path $relative -Parent)) (Get-OutputName $file)
            if (-not $reservedOutputs.ContainsKey($target)) { $reservedOutputs[$target]=@() }
            $reservedOutputs[$target] += [pscustomobject]@{Plan=$plan;Source=$file.FullName}
        }
    }
    foreach ($target in @($reservedOutputs.Keys)) {
        if ($reservedOutputs[$target].Count -lt 2) { continue }
        $failed=$true
        foreach ($item in $reservedOutputs[$target]) {
            $item.Plan.Failed=$true
            Set-QueueRecord $item.Source 'Conflict' 'Multiple selected inputs would create the same output. Rename one or use separate folders.' $target 'MultipleInputs'
        }
        Log "ERROR Multiple inputs would create the same output: $target"
    }
    # Format phases guarantee PDFs start only after all eligible CBZs finish.
    foreach ($extension in @('.cbz','.pdf','.epub','.cbr','.cb7') | Where-Object { $_ -in $inputExtensions }) {
        foreach ($plan in $plans) {
            if ($plan.Failed) { continue }
            foreach ($cbz in @($plan.Files | Where-Object { $_.Extension.ToLowerInvariant() -eq $extension })) {
              if ($selectedPaths -and $cbz.FullName -notin $selectedPaths) { continue }
              if ($StopFile -and (Test-Path -LiteralPath $StopFile)) { Log 'STOP requested. Current file finished; remaining inputs stay in place.'; exit 2 }
              try {
                $currentSource=$cbz.FullName
                Select-Conversion $cbz
                $relative = $cbz.FullName.Substring($incoming.Length).TrimStart('\')
                $dest = Join-Path $output (Split-Path $relative -Parent)
                $job = Get-JobFolder $cbz
                $receiptPath = Join-Path $job 'receipt.json'
                if (Test-Path -LiteralPath $receiptPath) {
                    $validReceipt=$false
                    try { $validReceipt=Test-Receipt $cbz } catch { $validReceipt=$false }
                    if ($validReceipt) {
                        Log "ALREADY CONVERTED: $relative"
                        Set-QueueRecord $cbz.FullName 'Converted' 'Verified an existing completed conversion.'
                        continue
                    }
                    if ($duplicateAction -eq 'Review') { throw 'Previously published output is missing or changed. Choose Replace or Keep both for this conflict, or restore the verified output.' }
                }
                $nominalTarget=Join-Path $dest (Get-OutputName $cbz)
                if ($duplicateAction -eq 'Skip' -and (Test-Path -LiteralPath $nominalTarget -PathType Leaf)) {
                    Set-QueueRecord $cbz.FullName 'Skipped existing output' 'Existing output kept. Incoming originals stay in place until a conversion is verified.' $nominalTarget
                    Log "SKIPPED existing output; incoming retained: $relative"
                    continue
                }
                New-Item -ItemType Directory -Path $job -Force | Out-Null
                # A fresh attempt directory preserves failed attempts for diagnosis.
                $attempt = Join-Path $job ([Guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $attempt | Out-Null
                $conversionSource = $cbz.FullName
                if ($extension -eq '.cbz') { $conversionSource = Prepare-Cbz $cbz.FullName $attempt }
                Log "CONVERT: $relative"
                Set-QueueRecord $cbz.FullName 'Converting' 'KCC is creating the book.'
                # KindleGen is a legacy program: keep its EPUB/MOBI paths short.
                # KCC accepts an explicit MOBI filename and uses the same short
                # stem for its intermediate EPUB. Restore the source name below.
                $shortOutput = Join-Path $attempt ('book' + $outputExtension)
                $titleArguments = @()
                if ($conversionSource -ne $cbz.FullName) { $titleArguments = @('--title', $cbz.BaseName) }
                $conversion = Invoke-Converter $KccExe ($arguments + $titleArguments + @('--output',$shortOutput,$conversionSource)) (Join-Path $job 'kcc.log')
                if ($conversion.ExitCode -ne 0) { throw "KCC failed; see $job\kcc.log" }
                $books = @(Get-ChildItem -LiteralPath $attempt -File | Where-Object { $_.Name -like ('book*' + $outputExtension) })
                if (-not $books.Count -or @($books | Where-Object Length -EQ 0).Count) { throw "KCC produced no usable output: $relative. See $job\kcc.log and any kindlegen-log files in $attempt" }
                if ((Fingerprint (Get-Item -LiteralPath $cbz.FullName)) -ne (Fingerprint $cbz)) { throw "Source changed during conversion: $relative" }
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                $publication=Publish-ConvertedBooks $cbz $books $dest $duplicateAction
                if ($publication.Skipped) {
                    Set-QueueRecord $cbz.FullName 'Skipped existing output' 'Existing split output kept. Incoming originals stay in place until a conversion is verified.' $publication.Target
                    Log "SKIPPED existing output; incoming retained: $relative"
                    continue
                }
                $receipt=@($publication.Receipt)
                ConvertTo-Json -InputObject $receipt | Set-Content -LiteralPath $receiptPath -Encoding UTF8
                [IO.File]::WriteAllText((Join-Path $attempt 'result.json'), '{"Succeeded":true}')
                Set-QueueRecord $cbz.FullName 'Converted' 'Output verified; waiting for the rest of its batch.' $receipt[0].Path
              } catch { $plan.Failed = $true; $failed = $true; Log "ERROR $($plan.Batch.Name): $_"; $kind=Get-ConflictKind ([string]$_); Set-QueueRecord $cbz.FullName $(if($kind){'Conflict'}else{'Failed'}) ([string]$_) (Join-Path $dest (Get-OutputName $cbz)) $kind; break }
            }
        }
    }
    foreach ($plan in $plans) {
        if ($StopFile -and (Test-Path -LiteralPath $StopFile)) { Log 'STOP requested. Originals retained; verified conversions can resume next time.'; exit 2 }
        if ($plan.Failed) { continue }
        try {
            $complete=$true
            foreach ($file in $plan.Files) { Select-Conversion $file; if (-not (Test-Receipt $file)) { $complete=$false; break } }
            if (-not $complete) { Log "WAIT $($plan.Batch.Name): other selected inputs still need successful conversions."; continue }
            if ((Snapshot $plan.Batch) -ne $plan.Before) { throw "Batch changed; originals left in place: $($plan.Batch.Name)" }
            Archive-Batch $plan.Batch $plan.ArchivePath $plan.Before
            Log "ARCHIVED: $($plan.Batch.Name)"
            foreach ($file in $plan.Files) { Set-QueueRecord $file.FullName 'Archived' 'Conversion and archive copy verified.' }
        } catch { $failed = $true; Log "ERROR $($plan.Batch.Name): $_"; foreach ($file in $plan.Files) { Set-QueueRecord $file.FullName 'Failed' ([string]$_) } }
    }
    Log 'Scan finished.'
    Remove-ExpiredAttempts
    if ($config -and $config.NotificationMode -and $config.NotificationMode -ne 'Off') {
        & (Join-Path $PSScriptRoot 'Notify-Result.ps1') -ConfigPath $ConfigPath -Failed:$failed
    }
} finally { $lock.Dispose() }
if ($failed) { exit 1 }
