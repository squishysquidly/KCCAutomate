$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\of-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
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

function Output-Paths { @(Get-ChildItem -LiteralPath $config.ConvertedFolder -File -Recurse | ForEach-Object {$_.FullName.Substring($config.ConvertedFolder.Length+1)} | Sort-Object) }
function Preview {
    $script:report=Join-Path $case 'preview.json'
    Run @('-Preview','-ReportPath',$report)
    Require ($code -eq 0) 'Preview failed.'
    $script:rows=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
}
function Clean-Case([string]$Name) {New-Case $Name; $config.BundleChapters=$false;$config.BookTitleStyle='Clean'}

Clean-Case 'user-example'
$title='The Hero and the Sage, Reincarnated and Engaged'
$folder=$title+' (Digital-Compilation) (Square Enix) (DigitalMangaFan)'
$name=$title+' v01 (Digital-Compilation) (Square Enix) (DigitalMangaFan).cbz'
$input=Book ($folder+'/'+$name) 3
$hash=(Get-FileHash -LiteralPath $input).Hash
$expected=Join-Path $config.ConvertedFolder ($title+'/'+$title+' v01.mobi')
Preview
Require ($rows.Count -eq 1 -and $rows[0].OutputPath -eq $expected -and -not (Outputs).Count) 'Preview did not use the clean folder, or changed output files.'
Run
Require ($code -eq 0 -and (Test-Path -LiteralPath $expected) -and -not (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder $folder))) 'The converted series folder still included release information.'
Require ((Get-FileHash -LiteralPath (Join-Path $config.ArchiveFolder ($folder+'/'+$name))).Hash -eq $hash) 'Archiving changed the original folder, filename or contents.'
$queue=Get-Content -LiteralPath (Join-Path $config.WorkFolder 'queue.json') -Raw | ConvertFrom-Json
Require ($queue[0].OutputPath -eq $expected -and $queue[0].Status -eq 'Archived') 'Completion history disagrees with the published clean path.'
'PASS: the user example, preview, publication, history and original/archive preservation agree.'

Clean-Case 'nested-alias'
$config.SeriesAliases=@{'Long Series'='Short'}
Book 'Shelf/Long Series [Digital] (Publisher)/Extras/Long Series v01 (Digital).cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and ((Output-Paths) -join '|') -eq 'Shelf\Short\Extras\Short v01.mobi') 'Aliases did not clean the matching series folder while retaining other nesting.'
'PASS: shortened names apply to matching folders and books, retaining surrounding subfolders.'

Clean-Case 'folder-volume-marker'
Book 'Series v01 (Digital)/Series v01 (Publisher).cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and ((Output-Paths) -join '|') -eq 'Series\Series v01.mobi') 'The series folder retained its volume/release suffix.'

Clean-Case 'unmatched-and-literal-title'
Book 'Mixed batch (2026)/Series v01 (Digital).cbz' 2 | Out-Null
Book 'Series Sequel (Digital)/Series v02 (Digital).cbz' 2 | Out-Null
Book 'Series (The Beginning) (Digital)/Series (The Beginning) v01 (Publisher).cbz' 2 | Out-Null
Book 'Unclear (Digital)/No Marker (Digital).cbz' 2 | Out-Null
Run
$expectedPaths=@('Mixed batch (2026)\Series v01.mobi','Series Sequel (Digital)\Series v02.mobi','Series (The Beginning)\Series (The Beginning) v01.mobi','Unclear (Digital)\No Marker (Digital).mobi')
Require ($code -eq 0 -and -not @(Compare-Object (Output-Paths) $expectedPaths).Count) 'Unrelated folder names or parentheses belonging to a title were removed.'
'PASS: volume folder suffixes are removed, while unrelated names and meaningful title parentheses survive.'

Clean-Case 'loose-and-range'
Book 'Series v01-02 (Digital).cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and ((Output-Paths) -join '|') -eq 'Series v01-02.mobi') 'A loose book gained a folder or lost its volume range.'
Clean-Case 'original-preference'
$config.BookTitleStyle='Original'
Book 'Series (Digital)/Series v01 (Digital).cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and ((Output-Paths) -join '|') -eq 'Series (Digital)\Series v01 (Digital).mobi') 'Keep original names unexpectedly changed a folder.'
'PASS: loose-book layout, ranges and Keep original names remain compatible.'

foreach($kind in @('chapters','volumes')){
    Clean-Case ('bundle-'+$kind)
    $config.HoldShortBundles=$false
    $config.SeriesAliases=@{'Long Series'='Short'}
    if($kind -eq 'chapters'){$config.BundleChapters=$true;$token='ch';$range='001-002'}
    else {$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$token='v';$range='01-02'}
    foreach($number in 1..2){Book ('Long Series (Digital)/Long Series '+$token+$number.ToString('00')+' (Publisher).cbz') 30 | Out-Null}
    $expected=Join-Path $config.ConvertedFolder ('Short/Short '+$token+$range+'.mobi')
    Preview
    Require ($rows.Count -eq 2 -and @($rows | Where-Object OutputPath -ne $expected).Count -eq 0) 'Bundle preview used a different folder from publication.'
    Run
    Require ($code -eq 0 -and (Test-Path -LiteralPath $expected) -and (Outputs).Count -eq 1) 'Chapter/volume bundling did not use the clean aliased folder.'
}
'PASS: chapter and whole-volume bundles share clean folder paths with their previews.'

