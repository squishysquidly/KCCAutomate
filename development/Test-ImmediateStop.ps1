$ErrorActionPreference='Stop'
[void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'dist\KCCAutomate\KCCAutomate.exe'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=Join-Path $PSScriptRoot ('test-results\stop-'+[guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $root -Force|Out-Null
$src=Join-Path $root 'Mock.cs'
@"
using System;using System.IO;using System.Diagnostics;using System.Threading;
class Mock {
 static int Main(string[] args){
  string root=AppDomain.CurrentDomain.BaseDirectory;
  if(args.Length>0&&args[0]=="child"){Thread.Sleep(60000);return 0;}
  if(Array.IndexOf(args,"--help")>=0){Console.WriteLine("comic2ebook v99.0.0 --profile --format KS1860");return 0;}
  int outputIndex=Array.IndexOf(args,"--output");bool decoder=outputIndex<0;
  string output=args[decoder?1:outputIndex+1];File.WriteAllText(output,"partial output must not be published on cancellation");
  if(!File.Exists(Path.Combine(root,"fast"))){
   var child=Process.Start(new ProcessStartInfo(Environment.GetCommandLineArgs()[0],"child"){UseShellExecute=false,CreateNoWindow=true});
   File.WriteAllText(Path.Combine(root,"pids.txt"),Process.GetCurrentProcess().Id+" "+child.Id);
   Thread.Sleep(60000);
  }
  if(decoder)File.WriteAllBytes(output,new byte[]{137,80,78,71,13,10,26,10});else File.WriteAllText(output,"verified fixture output");return 0;
 }
}
"@|Set-Content -LiteralPath $src -Encoding utf8
$mock=Join-Path $root 'mock.exe'; & "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe ("/out:"+$mock) $src
if($LASTEXITCODE){throw 'Stop fixture compilation failed'}
foreach($mode in @('Archive','Delete','Jxl')){
 $case=Join-Path $root $mode;New-Item -ItemType Directory -Path $case -Force|Out-Null;$tool=Join-Path $case 'kcc-c2e.exe';Copy-Item -LiteralPath $mock -Destination $tool
 $input=Join-Path $case 'in';$output=Join-Path $case 'out';$archive=Join-Path $case 'originals';$work=Join-Path $case 'w';New-Item -ItemType Directory -Path $input,$output,$archive,$work -Force|Out-Null
 $page=if($mode-eq'Jxl'){'001.jxl'}else{'001.jpg'}
 $book=Join-Path $input 'Series v01.cbz';$zip=[IO.Compression.ZipFile]::Open($book,'Create');try{$s=$zip.CreateEntry($page).Open();try{$s.WriteByte(42)}finally{$s.Dispose()}}finally{$zip.Dispose()};$hash=(Get-FileHash -LiteralPath $book).Hash
 $action=if($mode-eq'Delete'){'Delete'}else{'Archive'}
 $settings=@{WatchFolder=$input;ConvertedFolder=$output;ArchiveFolder=$archive;WorkFolder=$work;KccExe=$tool;DjxlExe=$tool;QuietMinutes=0;Profile='KS';Format='EPUB';MangaStyle=$true;Cropping=0;Splitter=0;ConvertJxl=($mode-eq'Jxl');InputExtensions=@('.cbz');OutputNaming='{name}';NotificationMode='Off';OriginalsAction=$action;DeleteOriginalsConfirmed=($mode-eq'Delete')}
 $config=Join-Path $case 'settings.json';$settings|ConvertTo-Json|Set-Content -LiteralPath $config -Encoding utf8
 $workerScript=if($mode-eq'Jxl'){Join-Path $PSScriptRoot 'dist\KCCAutomate\Convert-Manga.ps1'}else{Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Convert-Manga.ps1'}
 $stop=Join-Path $case 'stop';$args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$workerScript,'-ConfigPath',$config)
 if($mode-eq'Archive'){$args+=@('-StopFile',$stop)}
 $unrelated=Start-Process -FilePath $tool -ArgumentList 'child' -WindowStyle Hidden -PassThru;$null=$unrelated.Handle
 $worker=Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $case 'worker.out') -RedirectStandardError (Join-Path $case 'worker.err')
 $null=$worker.Handle
 $parent=$null;$child=$null
 try{
  $deadline=[DateTime]::UtcNow.AddSeconds(25);$pids=Join-Path $case 'pids.txt'
  while(-not(Test-Path -LiteralPath $pids)-and[DateTime]::UtcNow-lt$deadline-and-not$worker.HasExited){Start-Sleep -Milliseconds 80}
  if(-not(Test-Path -LiteralPath $pids)){throw ('Converter did not start: '+(Get-Content -LiteralPath (Join-Path $case 'worker.err') -Raw))}
  $ids=([IO.File]::ReadAllText($pids)).Split(' ');$parent=[Diagnostics.Process]::GetProcessById([int]$ids[0]);$child=[Diagnostics.Process]::GetProcessById([int]$ids[1]);$watch=[Diagnostics.Stopwatch]::StartNew()
  if($mode-eq'Archive'){[IO.File]::WriteAllText($stop,'now')}else{$run=[KCCAutomate.ConversionControl]::Read($work);if(-not$run-or-not[KCCAutomate.ConversionControl]::Request($work,$run.RunId,$true)){throw 'Could not signal scheduled-style run'}}
  if(-not$worker.WaitForExit(12000)){throw 'Immediate stop did not finish within 12 seconds'}
  if($worker.ExitCode-ne2){throw ('Wrong stop exit code '+$worker.ExitCode+': '+(Get-Content -LiteralPath (Join-Path $case 'worker.err') -Raw))}
  if(-not$parent.HasExited-or-not$child.HasExited){throw 'Converter or child process survived cancellation'}
  if($unrelated.HasExited){throw 'Stop terminated an unrelated process with the same executable name'}
  if(-not(Test-Path -LiteralPath $book)-or(Get-FileHash -LiteralPath $book).Hash-ne$hash-or@(Get-ChildItem -LiteralPath $output -Recurse -File).Count-or@(Get-ChildItem -LiteralPath $archive -Recurse -File).Count){throw 'Cancellation published partial output or moved/removed originals'}
  if((Get-Content -LiteralPath (Join-Path $work 'queue.json') -Raw|ConvertFrom-Json).Status-ne'Stopped'){throw 'Cancelled book did not have Stopped status'}
  if(Test-Path -LiteralPath (Join-Path $work 'active-run.json')){throw 'Active run metadata was not cleaned'}
  $lock=[IO.File]::Open((Join-Path $work 'running.lock'),'Open','ReadWrite','None');$lock.Dispose()
  'PASS: '+$mode+' mode stops the converter tree in '+$watch.Elapsed.TotalSeconds.ToString('0.0')+'s, retains original hashes, publishes nothing and releases the run lock.'
 }finally{
  if(-not$worker.HasExited){$i=[Diagnostics.ProcessStartInfo]::new((Join-Path $env:WINDIR 'System32\taskkill.exe'),('/PID '+$worker.Id+' /T /F'));$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$p=[Diagnostics.Process]::Start($i);$p.WaitForExit();$p.Dispose()}
  if($parent){$parent.Dispose()};if($child){$child.Dispose()};$worker.Dispose()
  if(-not$unrelated.HasExited){$unrelated.Kill();$unrelated.WaitForExit()};$unrelated.Dispose()
 }
 if(Test-Path -LiteralPath $stop){Remove-Item -LiteralPath $stop};[IO.File]::WriteAllText((Join-Path $case 'fast'),'resume')
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $workerScript -ConfigPath $config *> (Join-Path $case 'retry.log')
 if($LASTEXITCODE-ne0-or-not@(Get-ChildItem -LiteralPath $output -Recurse -File).Count){throw 'Retry after cancellation failed'}
 'PASS: '+$mode+' mode resumes and completes the previously stopped book.'
}
