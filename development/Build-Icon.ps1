param(
    [string]$Source=(Join-Path (Split-Path $PSScriptRoot -Parent) 'app/assets/KCCAutomate.png'),
    [string]$Destination=(Join-Path (Split-Path $PSScriptRoot -Parent) 'app/assets/KCCAutomate.ico')
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$sourceImage=[Drawing.Bitmap]::FromFile($Source)
try {
    if([Math]::Max($sourceImage.Width,$sourceImage.Height) -lt 256){throw 'Use artwork of at least 256 pixels on its longest side; the artwork is never cropped.'}
    $frames=@()
    foreach($size in @(16,24,32,48,64,128,256)){
        $bitmap=New-Object Drawing.Bitmap($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        $attributes=New-Object Drawing.Imaging.ImageAttributes
        $buffer=New-Object IO.MemoryStream
        try {
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.CompositingQuality=[Drawing.Drawing2D.CompositingQuality]::HighQuality
            $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
            # Fit rectangular artwork inside a transparent square without
            # changing its proportions or cutting off any part of the design.
            $scale=$size/[double][Math]::Max($sourceImage.Width,$sourceImage.Height)
            $width=[Math]::Max(1,[int][Math]::Round($sourceImage.Width*$scale))
            $height=[Math]::Max(1,[int][Math]::Round($sourceImage.Height*$scale))
            $left=[int][Math]::Floor(($size-$width)/2.0);$top=[int][Math]::Floor(($size-$height)/2.0)
            $graphics.DrawImage($sourceImage,(New-Object Drawing.Rectangle($left,$top,$width,$height)),0,0,$sourceImage.Width,$sourceImage.Height,[Drawing.GraphicsUnit]::Pixel,$attributes)
            if($size -eq 256){$bitmap.Save($buffer,[Drawing.Imaging.ImageFormat]::Png)}else{
                # DIB frames retain legacy shell/.NET icon support. The largest
                # frame uses lossless PNG compression, supported on Windows 7+.
                $writer=New-Object IO.BinaryWriter($buffer)
                $writer.Write([uint32]40);$writer.Write([int]$size);$writer.Write([int]($size*2))
                $writer.Write([uint16]1);$writer.Write([uint16]32)
                foreach($zero in 1..6){$writer.Write([uint32]0)}
                $maskStride=[int]([Math]::Ceiling($size/32.0)*4)
                $mask=New-Object byte[] ($maskStride*$size)
                for($y=$size-1;$y -ge 0;$y--){
                    for($x=0;$x -lt $size;$x++){
                        $pixel=$bitmap.GetPixel($x,$y)
                        $writer.Write([byte]$pixel.B);$writer.Write([byte]$pixel.G);$writer.Write([byte]$pixel.R);$writer.Write([byte]$pixel.A)
                        if($pixel.A -eq 0){$index=($size-1-$y)*$maskStride+[int][Math]::Floor($x/8.0);$mask[$index]=$mask[$index] -bor (128 -shr ($x%8))}
                    }
                }
                $writer.Write($mask);$writer.Flush()
            }
            $frames+=[pscustomobject]@{Size=$size;Data=$buffer.ToArray()}
        }finally{$buffer.Dispose();$attributes.Dispose();$graphics.Dispose();$bitmap.Dispose()}
    }
    $output=New-Object IO.MemoryStream;$directory=New-Object IO.BinaryWriter($output)
    try {
        $directory.Write([uint16]0);$directory.Write([uint16]1);$directory.Write([uint16]$frames.Count)
        $offset=6+16*$frames.Count
        foreach($frame in $frames){
            $dimension=if($frame.Size -eq 256){0}else{$frame.Size}
            $directory.Write([byte]$dimension);$directory.Write([byte]$dimension);$directory.Write([byte]0);$directory.Write([byte]0)
            $directory.Write([uint16]1);$directory.Write([uint16]32);$directory.Write([uint32]$frame.Data.Length);$directory.Write([uint32]$offset)
            $offset+=$frame.Data.Length
        }
        foreach($frame in $frames){$directory.Write([byte[]]$frame.Data)}
        $directory.Flush();[IO.File]::WriteAllBytes($Destination,$output.ToArray())
    }finally{$directory.Dispose();$output.Dispose()}
}finally{$sourceImage.Dispose()}
'Created application icon at 16, 24, 32, 48, 64, 128 and 256 pixels: '+$Destination
