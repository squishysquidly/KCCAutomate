$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\fs-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
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

function Clean-Case([string]$Name){New-Case $Name;$config.BundleChapters=$false;$config.BookTitleStyle='Clean'}
function Output-Paths {@(Get-ChildItem -LiteralPath $config.ConvertedFolder -File -Recurse | ForEach-Object {$_.FullName.Substring($config.ConvertedFolder.Length+1)} | Sort-Object)}
function Preview {
    $script:report=Join-Path $case 'preview.json'
    Run @('-Preview','-ReportPath',$report)
    Require ($code -eq 0) 'Preview failed.'
    $script:rows=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
}

foreach($format in @('MOBI','CBZ')){
    Clean-Case ('artist-tree-'+$format)
    $config.Format=$format
    $hashes=@{}
    foreach($series in @('First Series','Second Series')){foreach($volume in 1..3){
        $relative='Artist/'+$series+'/v'+$volume+'.cbz'
        $input=Book $relative 2 '<ComicInfo><Series>Wrong metadata</Series><Number>99</Number></ComicInfo>'
        $hashes[$relative]=(Get-FileHash -LiteralPath $input).Hash
    }}
    Preview
    Require ($rows.Count -eq 6 -and @($rows | Where-Object Status -eq 'Conflict').Count -eq 0 -and @($rows | Where-Object OutputPath -Match 'Wrong metadata').Count -eq 0) 'Preview confused artist, series or embedded metadata.'
    Run
    Require ($code -eq 0 -and (Outputs).Count -eq 6) 'Artist/series conversion did not finish all volumes.'
    foreach($series in @('First Series','Second Series')){foreach($volume in 1..3){
        $name=$series+' v'+$volume
        $target=Join-Path $config.ConvertedFolder ('Artist/'+$series+'/'+$name+'.'+$format.ToLowerInvariant())
        Require ((Test-Path -LiteralPath $target) -and (Get-Content -LiteralPath $target -Raw).StartsWith($name)) 'The converted filename or embedded title omitted the parent series.'
        $relative='Artist/'+$series+'/v'+$volume+'.cbz'
        Require ((Get-FileHash -LiteralPath (Join-Path $config.ArchiveFolder $relative)).Hash -eq $hashes[$relative]) 'Original CBZ names, artist/series nesting or contents changed.'
        Require (@($rows | Where-Object OutputPath -eq $target).Count -eq 1) 'Preview and publication disagreed.'
    }}
}
'PASS: two series under one artist get distinct complete titles in MOBI and CBZ output; metadata, previews and original hashes are handled correctly.'

Clean-Case 'decorated-folder-alias'
$config.SeriesAliases=@{'Long Series'='Short'}
Book '[Artist] Collection/[Group] Long Series (Digital) (Publisher)/[Group] v01 [extra].cbz' 2 | Out-Null
Book '[Artist] Collection/Series (The Beginning)/Vol. 2.cbz' 2 | Out-Null
Book '[Artist] Collection/Other/ch012.5 [extra].cbz' 2 | Out-Null
Book '[Artist] Collection/Ranges/v01-v02 [extra].cbz' 2 | Out-Null
Run
$expected=@('[Artist] Collection\Short\Short v01.mobi','[Artist] Collection\Series (The Beginning)\Series (The Beginning) Vol. 2.mobi','[Artist] Collection\Other\Other ch012.5.mobi','[Artist] Collection\Ranges\Ranges v01-v02.mobi')
Require ($code -eq 0 -and -not @(Compare-Object (Output-Paths) $expected).Count) 'Folder cleanup, aliases, chapter decimals, range tokens or artist preservation failed.'
'PASS: immediate series folder cleanup and aliases retain literal number tokens, meaningful title parentheses and artist folders.'

foreach($style in @('SeriesFirst','NumberFirst','Original')){
    Clean-Case ('style-'+$style);$config.BookTitleStyle=$style
    Book 'Artist/Series/v2.cbz' 2 | Out-Null
    Run
    $name=switch($style){'SeriesFirst'{'Series - Vol. 002.mobi'}'NumberFirst'{'002 - Series (Vol.).mobi'}'Original'{'v2.mobi'}}
    Require ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $config.ConvertedFolder ('Artist/Series/'+$name)))) 'A naming mode did not preserve its established behavior.'
}
'PASS: Series-first and Number-first include the inferred series; Keep original names preserves v2.'

Clean-Case 'no-upward-guessing'
Book 'v1.cbz' 2 | Out-Null
Book 'Artist/v01/v2.cbz' 2 | Out-Null
Book 'Artist/123/v3.cbz' 2 | Out-Null
Book 'Artist/Unclear/v1 Extra Title.cbz' 2 | Out-Null
Book 'Artist/Wrong Folder/Correct Series v4.cbz' 2 | Out-Null
Run
$expected=@('v1.mobi','Artist\v01\v2.mobi','Artist\123\v3.mobi','Artist\Unclear\v1.mobi','Artist\Wrong Folder\Correct Series v4.mobi')
Require ($code -eq 0 -and -not @(Compare-Object (Output-Paths) $expected).Count) 'A loose/unclear book borrowed an artist/watch title, or an explicit filename title was replaced.'
'PASS: explicit filename titles win, while loose files and numeric/number-only parents do not borrow an artist or watch-folder title.'

foreach($kind in @('chapters','volumes')){
    Clean-Case ('grouped-'+$kind)
    $config.HoldShortBundles=$false
    if($kind -eq 'volumes'){$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$token='v';$range='01-02'}
    else{$config.BundleChapters=$true;$token='ch';$range='001-002'}
    foreach($series in @('First Series','Second Series')){foreach($number in 1..2){Book ('Artist/'+$series+'/'+$token+$number+'.cbz') 30 | Out-Null}}
    Preview
    Require ($rows.Count -eq 4 -and @($rows | Where-Object Status -eq 'Conflict').Count -eq 0) 'Series folders became ambiguous during bundle preview.'
    Run
    Require ($code -eq 0 -and (Outputs).Count -eq 2) 'Number-only inputs were not grouped independently by series.'
    foreach($series in @('First Series','Second Series')){
        $target=Join-Path $config.ConvertedFolder ('Artist/'+$series+'/'+$series+' '+$token+$range+'.mobi')
        Require ((Test-Path -LiteralPath $target) -and @($rows | Where-Object OutputPath -eq $target).Count -eq 2) 'A bundle used the artist title or the other series.'
    }
}
'PASS: chapter and whole-volume groups remain distinct per series, with correct previews and titles.'

Clean-Case 'duplicate-volume'
$config.DuplicateAction='Replace'
Book 'Artist/Series/v1.cbz' 2 | Out-Null
Book 'Artist/Series/Series v1.cbz' 2 | Out-Null
Preview
Require ($rows.Count -eq 2 -and @($rows | Where-Object Status -eq 'Conflict').Count -eq 2) 'Preview missed a collision between a bare number and an existing full title.'
Run
Require ($code -eq 1 -and -not (Outputs).Count -and -not @(Calls).Count -and @(Get-ChildItem -LiteralPath $config.WatchFolder -File -Recurse).Count -eq 2) 'Inferred naming overwrote a duplicate or removed originals.'
'PASS: inferred and explicit names that target the same book are blocked before conversion.'
'Only generated fixtures were used: '+$root
# Expected collision failures must not become the GitHub step's exit status.
$global:LASTEXITCODE=0

