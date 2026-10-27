$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\fm-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
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

. (Join-Path $project 'app/Chapter-Support.ps1')
$title='The Hero and the Sage, Reincarnated and Engaged'
$cases=@(
    @(($title+' v01 (Digital-Compilation) (Square Enix) (DigitalMangaFan)'),($title+' v01'),'Vol.','01',$false),
    @('Series ch012.5 (Digital)','Series ch012.5','Ch.','012.5',$false),
    @('Series VOL. 02 [Publisher]','Series VOL. 02','Vol.','02',$false),
    @('Series Ch. 03-04 (Digital)','Series Ch. 03-04','Ch.','03',$true),
    @('Series v01-v02 (Digital)','Series v01-v02','Vol.','01',$true),
    @('Series v01 ch100 (Digital)','Series v01','Vol.','01',$false),
    @('Series (Digital v99) ch005 (Group)','Series (Digital v99) ch005','Ch.','005',$false)
)
foreach($row in $cases){
    $marker=Get-FilenameBookMarker $row[0]
    Require ($marker -and $marker.CleanName -ceq $row[1] -and $marker.Kind -eq $row[2] -and $marker.NumberText -ceq $row[3] -and $marker.IsRange -eq $row[4]) ('Incorrect marker parse: '+$row[0])
}
foreach($name in @('C3PO Story','Rev01','Series v01beta','Series v1.5a','Series (Digital v99)','No volume or chapter marker')){
    Require ($null -eq (Get-FilenameBookMarker $name)) ('A title word or release annotation was mistaken for a marker: '+$name)
}
'PASS: compact/long markers, decimals, case, ranges and internal chapters parse without title-word or annotation false positives.'

New-Case 'exact-example'
$config.BundleChapters=$false;$config.BookTitleStyle='Clean'
$originalName=$title+' v01 (Digital-Compilation) (Square Enix) (DigitalMangaFan).cbz'
$input=Book $originalName 4;$hash=(Get-FileHash -LiteralPath $input).Hash
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -ceq ($title+' v01.mobi')) 'The supplied example was not cleaned through v01.'
$book=Join-Path $config.ConvertedFolder ($title+' v01.mobi')
Require ((Get-Content -LiteralPath $book -Raw).StartsWith($title+' v01')) 'The embedded book title still included release tags.'
Require ((Get-FileHash -LiteralPath (Join-Path $config.ArchiveFolder $originalName)).Hash -eq $hash) 'The original archive was renamed or modified.'
'PASS: exact user example gets a clean filename and embedded title; original name and bytes are preserved.'

New-Case 'long-explicit-chapters' 300 100
$config.BookTitleStyle='Clean';$config.BundleVolumes=$true;$config.VolumeTargetPages=500;$config.HoldShortBundles=$false
Book 'Series/Series ch001 (Publisher A).cbz' 120 '<ComicInfo><Series>Wrong metadata A</Series><Number>99</Number></ComicInfo>' | Out-Null
Book 'Series/Series ch002 (Publisher B).cbz' 120 '<ComicInfo><Series>Wrong metadata B</Series><Number>66</Number></ComicInfo>' | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series ch001-002.mobi') 'Explicit chapter markers did not override page count or inconsistent metadata.'
$text=Get-Content -LiteralPath (Join-Path $config.ConvertedFolder 'Series/Series ch001-002.mobi') -Raw
Require ($text.Contains('0001 - Ch. 001/') -and $text.Contains('0002 - Ch. 002/')) 'Chapter navigation boundaries were lost.'
'PASS: ch markers determine chapter grouping above the inference threshold and override conflicting metadata.'

New-Case 'short-explicit-volumes' 200 100
$config.BookTitleStyle='Clean';$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$config.HoldShortBundles=$false
Book 'Series/Series v01 (Publisher A).cbz' 30 | Out-Null
Book 'Series/Series v02 (Publisher B).cbz' 30 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series v01-02.mobi') 'Short v-marked volumes were treated as chapters or split by release tags.'
'PASS: v markers determine whole-volume grouping below the chapter threshold; release tags do not split a series.'

New-Case 'volume-only'
$config.BundleChapters=$false;$config.BundleVolumes=$true;$config.VolumeTargetPages=500;$config.HoldShortBundles=$false;$config.BookTitleStyle='Clean'
Book 'Series/Series ch001 (Digital).cbz' 120 | Out-Null
Book 'Series/Series ch002 (Digital).cbz' 120 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series ch001.mobi|Series ch002.mobi') 'Volume-only grouping combined explicitly marked chapters.'
'PASS: volume-only mode never combines explicit chapters, even when they are long.'

New-Case 'chapter-above-target' 50 25
$config.BookTitleStyle='Clean';$config.HoldShortBundles=$true
Book 'Series ch001 (Digital).cbz' 60 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series ch001.mobi') 'A chapter above its grouping target was held or cut.'
'PASS: a chapter above its grouping page target converts separately as a complete input.'

New-Case 'existing-range'
$config.BundleChapters=$false;$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$config.HoldShortBundles=$false;$config.BookTitleStyle='Clean'
Book 'Series v01-02 (Digital).cbz' 40 | Out-Null
Book 'Series v03 (Digital).cbz' 40 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series v01-02.mobi|Series v03.mobi') 'An existing range was truncated or combined as a single volume.'
'PASS: existing volume ranges are cleaned without losing numbers and remain separate.'

New-Case 'fallback-and-alias'
$config.BundleChapters=$false;$config.BookTitleStyle='Clean';$config.SeriesAliases=@{'Long Series'='Short'}
Book 'Long Series ch012.5 (Digital).cbz' 2 | Out-Null
Book 'No Marker (Digital).cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'No Marker (Digital).mobi|Short ch012.5.mobi') 'Alias, fractional chapter, or conservative no-marker fallback failed.'
'PASS: optional aliases and decimal chapter numbers work; names without a marker are kept.'

New-Case 'clean-collision'
$config.BundleChapters=$false;$config.BookTitleStyle='Clean';$config.DuplicateAction='Replace'
Book 'Series v01 (Publisher A).cbz' 2 | Out-Null;Book 'Series v01 (Publisher B).cbz' 2 | Out-Null
Run
Require ($code -eq 1 -and -not (Outputs).Count -and -not @(Calls).Count) 'Cleaning silently overwrote two releases of one volume.'
'PASS: releases that clean to the same name require review before conversion, including under Replace.'

New-Case 'legacy-original-names'
$config.BundleChapters=$false
Book 'Series v01 (Digital).cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series v01 (Digital).mobi') 'Existing Original naming preferences changed.'
'PASS: existing Keep original names preference remains unchanged.'

