$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot ('test-results\i-'+[guid]::NewGuid().ToString('N').Substring(0,12))
New-Item -ItemType Directory -Path $root -Force|Out-Null
$setup=Join-Path $PSScriptRoot 'dist\MangaFlow-Setup.exe'
$target=Join-Path $root 'installed'
function Run-Installer($Program,$Mode,$Folder){
 $process=Start-Process -FilePath $Program -ArgumentList @($Mode,('"'+$Folder+'"')) -WindowStyle Hidden -Wait -PassThru
 $script:installerCode=$process.ExitCode
}
Run-Installer $setup '--test-install' $target
if($installerCode -ne 0){throw (Get-Content -LiteralPath ($target+'.setup-error.txt') -Raw)}
$manifest=Join-Path $target '.mangaflow-install.json'
if(-not(Test-Path -LiteralPath $manifest)-or(Test-Path -LiteralPath (Join-Path $target 'portable.flag'))){throw 'Installed-mode payload/record incorrect'}
$record=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
foreach($name in $record.Files){if(-not(Test-Path -LiteralPath (Join-Path $target $name))){throw "Installed file missing: $name"}}
$source=Join-Path $PSScriptRoot 'dist\MangaFlow\MangaFlow.exe'
if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath (Join-Path $target 'MangaFlow.exe')).Hash){throw 'Installed executable differs'}
'PASS: embedded installer payload, checksums, complete installed file set and installed-mode settings separation.'
New-Item -ItemType Directory -Path (Join-Path $target 'data'),(Join-Path $target 'Books')|Out-Null
[IO.File]::WriteAllText((Join-Path $target 'data\settings.json'),'keep settings')
[IO.File]::WriteAllText((Join-Path $target 'Books\original.cbz'),'keep book')
Run-Installer $setup '--test-install' $target
if($installerCode -ne 0-or[IO.File]::ReadAllText((Join-Path $target 'data\settings.json'))-ne'keep settings'){throw 'Installer upgrade lost user data'}
'PASS: installing over an owned installation preserves user files.'
$before=Get-Content -LiteralPath $manifest -Raw
$record.Files+= '..\outside.txt'
$record|ConvertTo-Json|Set-Content -LiteralPath $manifest
[IO.File]::WriteAllText((Join-Path $root 'outside.txt'),'keep outside')
Run-Installer (Join-Path $PSScriptRoot 'dist\Uninstall-MangaFlow.exe') '--test-remove' $target
if($installerCode -eq 0-or-not(Test-Path -LiteralPath (Join-Path $target 'MangaFlow.exe'))-or[IO.File]::ReadAllText((Join-Path $root 'outside.txt'))-ne'keep outside'){throw 'Uninstaller accepted an unsafe record'}
[IO.File]::WriteAllText($manifest,$before)
Run-Installer (Join-Path $PSScriptRoot 'dist\Uninstall-MangaFlow.exe') '--test-remove' $target
if($installerCode -ne 0-or(Test-Path -LiteralPath (Join-Path $target 'MangaFlow.exe'))-or[IO.File]::ReadAllText((Join-Path $target 'data\settings.json'))-ne'keep settings'-or[IO.File]::ReadAllText((Join-Path $target 'Books\original.cbz'))-ne'keep book'){throw 'Safe removal failed'}
'PASS: uninstaller rejects traversal and removes only owned application files, retaining books and settings.'
$unrelated=Join-Path $root 'unrelated';New-Item -ItemType Directory -Path $unrelated|Out-Null;[IO.File]::WriteAllText((Join-Path $unrelated 'book.cbz'),'do not replace')
Run-Installer $setup '--test-install' $unrelated
if($installerCode -eq 0-or[IO.File]::ReadAllText((Join-Path $unrelated 'book.cbz'))-ne'do not replace'){throw 'Installer accepted an unrelated nonempty folder'}
'PASS: installer refuses to overwrite an unrelated nonempty folder.'
# Exercise the wizard's isolated test with a real child process and mock KCC.
$mockSource=Join-Path $root 'Mock.cs';$mock=Join-Path $root 'kcc-c2e.exe'
@'
using System;using System.IO;
class Mock{public static int Main(string[] a){if(Array.IndexOf(a,"--help")>=0){Console.WriteLine("comic2ebook v12.0.0");return 0;}if(!Environment.GetEnvironmentVariable("PATH").Split(';')[0].Equals(AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\'),StringComparison.OrdinalIgnoreCase))throw new Exception("Selected KindleGen directory was not passed to the converter.");File.WriteAllText(a[Array.IndexOf(a,"--output")+1],"mock converted book");return 0;}}
'@|Set-Content -LiteralPath $mockSource
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe "/out:$mock" $mockSource
if($LASTEXITCODE){throw 'Mock compiler failed'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$book=Join-Path $root 'source.cbz';$zip=[IO.Compression.ZipFile]::Open($book,'Create');try{$stream=$zip.CreateEntry('001.jpg').Open();try{$stream.WriteByte(42)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
$hash=(Get-FileHash -LiteralPath $book).Hash
$watch=Join-Path $root 'normal-input';$output=Join-Path $root 'normal-output';$archive=Join-Path $root 'normal-archive';$work=Join-Path $root 'normal-work'
foreach($folder in @($watch,$output,$archive,$work)){New-Item -ItemType Directory -Path $folder|Out-Null}
[IO.File]::WriteAllText((Join-Path $watch 'untouched.cbz'),'normal incoming')
$config=@{WatchFolder=$watch;ConvertedFolder=$output;ArchiveFolder=$archive;WorkFolder=$work;KccExe=$mock;KindlegenExe=$mock;DjxlExe='';QuietMinutes=30;Profile='KS';Format='MOBI';Cropping=0;Splitter=0;ConvertJxl=$false;InputExtensions=@('.cbz');OutputNaming='{name}';NotificationMode='Off'}
$configPath=Join-Path $root 'settings.json';$config|ConvertTo-Json|Set-Content -LiteralPath $configPath
$report=Join-Path $root 'test-conversion.json'
$process=Start-Process -FilePath $source -ArgumentList @('--test-setup',('"'+$configPath+'"'),('"'+$book+'"'),('"'+$report+'"')) -WindowStyle Hidden -Wait -PassThru
$result=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
if($process.ExitCode -ne 0-or-not$result.Passed){throw "Setup test conversion failed: $($result.Log)"}
if((Get-FileHash -LiteralPath $book).Hash-ne$hash-or[IO.File]::ReadAllText((Join-Path $watch 'untouched.cbz'))-ne'normal incoming'-or@(Get-ChildItem -LiteralPath $output).Count-or@(Get-ChildItem -LiteralPath $archive).Count){throw 'Wizard test affected the original or normal folders'}
if(-not(Test-Path -LiteralPath (Join-Path $result.Output 'sample.mobi'))){throw 'Wizard test output missing'}
'PASS: wizard test converts an isolated copy and leaves the selected original and normal queue/archive/output unchanged.'
'Installer tests skipped actual registry, shortcut and scheduled-task registration; no application was installed on this PC.'
"Test fixtures retained at: $root"