foreach($bundling in @($false,$true)){
    Clean-Case ('collision-'+$bundling)
    $config.BundleVolumes=$bundling;$config.VolumeTargetPages=100;$config.HoldShortBundles=$false;$config.DuplicateAction='Replace'
    Book 'Series (Digital A)/Series v01 (Publisher A).cbz' 2 | Out-Null
    Book 'Series (Digital B)/Series v01 (Publisher B).cbz' 2 | Out-Null
    Preview
    Require ($rows.Count -eq 2 -and @($rows | Where-Object Status -eq 'Conflict').Count -eq 2) 'Preview missed colliding names from different release folders.'
    Run
    Require ($code -eq 1 -and -not (Outputs).Count -and -not @(Calls).Count) 'Folder cleanup silently overwrote colliding releases or converted before detecting the conflict.'
    Require (@(Get-ChildItem -LiteralPath $config.WatchFolder -File -Recurse).Count -eq 2) 'A collision removed incoming originals.'
}
Clean-Case 'distinct-volumes'
Book 'Series (Digital A)/Series v01 (Publisher A).cbz' 2 | Out-Null
Book 'Series (Digital B)/Series v02 (Publisher B).cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and ((Output-Paths) -join '|') -eq 'Series\Series v01.mobi|Series\Series v02.mobi') 'Different volumes could not share the clean series folder.'
'PASS: collisions require review before conversion, while distinct volumes share the clean folder.'

foreach($policy in @('Review','Skip','KeepBoth','Replace')){
    Clean-Case ('existing-'+$policy)
    $config.DuplicateAction=$policy
    $input=Book 'Series (Digital)/Series v01 (Digital).cbz' 2
    $target=Join-Path $config.ConvertedFolder 'Series/Series v01.mobi'
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) | Out-Null
    [IO.File]::WriteAllText($target,'existing book')
    Run
    if($policy -in @('Review','Skip')){
        Require ((Get-Content -LiteralPath $target -Raw) -eq 'existing book' -and (Test-Path -LiteralPath $input)) 'Review/Skip changed an existing output or removed its unconverted original.'
    } elseif($policy -eq 'KeepBoth'){
        Require ($code -eq 0 -and (Get-Content -LiteralPath $target -Raw) -eq 'existing book' -and (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder 'Series/Series v01 (2).mobi'))) 'KeepBoth did not retain both books in the clean folder.'
    } else {
        Require ($code -eq 0 -and (Get-Content -LiteralPath $target -Raw).StartsWith('Series v01')) 'Replace did not publish into the clean folder.'
    }
}
'PASS: all four existing-output policies operate on the cleaned destination.'

Clean-Case 'safe-alias-folder'
$config.SeriesAliases=@{'Series'='CON'}
Book 'Series (Digital)/Series v01 (Digital).cbz' 2 | Out-Null
Run
Require ($code -eq 0 -and ((Output-Paths) -join '|') -eq '_CON\CON v01.mobi') 'A Windows reserved folder name was not handled safely.'

# Generate verified completions using the earlier unchanged-folder layout.
# A failed second volume keeps the first source in Incoming for a real resume.
$legacy=Join-Path $root 'legacy-worker';New-Item -ItemType Directory -Path $legacy | Out-Null
Get-ChildItem -LiteralPath (Join-Path $project 'app') -Filter '*.ps1' -File | Copy-Item -Destination $legacy
@'
function Get-OutputDirectory($File) {Join-Path $output (Split-Path ($File.FullName.Substring($incoming.Length).TrimStart('\')) -Parent)}
function Get-OutputFolderKey($File) {return ''}
'@ | Add-Content -LiteralPath (Join-Path $legacy 'Book-Labels.ps1') -Encoding UTF8
foreach($folder in @('Series (Digital)','Series')){
    Clean-Case ('receipt-'+$folder.Replace(' ','-'))
    foreach($number in 1..2){Book ($folder+'/Series v'+$number.ToString('00')+' (Digital).cbz') 2 | Out-Null}
    [IO.File]::WriteAllText((Join-Path $root 'mode'),'fail-second')
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $saved=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$log=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $legacy 'Convert-Manga.ps1') -ConfigPath $configPath 2>&1);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$saved}
    Require ($code -eq 1 -and (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder ($folder+'/Series v01.mobi')))) 'Could not seed an earlier verified completion.'
    $before=@(Calls).Count
    [IO.File]::WriteAllText((Join-Path $root 'mode'),'')
    Run
    $expectedCalls=if($folder -eq 'Series'){1}else{2}
    Require ($code -eq 0 -and @(Calls).Count-$before -eq $expectedCalls -and (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder 'Series/Series v01.mobi')) -and (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder 'Series/Series v02.mobi'))) 'Resume trusted the previous destination after it changed, or invalidated an unchanged completion.'
}
'PASS: old completion records are retained for unchanged paths and cannot bypass a newly cleaned destination.'
'Only generated fixtures were used: '+$root

