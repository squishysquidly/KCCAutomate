$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\bl-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
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

Add-Type -AssemblyName System.Drawing
function Cover-Book([string]$Name){
    $path=Join-Path $config.WatchFolder $Name
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    $zip=[IO.Compression.ZipFile]::Open($path,'Create')
    $bitmap=New-Object Drawing.Bitmap(240,360);$graphics=[Drawing.Graphics]::FromImage($bitmap)
    try{
        $graphics.Clear([Drawing.Color]::Blue)
        $stream=$zip.CreateEntry('001.png').Open();try{$bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)}finally{$stream.Dispose()}
    }finally{$graphics.Dispose();$bitmap.Dispose();$zip.Dispose()}
    return $path
}
New-Case 'leading'
$config.BundleChapters=$false;$config.BookTitleStyle='NumberFirst';$config.SeriesAliases=@{'The Very Long Series Name'='Short Series'};$config.CoverNumberBadge=$true
$input=Cover-Book 'The Very Long Series Name Vol. 3.cbz';$hash=(Get-FileHash -LiteralPath $input).Hash
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq '003 - Short Series (Vol.).mobi') 'Leading number or short series alias failed.'
$output=Join-Path $config.ConvertedFolder '003 - Short Series (Vol.).mobi'
Require ((Get-Content -LiteralPath $output -Raw).StartsWith('003 - Short Series (Vol.)')) 'Readable filename did not match embedded title.'
$cover=Get-ChildItem -LiteralPath $config.WorkFolder -Filter cover.png -Recurse | Select-Object -First 1
$image=[Drawing.Bitmap]::FromFile($cover.FullName)
try{Require ($image.Width -eq 400 -and $image.Height -eq 680 -and $image.GetPixel(0,0).R -eq 0 -and $image.GetPixel(200,500).B -eq 255) 'Cover number strip cropped or distorted the cover artwork.'}finally{$image.Dispose()}
Require ((Get-FileHash -LiteralPath (Join-Path $config.ArchiveFolder 'The Very Long Series Name Vol. 3.cbz')).Hash -eq $hash) 'Cover labeling rewrote an original CBZ.'
'PASS: leading numbers, short series names, matching embedded title, cover strip and unchanged original.'

New-Case 'series-first'
$config.BundleChapters=$false;$config.BookTitleStyle='SeriesFirst';$config.SeriesAliases=@{'Long'='Short'}
Cover-Book 'Long Vol. 12.cbz' | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Short - Vol. 012.mobi') 'Series-first title failed.'
'PASS: series-first numbering keeps a stable sortable series prefix.'

New-Case 'original'
$config.BundleChapters=$false
Cover-Book 'Long Vol. 12.cbz' | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Long Vol. 12.mobi') 'Default naming changed.'
'PASS: existing naming remains the default.'

New-Case 'bundle' 50 50
$config.BookTitleStyle='NumberFirst';$config.SeriesAliases=@{'Series'='Short'}
Book 'Series Ch. 1.cbz' 25 | Out-Null;Book 'Series Ch. 2.cbz' 25 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq '001-002 - Short (Ch.).mobi') 'Chapter range labeling failed.'
$book=Get-Content -LiteralPath (Join-Path $config.ConvertedFolder '001-002 - Short (Ch.).mobi') -Raw
Require ($book.Contains('0001 - Ch. 001/') -and $book.Contains('0002 - Ch. 002/')) 'Labeling changed chapter navigation paths.'
'PASS: range labels retain the underlying chapter navigation structure.'

New-Case 'collision'
$config.BundleChapters=$false;$config.BookTitleStyle='NumberFirst';$config.SeriesAliases=@{'First'='Same';'Second'='Same'};$config.DuplicateAction='Replace'
Cover-Book 'First Vol. 1.cbz' | Out-Null;Cover-Book 'Second Vol. 1.cbz' | Out-Null
Run
Require ($code -eq 1 -and -not (Outputs).Count -and -not @(Calls).Count) 'Alias collision was allowed to overwrite a book.'
'PASS: ambiguous alias output collisions stop before conversion, including under Replace.'

New-Case 'existing-range'
$config.BundleChapters=$false;$config.BookTitleStyle='NumberFirst';$config.CoverNumberBadge=$true
Cover-Book 'Series Vol. 1-2.cbz' | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series Vol. 1-2.mobi') 'An existing range was relabeled as just its first volume.'
Require (-not @(Get-ChildItem -LiteralPath $config.WorkFolder -Filter cover.png -Recurse).Count) 'An ambiguous existing range got an incorrect single-number cover.'
'PASS: existing ranges retain their full names and never get a misleading single-number cover.'

