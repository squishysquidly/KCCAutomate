$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$icon=Join-Path $project 'app/assets/KCCAutomate.ico'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
$stream=[IO.File]::OpenRead($icon)
try{
    $decoder=New-Object Windows.Media.Imaging.IconBitmapDecoder($stream,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $sizes=@($decoder.Frames | ForEach-Object {if($_.PixelWidth -ne $_.PixelHeight){throw 'Icon frame is not square.'};$_.PixelWidth} | Sort-Object)
    if(($sizes -join ',') -ne '16,24,32,48,64,128,256'){throw 'The icon is missing a required shell/display size.'}
}finally{$stream.Dispose()}
$executable=Join-Path $PSScriptRoot 'dist/KCCAutomate/KCCAutomate.exe'
$assembly=[Reflection.Assembly]::LoadFile($executable)
$resource=$assembly.GetManifestResourceStream('KCCAutomate.Icon.ico')
if(-not $resource){throw 'The window icon was not embedded in the application.'}
$sha=[Security.Cryptography.SHA256]::Create()
try{$actual=[BitConverter]::ToString($sha.ComputeHash($resource)).Replace('-','');if($actual -ne (Get-FileHash -LiteralPath $icon).Hash){throw 'The window icon differs from the approved artwork icon.'}}finally{$sha.Dispose();$resource.Dispose()}
Add-Type @'
using System;using System.Collections.Generic;using System.Runtime.InteropServices;
public static class NativeAppIcon {
 delegate bool ResourceName(IntPtr module,IntPtr type,IntPtr name,IntPtr parameter);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool EnumResourceNames(IntPtr module,IntPtr type,ResourceName callback,IntPtr parameter);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr FindResource(IntPtr module,IntPtr name,IntPtr type);
 [DllImport("kernel32.dll")]static extern IntPtr LoadResource(IntPtr module,IntPtr resource);
 [DllImport("kernel32.dll")]static extern IntPtr LockResource(IntPtr resource);
 [DllImport("kernel32.dll")]static extern uint SizeofResource(IntPtr module,IntPtr resource);
 [DllImport("kernel32.dll")]static extern bool FreeLibrary(IntPtr module);
 public static int[] Sizes(string path){
  IntPtr module=LoadLibraryEx(path,IntPtr.Zero,2);if(module==IntPtr.Zero)throw new Exception("Cannot inspect executable icon resources.");
  try{
   var sizes=new List<int>();
   ResourceName callback=delegate(IntPtr owner,IntPtr type,IntPtr name,IntPtr data){
    IntPtr entry=FindResource(owner,name,type),memory=LockResource(LoadResource(owner,entry));uint bytes=SizeofResource(owner,entry);
    if(memory==IntPtr.Zero||bytes<6)throw new Exception("Invalid native icon group.");
    int count=(ushort)Marshal.ReadInt16(memory,4);if(bytes<6+count*14)throw new Exception("Truncated native icon group.");
    for(int i=0;i<count;i++){int width=Marshal.ReadByte(memory,6+i*14);sizes.Add(width==0?256:width);}
    return true;
   };
   EnumResourceNames(module,new IntPtr(14),callback,IntPtr.Zero);sizes.Sort();return sizes.ToArray();
  }finally{FreeLibrary(module);}
 }
}
'@
foreach($path in @($executable,(Join-Path $PSScriptRoot 'dist/KCCAutomate-Setup.exe'),(Join-Path $PSScriptRoot 'dist/Uninstall-KCCAutomate.exe'))){
    if(([NativeAppIcon]::Sizes($path) -join ',') -ne '16,24,32,48,64,128,256'){throw ('Missing native executable icon sizes: '+$path)}
    $associated=[Drawing.Icon]::ExtractAssociatedIcon($path)
    try{
        $bitmap=$associated.ToBitmap()
        try{
            $expectedIcon=New-Object Drawing.Icon($icon,$bitmap.Width,$bitmap.Height)
            $expected=$expectedIcon.ToBitmap()
            try{
                for($y=0;$y -lt $bitmap.Height;$y++){
                    for($x=0;$x -lt $bitmap.Width;$x++){
                        $actualPixel=$bitmap.GetPixel($x,$y);$expectedPixel=$expected.GetPixel($x,$y)
                        if($actualPixel.A -ne $expectedPixel.A -or ($actualPixel.A -gt 0 -and ($actualPixel.R -ne $expectedPixel.R -or $actualPixel.G -ne $expectedPixel.G -or $actualPixel.B -ne $expectedPixel.B))){throw ('Windows shell extraction differs from the source artwork icon: '+$path)}
                    }
                }
            }finally{$expected.Dispose();$expectedIcon.Dispose()}
        }finally{$bitmap.Dispose()}
    }finally{$associated.Dispose()}
    'PASS: seven native icon sizes and Windows shell artwork extraction: '+[IO.Path]::GetFileName($path)
}
'PASS: the embedded WPF window icon matches the source ICO; all seven display sizes decode correctly.'

$sourceImage=[Drawing.Bitmap]::FromFile((Join-Path $project 'app/assets/KCCAutomate.png'))
$largest=$decoder.Frames | Where-Object PixelWidth -eq 256 | Select-Object -First 1
$converted=New-Object Windows.Media.Imaging.FormatConvertedBitmap
$converted.BeginInit();$converted.Source=$largest;$converted.DestinationFormat=[Windows.Media.PixelFormats]::Bgra32;$converted.EndInit()
$pixels=New-Object byte[] (256*256*4);$converted.CopyPixels($pixels,1024,0)
try{
    $fitWidth=[int][Math]::Round($sourceImage.Width*256.0/[Math]::Max($sourceImage.Width,$sourceImage.Height))
    $fitHeight=[int][Math]::Round($sourceImage.Height*256.0/[Math]::Max($sourceImage.Width,$sourceImage.Height))
    $left=[int][Math]::Floor((256-$fitWidth)/2.0);$top=[int][Math]::Floor((256-$fitHeight)/2.0)
    for($y=0;$y -lt 256;$y++){for($x=0;$x -lt 256;$x++){
        if(($x -lt $left -or $x -ge $left+$fitWidth -or $y -lt $top -or $y -ge $top+$fitHeight) -and $pixels[($y*256+$x)*4+3] -ne 0){throw 'Padding around rectangular artwork must remain transparent.'}
    }}
}finally{$sourceImage.Dispose()}
'PASS: rectangular artwork fits within transparent square padding.'
