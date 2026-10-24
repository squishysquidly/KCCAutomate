$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot ('test-results\d-'+[guid]::NewGuid().ToString('N').Substring(0,12))
New-Item -ItemType Directory -Path $fixture -Force|Out-Null
$mock=Join-Path $fixture 'mock.exe';$source=Join-Path $fixture 'Mock.cs'
@'
using System;using System.IO;
class Mock {
 public static int Main(string[] a){
  if(Array.IndexOf(a,"--help")>=0){Console.WriteLine("comic2ebook v12.0.0");return 0;}
  string input=a[a.Length-1],home=AppDomain.CurrentDomain.BaseDirectory;
  File.AppendAllText(Path.Combine(home,"calls.txt"),input+Environment.NewLine);
  if(input.EndsWith("fail.pdf")&&!File.Exists(Path.Combine(home,"allow")))return 1;
  string output=a[Array.IndexOf(a,"--output")+1];
  if(input.EndsWith("split.cbz")){string folder=Path.GetDirectoryName(output);File.WriteAllText(Path.Combine(folder,"book_001.mobi"),"part one");File.WriteAllText(Path.Combine(folder,"book_002.mobi"),"part two");}
  else File.WriteAllText(output,"converted "+Path.GetFileName(input));return 0;
 }
}
'@|Set-Content -LiteralPath $source
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe "/out:$mock" $source
if($LASTEXITCODE){throw 'Mock compiler failed.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-Case($Name,$Policy='Review') {
 $script:caseRoot=Join-Path $fixture $Name
 $script:incoming=Join-Path $caseRoot 'in';$script:output=Join-Path $caseRoot 'out';$script:archive=Join-Path $caseRoot 'archive';$script:work=Join-Path $caseRoot 'work'
 foreach($folder in @($incoming,$output,$archive,$work)){New-Item -ItemType Directory -Path $folder -Force|Out-Null}
 $script:settings=[ordered]@{WatchFolder=$incoming;ConvertedFolder=$output;ArchiveFolder=$archive;WorkFolder=$work;KccExe=$mock;DjxlExe='';QuietMinutes=0;Profile='KS';Format='MOBI';Cropping=0;Splitter=0;ConvertJxl=$false;OverwriteConverted=$false;InputExtensions=@('.cbz','.pdf');OutputNaming='{name}';NotificationMode='Off';FolderRules=@()}
 if($Policy){$settings.DuplicateAction=$Policy}
 $script:config=Join-Path $caseRoot 'settings.json'
}
function New-Input($Name) {
 $path=Join-Path $incoming $Name
 New-Item -ItemType Directory -Path (Split-Path $path) -Force|Out-Null
 if([IO.Path]::GetExtension($path)-eq'.cbz'){$zip=[IO.Compression.ZipFile]::Open($path,'Create');try{$stream=$zip.CreateEntry('001.jpg').Open();try{$stream.WriteByte(42)}finally{$stream.Dispose()}}finally{$zip.Dispose()}}
 else{[IO.File]::WriteAllText($path,'mock PDF')}
}
function Save-Config {[IO.File]::WriteAllText($config,($settings|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))}
function Run-Worker([string[]]$Options) {
 Save-Config;$previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$script:workerLog=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Convert-Manga.ps1') -ConfigPath $config @Options 2>&1;$script:workerCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
}
function Assert($Condition,$Message){if(-not$Condition){throw ($Message+"`n"+($workerLog-join"`n"))}}
function Rows {Get-Content -LiteralPath (Join-Path $work 'queue.json') -Raw -Encoding UTF8|ConvertFrom-Json}
function Calls {if(Test-Path -LiteralPath (Join-Path $fixture 'calls.txt')){@(Get-Content -LiteralPath (Join-Path $fixture 'calls.txt')).Count}else{0}}

New-Case review;New-Input 'book.cbz';[IO.File]::WriteAllText((Join-Path $output 'book.mobi'),'keep old')
Run-Worker
Assert ($workerCode-eq1-and[IO.File]::ReadAllText((Join-Path $output 'book.mobi'))-eq'keep old'-and(Test-Path -LiteralPath (Join-Path $incoming 'book.cbz'))) 'Review must retain conflicting output and original.'
Assert (@(Rows|Where-Object {$_.Status-eq'Conflict'-and$_.ConflictKind-eq'ExistingOutput'}).Count-eq1) 'Existing-output conflict was not classified.'
'PASS: default review retains both files and reports an actionable output conflict.'

New-Case legacy $null;New-Input 'book.cbz';$settings.OverwriteConverted=$true;[IO.File]::WriteAllText((Join-Path $output 'book.mobi'),'old')
Run-Worker
Assert ($workerCode-eq0-and[IO.File]::ReadAllText((Join-Path $output 'book.mobi'))-eq'converted book.cbz'-and(Test-Path -LiteralPath (Join-Path $archive 'book.cbz'))) 'Legacy replacement preference was not preserved.'
'PASS: earlier replacement settings migrate without changing their behavior.'

