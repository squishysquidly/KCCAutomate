$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Join-Path $PSScriptRoot ('test-results\taskbar-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null

# A visibly different native icon seeds Explorer's cache for the destination path.
$bitmap=New-Object Drawing.Bitmap(32,32)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$previousIcon=Join-Path $root 'previous.ico'
Add-Type @'
using System;using System.Runtime.InteropServices;
public static class FixtureIconHandle {
 [DllImport("user32.dll")]public static extern bool DestroyIcon(IntPtr icon);
}
'@
try {
    $graphics.Clear([Drawing.Color]::Red)
    $handle=$bitmap.GetHicon()
    try {
        $icon=[Drawing.Icon]::FromHandle($handle)
        $stream=[IO.File]::Create($previousIcon)
        try {$icon.Save($stream)} finally {$stream.Dispose();$icon.Dispose()}
    } finally {[void][FixtureIconHandle]::DestroyIcon($handle)}
} finally {$graphics.Dispose();$bitmap.Dispose()}
$source=Join-Path $root 'Previous.cs'
[IO.File]::WriteAllText($source,'class Previous { static void Main() {} }')
$previousExe=Join-Path $root 'previous.exe'
& (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe "/win32icon:$previousIcon" "/out:$previousExe" $source
if($LASTEXITCODE){throw 'Could not build the previous-icon fixture.'}

function Get-IconFingerprint([string]$Path) {
    $icon=[Drawing.Icon]::ExtractAssociatedIcon($Path)
    try {
        $image=$icon.ToBitmap()
        try {
            $pixels=New-Object IO.MemoryStream
            $writer=New-Object IO.BinaryWriter($pixels)
            $sha=[Security.Cryptography.SHA256]::Create()
            try {
                $writer.Write($image.Width);$writer.Write($image.Height)
                for($y=0;$y -lt $image.Height;$y++){for($x=0;$x -lt $image.Width;$x++){
                    $pixel=$image.GetPixel($x,$y)
                    $value=if($pixel.A -eq 0){0}else{$pixel.ToArgb()}
                    $writer.Write([int]$value)
                }}
                $writer.Flush();$pixels.Position=0
                return [BitConverter]::ToString($sha.ComputeHash($pixels))
            } finally {$sha.Dispose();$writer.Dispose();$pixels.Dispose()}
        } finally {$image.Dispose()}
    } finally {$icon.Dispose()}
}

$app=Join-Path $PSScriptRoot 'dist\KCCAutomate\KCCAutomate.exe'
$expected=Get-IconFingerprint $app
foreach($owner in @($app,(Join-Path $PSScriptRoot 'dist\KCCAutomate-Setup.exe'))) {
    $assembly=[Reflection.Assembly]::LoadFile($owner)
    $refresh=$assembly.GetType('KCCAutomate.ShellIcons').GetMethod('Refresh')
    $target=Join-Path $root ([IO.Path]::GetFileNameWithoutExtension($owner)+'-replaced.exe')
    Copy-Item -LiteralPath $previousExe -Destination $target
    $old=Get-IconFingerprint $target
    if($old -eq $expected){throw 'The fixture did not start with different artwork.'}
    Copy-Item -LiteralPath $app -Destination $target -Force
    $cached=Get-IconFingerprint $target
    if($cached -eq $old){'PASS: reproduced stale Windows icon after replacing an EXE at the same path.'}
    else {'Windows had already refreshed this fixture path; checking explicit notification too.'}
    $parameters=New-Object object[] 1
    $parameters[0]=[string]$target
    [void]$refresh.Invoke($null,$parameters)
    if((Get-IconFingerprint $target) -ne $expected){throw ('The targeted shell notification did not refresh the artwork: '+$owner)}
    'PASS: '+[IO.Path]::GetFileName($owner)+' refreshes the replaced executable to the current transparent artwork.'
}
'Only fixture paths were notified; no actual app, shortcuts, registry, books or settings changed.'
'Fixtures: '+$root
