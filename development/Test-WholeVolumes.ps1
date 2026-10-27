$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\bv-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$mock=Join-Path $root 'mock.exe'; $source=Join-Path $root 'Mock.cs'
@'
using System;using System.IO;using System.IO.Compression;using System.Linq;
class Mock {
 static int Main(string[] args) {
  if(Array.IndexOf(args,"--help")>=0){Console.WriteLine("comic2ebook v12.0.0 --profile --format");return 0;}
  string home=AppDomain.CurrentDomain.BaseDirectory;
  if(args.Length==2){File.WriteAllBytes(args[1],new byte[]{137,80,78,71,13,10,26,10});return 0;}
  string input=args[args.Length-1],output=args[Array.IndexOf(args,"--output")+1];
  string title=Array.IndexOf(args,"--title")<0?Path.GetFileNameWithoutExtension(input):args[Array.IndexOf(args,"--title")+1];
  File.AppendAllText(Path.Combine(home,"calls.txt"),title+Environment.NewLine);
  bool bundle=Path.GetFileName(input)=="chapters.cbz";
  string[] names;
  using(var zip=ZipFile.OpenRead(input))names=zip.Entries.Select(e=>e.FullName).ToArray();
  int chapters=names.Where(n=>n.Contains("/")).Select(n=>n.Split('/')[0]).Distinct().Count();
  string mode=File.Exists(Path.Combine(home,"mode"))?File.ReadAllText(Path.Combine(home,"mode")):"";
  if(bundle&&(mode=="always-split"||(mode=="split-three"&&chapters>2))){File.WriteAllText(Path.Combine(Path.GetDirectoryName(output),"book_001.mobi"),"part1");File.WriteAllText(Path.Combine(Path.GetDirectoryName(output),"book_002.mobi"),"part2");return 0;}
  if(bundle&&mode=="bytes-three"&&chapters>2){using(var file=File.Create(output))file.SetLength(10*1048576+1);return 0;}
  string cover="",covers=Path.Combine(Path.GetDirectoryName(input),"Covers");
  if(Directory.Exists(covers))cover=File.ReadAllText(Directory.GetFiles(covers)[0]);
  File.WriteAllText(output,title+"\n"+String.Join("\n",names)+"\nCOVER="+cover);
  return 0;
 }
}
'@ | Set-Content -LiteralPath $source -Encoding UTF8
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
& (Join-Path $framework 'csc.exe') /nologo /target:exe "/out:$mock" (('/reference:')+(Join-Path $framework 'System.IO.Compression.dll')) (('/reference:')+(Join-Path $framework 'System.IO.Compression.FileSystem.dll')) $source
if ($LASTEXITCODE) { throw 'Chapter test fixture compilation failed.' }
function New-Case([string]$Name,[int]$Target=200,[int]$Threshold=100) {
    $script:case=Join-Path $root $Name
    $script:config=[ordered]@{WatchFolder=(Join-Path $case 'in');ConvertedFolder=(Join-Path $case 'out');ArchiveFolder=(Join-Path $case 'archive');WorkFolder=(Join-Path $case 'work');KccExe=$mock;DjxlExe=$mock;QuietMinutes=0;Profile='KS';Format='MOBI';Cropping=0;Splitter=0;MangaStyle=$true;Upscale=$true;ConvertJxl=$true;InputExtensions=@('.cbz');DuplicateAction='Review';NotificationMode='Off';BundleChapters=$true;BundleTargetPages=$Target;ChapterPageThreshold=$Threshold;BundleMaxMiB=10;HoldShortBundles=$true}
    foreach ($key in @('WatchFolder','ConvertedFolder','ArchiveFolder','WorkFolder')) { New-Item -ItemType Directory -Path $config[$key] -Force | Out-Null }
    $script:configPath=Join-Path $case 'settings.json'
    foreach ($name in @('mode','calls.txt')) { $path=Join-Path $root $name; if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path} }
}
function Book([string]$Relative,[int]$Pages,[string]$Metadata='',[switch]$Jxl) {
    $path=Join-Path $config.WatchFolder $Relative
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    $zip=[IO.Compression.ZipFile]::Open($path,'Create')
    try {
        # Deliberately insert pages in reverse order; output must use natural order.
        for($page=$Pages;$page -ge 1;$page--) {
            $stream=$zip.CreateEntry(('p'+$page+$(if($Jxl -and $page -eq 2){'.jxl'}else{'.jpg'}))).Open()
            try {$bytes=[Text.Encoding]::UTF8.GetBytes('page-'+$page);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
        }
        if($Metadata){$writer=New-Object IO.StreamWriter($zip.CreateEntry('ComicInfo.xml').Open());try{$writer.Write($Metadata)}finally{$writer.Dispose()}}
    }finally{$zip.Dispose()}
    return $path
}
function Run([string[]]$Options=@()) {
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $saved=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try {$script:log=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $project 'app\Convert-Manga.ps1') -ConfigPath $configPath @Options 2>&1);$script:code=$LASTEXITCODE}finally{$ErrorActionPreference=$saved}
    $log | Out-File -LiteralPath (Join-Path $case ('run-'+[Guid]::NewGuid().ToString('N')+'.txt')) -Encoding UTF8
}
function Require($Condition,[string]$Message) {if(-not $Condition){throw ($Message+"`n"+(@($log | Where-Object {$_ -notlike '@@MF:*'} | Select-Object -Last 8) -join "`n"))}}
function Outputs { @(Get-ChildItem -LiteralPath $config.ConvertedFolder -File -Recurse | ForEach-Object Name | Sort-Object) }
function Calls { if(Test-Path -LiteralPath (Join-Path $root 'calls.txt')){@(Get-Content -LiteralPath (Join-Path $root 'calls.txt'))} }

