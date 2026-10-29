param([switch]$RequireJunction)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot ('test-results\or-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
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
  bool bundle=Path.GetFileName(input)=="chapters.cbz"; if(Path.GetFileName(input)=="fail.cbz")return 1;
  string[] names;
  using(var zip=ZipFile.OpenRead(input))names=zip.Entries.Select(e=>e.FullName).ToArray();
  int chapters=names.Where(n=>n.Contains("/")).Select(n=>n.Split('/')[0]).Distinct().Count();
  string mode=File.Exists(Path.Combine(home,"mode"))?File.ReadAllText(Path.Combine(home,"mode")):"";
  if(bundle&&(mode=="always-split"||(mode=="split-three"&&chapters>2))){File.WriteAllText(Path.Combine(Path.GetDirectoryName(output),"book_001.mobi"),"part1");File.WriteAllText(Path.Combine(Path.GetDirectoryName(output),"book_002.mobi"),"part2");return 0;}
  if(bundle&&mode=="bytes-three"&&chapters>2){using(var file=File.Create(output))file.SetLength(10*1048576+1);return 0;}
  if(mode=="mutate-source"){var stamp=File.GetLastWriteTimeUtc(input);var bytes=File.ReadAllBytes(input);bytes[bytes.Length-1]^=1;File.WriteAllBytes(input,bytes);File.SetLastWriteTimeUtc(input,stamp);} string cover="",covers=Path.Combine(Path.GetDirectoryName(input),"Covers");
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

New-Case 'default-archive'
$config.BundleChapters=$false
$input=Book 'Series/Series Vol. 1.cbz' 2;$hash=(Get-FileHash -LiteralPath $input).Hash
Run
Require ($code -eq 0 -and -not (Test-Path -LiteralPath $input)) 'Default conversion did not finish.'
Require ((Get-FileHash -LiteralPath (Join-Path $config.ArchiveFolder 'Series/Series Vol. 1.cbz')).Hash -eq $hash) 'Archive is no longer the default.'
'PASS: moving verified originals to Originals remains the default.'

New-Case 'delete-selected-only'
$config.BundleChapters=$false;$config.OriginalsAction='Delete';$config.DeleteOriginalsConfirmed=$true
$config.ArchiveFolder=Join-Path $case 'unused-originals'
$input=Book 'Series/Series Vol. 1.cbz' 2
$note=Join-Path (Split-Path $input -Parent) 'notes.txt';'keep these notes' | Set-Content -LiteralPath $note
$pdf=Join-Path (Split-Path $input -Parent) 'unselected.pdf';'unselected book' | Set-Content -LiteralPath $pdf
Run
Require ($code -eq 0 -and -not (Test-Path -LiteralPath $input) -and (Outputs).Count -eq 1) 'Acknowledged removal did not finish after conversion.'
Require ((Test-Path -LiteralPath $note) -and (Test-Path -LiteralPath $pdf) -and -not (Test-Path -LiteralPath $config.ArchiveFolder)) 'Removal touched unconverted files or required an unused archive folder.'
Require (@($log | Where-Object {$_ -like '*Originals deleted*'}).Count -gt 0) 'Deletion completion was not reported.'
'PASS: deletion removes only verified converted inputs, leaves notes/unselected formats, and does not create Originals.'

foreach($ack in @($false,'true')){
    New-Case ('unacknowledged-'+[string]$ack)
    $config.BundleChapters=$false;$config.OriginalsAction='Delete';$config.DeleteOriginalsConfirmed=$ack
    $input=Book 'Series Vol. 1.cbz' 2;$hash=(Get-FileHash -LiteralPath $input).Hash
    Run
    Require ($code -ne 0 -and (Get-FileHash -LiteralPath $input).Hash -eq $hash -and -not @(Calls).Count) 'Unacknowledged or non-boolean deletion was allowed.'
}
'PASS: a real boolean acknowledgement is required before any conversion or removal.'

New-Case 'preview'
$config.BundleChapters=$false;$config.OriginalsAction='Delete';$config.DeleteOriginalsConfirmed=$true
$input=Book 'Series Vol. 1.cbz' 2;$hash=(Get-FileHash -LiteralPath $input).Hash
Run @('-Preview')
Require ($code -eq 0 -and (Get-FileHash -LiteralPath $input).Hash -eq $hash -and -not @(Calls).Count -and -not (Outputs).Count) 'Preview removed or converted an input.'
'PASS: preview stays read-only in deletion mode.'

New-Case 'failure-isolation'
$config.BundleChapters=$false;$config.OriginalsAction='Delete';$config.DeleteOriginalsConfirmed=$true
$bad=Book 'Bad/fail.cbz' 2;$badHash=(Get-FileHash -LiteralPath $bad).Hash
$good=Book 'Good/Series Vol. 1.cbz' 2
Run
Require ($code -eq 1 -and (Get-FileHash -LiteralPath $bad).Hash -eq $badHash -and -not (Test-Path -LiteralPath $good) -and (Outputs).Count -eq 1) 'A failed batch lost originals or stopped an independent successful batch.'
'PASS: failed originals remain while an independent successful folder completes.'

New-Case 'skip-is-unverified'
$config.BundleChapters=$false;$config.OriginalsAction='Delete';$config.DeleteOriginalsConfirmed=$true;$config.DuplicateAction='Skip'
$input=Book 'Series Vol. 1.cbz' 2;$hash=(Get-FileHash -LiteralPath $input).Hash
$existing=Join-Path $config.ConvertedFolder 'Series Vol. 1.mobi';'existing book' | Set-Content -LiteralPath $existing;$existingHash=(Get-FileHash -LiteralPath $existing).Hash
Run
Require ($code -eq 0 -and (Get-FileHash -LiteralPath $input).Hash -eq $hash -and (Get-FileHash -LiteralPath $existing).Hash -eq $existingHash -and -not @(Calls).Count) 'Skip allowed an unverified original to be removed.'
'PASS: skipping an existing book never authorizes original deletion.'

New-Case 'source-hash-change'
$config.BundleChapters=$false;$config.OriginalsAction='Delete';$config.DeleteOriginalsConfirmed=$true
$input=Book 'Series Vol. 1.cbz' 2;$hash=(Get-FileHash -LiteralPath $input).Hash
'mutate-source' | Set-Content -LiteralPath (Join-Path $root 'mode') -NoNewline
Run
Require ($code -eq 1 -and (Test-Path -LiteralPath $input) -and (Get-FileHash -LiteralPath $input).Hash -ne $hash -and (Outputs).Count -eq 1) 'Source content changed without size/time changes but was still removed.'
'PASS: SHA-256 detects a changed original even when its size and timestamp match.'

New-Case 'whole-volumes'
$config.BundleChapters=$false;$config.BundleVolumes=$true;$config.VolumeTargetPages=100;$config.HoldShortBundles=$false
$config.OriginalsAction='Delete';$config.DeleteOriginalsConfirmed=$true;$config.ArchiveFolder=''
$first=Book 'Series/Series Vol. 1.cbz' 30;$second=Book 'Series/Series Vol. 2.cbz' 30
Run
Require ($code -eq 0 -and -not (Test-Path -LiteralPath $first) -and -not (Test-Path -LiteralPath $second) -and ((Outputs) -join '|') -eq 'Series - Vol. 001-002.mobi') 'Whole-volume receipt did not safely authorize member removal.'
Require (-not (Test-Path -LiteralPath (Split-Path $first -Parent))) 'An empty completed source folder was left behind.'
'PASS: verified whole-volume membership supports deletion and empty-folder cleanup.'

New-Case 'changed-output'
$config.OriginalsAction='Delete';$config.DeleteOriginalsConfirmed=$true
$input=Book 'Series/Series Vol. 1.cbz' 2;$hash=(Get-FileHash -LiteralPath $input).Hash
Book 'Series/Series Ch. 1.cbz' 10 | Out-Null
Run
Require ($code -eq 0 -and (Test-Path -LiteralPath $input) -and (Outputs).Count -eq 1) 'A pending chapter did not retain its batch after a completed volume.'
$output=Get-ChildItem -LiteralPath $config.ConvertedFolder -File -Recurse | Select-Object -First 1
'changed output' | Set-Content -LiteralPath $output.FullName
Run
Require ($code -eq 1 -and (Get-FileHash -LiteralPath $input).Hash -eq $hash) 'A changed published output still authorized source removal.'
'PASS: an output changed after an earlier scan cannot authorize original deletion.'

# Exercise containment directly without pointing the worker at external data.
$incoming=$config.WatchFolder
. (Join-Path $project 'app/Originals-Handling.ps1')
$protected=Join-Path $case 'protected';New-Item -ItemType Directory -Path $protected | Out-Null
$outside=Join-Path $protected 'protected.txt';'protected fixture' | Set-Content -LiteralPath $outside
$rejected=$false;try{Assert-IncomingFile $outside | Out-Null}catch{$rejected=$true}
Require ($rejected -and (Test-Path -LiteralPath $outside)) 'The removal boundary accepted a path outside Incoming.'
$link=Join-Path $config.WatchFolder 'linked'
try{New-Item -ItemType Junction -Path $link -Target $protected | Out-Null}catch{
    if($RequireJunction){throw}
    'PASS: removal rejects paths outside Incoming.'
    'SKIP: this environment does not allow creating a junction fixture. Use -RequireJunction on a capable Windows host.'
    $global:LASTEXITCODE=0
    return
}
try{
    $rejected=$false;try{Assert-IncomingFile (Join-Path $link 'protected.txt') | Out-Null}catch{$rejected=$true}
    Require ($rejected -and (Test-Path -LiteralPath $outside)) 'The removal boundary followed a linked directory.'
}finally{
    if(-not $link.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or -not ((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unexpected link cleanup path.'}
    [IO.Directory]::Delete($link)
}
'PASS: removal rejects outside paths and linked directories, retaining the protected fixture.'
# All expected worker failures have been checked, including changed output.
$global:LASTEXITCODE=0

