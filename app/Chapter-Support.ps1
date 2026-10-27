# Optional CBZ chapter grouping. Source archives are read, never rewritten.
function Get-BundleOptions {
    $chapters=$config -and [bool]$config.BundleChapters
    $volumes=$config -and [bool]$config.BundleVolumes
    $enabled=$chapters -or $volumes
    $volumePages=600
    if($config -and $config.PSObject.Properties['VolumeTargetPages']){$volumePages=[int]$config.VolumeTargetPages}
    if($volumePages -lt 100 -or $volumePages -gt 5000){throw 'Volume grouping needs a target between 100 and 5000 source pages.'}
    $pages=200; $chapter=100; $size=350; $hold=$false
    if ($config -and $config.PSObject.Properties['BundleTargetPages']) { $pages=[int]$config.BundleTargetPages }
    if ($config -and $config.PSObject.Properties['ChapterPageThreshold']) { $chapter=[int]$config.ChapterPageThreshold }
    if ($config -and $config.PSObject.Properties['BundleMaxMiB']) { $size=[int]$config.BundleMaxMiB }
    if ($config -and $config.PSObject.Properties['HoldShortBundles']) { $hold=[bool]$config.HoldShortBundles }
    if ($pages -lt 50 -or $pages -gt 1000 -or $chapter -lt 1 -or $chapter -gt $pages -or $size -lt 10 -or $size -gt 390) {
        throw 'Chapter grouping needs a 50-1000 page target, a chapter threshold no higher than that target, and a 10-390 MiB size budget.'
    }
    [pscustomobject]@{Enabled=$enabled;Chapters=$chapters;Volumes=$volumes;VolumePages=$volumePages;Pages=$pages;ChapterThreshold=$chapter;MaxMiB=$size;Hold=$hold}
}
function Get-BundleKey($File) {
    if (-not $bundleOptions.Enabled -or $File.Extension -ne '.cbz') { return '' }
    # Grouping preferences apply to unconverted chapters. Keep published groups
    # stable when a user changes the page target or releases a short remainder.
    '|chapter-bundles-v1'
}
function Read-ChapterReceipts {
    if ($script:chapterReceiptsLoaded) { return }
    $ledger=@{}; $path=Join-Path $work 'chapter-receipts.json'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($saved.Version -ne 1 -or -not $saved.Entries) { throw 'Invalid chapter completion records.' }
            foreach ($entry in $saved.Entries.PSObject.Properties) { $ledger[$entry.Name]=@($entry.Value) }
        } catch { throw ('Chapter completion records could not be read. Preserve chapter-receipts.json and restore its .bak copy before resuming grouping. '+$_) }
    }
    $script:chapterReceipts=$ledger; $script:chapterReceiptsLoaded=$true
}
function Get-ChapterReceipt($File) {
    if (-not $bundleOptions.Enabled -or $File.Extension -ine '.cbz') { return }
    Read-ChapterReceipts
    $id=Split-Path (Get-JobFolder $File) -Leaf
    if ($chapterReceipts.ContainsKey($id)) { $chapterReceipts[$id] }
}
function Save-ChapterReceipts($Members,$Receipt) {
    Read-ChapterReceipts
    $next=@{}; foreach ($id in $chapterReceipts.Keys) { $next[$id]=$chapterReceipts[$id] }
    foreach ($info in $Members) { Select-Conversion $info.File; $id=Split-Path (Get-JobFolder $info.File) -Leaf; $next[$id]=@($Receipt) }
    $path=Join-Path $work 'chapter-receipts.json'
    $temp=Join-Path $work ('chapter-receipts-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject @{Version=1;Entries=$next} -Depth 8),[Text.UTF8Encoding]::new($false))
    # All chapter members become complete in one filesystem operation, so a
    # partial member-by-member receipt save cannot regroup half a published book.
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temp,$path,$path+'.bak') } else { [IO.File]::Move($temp,$path) }
    $script:chapterReceipts=$next
}
function Natural-Key([string]$Text) {
    [regex]::Replace($Text.ToLowerInvariant(),'\d+',{param($match) $match.Value.PadLeft(16,'0')})
}
function Image-Entries($Zip) {
    @($Zip.Entries | Where-Object { $_.Name -and $_.FullName -notmatch '(^|[/\\])(__MACOSX|\.)' -and $_.FullName -match '(?i)\.(jpe?g|png|gif|webp|bmp|tiff?|jxl)$' } | Sort-Object {Natural-Key $_.FullName})
}
function Remove-LeadingBookTags([string]$Name) {
    # Remove only complete square-bracketed prefixes. Keep brackets within a
    # title, parentheses and malformed prefixes rather than guessing their role.
    [regex]::Replace($Name,'^\s*(?:\[[^\[\]]*\]\s*)+','')
}
function Get-FilenameBookMarker([string]$Name) {
    # Ignore release annotations when locating a marker, while keeping indexes
    # into the original name for an exact, lossless cut after its number.
    $search=[regex]::Replace($Name,'\([^)]*\)|\[[^\]]*\]',{param($m) ' '*$m.Length})
    $pattern='(?i)(?:^|[\s._-])(?<marker>volume|vol|v|chapter|chap|ch|c)\.?\s*(?<n>(?>\d+(?:\.\d+)?))(?![\p{L}\p{N}]|\.\d)'
    $markers=@([regex]::Matches($search,$pattern))
    if(-not $markers.Count){return $null}
    # A filename can include internal chapter details after its volume number.
    $volumes=@($markers | Where-Object {$_.Groups['marker'].Value -match '^(?i:v|vol|volume)$'})
    $match=if($volumes.Count){$volumes[0]}else{$markers[0]}
    $kind=if($match.Groups['marker'].Value -match '^(?i:v|vol|volume)$'){'Vol.'}else{'Ch.'}
    $end=$match.Index+$match.Length
    $range=[regex]::Match($search.Substring($end),'(?i)^\s*[-~\u2013\u2014]\s*(?:(?:volume|vol|v|chapter|chap|ch|c)\.?\s*)?(?<n>(?>\d+(?:\.\d+)?))(?![\p{L}\p{N}]|\.\d)')
    if($range.Success){$end+=$range.Length}
    $tokenStart=$match.Groups['marker'].Index
    [pscustomobject]@{Kind=$kind;NumberText=$match.Groups['n'].Value;IsRange=$range.Success;Series=(Remove-LeadingBookTags $Name.Substring(0,$match.Index)).Trim(' ','-','_','.');Token=$Name.Substring($tokenStart,$end-$tokenStart);CleanName=(Remove-LeadingBookTags $Name.Substring(0,$end).Trim())}
}
function Get-FolderBookSeries($File,$Marker) {
    if(-not $Marker -or $Marker.Series){return ''}
    $name=(Remove-LeadingBookTags ([IO.Path]::GetFileNameWithoutExtension($File.FullName))).Trim()
    $numberOnly='^'+[regex]::Escape($Marker.Token)+'\s*(?:(?:\([^()]*\)|\[[^\[\]]*\])\s*)*$'
    if($name -notmatch $numberOnly){return ''}
    $parent=[IO.Path]::GetDirectoryName($File.FullName)
    # The watch folder itself is not a series. Never search upwards through
    # artist/collection folders when the immediate parent is uninformative.
    if(-not $parent -or $parent -ieq $incoming){return ''}
    $series=(Remove-LeadingBookTags ([IO.Path]::GetFileName($parent))).Trim(' ','-','_','.')
    # Only discard recognizable release annotations, preserving title text
    # such as "Series (The Beginning)" when there is no filename to confirm it.
    $suffix=[regex]::Match($series,'(?i)\s*(?:\((?:Digital|Scan|Web|HQ)[^()]*\)|\[[^\[\]]*\])(?:\s*(?:\([^()]*\)|\[[^\[\]]*\]))*\s*$')
    if($suffix.Success){$series=$series.Substring(0,$suffix.Index).Trim(' ','-','_','.')}
    $parentMarker=Get-FilenameBookMarker $series
    if(-not $series -or $series -match '^\d+(?:\.\d+)?$' -or ($parentMarker -and -not $parentMarker.Series)){return ''}
    return $series
}
function Read-CbzInfo($File) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($File.FullName)
    try {
        $images=@(Image-Entries $zip)
        if (-not $images.Count) { throw ('No image pages found: '+$File.Name) }
        $series=''; $number=''; $writer=''; $cover=$images[0].FullName; $marked=$false
        $xmlEntry=@($zip.Entries | Where-Object { $_.FullName.Replace('\','/') -ieq 'ComicInfo.xml' })
        if ($xmlEntry.Count -eq 1 -and $xmlEntry[0].Length -le 1048576) {
            $stream=$xmlEntry[0].Open(); $reader=$null
            try {
                $settings=New-Object Xml.XmlReaderSettings
                $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit; $settings.XmlResolver=$null; $settings.MaxCharactersInDocument=1048576
                $reader=[Xml.XmlReader]::Create($stream,$settings)
                $xml=New-Object Xml.XmlDocument; $xml.XmlResolver=$null; $xml.Load($reader)
                $series=[string]$xml.ComicInfo.Series
                $number=[string]$xml.ComicInfo.Number
                $writer=[string]$xml.ComicInfo.Writer
                $front=@($xml.SelectNodes('/ComicInfo/Pages/Page') | Where-Object { $_.GetAttribute('Type') -ieq 'FrontCover' })
                $index=0
                if ($front.Count -eq 1 -and [int]::TryParse($front[0].GetAttribute('Image'),[ref]$index) -and $index -ge 0 -and $index -lt $images.Count) { $cover=$images[$index].FullName; $marked=$true }
            } catch { $series=''; $number=''; $writer=''; $cover=$images[0].FullName; $marked=$false }
            finally { if ($reader) { $reader.Dispose() }; $stream.Dispose() }
        }
        $marker=Get-FilenameBookMarker $File.BaseName
        $numberRange=if($marker){[bool]$marker.IsRange}else{$number -match '^\d+\s*[-~]\s*\d+$'}
        if($marker){
            $number=$marker.NumberText
            if($marker.Series){$series=$marker.Series}
        }
        $folderSeries=Get-FolderBookSeries $File $marker
        if($folderSeries){$series=$folderSeries}
        # Without an explicit marker, retain metadata/parent/page-count inference.
        if (-not $number) { $bare=[regex]::Match($File.BaseName,'^\s*(?<n>\d+(?:\.\d+)?)\s*$'); if ($bare.Success) { $number=$bare.Groups['n'].Value } }
        if (-not $series -and $File.DirectoryName -ne $incoming) { $series=$File.Directory.Name }
        $series=([regex]::Replace($series,'\s*(\[[^\]]*\]|\((?:Digital|Scan|Web|HQ)[^)]*\))\s*',' ')).Trim(' ','-','_','.')
        $ordinal=[decimal]0
        $hasNumber=[decimal]::TryParse($number,[Globalization.NumberStyles]::AllowDecimalPoint,[Globalization.CultureInfo]::InvariantCulture,[ref]$ordinal) -and $ordinal -ge 0
        $isChapter=if($marker){$marker.Kind -eq 'Ch.' -and -not $numberRange}else{-not $numberRange -and $images.Count -lt $bundleOptions.ChapterThreshold}
        $kind=if($marker){$marker.Kind}elseif($isChapter){'Ch.'}else{'Vol.'}
        $reason=if($numberRange){'Existing number range; kept separate.'}elseif($marker){'Explicit '+$kind+' filename marker.'}elseif(-not $isChapter){'Volume-sized input; kept separate.'}elseif(-not $hasNumber -or -not $series){'Short input, but its series/chapter number is unclear. Rename it with a series and Ch. number.'}else{'Likely chapter from its page count.'}
        [pscustomobject]@{File=$File;Pages=$images.Count;Series=$series;Writer=$writer;Kind=$kind;Number=$ordinal;HasNumber=$hasNumber;HasNumberRange=[bool]$numberRange;HasChapterLabel=($marker -and $marker.Kind -eq 'Ch.');IsExplicitVolume=($marker -and $marker.Kind -eq 'Vol.');IsChapter=$isChapter;CanGroup=($hasNumber -and [bool]$series -and -not $numberRange);FilenameMarker=$marker;FolderSeries=$folderSeries;CoverEntry=$cover;MarkedCover=$marked;Reason=$reason;JxlPages=@($images | Where-Object {$_.FullName -match '(?i)\.jxl$'}).Count}
    } finally { $zip.Dispose() }
}
function Bundle-Name($Members) {
    $first=$Members[0]; $last=$Members[-1]
    $digits=if((Get-LabelStyle) -eq 'Clean' -and $first.Kind -eq 'Vol.'){'00.###'}else{'000.###'}
    $start=$first.Number.ToString($digits,[Globalization.CultureInfo]::InvariantCulture)
    $end=$last.Number.ToString($digits,[Globalization.CultureInfo]::InvariantCulture)
    if((Get-LabelStyle) -ne 'Original'){return Format-BookLabel $first.Series ($start+$(if($Members.Count -gt 1){'-'+$end}else{''})) $first.Kind}
    $suffix=' - '+$first.Kind+' '+$start+$(if($Members.Count -gt 1){'-'+$end}else{''})
    $series=[regex]::Replace($first.Series,'[<>:"/\\|?*\x00-\x1f]','_').Trim(' ','.')
    if ($series.Length -gt 150) { $series=$series.Substring(0,150).TrimEnd(' ','.') }
    $series+$suffix
}
function Bundle-File($Members) {
    [pscustomobject]@{FullName=$Members[0].File.FullName;BaseName=(Bundle-Name $Members);Extension='.cbz';IsBundle=$true}
}
function New-BundlePlan($Files) {
    $groups=@(); $states=@{}; $candidates=@()
    foreach ($file in @($Files | Where-Object {$_.Extension -ieq '.cbz'})) {
        Select-Conversion $file
        try { $info=Read-CbzInfo $file } catch { $states[$file.FullName]=[pscustomobject]@{State='Failed';Detail=[string]$_;Group=$null}; continue }
        if(($info.IsChapter -and -not $bundleOptions.Chapters) -or (-not $info.IsChapter -and -not $bundleOptions.Volumes)){continue}
        if($info.IsChapter -and $info.Pages -gt $bundleOptions.Pages){continue}
        if(-not $info.IsChapter -and (-not $info.CanGroup -or $info.Pages -gt $bundleOptions.VolumePages -or ($info.HasChapterLabel -and -not $info.IsExplicitVolume))){continue}
        if (Test-Receipt $file) { $states[$file.FullName]=[pscustomobject]@{State='Converted';Detail='Previously completed chapter bundle verified.';Group=$null}; continue }
        if (-not $info.CanGroup) { $states[$file.FullName]=[pscustomobject]@{State='Waiting';Detail=$info.Reason;Group=$null}; continue }
        if ($selectedPaths -and $file.FullName -notin $selectedPaths) { $states[$file.FullName]=[pscustomobject]@{State='Waiting';Detail='Not selected for this retry.';Group=$null}; continue }
        # Never mix folders, series, output formats, or different effective presets.
        $info | Add-Member -NotePropertyName GroupKey -NotePropertyValue ($file.DirectoryName+'|'+$info.Series+'|'+$info.Kind+'|'+($arguments -join ' ')+'|'+$activeNaming)
        $candidates+=$info
    }
    foreach ($partition in @($candidates | Group-Object GroupKey)) {
        $ordered=@($partition.Group | Sort-Object Number)
        $targetPages=if($ordered[0].IsChapter){$bundleOptions.Pages}else{$bundleOptions.VolumePages}
        if (@($ordered | Group-Object Number | Where-Object Count -gt 1).Count) {
            foreach ($info in $ordered) { $states[$info.File.FullName]=[pscustomobject]@{State='Failed';Detail='Duplicate chapter numbers found in one series/folder. Resolve the duplicate before grouping.';Group=$null} }
            continue
        }
        $members=@(); $pages=0; $last=$null
        foreach ($info in $ordered) {
            $gap=$last -and ($info.Number-$last.Number -gt 1)
            if ($members.Count -and ($gap -or $pages+$info.Pages -gt $targetPages)) {
                $ready=(-not $gap) -or -not $bundleOptions.Hold
                $groups += [pscustomobject]@{Members=$members;Pages=$pages;Ready=$ready;Name=(Bundle-Name $members)}
                $members=@(); $pages=0
            }
            $members+=$info; $pages+=$info.Pages; $last=$info
            if ($pages -ge $targetPages) {
                $groups += [pscustomobject]@{Members=$members;Pages=$pages;Ready=$true;Name=(Bundle-Name $members)}
                $members=@(); $pages=0; $last=$null
            }
        }
        if ($members.Count) { $groups += [pscustomobject]@{Members=$members;Pages=$pages;Ready=(-not $bundleOptions.Hold);Name=(Bundle-Name $members)} }
    }
    foreach ($group in $groups) {
        foreach ($info in $group.Members) {
            $limit=if($group.Members[0].IsChapter){$bundleOptions.Pages}else{$bundleOptions.VolumePages}
            $detail=if($group.Ready){'Book bundle: '+$group.Name+' ('+$group.Pages+' source pages).'}else{'Waiting for more chapters or volumes: '+$group.Name+' ('+$group.Pages+'/'+$limit+' source pages).'}
            $states[$info.File.FullName]=[pscustomobject]@{State='Waiting';Detail=$detail;Group=$group}
        }
    }
    [pscustomobject]@{Groups=$groups;States=$states}
}
function Write-BundleSource($Members,[string]$Attempt) {
    $combined=Join-Path $Attempt 'chapters.cbz'
    $target=[IO.Compression.ZipFile]::Open($combined,'Create')
    try {
        $chapterIndex=0
        foreach ($info in $Members) {
            $chapterIndex++
            $folder=Join-Path $Attempt ('c'+$chapterIndex)
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $prepared=Prepare-Cbz $info.File.FullName $folder
            $zip=[IO.Compression.ZipFile]::OpenRead($prepared)
            try {
                $page=0; $cover=$info.CoverEntry.Replace('\','/')
                if ($cover -match '(?i)\.jxl$') { $cover=[IO.Path]::ChangeExtension($cover,'.png') }
                foreach ($entry in @(Image-Entries $zip)) {
                    $page++
                    $name=('{0:0000} - {1} {2}/{3:000000}{4}' -f $chapterIndex,$info.Kind,$info.Number.ToString('000.###',[Globalization.CultureInfo]::InvariantCulture),$page,[IO.Path]::GetExtension($entry.Name).ToLowerInvariant())
                    $source=$entry.Open(); $destination=$target.CreateEntry($name,[IO.Compression.CompressionLevel]::NoCompression).Open()
                    try { $source.CopyTo($destination) } finally {$source.Dispose();$destination.Dispose()}
                    if ($chapterIndex -eq 1 -and $entry.FullName.Replace('\','/') -ceq $cover) {
                        $start=$Members[0].Number.ToString('000.###',[Globalization.CultureInfo]::InvariantCulture)
                        $end=$Members[-1].Number.ToString('000.###',[Globalization.CultureInfo]::InvariantCulture)
                        Write-BookCover $entry $Attempt ($Members[0].Kind.ToUpperInvariant()+' '+$start+$(if($Members.Count -gt 1){'-'+$end}else{''}))
                    }
                }
            } finally { $zip.Dispose() }
            if ((Fingerprint (Get-Item -LiteralPath $info.File.FullName)) -ne (Fingerprint $info.File)) { throw ('Source changed during chapter preparation: '+$info.File.Name) }
        }
        $metadata=New-Object Xml.XmlDocument
        $comic=$metadata.CreateElement('ComicInfo'); $metadata.AppendChild($comic) | Out-Null
        $series=$metadata.CreateElement('Series'); $series.InnerText=$Members[0].Series; $comic.AppendChild($series) | Out-Null
        $writers=@($Members | ForEach-Object Writer | Where-Object {$_} | Select-Object -Unique)
        if ($writers.Count) { $writer=$metadata.CreateElement('Writer'); $writer.InnerText=$writers -join ', '; $comic.AppendChild($writer) | Out-Null }
        $stream=$target.CreateEntry('ComicInfo.xml').Open()
        try { $metadata.Save($stream) } finally { $stream.Dispose() }
    } finally { $target.Dispose() }
    return $combined
}
function Invoke-ChapterGroups($Plan) {
    foreach ($group in @($Plan.Bundles.Groups | Where-Object Ready)) {
        $remaining=@($group.Members)
        while ($remaining.Count) {
            if ($StopFile -and (Test-Path -LiteralPath $StopFile)) { throw 'Stop requested. Chapter originals were retained.' }
            $members=@($remaining)
            while ($members.Count) {
                $first=$members[0].File; $currentSource=$first.FullName
                Select-Conversion $first
                $virtual=Bundle-File $members
                $dest=Get-OutputDirectory $first
                $job=Get-JobFolder $first; New-Item -ItemType Directory -Path $job -Force | Out-Null
                $attempt=Join-Path $job ([Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $attempt | Out-Null
                foreach ($info in $members) { Set-QueueRecord $info.File.FullName 'Converting' ('Creating '+$virtual.BaseName) }
                $source=Write-BundleSource $members $attempt
                $shortOutput=Join-Path $attempt ('book'+$outputExtension)
                $title=[IO.Path]::GetFileNameWithoutExtension((Get-OutputName $virtual))
                Log ('BUNDLE: '+$title+' ('+(@($members | ForEach-Object Pages | Measure-Object -Sum).Sum)+' source pages)')
                $conversion=Invoke-Converter $KccExe ($arguments+@('--title',$title,'--targetsize',[string]$bundleOptions.MaxMiB,'--output',$shortOutput,$source)) (Join-Path $attempt 'kcc.log')
                if ($conversion.ExitCode -ne 0) { throw ('KCC failed for chapter bundle; see '+$attempt+'\kcc.log') }
                $books=@(Get-ChildItem -LiteralPath $attempt -File | Where-Object {$_.Name -like ('book*'+$outputExtension)})
                if (-not $books.Count -or @($books | Where-Object Length -eq 0).Count) { throw ('KCC produced no usable output for the chapter bundle; see '+$attempt+'\kcc.log') }
                $size=($books | Measure-Object Length -Sum).Sum
                if ($books.Count -gt 1 -or $size -gt $bundleOptions.MaxMiB*1048576) {
                    if ($members.Count -eq 1) { throw 'A single chapter exceeds the configured size budget, or a single volume cannot fit whole. Raise the budget or convert this input with grouping off.' }
                    [IO.File]::WriteAllText((Join-Path $attempt 'result.json'),'{"Succeeded":false,"Reason":"Size budget; retried with fewer chapters"}')
                    $members=@($members | Select-Object -First ($members.Count-1))
                    continue
                }
                foreach ($info in $members) { if ((Fingerprint (Get-Item -LiteralPath $info.File.FullName)) -ne (Fingerprint $info.File)) { throw 'A chapter changed during conversion. Originals retained.' } }
                $target=Join-Path $dest (Get-OutputName $virtual)
                $owner=$group.Members[0].File.FullName
                if ($reservedOutputs.ContainsKey($target) -and @($reservedOutputs[$target] | Where-Object {$_.Source -ne $owner}).Count) { throw ('Multiple inputs would create the same output after size rounding: '+$target) }
                $reservedOutputs[$target]=@([pscustomobject]@{Plan=$Plan;Source=$owner})
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                $publication=Publish-ConvertedBooks $virtual $books $dest $duplicateAction
                if ($publication.Skipped) { foreach ($info in $remaining) {Set-QueueRecord $info.File.FullName 'Skipped existing output' 'Existing bundle kept; incoming originals retained.' $publication.Target}; break }
                $receipt=@($publication.Receipt)
                Save-ChapterReceipts $members $receipt
                foreach ($info in $members) {
                    Set-QueueRecord $info.File.FullName 'Converted' ('Chapter bundle verified: '+$title) $receipt[0].Path
                }
                [IO.File]::WriteAllText((Join-Path $attempt 'result.json'),'{"Succeeded":true}')
                $remaining=@($remaining | Select-Object -Skip $members.Count)
                break
            }
            if ($remaining.Count -and $bundleOptions.Hold) { foreach ($info in $remaining) { Set-QueueRecord $info.File.FullName 'Waiting' 'Size budget reached; waiting to combine the remaining chapters with later arrivals.' }; break }
        }
    }
}
function Get-ChapterPreview {
    Read-QueueHistory
    $batches=@(Get-ChildItem -LiteralPath $incoming -Force | Where-Object {$_.Name -notlike 'KCC-*'})
    $filesByBatch=@{}; $recentByBatch=@{}; $all=@()
    foreach ($batch in $batches) {
        try {
            if (($batch.Attributes -band [IO.FileAttributes]::ReparsePoint) -or @((Get-ChildItem -LiteralPath $batch.FullName -Recurse -Force) | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count) { throw 'Linked files or folders are not processed.' }
            $files=@(BatchFiles $batch); $filesByBatch[$batch.FullName]=$files
            $recentByBatch[$batch.FullName]=@($files | Where-Object {$_.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddMinutes(-$QuietMinutes) -or $_.Extension -in @('.part','.tmp','.crdownload','.download')}).Count -gt 0
            $all+=@($files | Where-Object {$_.Extension.ToLowerInvariant() -in $inputExtensions})
        } catch { Set-QueueRecord $batch.FullName 'Failed' ([string]$_); $filesByBatch[$batch.FullName]=@() }
    }
    $planning=New-BundlePlan $all
    $records=@(); $targets=@{}
    foreach ($batch in $batches) {
        $files=@($filesByBatch[$batch.FullName]); $selected=@($files | Where-Object {$_.Extension.ToLowerInvariant() -in $inputExtensions})
        foreach ($file in $files) {
            try {
                if ($file.Extension.ToLowerInvariant() -notin $inputExtensions) { Set-QueueRecord $file.FullName $(if($batch.PSIsContainer -and $selected.Count){'Accompanying'}else{'Ignored'}) 'Not converted; accompanies a successful folder into Originals.'; continue }
                Select-Conversion $file
                $state='Waiting'; $detail='Ready to convert.'; $virtual=$file; $groupId=$file.FullName; $jxl=0; $waiting=$false
                if ($planning.States.ContainsKey($file.FullName)) {
                    $planned=$planning.States[$file.FullName]; $state=$planned.State; $detail=$planned.Detail
                    if ($planned.Group) { $virtual=Bundle-File $planned.Group.Members; $groupId=$planned.Group.Members[0].File.FullName; $waiting=-not $planned.Group.Ready } else { $waiting=$state -ne 'Converted' }
                }
                $folder=Get-OutputDirectory $file
                $target=Join-Path $folder (Get-OutputName $virtual)
                if ($file.Extension -ieq '.cbz') { $info=Read-CbzInfo $file; $jxl=$info.JxlPages; if (-not $info.IsChapter) { $detail=$info.Reason+' ('+$info.Pages+' source pages)' } }
                if ($recentByBatch[$batch.FullName]) { $state='Waiting for download'; $detail='Recent or partial files exist in this batch.'; $waiting=$true }
                elseif ($jxl -gt 0 -and (-not $convertJxl -or -not $DjxlExe -or -not (Test-Path -LiteralPath $DjxlExe))) { $state='Failed'; $detail='JXL pages require an enabled, installed djxl decoder.'; $waiting=$true }
                elseif (Test-Receipt $file) { $state='Converted'; if (-not $planning.States.ContainsKey($file.FullName)) {$detail='Previously completed output verified.'} }
                elseif (-not $waiting -and (Test-Path -LiteralPath $target -PathType Leaf)) {
                    if ($duplicateAction -eq 'Review') {$state='Conflict';$detail='Different output already exists or has not been verified. Review the existing book before replacing it.'}
                    elseif ($duplicateAction -eq 'Skip') {$state='Skipped existing output';$detail='Existing output kept; incoming originals retained.'}
                }
                if (-not $waiting -and $state -ne 'Converted') { if (-not $targets.ContainsKey($target)) {$targets[$target]=@{}}; $targets[$target][$groupId]=$true }
                $records+=[pscustomobject]@{File=$file;State=$state;Detail=$detail;Target=$target;Jxl=$jxl;Waiting=$waiting}
            } catch { Set-QueueRecord $file.FullName 'Failed' ([string]$_) }
        }
    }
    foreach ($record in $records) {
        if (-not $record.Waiting -and $targets.ContainsKey($record.Target) -and $targets[$record.Target].Count -gt 1) { $record.State='Conflict'; $record.Detail='Multiple selected inputs would create the same output.' }
        Set-QueueRecord $record.File.FullName $record.State $record.Detail $record.Target (Get-ConflictKind $record.Detail)
        $queueState[$record.File.FullName].JxlPages=$record.Jxl
        $queueState[$record.File.FullName].Fingerprint=Fingerprint $record.File
    }
    if ($ReportPath) { [IO.File]::WriteAllText($ReportPath,(ConvertTo-Json -InputObject @($queueState.Values | Sort-Object Batch,Name) -Depth 8)) }
}
