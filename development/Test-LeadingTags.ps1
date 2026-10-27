$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\lt-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$mock=Join-Path $root 'mock.exe'; $source=Join-Path $root 'Mock.cs'
@'
using System;using System.IO;using System.IO.Compression;using System.Linq;
class Mock {
 static int Main(string[] args) {
  AppContext.SetSwitch("Switch.System.IO.UseLegacyPathHandling",false);
  AppContext.SetSwitch("Switch.System.IO.BlockLongPaths",false);
  if(Array.IndexOf(args,"--help")>=0){Console.WriteLine("comic2ebook v12.0.0 --profile --format");return 0;}
  string home=AppDomain.CurrentDomain.BaseDirectory;
  if(args.Length==2){File.WriteAllBytes(args[1],new byte[]{137,80,78,71,13,10,26,10});return 0;}
  string input=args[args.Length-1],output=args[Array.IndexOf(args,"--output")+1];
  string title=Array.IndexOf(args,"--title")<0?Path.GetFileNameWithoutExtension(input):args[Array.IndexOf(args,"--title")+1];
  File.AppendAllText(Path.Combine(home,"calls.txt"),title+Environment.NewLine);
  if(File.Exists(Path.Combine(home,"mode")) && File.ReadAllText(Path.Combine(home,"mode"))=="fail-second" && title.EndsWith("v02"))return 1;
  bool bundle=Path.GetFileName(input)=="chapters.cbz";
  string[] names;
  using(var zip=ZipFile.OpenRead(input.Length>=260?@"\\?\"+input:input))names=zip.Entries.Select(e=>e.FullName).ToArray();
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
foreach($row in @(
    @('[sunshine] Rainbows v1 [truth]','Rainbows v1','Rainbows'),
    @(' [Group] [EN] Rainbows ch012.5 [extra]','Rainbows ch012.5','Rainbows'),
    @('[v99][Group]Rainbows v01-v02 [extra]','Rainbows v01-v02','Rainbows'),
    @('[Group] Rainbows [Blue] v1 [extra]','Rainbows [Blue] v1','Rainbows [Blue]'),
    @('(Group) Rainbows v1 [extra]','(Group) Rainbows v1','(Group) Rainbows')
)){
    $marker=Get-FilenameBookMarker $row[0]
    Require ($marker -and $marker.CleanName -ceq $row[1] -and $marker.Series -ceq $row[2]) ('Incorrect leading tag parse: '+$row[0])
}
'PASS: repeated prefixes, adjacent tags, false markers inside tags, decimals/ranges and preserved title punctuation.'

function Clean-Case([string]$Name) {New-Case $Name;$config.BundleChapters=$false;$config.BookTitleStyle='Clean'}
function Preview {
    $script:report=Join-Path $case 'preview.json'
    Run @('-Preview','-ReportPath',$report)
    Require ($code -eq 0) 'Preview failed.'
    $script:rows=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
}
Clean-Case 'user-example'
$input=Book '[sunshine] Rainbows (Digital)/[sunshine] Rainbows v1 [truth].cbz' 3
$hash=(Get-FileHash -LiteralPath $input).Hash
$target=Join-Path $config.ConvertedFolder 'Rainbows/Rainbows v1.mobi'
Preview
Require ($rows.OutputPath -eq $target -and -not (Outputs).Count) 'Preview did not remove the leading tags or changed output files.'
Run
Require ($code -eq 0 -and (Test-Path -LiteralPath $target) -and (Get-Content -LiteralPath $target -Raw).StartsWith('Rainbows v1')) 'The user example retained a leading tag in its filename, embedded title or series folder.'
$archived=Join-Path $config.ArchiveFolder '[sunshine] Rainbows (Digital)/[sunshine] Rainbows v1 [truth].cbz'
Require ((Get-FileHash -LiteralPath $archived).Hash -eq $hash) 'The original name, folder or contents changed.'
'PASS: exact user example cleans filename/title/folder; preview matches publication and archived originals are unchanged.'

Clean-Case 'aliases-and-adjacent-tags'
$config.SeriesAliases=@{'Rainbows'='Rainbow'}
Book 'Shelf/[Group] [EN] Rainbows (Digital)/[Group][EN]Rainbows ch012.5 [extra].cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder 'Shelf/Rainbow/Rainbow ch012.5.mobi'))) 'An alias did not match the title after prefix removal.'

Clean-Case 'conservative-fallback'
Book '[unrelated] Shelf/[Group] A Standalone [extra].cbz' 2 | Out-Null
Book '[Group].cbz' 2 | Out-Null
Book '[broken Rainbows.cbz' 2 | Out-Null
Book 'Rainbows [Blue] v1 [extra].cbz' 2 | Out-Null
Book '(Group) Rainbows v2 [extra].cbz' 2 | Out-Null
Run
$expected=@('(Group) Rainbows v2.mobi','[broken Rainbows.mobi','[Group].mobi','A Standalone [extra].mobi','Rainbows [Blue] v1.mobi')
Require ($code -eq 0 -and -not @(Compare-Object (Outputs) $expected).Count -and (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder '[unrelated] Shelf/A Standalone [extra].mobi'))) 'Cleanup removed meaningful/interior text, guessed an unrelated folder, or produced an empty title.'
'PASS: aliases use the clean series; no-marker names lose only prefixes; all-tag/malformed names and unrelated folders are preserved.'

foreach($kind in @('chapters','volumes')){
    Clean-Case ('bundle-'+$kind)
    $config.HoldShortBundles=$false
    if($kind -eq 'chapters'){$config.BundleChapters=$true;$token='ch';$range='001-002'}
    else{$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$token='v';$range='01-02'}
    foreach($number in 1..2){Book ('[Group] Rainbows (Digital)/[Group'+$number+'] Rainbows '+$token+$number.ToString('00')+' [extra].cbz') 30 | Out-Null}
    $target=Join-Path $config.ConvertedFolder ('Rainbows/Rainbows '+$token+$range+'.mobi')
    Preview
    Require ($rows.Count -eq 2 -and @($rows | Where-Object OutputPath -ne $target).Count -eq 0) 'Bundle preview retained prefix tags or split the series by release group.'
    Run
    Require ($code -eq 0 -and (Test-Path -LiteralPath $target) -and (Outputs).Count -eq 1) 'Different leading release tags prevented clean chapter/volume bundling.'
}
'PASS: chapter and whole-volume groups recognize one series across different leading tags.'

foreach($grouping in @($false,$true)){
    Clean-Case ('collision-'+$grouping)
    $config.BundleVolumes=$grouping;$config.VolumeTargetPages=100;$config.HoldShortBundles=$false;$config.DuplicateAction='Replace'
    foreach($group in @('A','B')){Book ('['+$group+'] Rainbows/['+$group+'] Rainbows v1 [extra].cbz') 2 | Out-Null}
    Preview
    Require ($rows.Count -eq 2 -and @($rows | Where-Object Status -eq 'Conflict').Count -eq 2) 'Preview missed a collision after leading-tag cleanup.'
    Run
    Require ($code -eq 1 -and -not (Outputs).Count -and -not @(Calls).Count -and @(Get-ChildItem -LiteralPath $config.WatchFolder -File -Recurse).Count -eq 2) 'Prefix cleanup overwrote a competing release or removed an original.'
}
'PASS: different releases cleaning to the same book are blocked before conversion, even with Replace.'

Clean-Case 'original-preference'
$config.BookTitleStyle='Original'
Book '[sunshine] Rainbows/[sunshine] Rainbows v1 [truth].cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder '[sunshine] Rainbows/[sunshine] Rainbows v1 [truth].mobi'))) 'Keep original names unexpectedly removed leading tags.'
'PASS: Keep original names retains downloaded filenames and folder names.'
'Only generated fixtures were used: '+$root

