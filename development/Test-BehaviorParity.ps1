$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$corpus=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'contracts\behavior-v1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($corpus.schemaVersion -ne 1) { throw 'Unsupported behavior corpus.' }
$root=Join-Path $PSScriptRoot ('test-results\bp-'+[Guid]::NewGuid().ToString('N').Substring(0,10))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$mockSource=Join-Path $root 'Mock.cs'; $mock=Join-Path $root 'mock.exe'
@'
using System;using System.IO;
class Mock {
 static int Main(string[] args) {
  if(Array.IndexOf(args,"--help")>=0){Console.WriteLine("comic2ebook v12.0.0 --profile --format");return 0;}
  string home=AppDomain.CurrentDomain.BaseDirectory,input=args[args.Length-1];
  File.AppendAllText(Path.Combine(home,"calls.txt"),Path.GetExtension(input)+Environment.NewLine);
  Console.Error.WriteLine("ordinary converter progress");
  if(Path.GetFileName(input)=="fail.pdf"&&!File.Exists(Path.Combine(home,"allow")))return 1;
  if(Path.GetFileName(input)=="empty.cbz")return 0;
  int outputIndex=Array.IndexOf(args,"--output");if(outputIndex<0)return 3;
  string output=args[outputIndex+1];
  if(Path.GetFileName(input)=="split.cbz") {
   string folder=Path.GetDirectoryName(output),extension=Path.GetExtension(output);
   File.WriteAllText(Path.Combine(folder,"book_001"+extension),"part one");
   File.WriteAllText(Path.Combine(folder,"book_002"+extension),"part two");
  } else File.WriteAllText(output,"converted "+Path.GetFileName(input));
  return 0;
 }
}
'@ | Set-Content -LiteralPath $mockSource -Encoding UTF8
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe "/out:$mock" $mockSource
if ($LASTEXITCODE) { throw 'Behavior converter fixture failed to compile.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Child-Path($Parent,$Relative) {
 if (!$Relative -or $Relative -match '\\|(^|/)\.\.?(/|$)' -or [IO.Path]::IsPathRooted($Relative)) { throw 'Unsafe fixture path.' }
 $result=[IO.Path]::GetFullPath((Join-Path $Parent $Relative.Replace('/','\')))
 if (!$result.StartsWith([IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture escaped its root.' }
 return $result
}
function Tree($Folder) {
 @(Get-ChildItem -LiteralPath $Folder -File -Recurse | ForEach-Object { $_.FullName.Substring($Folder.Length+1).Replace('\','/') } | Sort-Object)
}
function Equal-List($Actual,$Expected,$Label) {
 if ((@($Actual) -join "`n") -cne (@($Expected) -join "`n")) { throw ($Label+': expected '+(@($Expected)-join ', ')+'; got '+(@($Actual)-join ', ')) }
}
$stateNames=@{'Waiting'='waiting';'Waiting for download'='waiting-download';'Converting'='converting';'Converted'='converted';'Archived'='archived';'Conflict'='conflict';'Failed'='failed';'Skipped existing output'='skipped-existing';'Accompanying'='accompanying';'Ignored'='ignored'}
$number=0; $runs=0
foreach ($scenario in $corpus.scenarios) {
 $number++; $case=Join-Path $root ('c'+$number)
 $areas=@{}; $initial=@{}
 foreach ($area in @('incoming','converted','originals','working')) { $areas[$area]=Join-Path $case $area; New-Item -ItemType Directory -Path $areas[$area] -Force | Out-Null }
 foreach ($area in @('incoming','converted','originals')) {
  foreach ($file in @($scenario.files.$area)) {
   if (!$file) { continue }
   $path=Child-Path $areas[$area] $file.path
   New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
   if ($file.kind -in @('cbz','jxl-cbz')) {
    $zip=[IO.Compression.ZipFile]::Open($path,'Create')
    try { $stream=$zip.CreateEntry($(if($file.kind -eq 'jxl-cbz'){'001.jxl'}else{'001.jpg'})).Open(); try {$stream.WriteByte(42)} finally {$stream.Dispose()} } finally {$zip.Dispose()}
   } else { [IO.File]::WriteAllText($path,[string]$file.content) }
   [IO.File]::SetLastWriteTimeUtc($path,[DateTime]::UtcNow.AddMinutes(-[double]$file.ageMinutes))
   $initial[$area+':'+$file.path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  }
 }
 $settings=[ordered]@{WatchFolder=$areas.incoming;ConvertedFolder=$areas.converted;ArchiveFolder=$areas.originals;WorkFolder=$areas.working;KccExe=$mock;DjxlExe='';OverwriteConverted=$false;NotificationMode='Off';FolderRules=@()}
 foreach ($property in $corpus.settings.PSObject.Properties) { $settings[$property.Name]=$property.Value }
 foreach ($property in $scenario.settings.PSObject.Properties) { $settings[$property.Name]=$property.Value }
 $config=Join-Path $case 'settings.json'
 [IO.File]::WriteAllText($config,($settings | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
 $allow=Join-Path $root 'allow'
 if (Test-Path -LiteralPath $allow) { Remove-Item -LiteralPath $allow }
 foreach ($run in $scenario.runs) {
  $runs++
  if ($run.allowFailures) { [IO.File]::WriteAllText($allow,'allow') }
  $calls=Join-Path $root 'calls.txt'; $before=0
  if (Test-Path -LiteralPath $calls) { $before=@(Get-Content -LiteralPath $calls).Count }
  $options=@()
  if ($run.command -eq 'preview') { $options+=@('-Preview') }
  if ($run.stopBeforeRun) {
   $stop=Join-Path $case 'stop'
   [IO.File]::WriteAllText($stop,'stop')
   $options+=@('-StopFile',$stop)
  }
  if ($run.PSObject.Properties['selection']) {
   $selection=Join-Path $case 'selection.json'
   $selected=@($run.selection | ForEach-Object { Child-Path $areas.incoming $_ })
   [IO.File]::WriteAllText($selection,(ConvertTo-Json -InputObject $selected),[Text.UTF8Encoding]::new($false))
   $options+=@('-SelectionPath',$selection)
  }
  $savedPreference=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try { $log=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $project 'app\Convert-Manga.ps1') -ConfigPath $config @options 2>&1); $code=$LASTEXITCODE } finally { $ErrorActionPreference=$savedPreference }
  $log | Out-File -LiteralPath (Join-Path $case ('run-'+$runs+'.txt')) -Encoding UTF8
  if ($code -ne $run.expect.windowsExitCode) { throw ($scenario.id+': wrong exit code '+$code+"`n"+($log -join "`n")) }
  foreach ($area in @('incoming','converted','originals')) { Equal-List @(Tree $areas[$area]) @($run.expect.trees.$area | Sort-Object) ($scenario.id+' '+$area) }
  $actualCalls=@(); if (Test-Path -LiteralPath $calls) { $actualCalls=@(Get-Content -LiteralPath $calls | Select-Object -Skip $before) }
  Equal-List $actualCalls @($run.expect.callFormats) ($scenario.id+' converter order')
  foreach ($key in $run.expect.unchanged) {
   $parts=$key.Split(':',2); $path=Child-Path $areas[$parts[0]] $parts[1]
   if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $initial[$key]) { throw ($scenario.id+': source/existing output changed: '+$key) }
  }
  foreach ($relative in $run.expect.archivedFromIncoming) {
   if ((Get-FileHash -LiteralPath (Child-Path $areas.originals $relative) -Algorithm SHA256).Hash -ne $initial['incoming:'+$relative]) { throw ($scenario.id+': archive differs from source: '+$relative) }
  }
  $states=@{}
  foreach ($line in $log) {
   if ([string]$line -match '^@@MF:(.+)$') {
    $row=$Matches[1] | ConvertFrom-Json
    $relative=$row.SourcePath.Substring($areas.incoming.Length+1).Replace('\','/')
    $states[$relative]=$stateNames[$row.Status]
   }
  }
  foreach ($property in $run.expect.states.PSObject.Properties) {
   if ($states[$property.Name] -ne $property.Value) { throw ($scenario.id+': wrong queue state for '+$property.Name) }
  }
 }
 'PASS: '+$scenario.id
}
'Behavior parity: '+$number+' shared scenarios, '+$runs+' Windows worker runs; originals and existing outputs verified by hash.'
