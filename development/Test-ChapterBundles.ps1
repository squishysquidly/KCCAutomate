$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\cb-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
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

New-Case 'stable'
$originals=@()
foreach($n in 1..4){$originals+=Book ('Series\Series Ch. '+$n+'.cbz') 60}
$volume=Book 'Series\Series Vol. 002.cbz' 120
$before=@{};foreach($path in @($originals)+@($volume)){$before[$path]=(Get-FileHash -LiteralPath $path).Hash}
Run @('-Preview','-ReportPath',(Join-Path $case 'preview.json'))
Require ($code -eq 0 -and -not @(Calls).Count -and -not (Outputs).Count) 'Grouping preview changed files or invoked KCC.'
$preview=Get-Content -LiteralPath (Join-Path $case 'preview.json') -Raw | ConvertFrom-Json
Require (@($preview | Where-Object {$_.Detail -like '*Ch. 001-003*'}).Count -eq 3 -and @($preview | Where-Object {$_.Detail -like '*Waiting for more chapters*'}).Count -eq 1) 'Preview did not explain planned and pending groups.'
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Ch. 001-003.mobi|Series Vol. 002.mobi') 'Page limit or standalone volume behavior failed.'
foreach($path in $before.Keys){Require ((Get-FileHash -LiteralPath $path).Hash -eq $before[$path]) 'An original changed while a short tail was waiting.'}
$published=Join-Path $config.ConvertedFolder 'Series\Series - Ch. 001-003.mobi';$hash=(Get-FileHash -LiteralPath $published).Hash
foreach($n in 5..7){Book ('Series\Series Ch. '+$n+'.cbz') 60 | Out-Null}
Run
Require ($code -eq 0 -and (Get-FileHash -LiteralPath $published).Hash -eq $hash -and @(Calls | Where-Object {$_ -eq 'Series - Ch. 001-003'}).Count -eq 1) 'A later arrival rebuilt a published bundle.'
Require ((Outputs).Count -eq 3) 'The next full group was not published.'
$config.HoldShortBundles=$false;Run
Require ($code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Series')) -and (Outputs).Count -eq 4) 'Releasing the short tail or archival failed.'
foreach($path in $before.Keys){$archived=Join-Path $config.ArchiveFolder $path.Substring($config.WatchFolder.Length+1);Require ((Get-FileHash -LiteralPath $archived).Hash -eq $before[$path]) 'Archived chapter differs from its original.'}
'PASS: read-only preview, page rounding, standalone volumes, waiting tails, frozen published groups, explicit tail release and verified originals.'

New-Case 'size' 100 100
foreach($n in 1..4){Book ('Series\Series Ch. '+$n+'.cbz') 30 | Out-Null}
[IO.File]::WriteAllText((Join-Path $root 'mode'),'split-three')
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Ch. 001-002.mobi' -and @(Calls).Count -eq 2) 'Size fallback did not remove the last whole chapter before publishing.'
Require (@(Get-ChildItem -LiteralPath $config.WatchFolder -File -Recurse).Count -eq 4) 'Size fallback moved uncompleted originals.'
'PASS: KCC multipart output triggers a smaller whole-chapter bundle; remaining chapters stay pending.'

New-Case 'cover-and-jxl' 50 50
$first=Book '漫画 [A]\Series Ch. 1.cbz' 25 '<ComicInfo><Series>Series</Series><Number>1</Number><Pages><Page Image="2" Type="FrontCover"/></Pages></ComicInfo>' -Jxl
$second=Book '漫画 [A]\Series Ch. 2.cbz' 25
$before=(Get-FileHash -LiteralPath $first).Hash
Run
Require ($code -eq 0 -and (Outputs).Count -eq 1) 'Mixed JXL grouping or Unicode path handling failed.'
$book=Get-Content -LiteralPath (Join-Path $config.ConvertedFolder '漫画 [A]\Series - Ch. 001-002.mobi') -Raw
Require ($book -match 'COVER=page-3' -and $book -match '000001.jpg' -and $book -match '000002.png' -and $book -notmatch '\.jxl') 'Cover metadata, natural page order, or JXL decoding was lost.'
Require ((Get-FileHash -LiteralPath (Join-Path $config.ArchiveFolder '漫画 [A]\Series Ch. 1.cbz')).Hash -eq $before) 'JPEG XL original was rewritten.'
'PASS: metadata-selected cover, natural image order, JPEG XL preparation and unchanged archived source.'

New-Case 'unclear-and-gap' 50 50
Book 'Series\mystery.cbz' 20 | Out-Null
foreach($n in @(1,2,4,5)){Book ('Series\Series Ch. '+$n+'.cbz') 20 | Out-Null}
Run
Require ($code -eq 0 -and -not (Outputs).Count -and @($log | Where-Object {$_ -like '*series/chapter number is unclear*'}).Count) 'Ambiguous numbers or missing-chapter gaps were guessed.'
'PASS: uncertain chapter identities and incomplete groups around a numbering gap remain in Incoming.'

New-Case 'duplicate-isolation' 50 50
Book 'Bad\Bad Ch. 1.cbz' 25 | Out-Null;Book 'Bad\Bad c001.cbz' 25 | Out-Null
Book 'Good\Good Ch. 1.cbz' 25 | Out-Null;Book 'Good\Good Ch. 2.cbz' 25 | Out-Null
Run
Require ($code -eq 1 -and ((Outputs) -join '|') -eq 'Good - Ch. 001-002.mobi' -and (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Bad'))) 'Duplicate chapter numbers were accepted or blocked a separate healthy batch.'
'PASS: duplicate chapter identities retain originals while unrelated series continue.'

New-Case 'oversize' 50 50
Book 'Series\Series Ch. 1.cbz' 25 | Out-Null;Book 'Series\Series Ch. 2.cbz' 25 | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'mode'),'always-split')
Run
Require ($code -eq 1 -and -not (Outputs).Count -and @($log | Where-Object {$_ -like '*single chapter exceeds*'}).Count -and (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Series'))) 'Oversized individual chapter was split/published or archived.'
'PASS: a chapter that cannot fit fails with its original retained.'

New-Case 'output-conflict' 50 50
Book 'Series\Series Ch. 1.cbz' 25 | Out-Null;Book 'Series\Series Ch. 2.cbz' 25 | Out-Null
$destination=Join-Path $config.ConvertedFolder 'Series';New-Item -ItemType Directory -Path $destination -Force | Out-Null
$existing=Join-Path $destination 'Series - Ch. 001-002.mobi';[IO.File]::WriteAllText($existing,'keep this book')
Run
Require ($code -eq 1 -and [IO.File]::ReadAllText($existing) -eq 'keep this book' -and (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Series'))) 'A chapter bundle overwrote an existing book under Review.'
$config.DuplicateAction='KeepBoth';Run
Require ($code -eq 0 -and [IO.File]::ReadAllText($existing) -eq 'keep this book' -and (Outputs).Count -eq 2 -and -not (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Series'))) 'Keep both did not preserve the original book and archive verified chapters.'
'PASS: existing-output Review and Keep both policies apply to chapter bundles.'

New-Case 'loose' 50 50
Book 'Series Ch. 1.cbz' 25 | Out-Null;Book 'Series Ch. 2.cbz' 25 | Out-Null
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Ch. 001-002.mobi' -and -not @(Get-ChildItem -LiteralPath $config.WatchFolder -File).Count) 'Loose chapters were not grouped by their series identity.'
'PASS: loose chapters combine by series without requiring a parent series folder.'

New-Case 'immediate-tail'
foreach($n in 1..4){Book ('Series\Series Ch. '+$n+'.cbz') 60 | Out-Null}
$config.HoldShortBundles=$false
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Ch. 001-003.mobi|Series - Ch. 004.mobi' -and -not (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Series'))) 'Immediate short leftovers were held for later.'
'PASS: the selected default creates short leftovers on the current scan.'

New-Case 'byte-limit' 100 100
foreach($n in 1..4){Book ('Series\Series Ch. '+$n+'.cbz') 30 | Out-Null}
[IO.File]::WriteAllText((Join-Path $root 'mode'),'bytes-three')
Run
Require ($code -eq 0 -and ((Outputs) -join '|') -eq 'Series - Ch. 001-002.mobi' -and @(Calls).Count -eq 2) 'An unsplit file exceeding the actual byte budget was published.'
'PASS: actual output bytes, as well as KCC splitting, enforce the configured size budget.'

New-Case 'collision' 50 50
foreach($n in 1..4){Book ('Series\Series Ch. '+$n+'.cbz') 25 | Out-Null}
$config.OutputNaming='Same book';$config.DuplicateAction='Replace'
Run
Require ($code -eq 1 -and -not (Outputs).Count -and -not @(Calls).Count -and (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Series'))) 'Multiple bundle targets collided under Replace.'
'PASS: colliding output templates fail before conversion even when Replace is selected.'

New-Case 'stop' 50 50
Book 'Series\Series Ch. 1.cbz' 25 | Out-Null;Book 'Series\Series Ch. 2.cbz' 25 | Out-Null
$stop=Join-Path $case 'stop';[IO.File]::WriteAllText($stop,'stop')
Run @('-StopFile',$stop)
Require ($code -eq 2 -and -not (Outputs).Count -and -not @(Calls).Count -and (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Series'))) 'Stop-before-bundle converted or archived an input.'
'PASS: cooperative stop retains pending chapter originals.'

New-Case 'damaged-records' 50 50
Book 'Series\Series Ch. 1.cbz' 25 | Out-Null;Book 'Series\Series Ch. 2.cbz' 25 | Out-Null
[IO.File]::WriteAllText((Join-Path $config.WorkFolder 'chapter-receipts.json'),'damaged')
Run
Require ($code -ne 0 -and -not (Outputs).Count -and -not @(Calls).Count -and (Test-Path -LiteralPath (Join-Path $config.WatchFolder 'Series'))) 'Damaged completion records silently regrouped a published book.'
'PASS: damaged shared completion records stop grouping rather than guessing prior bundle membership.'
'Chapter grouping checks passed. Converter fixtures verify orchestration, not ebook rendering or a Kindle hardware size limit.'

