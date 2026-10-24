$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot ('test-results\upgrades-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$incoming=Join-Path $fixture 'in';$output=Join-Path $fixture 'out';$archive=Join-Path $fixture 'archive';$work=Join-Path $fixture 'work'
foreach($path in @($incoming,$output,$archive,$work)){New-Item -ItemType Directory -Path $path -Force|Out-Null}
$source=Join-Path $fixture 'Mock.cs';$exe=Join-Path $fixture 'mock.exe'
@'
using System;using System.IO;
class Mock {
 public static int Main(string[] a){
  if(Array.IndexOf(a,"--help")>=0){Console.WriteLine("comic2ebook v12.0.0");return 0;}
  string input=a[a.Length-1];
  File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"order.txt"),input+Environment.NewLine);
  if(input.Contains("retryfail") && !File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"allow")))return 1;
  File.WriteAllText(a[Array.IndexOf(a,"--output")+1],"converted "+Path.GetFileName(input));return 0;
 }
}
'@|Set-Content -LiteralPath $source
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe "/out:$exe" $source
if($LASTEXITCODE){throw 'Mock build failed'}
$config=[ordered]@{WatchFolder=$incoming;ConvertedFolder=$output;ArchiveFolder=$archive;WorkFolder=$work;KccExe=$exe;DjxlExe='';QuietMinutes=0;Profile='KS';Format='MOBI';Cropping=0;Splitter=0;MangaStyle=$true;Upscale=$true;ConvertJxl=$true;OverwriteConverted=$false;InputExtensions=@('.cbz','.pdf');OutputNaming='{name}';AutoCleanup=$false;SuccessRetentionDays=7;FailureRetentionDays=30;NotificationMode='Off';FolderRules=@(@{Pattern='A\*';PresetName='Example EPUB';Options=@{Profile='KV';Format='EPUB';Cropping=0;Splitter=0;OutputNaming='{name}-{profile}'}})}
$configPath=Join-Path $fixture 'settings.json'
function Invoke-Worker([string[]]$Options){
 $config|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $configPath -Encoding UTF8
 $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$script:workerLog=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Convert-Manga.ps1') -ConfigPath $configPath @Options 2>&1;$script:workerCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-Cbz($Path,[string]$Entry='001.jpg'){
 $z=[IO.Compression.ZipFile]::Open($Path,'Create');try{$s=$z.CreateEntry($Entry).Open();try{$s.WriteByte(42)}finally{$s.Dispose()}}finally{$z.Dispose()}
}
foreach($name in @('A','B','C')){New-Item -ItemType Directory -Path (Join-Path $incoming $name)|Out-Null}
New-Cbz (Join-Path $incoming 'A\one.cbz');[IO.File]::WriteAllText((Join-Path $incoming 'A\two.pdf'),'PDF')
New-Cbz (Join-Path $incoming 'B\retryfail.cbz');New-Cbz (Join-Path $incoming 'C\retryfail.cbz')
Invoke-Worker
if($workerCode -ne 1 -or -not(Test-Path -LiteralPath (Join-Path $output 'A\one-KV.epub')) -or -not(Test-Path -LiteralPath (Join-Path $output 'A\two-KV.epub'))){throw "Folder preset or naming failed: $workerLog"}
$queue=Get-Content -LiteralPath (Join-Path $work 'queue.json') -Raw|ConvertFrom-Json
if(@($queue|Where-Object Status -EQ 'Failed').Count -ne 2 -or @($queue|Where-Object Status -EQ 'Archived').Count -ne 2){throw 'Durable queue statuses failed'}
'PASS: folder preset, output naming and durable failed/completed queue records.'
[IO.File]::WriteAllText((Join-Path $fixture 'allow'),'allow')
$selection=Join-Path $fixture 'selection.json';ConvertTo-Json -InputObject @((Join-Path $incoming 'B\retryfail.cbz'))|Set-Content -LiteralPath $selection
$before=@(Get-Content -LiteralPath (Join-Path $fixture 'order.txt')).Count
Invoke-Worker @('-SelectionPath',$selection)
$after=@(Get-Content -LiteralPath (Join-Path $fixture 'order.txt')).Count
if($workerCode -ne 0 -or (Test-Path -LiteralPath (Join-Path $incoming 'B')) -or -not(Test-Path -LiteralPath (Join-Path $incoming 'C\retryfail.cbz')) -or $after-$before -ne 1){throw "Selected retry failed: $workerLog"}
'PASS: selected retry processes one book and retains other failed batches.'
New-Cbz (Join-Path $incoming 'jxl.cbz') 'pages/001.jxl'
[IO.File]::WriteAllText((Join-Path $incoming 'ignored.txt'),'notes')
$report=Join-Path $fixture 'queue-report.json'
Invoke-Worker @('-Preview','-ReportPath',$report)
$rows=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
if($workerCode -ne 0 -or @($rows|Where-Object {$_.Name -eq 'jxl.cbz' -and $_.JxlPages -eq 1}).Count -ne 1 -or -not(Test-Path -LiteralPath (Join-Path $incoming 'ignored.txt'))){throw "Rich preview failed: $workerLog"}
'PASS: read-only preview detects JXL pages and unselected companions.'
$job=Join-Path $work ('D'*64);New-Item -ItemType Directory -Path $job|Out-Null
$success=Join-Path $job ('a'*32);$recentFailure=Join-Path $job ('b'*32);$expiredFailure=Join-Path $job ('c'*32)
foreach($path in @($success,$recentFailure,$expiredFailure)){New-Item -ItemType Directory -Path $path|Out-Null;[IO.File]::WriteAllText((Join-Path $path 'scratch'),'scratch')}
[IO.File]::WriteAllText((Join-Path $success 'result.json'),'{"Succeeded":true}')
[IO.File]::WriteAllText((Join-Path $job 'receipt.json'),'keep receipt')
[IO.Directory]::SetLastWriteTimeUtc($success,[DateTime]::UtcNow.AddDays(-10));[IO.Directory]::SetLastWriteTimeUtc($recentFailure,[DateTime]::UtcNow.AddDays(-10));[IO.Directory]::SetLastWriteTimeUtc($expiredFailure,[DateTime]::UtcNow.AddDays(-40))
$config.AutoCleanup=$true
Invoke-Worker @('-CleanupOnly')
if($workerCode -ne 0 -or (Test-Path -LiteralPath $success) -or (Test-Path -LiteralPath $expiredFailure) -or -not(Test-Path -LiteralPath $recentFailure) -or -not(Test-Path -LiteralPath (Join-Path $job 'receipt.json')) -or -not(Test-Path -LiteralPath (Join-Path $incoming 'C\retryfail.cbz'))){throw "Retention cleanup failed: $workerLog"}
'PASS: separate success/failure retention; receipts and originals preserved.'
$target=Join-Path $fixture 'installed';$stage=Join-Path $fixture 'stage';$backup=Join-Path $fixture 'backup'
New-Item -ItemType Directory -Path $target,$stage|Out-Null
$required=@('KCCAutomate.exe','MainWindow.xaml','Convert-Manga.ps1','Workflow-Support.ps1','Manage-Schedule.ps1','Read-Log.ps1','Notify-Result.ps1','Apply-Update.ps1','Workspace-Info.ps1','README.md','license.txt')
$manifest=@()
foreach($name in $required){[IO.File]::WriteAllText((Join-Path $stage $name),"new $name");$manifest+=@{Name=$name;Hash=(Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash}}
foreach($name in @('KCCAutomate.exe','MainWindow.xaml','Convert-Manga.ps1','license.txt')){[IO.File]::WriteAllText((Join-Path $target $name),"old $name")}
$manifestPath=Join-Path $stage 'verified-files.json';ConvertTo-Json -InputObject $manifest|Set-Content -LiteralPath $manifestPath
$manifestHash=(Get-FileHash -LiteralPath $manifestPath).Hash
function Invoke-Installer([string[]]$Options){
 $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$script:installLog=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Apply-Update.ps1') -TargetDirectory $target -ConfigPath $configPath -BackupDirectory $backup -NoRelaunch @Options 2>&1;$script:installCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
}
$handle=[IO.File]::Open((Join-Path $work 'running.lock'),'OpenOrCreate','ReadWrite','None')
try{Invoke-Installer @('-StageDirectory',$stage,'-ManifestHash',$manifestHash)}finally{$handle.Dispose()}
if($installCode -eq 0 -or [IO.File]::ReadAllText((Join-Path $target 'KCCAutomate.exe')) -ne 'old KCCAutomate.exe'){throw 'Updater ignored conversion lock'}
'PASS: app update is blocked while conversion lock is held.'
Invoke-Installer @('-StageDirectory',$stage,'-ManifestHash',$manifestHash)
if($installCode -ne 0 -or [IO.File]::ReadAllText((Join-Path $target 'KCCAutomate.exe')) -ne 'new KCCAutomate.exe' -or -not(Test-Path -LiteralPath (Join-Path $backup 'backup-info.json'))){throw "Update installation failed: $installLog"}
if([IO.File]::ReadAllText((Join-Path $target 'license.txt')) -ne 'new license.txt'){throw 'The app update did not carry the licence notices.'}
Invoke-Installer @('-Rollback')
if($installCode -ne 0 -or [IO.File]::ReadAllText((Join-Path $target 'KCCAutomate.exe')) -ne 'old KCCAutomate.exe' -or (Test-Path -LiteralPath (Join-Path $target 'Notify-Result.ps1'))){throw "Rollback failed: $installLog"}
if([IO.File]::ReadAllText((Join-Path $target 'license.txt')) -ne 'old license.txt'){throw 'Rollback did not restore the corresponding licence notices.'}
'PASS: verified update, backup creation and restoration of the old file set.'
[IO.File]::WriteAllText((Join-Path $stage 'KCCAutomate.exe'),'tampered')
Invoke-Installer @('-StageDirectory',$stage,'-ManifestHash',$manifestHash)
if($installCode -eq 0 -or [IO.File]::ReadAllText((Join-Path $target 'KCCAutomate.exe')) -ne 'old KCCAutomate.exe'){throw 'Tampered update accepted'}
'PASS: tampered staged update rejected without changing installed files.'
