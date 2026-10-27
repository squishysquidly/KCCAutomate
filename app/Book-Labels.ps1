# Optional labels affect generated books only. They never rewrite source CBZs.
function Get-LabelStyle {
    $style=if($config -and $config.BookTitleStyle){[string]$config.BookTitleStyle}else{'Original'}
    if($style -notin @('Original','SeriesFirst','NumberFirst','Clean')){throw 'Choose a supported book title style.'}
    return $style
}
function Get-SeriesAlias([string]$Series) {
    if($config -and $config.SeriesAliases){
        foreach($property in $config.SeriesAliases.PSObject.Properties){if($property.Name -ieq $Series){return [string]$property.Value}}
    }
    return $Series
}
function Get-OutputDirectory($File) {
    $parent=Split-Path ($File.FullName.Substring($incoming.Length).TrimStart('\')) -Parent
    if((Get-LabelStyle) -ne 'Clean' -or -not $parent){return (Join-Path $output $parent)}
    # Match against the source filename, including for virtual chapter/volume
    # bundles whose displayed name may already contain a series alias.
    $marker=Get-FilenameBookMarker ([IO.Path]::GetFileNameWithoutExtension($File.FullName))
    if(-not $marker){return (Join-Path $output $parent)}
    $series=$marker.Series
    $fromFolder=-not [bool]$series
    if($fromFolder){$series=Get-FolderBookSeries $File $marker}
    if(-not $series){return (Join-Path $output $parent)}
    $label=[regex]::Replace((Get-SeriesAlias $series),'[<>:"/\\|?*\x00-\x1f]','_').Trim(' ','.')
    if($label.Length -gt 150){$label=$label.Substring(0,150).TrimEnd(' ','.')}
    if(-not $label){throw 'The shortened series name cannot produce an empty output folder.'}
    if($label -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){$label='_'+$label}
    $components=@($parent -split '\\');$componentIndex=0
    $parts=@($components | ForEach-Object {
        $originalPart=$_
        $componentIndex++
        if($fromFolder -and $componentIndex -lt $components.Count){$originalPart;return}
        $part=Remove-LeadingBookTags $originalPart
        $folderMarker=Get-FilenameBookMarker $part
        $matchesSeries=$part.Equals($series,[StringComparison]::OrdinalIgnoreCase)
        if(-not $matchesSeries -and $part.StartsWith($series,[StringComparison]::OrdinalIgnoreCase)){
            $matchesSeries=$part.Substring($series.Length) -match '^\s*(?:(?:\([^)]*\)|\[[^\]]*\])\s*)+$'
        }
        if(-not $matchesSeries -and $folderMarker){$matchesSeries=$folderMarker.Series -ieq $series}
        if($matchesSeries){$label}else{$originalPart}
    })
    Join-Path $output ($parts -join '\')
}
function Get-OutputFolderKey($File) {
    $original=Join-Path $output (Split-Path ($File.FullName.Substring($incoming.Length).TrimStart('\')) -Parent)
    $destination=Get-OutputDirectory $File
    # Retain earlier completion records when the destination did not change.
    if($destination -ine $original){'|output-folder-v1|'+$destination}
}
function Get-LabelKey {
    $style=Get-LabelStyle
    if($style -eq 'Original' -and -not ($config -and $config.CoverNumberBadge)){return ''}
    $aliases=if($config -and $config.SeriesAliases){@($config.SeriesAliases.PSObject.Properties | Sort-Object Name | ForEach-Object {$_.Name+'='+$_.Value}) -join '|'}else{''}
    '|book-labels-v1|'+$style+'|'+[bool]$config.CoverNumberBadge+'|'+$aliases
}
function Format-BookLabel([string]$Series,[string]$Range,[string]$Kind) {
    $series=Get-SeriesAlias $Series
    $series=[regex]::Replace($series,'[<>:"/\\|?*\x00-\x1f]','_').Trim(' ','.')
    if($series.Length -gt 150){$series=$series.Substring(0,150).TrimEnd(' ','.')}
    if((Get-LabelStyle) -eq 'NumberFirst'){return $Range+' - '+$series+' ('+$Kind+')'}
    if((Get-LabelStyle) -eq 'Clean'){return $series+' '+$(if($Kind -eq 'Vol.'){'v'}else{'ch'})+$Range}
    $series+' - '+$Kind+' '+$Range
}
function Get-BookLabel($File) {
    if($File.PSObject.Properties['IsBundle'] -and $File.IsBundle){return $File.BaseName}
    if((Get-LabelStyle) -eq 'Original' -or $File.Extension -ine '.cbz'){return $File.BaseName}
    $info=Read-CbzInfo $File
    if((Get-LabelStyle) -eq 'Clean'){
        if(-not $info.FilenameMarker){
            $cleaned=Remove-LeadingBookTags $File.BaseName
            if(-not [string]::IsNullOrWhiteSpace($cleaned)){return $cleaned}
            return $File.BaseName
        }
        $marker=$info.FilenameMarker
        if(-not $marker.Series -and $info.FolderSeries){return (Get-SeriesAlias $info.FolderSeries)+' '+$marker.Token}
        $alias=Get-SeriesAlias $marker.Series
        if($marker.Series -and $alias -cne $marker.Series){return $alias+' '+$marker.Token}
        return $marker.CleanName
    }
    if(-not $info.HasNumber -or -not $info.Series -or $info.HasNumberRange){return $File.BaseName}
    Format-BookLabel $info.Series ($info.Number.ToString('000.###',[Globalization.CultureInfo]::InvariantCulture)) $info.Kind
}
function Write-NumberedCover([string]$InputImage,[string]$OutputImage,[string]$Label) {
    Add-Type -AssemblyName System.Drawing
    $source=[Drawing.Image]::FromFile($InputImage)
    $bitmap=$null;$graphics=$null;$font=$null;$format=$null
    try{
        # Add a separate strip; the source cover artwork is never cropped.
        $width=[Math]::Max(400,$source.Width)
        $height=[int][Math]::Round($source.Height*$width/[double]$source.Width)
        $strip=[int][Math]::Max(80,$width*0.16)
        $bitmap=New-Object Drawing.Bitmap($width,($height+$strip))
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([Drawing.Color]::White)
        $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($source,0,$strip,$width,$height)
        $graphics.FillRectangle([Drawing.Brushes]::Black,0,0,$width,$strip)
        $size=[single]($strip*0.48)
        do{
            if($font){$font.Dispose()}
            $font=New-Object Drawing.Font('Arial',$size,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
            $fits=$graphics.MeasureString($Label,$font).Width -le $width-24
            $size-=2
        }while(-not $fits -and $size -gt 10)
        $format=New-Object Drawing.StringFormat
        $format.Alignment=[Drawing.StringAlignment]::Center;$format.LineAlignment=[Drawing.StringAlignment]::Center
        $graphics.DrawString($Label,$font,[Drawing.Brushes]::White,(New-Object Drawing.RectangleF(8,0,($width-16),$strip)),$format)
        $bitmap.Save($OutputImage,[Drawing.Imaging.ImageFormat]::Png)
    }finally{if($format){$format.Dispose()};if($font){$font.Dispose()};if($graphics){$graphics.Dispose()};if($bitmap){$bitmap.Dispose()};$source.Dispose()}
}
function Write-BookCover($Entry,[string]$Attempt,[string]$Label) {
    $covers=Join-Path $Attempt 'Covers';New-Item -ItemType Directory -Path $covers -Force | Out-Null
    $extension=[IO.Path]::GetExtension($Entry.Name)
    if($config -and $config.CoverNumberBadge -and $Label){
        $source=Join-Path $Attempt ('cover-input'+$extension)
        [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry,$source,$true)
        try{Write-NumberedCover $source (Join-Path $covers 'cover.png') $Label;return}catch{Log ('WARNING cover number could not be added; using the existing cover: '+$_)}
    }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry,(Join-Path $covers ('cover'+$extension)),$true)
}
function Prepare-LabelledCbz($File,[string]$Source,[string]$Attempt) {
    if(-not ($config -and $config.CoverNumberBadge)){return $Source}
    $info=Read-CbzInfo $File
    if(-not $info.HasNumber -or $info.HasNumberRange){return $Source}
    if($Source -eq $File.FullName){$Source=Join-Path $Attempt 'input.cbz';Copy-Item -LiteralPath $File.FullName -Destination $Source}
    $cover=$info.CoverEntry.Replace('\','/')
    if($cover -match '(?i)\.jxl$'){$cover=[IO.Path]::ChangeExtension($cover,'.png')}
    $zip=[IO.Compression.ZipFile]::OpenRead($Source)
    try{
        $entry=@($zip.Entries | Where-Object {$_.FullName.Replace('\','/') -ceq $cover})
        if($entry.Count -eq 1){Write-BookCover $entry[0] $Attempt ($info.Kind.ToUpperInvariant()+' '+$info.Number.ToString('000.###',[Globalization.CultureInfo]::InvariantCulture))}
    }finally{$zip.Dispose()}
    return $Source
}