New-Case both KeepBoth;New-Input 'book.cbz';[IO.File]::WriteAllText((Join-Path $output 'book.mobi'),'keep old');[IO.File]::WriteAllText((Join-Path $output 'book (2).mobi'),'keep second')
Run-Worker
Assert ($workerCode-eq0-and[IO.File]::ReadAllText((Join-Path $output 'book.mobi'))-eq'keep old'-and[IO.File]::ReadAllText((Join-Path $output 'book (2).mobi'))-eq'keep second'-and(Test-Path -LiteralPath (Join-Path $output 'book (3).mobi'))-and(Test-Path -LiteralPath (Join-Path $archive 'book.cbz'))) 'Keep both reused an occupied filename or failed verification/archive.'
'PASS: keep-both allocates a free numbered filename and preserves existing books.'

New-Case skip Skip;New-Input 'book.cbz';[IO.File]::WriteAllText((Join-Path $output 'book.mobi'),'keep old');$callsBefore=Calls
Run-Worker
Assert ($workerCode-eq0-and(Calls)-eq$callsBefore-and(Test-Path -LiteralPath (Join-Path $incoming 'book.cbz'))-and-not(Test-Path -LiteralPath (Join-Path $archive 'book.cbz'))-and[IO.File]::ReadAllText((Join-Path $output 'book.mobi'))-eq'keep old') 'Skip moved an unverified original, converted unnecessarily, or replaced output.'
'PASS: skip keeps unverified originals incoming and avoids conversion for an existing primary output.'

New-Case same;New-Input 'book.cbz';[IO.File]::WriteAllText((Join-Path $output 'book.mobi'),'converted book.cbz')
Run-Worker
Assert ($workerCode-eq0-and(Test-Path -LiteralPath (Join-Path $archive 'book.cbz'))-and-not(Test-Path -LiteralPath (Join-Path $output 'book (2).mobi'))) 'Identical output was not verified and reused.'
'PASS: identical output is hash-verified and reused before originals are archived.'

New-Case split KeepBoth;New-Input 'split.cbz';[IO.File]::WriteAllText((Join-Path $output 'split_001.mobi'),'keep split')
Run-Worker
Assert ($workerCode-eq0-and[IO.File]::ReadAllText((Join-Path $output 'split_001.mobi'))-eq'keep split'-and(Test-Path -LiteralPath (Join-Path $output 'split (2)_001.mobi'))-and(Test-Path -LiteralPath (Join-Path $output 'split (2)_002.mobi'))) 'Split output did not get one consistent free number.'
'PASS: split output parts are kept together under one numbered book name.'

New-Case splitreview;New-Input 'split.cbz';[IO.File]::WriteAllText((Join-Path $output 'split_002.mobi'),'keep second part')
Run-Worker
Assert ($workerCode-eq1-and-not(Test-Path -LiteralPath (Join-Path $output 'split_001.mobi'))-and[IO.File]::ReadAllText((Join-Path $output 'split_002.mobi'))-eq'keep second part') 'A conflicting split book was partially published before review.'
'PASS: review checks every output part before publishing any new part.'

New-Case splitskip Skip;New-Input 'split.cbz';[IO.File]::WriteAllText((Join-Path $output 'split_001.mobi'),'keep first part')
Run-Worker
Assert ($workerCode-eq0-and(Test-Path -LiteralPath (Join-Path $incoming 'split.cbz'))-and-not(Test-Path -LiteralPath (Join-Path $output 'split_002.mobi'))-and[IO.File]::ReadAllText((Join-Path $output 'split_001.mobi'))-eq'keep first part') 'Skipping split output published a part or archived an unverified original.'
'PASS: skip also retains originals when only split output exists.'

New-Case reserved KeepBoth;New-Input 'a.cbz';New-Input 'z.cbz'
$settings.FolderRules=@(@{Pattern='a.cbz';Options=@{OutputNaming='book'}},@{Pattern='z.cbz';Options=@{OutputNaming='book (2)'}})
[IO.File]::WriteAllText((Join-Path $output 'book.mobi'),'keep book')
Run-Worker
Assert ($workerCode-eq0-and[IO.File]::ReadAllText((Join-Path $output 'book (2).mobi'))-eq'converted z.cbz'-and[IO.File]::ReadAllText((Join-Path $output 'book (3).mobi'))-eq'converted a.cbz') 'Numbered output occupied a name reserved for another input.'
'PASS: keep-both leaves planned filenames available for other books in the same run.'