New-Case 'page-budget'
$config.BundleChapters=$false;$config.BundleVolumes=$true;$config.VolumeTargetPages=500;$config.HoldShortBundles=$false
$hashes=@{}
foreach($n in 1..5){$path=Book ('Series\Series Vol. '+$n+'.cbz') 180;$hashes[$path]=(Get-FileHash -LiteralPath $path).Hash}
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Vol. 001-002.mobi|Series - Vol. 003-004.mobi|Series - Vol. 005.mobi') 'Volumes were not rounded down as complete units.'
foreach($path in $hashes.Keys){Require ((Get-FileHash -LiteralPath (Join-Path $config.ArchiveFolder $path.Substring($config.WatchFolder.Length+1))).Hash -eq $hashes[$path]) 'A source volume changed.'}
$book=Get-Content -LiteralPath (Join-Path $config.ConvertedFolder 'Series\Series - Vol. 001-002.mobi') -Raw
Require ($book.Contains('0001 - Vol. 001/') -and $book.Contains('0002 - Vol. 002/')) 'Volume navigation boundaries were lost.'
'PASS: whole-volume page rounding, immediate leftovers, preserved navigation and verified original volume hashes.'

New-Case 'size-budget'
$config.BundleChapters=$false;$config.BundleVolumes=$true;$config.VolumeTargetPages=600;$config.HoldShortBundles=$false
foreach($n in 1..3){Book ('Series\Series Vol. '+$n+'.cbz') 180 | Out-Null}
[IO.File]::WriteAllText((Join-Path $root 'mode'),'split-three')
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Vol. 001-002.mobi|Series - Vol. 003.mobi') 'Size rounding cut a volume instead of removing the last whole volume.'
'PASS: KCC size splitting retries with fewer whole volumes.'

New-Case 'separate-types' 50 50
$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$config.HoldShortBundles=$false
Book 'Series\Series Ch. 1.cbz' 25 | Out-Null;Book 'Series\Series Ch. 2.cbz' 25 | Out-Null
Book 'Series\Series Vol. 1.cbz' 50 | Out-Null;Book 'Series\Series Vol. 2.cbz' 50 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Ch. 001-002.mobi|Series - Vol. 001-002.mobi') 'Chapters and volumes were mixed into one group.'
'PASS: chapter and volume switches remain independent and never mix unit types.'

New-Case 'oversized-pages'
$config.BundleChapters=$false;$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$config.HoldShortBundles=$false
Book 'Series Vol. 1.cbz' 120 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series Vol. 1.mobi') 'An individually long volume was cut to meet the grouping page target.'
'PASS: a volume above the grouping page target converts separately.'

New-Case 'default-off'
$config.BundleChapters=$false;$config.HoldShortBundles=$false
Book 'Series Vol. 1.cbz' 120 | Out-Null;Book 'Series Vol. 2.cbz' 120 | Out-Null
Run
Require ($code -eq 0 -and (Outputs).Count -eq 2) 'Volume grouping became the default.'
'PASS: volume grouping defaults off.'

New-Case 'internal-chapter-number'
$config.BundleChapters=$false;$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$config.HoldShortBundles=$false
Book 'Series Vol. 1 Ch. 10.cbz' 40 '<ComicInfo><Number>10</Number></ComicInfo>' | Out-Null
Book 'Series Vol. 2 Ch. 20.cbz' 40 '<ComicInfo><Number>20</Number></ComicInfo>' | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Vol. 001-002.mobi') 'Internal chapter metadata overrode an explicit whole-volume identity.'
'PASS: explicit volumes keep their volume numbers when internal chapter numbers are also present.'

