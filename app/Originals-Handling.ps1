function Assert-IncomingFile([string]$Path,[switch]$Directory) {
    $resolved=[IO.Path]::GetFullPath($Path)
    $root=[IO.Path]::GetFullPath($incoming).TrimEnd('\')
    if(-not $resolved.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing source removal outside Incoming.'}
    $item=Get-Item -LiteralPath $resolved -Force -ErrorAction Stop
    if([bool]$item.PSIsContainer -ne [bool]$Directory){throw 'Only verified converted inputs and their empty parent folders may be removed.'}
    while($item -and -not $item.FullName.TrimEnd('\').Equals($root,[StringComparison]::OrdinalIgnoreCase)){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked files or folders are not removed.'}
        $item=Get-Item -LiteralPath (Split-Path $item.FullName -Parent) -Force -ErrorAction Stop
    }
    if(-not $item -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Incoming must be a regular, reachable folder.'}
    return $resolved
}
function Remove-VerifiedOriginals($Plan) {
    if($originalsAction -ne 'Delete' -or -not ($config.DeleteOriginalsConfirmed -is [bool]) -or -not $config.DeleteOriginalsConfirmed){throw 'Original deletion was not explicitly enabled and acknowledged.'}
    if((Snapshot $Plan.Batch) -ne $Plan.Before){throw 'The batch changed. Originals were retained.'}
    $pending=@()
    # Verify the entire removal set before removing the first file. Files that
    # were not selected for conversion, including accompanying notes, are kept.
    foreach($file in $Plan.Files){
        Select-Conversion $file
        $path=Assert-IncomingFile $file.FullName
        if(-not (Test-Receipt $file)){throw 'Converted output could not be verified; originals retained.'}
        if(-not $Plan.SourceHashes.ContainsKey($path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Plan.SourceHashes[$path]){throw 'An original changed since the scan. Originals retained.'}
        $pending+=$file
    }
    foreach($file in $pending){
        $path=Assert-IncomingFile $file.FullName
        Select-Conversion $file
        if(-not (Test-Receipt $file) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Plan.SourceHashes[$path]){throw 'Source or output changed before removal; remaining originals retained.'}
        Remove-Item -LiteralPath $path -Force
        Set-QueueRecord $path 'Originals deleted' 'Converted output verified. Original permanently removed by your chosen policy.'
    }
    if($Plan.Batch.PSIsContainer){
        # Consider only ancestors of converted files, never a recursive tree
        # walk that could enter an unrelated folder or a linked directory.
        $folders=@{}
        foreach($file in $pending){
            $parent=Split-Path $file.FullName -Parent
            while($parent -and ($parent.Equals($Plan.Batch.FullName,[StringComparison]::OrdinalIgnoreCase) -or $parent.StartsWith($Plan.Batch.FullName+'\',[StringComparison]::OrdinalIgnoreCase))){
                $folders[$parent]=$true
                if($parent.Equals($Plan.Batch.FullName,[StringComparison]::OrdinalIgnoreCase)){break}
                $parent=Split-Path $parent -Parent
            }
        }
        foreach($folder in @($folders.Keys | Sort-Object Length -Descending)){
            if(-not (Test-Path -LiteralPath $folder -PathType Container)){continue}
            $path=Assert-IncomingFile $folder -Directory
            if(-not @(Get-ChildItem -LiteralPath $path -Force).Count){Remove-Item -LiteralPath $path -Force}
        }
    }
}