New-Case collision KeepBoth;New-Input 'same.cbz';New-Input 'same.pdf'
$report=Join-Path $caseRoot 'preview.json';Run-Worker @('-Preview','-ReportPath',$report)
$preview=Get-Content -LiteralPath $report -Raw -Encoding UTF8|ConvertFrom-Json
Assert (@($preview|Where-Object {$_.ConflictKind-eq'MultipleInputs'}).Count-eq2) 'Preview missed a same-name collision between loose formats.'
Run-Worker
Assert ($workerCode-eq1-and@(Get-ChildItem -LiteralPath $incoming -File).Count-eq2-and@(Get-ChildItem -LiteralPath $output -File).Count-eq0) 'Multiple inputs were silently merged or archived.'
'PASS: preview and worker block ambiguous same-name inputs, including loose CBZ/PDF pairs.'

New-Case retry;New-Input 'Series\book.cbz';New-Input 'Series\fail.pdf'
Run-Worker
Assert ($workerCode-eq1-and(Test-Path -LiteralPath (Join-Path $output 'Series\book.mobi'))) 'Retry fixture did not retain a partly completed batch.'
[IO.File]::WriteAllText((Join-Path $output 'Series\book.mobi'),'changed old output')
$selection=Join-Path $caseRoot 'selection.json';[IO.File]::WriteAllText($selection,(ConvertTo-Json -InputObject @((Join-Path $incoming 'Series\book.cbz'))))
Run-Worker @('-SelectionPath',$selection,'-ExistingOutputAction','KeepBoth')
Assert ($workerCode-eq0-and[IO.File]::ReadAllText((Join-Path $output 'Series\book.mobi'))-eq'changed old output'-and(Test-Path -LiteralPath (Join-Path $output 'Series\book (2).mobi'))-and(Test-Path -LiteralPath (Join-Path $incoming 'Series\book.cbz'))-and(Get-Content -LiteralPath $config -Raw -Encoding UTF8|ConvertFrom-Json).DuplicateAction-eq'Review') 'One-run choice changed the default, ignored selected scope, or archived a pending batch.'
[IO.File]::WriteAllText((Join-Path $fixture 'allow'),'allow')
Run-Worker
Assert ($workerCode-eq0-and(Test-Path -LiteralPath (Join-Path $archive 'Series\book.cbz'))-and-not(Test-Path -LiteralPath (Join-Path $output 'Series\book (3).mobi'))) 'Numbered output receipt was not reused on the next run.'
'PASS: selected keep-both recovers a changed receipt; other inputs and the saved policy remain unchanged, and later retries reuse the numbered receipt.'

New-Case scope;New-Input 'book.cbz'
Run-Worker @('-ExistingOutputAction','Replace')
Assert ($workerCode-ne0-and(Test-Path -LiteralPath (Join-Path $incoming 'book.cbz'))-and@(Get-ChildItem -LiteralPath $output -File).Count-eq0) 'Unscoped one-run replacement was accepted.'
'PASS: one-run duplicate actions require an explicit nonempty selection.'
$empty=Join-Path $caseRoot 'empty-selection.json';[IO.File]::WriteAllText($empty,'[]');Run-Worker @('-SelectionPath',$empty)
Assert ($workerCode-ne0-and(Test-Path -LiteralPath (Join-Path $incoming 'book.cbz'))) 'An empty selection unexpectedly scanned the whole incoming folder.'
'PASS: an empty selection cannot turn into a full-queue run.'

New-Case unicode KeepBoth;$title=([string][char]0x6F2B)+[char]0x753B+' [A]';New-Input ($title+'.cbz');[IO.File]::WriteAllText((Join-Path $output ($title+'.mobi')),'keep unicode')
$selection=Join-Path $caseRoot 'selection.json';[IO.File]::WriteAllText($selection,(ConvertTo-Json -InputObject @((Join-Path $incoming ($title+'.cbz')))))
Run-Worker @('-SelectionPath',$selection,'-ExistingOutputAction','KeepBoth')
Assert ($workerCode-eq0-and(Test-Path -LiteralPath (Join-Path $output ($title+' (2).mobi')))-and(Test-Path -LiteralPath (Join-Path $archive ($title+'.cbz')))) 'Unicode or bracketed filenames were not processed literally.'
'PASS: Unicode and bracketed filenames survive selected duplicate handling.'

Save-Config
$folderReport=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Workspace-Info.ps1') -ConfigPath $config -AvailabilityOnly|ConvertFrom-Json
Assert $folderReport.Ready 'Existing local folders were reported unavailable.'
$missing=Join-Path $caseRoot 'missing-work';$settings.WorkFolder=$missing;Save-Config
$folderReport=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Workspace-Info.ps1') -ConfigPath $config -AvailabilityOnly|ConvertFrom-Json
Assert (-not$folderReport.Ready-and$folderReport.Message.Contains('Working:')-and-not(Test-Path -LiteralPath $missing)) 'Startup availability did not identify the missing folder without creating it.'
'PASS: startup availability accepts local folders, identifies an unavailable folder, and creates or moves no book folders.'
