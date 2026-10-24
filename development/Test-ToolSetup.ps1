$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot ('test-results\tools-'+[guid]::NewGuid().ToString('N').Substring(0,10))
$source=Join-Path $root 'downloads';New-Item -ItemType Directory -Path $source -Force|Out-Null
[void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'dist\KCCAutomate\KCCAutomate.exe'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Assert($condition,$message){if(-not $condition){throw $message}}
$mockSource=Join-Path $root 'Mock.cs'
@'
using System;using System.IO;
class Mock {
 public static int Main(string[] args) {
  string root=AppDomain.CurrentDomain.BaseDirectory,name=Path.GetFileName(Environment.GetCommandLineArgs()[0]).ToLowerInvariant();
  if(name=="kindlegen.exe"){Console.WriteLine("Amazon kindlgen(Windows) V2.0 build 0000-kdevld\nA command line e-book compiler");if(Array.IndexOf(args,"-help")>=0)Console.WriteLine("Error(kindlegen):E30010:Unsupported argument -help");return 1;}
  if(name=="djxl.exe") {if(!File.Exists(Path.Combine(root,"codec.dll"))||!File.Exists(Path.Combine(root,@"..\lib\support.dat")))return 2;Console.WriteLine("djxl JPEG XL decoder");return 0;}
  if(File.Exists(Path.Combine(root,"broken"))){Console.Error.WriteLine("ModuleNotFoundError: No module named 'PySide6'");return 1;}
  if(!File.Exists(Path.Combine(root,@"_internal\required.dat"))||!File.Exists(Path.Combine(root,"helper.dll")))return 3;
  if(Array.IndexOf(args,"--help")>=0){Console.WriteLine("comic2ebook v"+(File.Exists(Path.Combine(root,"future"))?"13.0.0":"12.0.0")+" --profile --format");return 0;}
  string path=Environment.GetEnvironmentVariable("PATH");bool mobi=Array.IndexOf(args,"MOBI")>=0;
  if(mobi?(!File.Exists(Path.Combine(path.Split(';')[0],"kindlegen.exe"))||!File.Exists(Path.Combine(path.Split(';')[1],"7z.exe"))):!File.Exists(Path.Combine(path.Split(';')[0],"7z.exe")))return 4;
  File.WriteAllText(args[Array.IndexOf(args,"--output")+1],"mock converted book");return 0;
 }
}
'@|Set-Content -LiteralPath $mockSource
$kccFolder=Join-Path $source 'kcc';New-Item -ItemType Directory -Path (Join-Path $kccFolder '_internal') -Force|Out-Null
$kcc=Join-Path $kccFolder 'kcc-c2e.exe'
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe "/out:$kcc" $mockSource
Assert ($LASTEXITCODE-eq 0) 'Mock compiler failed'
[IO.File]::WriteAllText((Join-Path $kccFolder '_internal\required.dat'),'runtime')
[IO.File]::WriteAllText((Join-Path $kccFolder 'helper.dll'),'companion')
[IO.File]::WriteAllText((Join-Path $kccFolder 'LICENSE.txt'),'license')
[IO.File]::WriteAllText((Join-Path $kccFolder 'unrelated.cbz'),'never copy a book')
$kindle=Join-Path $source 'kindlegen.exe';Copy-Item -LiteralPath $kcc -Destination $kindle
$jxlFolder=Join-Path $source 'jxl-package';New-Item -ItemType Directory -Path (Join-Path $jxlFolder 'tools'),(Join-Path $jxlFolder 'lib') -Force|Out-Null
Copy-Item -LiteralPath $kcc -Destination (Join-Path $jxlFolder 'tools\djxl.exe')
[IO.File]::WriteAllText((Join-Path $jxlFolder 'tools\codec.dll'),'decoder runtime')
$unicodeCompanion='codec[1]'+[char]0x65E5+[char]0x672C+[char]0x8A9E+'.dll'
[IO.File]::WriteAllText((Join-Path $jxlFolder ('tools\'+$unicodeCompanion)),'Unicode companion')
[IO.File]::WriteAllText((Join-Path $jxlFolder 'lib\support.dat'),'sibling runtime')
[IO.File]::WriteAllText((Join-Path $jxlFolder 'LICENSE'),'decoder license')
New-Item -ItemType Directory -Path (Join-Path $jxlFolder 'samples') -Force|Out-Null
Copy-Item -LiteralPath $kcc -Destination (Join-Path $jxlFolder 'tools\cjxl.exe')
[IO.File]::WriteAllText((Join-Path $jxlFolder 'samples\example.jxl'),'unused sample')
$settings=New-Object KCCAutomate.Settings
Assert ([string]::IsNullOrEmpty($settings.KccExe)-and[string]::IsNullOrEmpty($settings.DjxlExe)) 'Fresh tool paths should be blank'
$settings.KccExe=$kcc;$settings.KindlegenExe=$kindle
$seven='C:\Program Files\7-Zip\7z.exe'
Assert (Test-Path -LiteralPath $seven) 'Install 7-Zip for the real .7z integration test'
$settings.SevenZipExe=$seven
Assert ([KCCAutomate.SetupChecks]::FindUsableSevenZip([string[]]@($seven))-eq$seven) 'Usable installed 7-Zip CLI was not found'
Assert ([KCCAutomate.SetupChecks]::ResolveToolPath('Kcc',$kccFolder)-eq$kcc) 'KCC folder selection did not resolve its CLI'
Assert ([KCCAutomate.SetupChecks]::ResolveToolPath('SevenZip',(Split-Path $seven))-eq$seven) '7-Zip folder selection did not resolve its CLI'
$kindleBanner="Amazon kindlgen(Windows) V2.0 build 0000-kdevld`nA command line e-book compiler`n"
Assert ([KCCAutomate.ToolValidation]::KindlegenReplyValid(1,($kindleBanner+'Error(kindlegen):E30010:Unsupported argument -help'))) 'The reported KindleGen version/help error was incorrectly rejected'
Assert (-not[KCCAutomate.ToolValidation]::KindlegenReplyValid(1,($kindleBanner+'Error(kindlegen):E99999:Failure'))) 'Unexpected KindleGen errors were accepted'
Assert (-not[KCCAutomate.ToolValidation]::KindlegenReplyValid(1,'Unrelated program usage')) 'An unrelated program was accepted as KindleGen'
'PASS: installed 7-Zip creates and extracts an archive; folder paths resolve to tools; the reported kindlgen banner and expected help error are accepted while unrelated programs/fatal errors are rejected.'
$locations=Join-Path $root 'installation-locations'
$emptyInstall=Join-Path $locations 'Amazon\Kindle Previewer 4'
$workingInstall=Join-Path $locations 'Amazon\Kindle Previewer 3'
$compilerFolder=Join-Path $workingInstall 'lib\fc\bin'
New-Item -ItemType Directory -Path $emptyInstall,$compilerFolder -Force|Out-Null
$locatedKindle=Join-Path $compilerFolder 'kindlegen.exe';[IO.File]::WriteAllText($locatedKindle,'locator fixture only; never execute')
$candidates=[string[]]@($emptyInstall,$workingInstall)
Assert ([KCCAutomate.KindleGenGuide]::FindFolder('', $candidates)-eq$compilerFolder) 'A newer empty installation hid an older working KindleGen location'
Assert ([KCCAutomate.KindleGenGuide]::FindFolder(('"'+$kindle+'"'),$candidates)-eq(Split-Path $kindle)) 'The existing selected compiler location was not preferred'
Assert ([KCCAutomate.KindleGenGuide]::FindFolder($workingInstall,[string[]]@())-eq$compilerFolder) 'A selected custom Previewer folder did not open its compiler subfolder'
Assert ([KCCAutomate.KindleGenGuide]::FindFolder('',[string[]]@($emptyInstall))-eq$emptyInstall) 'An installed folder without KindleGen could not be opened for manual inspection'
$missingInstall=Join-Path $locations 'not-installed'
Assert ($null-eq[KCCAutomate.KindleGenGuide]::FindFolder('',[string[]]@($missingInstall))) 'A missing installation yielded a folder to open'
Assert (-not(Test-Path -LiteralPath $missingInstall)) 'The folder locator created a missing installation'
$known=[KCCAutomate.KindleGenGuide]::InstallationRoots($locations,'','')
Assert (($known-contains(Join-Path $locations 'Amazon\Kindle Previewer 4'))-and($known-contains(Join-Path $locations 'Programs\Kindle Previewer 3'))-and($known-contains(Join-Path $locations 'Amazon\Kindle Comic Creator'))) 'Known installation locations omitted Previewer or Comic Creator'
Assert ([IO.File]::ReadAllText($locatedKindle)-eq'locator fixture only; never execute') 'Locating KindleGen changed the file'
'PASS: illustrated-guide folder lookup prefers the selected copy and folders containing KindleGen; supports custom, Previewer and Comic Creator locations; handles absent installations without creating, copying or executing files.'
$managed=Join-Path $root 'app-data\Tools'
$zip=Join-Path $source 'jxl.zip';[IO.Compression.ZipFile]::CreateFromDirectory($jxlFolder,$zip)
$settings.DjxlExe=[KCCAutomate.ManagedTools]::PrepareJxl($zip,$seven,$managed)
$selectedRoot=Split-Path (Split-Path $settings.DjxlExe)
Assert (-not(Test-Path -LiteralPath (Join-Path $selectedRoot 'tools\cjxl.exe'))-and-not(Test-Path -LiteralPath (Join-Path $selectedRoot 'samples\example.jxl'))) 'ZIP import extracted unrelated utilities or samples'
Assert ((Test-Path -LiteralPath (Join-Path $selectedRoot 'LICENSE'))-and(Test-Path -LiteralPath (Join-Path $selectedRoot 'lib\support.dat'))) 'Selective ZIP import omitted a licence or runtime companion'
$checks=[KCCAutomate.ToolValidation]::Check($settings)
Assert ([KCCAutomate.ToolValidation]::Passed($checks)) ([KCCAutomate.ToolValidation]::Report($checks))
'PASS: fresh paths are empty; KCC, djxl, KindleGen and actual 7-Zip identify themselves independently.'
$copy=[KCCAutomate.ManagedTools]::Import($settings,$managed)
Assert ((Test-Path -LiteralPath (Join-Path (Split-Path $copy.KccExe) '_internal\required.dat'))-and(Test-Path -LiteralPath (Join-Path (Split-Path $copy.KccExe) 'helper.dll'))-and(Test-Path -LiteralPath (Join-Path (Split-Path $copy.KccExe) 'LICENSE.txt'))) 'KCC companion files were lost'
Assert (-not(Test-Path -LiteralPath (Join-Path (Split-Path $copy.KccExe) 'unrelated.cbz'))) 'Import copied an unrelated book'
Assert (Test-Path -LiteralPath (Join-Path (Split-Path $copy.SevenZipExe) '7z.dll')) '7-Zip runtime DLL was lost'
Assert ($copy.KccExe-eq([KCCAutomate.ManagedTools]::Import($copy,$managed)).KccExe) 'Returning to Continue should reuse verified managed tools'
'PASS: verified managed copies preserve KCC runtime folders, JXL sibling libraries, 7-Zip DLL and license files; repeated Continue reuses a verified bundle.'
$settings.KccExe=Join-Path $kccFolder 'kcc.exe';Copy-Item -LiteralPath $kcc -Destination $settings.KccExe
$checks=[KCCAutomate.ToolValidation]::Check($settings)
Assert (-not[KCCAutomate.ToolValidation]::Passed($checks)) 'Graphical KCC executable was accepted'
Assert (@($checks|Where-Object Passed).Count-eq 3) 'One failed tool should not conceal the other tool checks'
$settings.KccExe=$kcc;[IO.File]::WriteAllText((Join-Path $kccFolder 'broken'),'broken package')
$failure=([KCCAutomate.ToolValidation]::Check($settings)|Where-Object Key -EQ Kcc)
Assert (-not$failure.Passed-and$failure.Message.Contains('12.0.0')-and$failure.Message.Contains('PySide6')) 'Broken PyInstaller package guidance missing'
Remove-Item -LiteralPath (Join-Path $kccFolder 'broken')
'PASS: wrong KCC executable and PySide6 failure produce specific errors while other checklist results remain available.'
$sevenArchive=Join-Path $source 'jxl.7z'
& $seven a -t7z $sevenArchive (Join-Path $jxlFolder '*') -bso0 -bsp0
Assert ($LASTEXITCODE-eq 0) '7-Zip fixture creation failed'
$decoder=[KCCAutomate.ManagedTools]::PrepareJxl($sevenArchive,$seven,$managed)
$selectedRoot=Split-Path (Split-Path $decoder)
Assert (-not(Test-Path -LiteralPath (Join-Path $selectedRoot 'tools\cjxl.exe'))-and-not(Test-Path -LiteralPath (Join-Path $selectedRoot 'samples\example.jxl'))) '7-Zip import extracted unrelated utilities or samples'
$settings.DjxlExe=$decoder
Assert ([KCCAutomate.ToolValidation]::Passed([KCCAutomate.ToolValidation]::Check($settings))) 'Real .7z import lost decoder dependencies'
Assert (Test-Path -LiteralPath (Join-Path (Split-Path $decoder) $unicodeCompanion)) '7-Zip streaming import lost a Unicode/bracketed filename'
try{[void][KCCAutomate.ManagedTools]::PrepareJxl($sevenArchive,'',$managed);throw 'Missing 7-Zip accepted'}catch{Assert ($_.Exception.Message.Contains('7z.exe')) 'Missing extractor error was unclear'}
'PASS: an actual .7z package imports djxl and companion libraries and runs; a missing extractor gives an actionable message.'
'PASS: ZIP and 7z imports select the decoder, runtime companions and licences while omitting encoders and sample images.'
$settings.ConvertJxl=$false;$settings.DjxlExe='missing-package.7z'
Assert ([KCCAutomate.ToolValidation]::Passed([KCCAutomate.ToolValidation]::Check($settings))) 'Disabled JPEG XL support blocked setup'
$settings.ConvertJxl=$true;$settings.DjxlExe=$decoder
foreach($extension in @('zip','7z')) {
 $unsafe=Join-Path $source ('unsafe.'+$extension)
 $archive=[IO.Compression.ZipFile]::Open($unsafe,'Create');try{[void]$archive.CreateEntry('../escaped.txt')}finally{$archive.Dispose()}
 try{[void][KCCAutomate.ManagedTools]::PrepareJxl($unsafe,$seven,$managed);throw 'Traversal accepted'}catch{Assert ($_.Exception.Message.Contains('Unsafe')) ('Traversal rejection failed: '+$_.Exception.Message)}
}
Assert (-not(Test-Path -LiteralPath (Join-Path $managed 'escaped.txt'))) 'Tool import escaped its destination'
foreach($name in @('C:\escape.exe','folder/CON.txt','folder/file:stream','folder/../escape','folder./djxl.exe')) {
 try{[void][KCCAutomate.ManagedTools]::SafePath($managed,$name);throw 'Unsafe path accepted'}catch{Assert ($_.Exception.Message.Contains('Unsafe')) 'Unsafe member path was accepted'}
}
'PASS: ZIP and 7-Zip readers reject traversal before writing members, including Windows device and alternate-stream paths.'
$before=(Get-FileHash -LiteralPath $kcc).Hash
Assert ($before-eq(Get-FileHash -LiteralPath $copy.KccExe).Hash) 'Tool source or copy was changed'
Rename-Item -LiteralPath $source -NewName 'downloads-unavailable'
Assert ([KCCAutomate.ToolValidation]::Passed([KCCAutomate.ToolValidation]::Check($copy))) 'Managed tools still rely on original download paths'
$copy.WatchFolder=Join-Path $root 'in';$copy.ConvertedFolder=Join-Path $root 'out';$copy.ArchiveFolder=Join-Path $root 'archive';$copy.WorkFolder=Join-Path $env:TEMP ('kcc-tooltest-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$book=Join-Path $root 'book.cbz';$z=[IO.Compression.ZipFile]::Open($book,'Create');try{$s=$z.CreateEntry('001.jpg').Open();try{$s.WriteByte(42)}finally{$s.Dispose()}}finally{$z.Dispose()}
$result=[KCCAutomate.SetupChecks]::ConvertTest($copy,$book,(Join-Path $PSScriptRoot 'dist\KCCAutomate'))
Assert ($result.Passed) ('Managed conversion failed: '+$result.Log)
Assert (Test-Path -LiteralPath $book) 'Original test book was removed'
'PASS: managed tools run and convert a copied fixture after the source downloads folder becomes unavailable; helper PATHs stay scoped to conversion processes.'
$inactiveCopy=New-Object KCCAutomate.Settings
$inactiveCopy.KccExe=$copy.KccExe;$inactiveCopy.SevenZipExe=$copy.SevenZipExe
$inactiveCopy.Format='EPUB';$inactiveCopy.ConvertJxl=$false
$inactiveCopy.KindlegenExe=Join-Path $root 'missing-kindlegen.exe';$inactiveCopy.DjxlExe=Join-Path $root 'missing-djxl.exe'
$inactiveCopy.WatchFolder=$copy.WatchFolder;$inactiveCopy.ConvertedFolder=$copy.ConvertedFolder;$inactiveCopy.ArchiveFolder=$copy.ArchiveFolder;$inactiveCopy.WorkFolder=$copy.WorkFolder
Assert ([KCCAutomate.ToolValidation]::Passed([KCCAutomate.ToolValidation]::Check($inactiveCopy))) 'Inactive missing tools blocked a non-MOBI tool check'
$inactiveManaged=[KCCAutomate.ManagedTools]::Import($inactiveCopy,$managed)
Assert (($inactiveManaged.KindlegenExe-eq$inactiveCopy.KindlegenExe)-and($inactiveManaged.DjxlExe-eq$inactiveCopy.DjxlExe)) 'Import discarded saved inactive tool paths'
Assert ($inactiveManaged.KccExe-eq([KCCAutomate.ManagedTools]::Import($inactiveManaged,$managed)).KccExe) 'An inactive external path prevented safe bundle reuse'
$result=[KCCAutomate.SetupChecks]::ConvertTest($inactiveManaged,$book,(Join-Path $PSScriptRoot 'dist\KCCAutomate'))
Assert $result.Passed ('EPUB worker still depended on inactive KindleGen or decoder paths: '+$result.Log)
$rule=New-Object KCCAutomate.FolderRule;$rule.Pattern='mobi/*';$rule.PresetName='Kindle';$rule.Options=New-Object 'System.Collections.Generic.Dictionary[string,object]';$rule.Options.Add('Format','MOBI');$inactiveManaged.FolderRules.Add($rule)
Assert ([KCCAutomate.ToolValidation]::RequiresKindlegen($inactiveManaged)-and-not([KCCAutomate.ToolValidation]::Check($inactiveManaged,'Kindle')).Passed) 'An EPUB default hid a MOBI folder preset dependency'
$inactiveManaged.FolderRules.Clear()
$inactiveManaged.Format='MOBI'
Assert (-not([KCCAutomate.ToolValidation]::Check($inactiveManaged,'Kindle')).Passed) 'Switching back to MOBI did not require KindleGen'
$result=[KCCAutomate.SetupChecks]::ConvertTest($inactiveManaged,$book,(Join-Path $PSScriptRoot 'dist\KCCAutomate'))
Assert (-not$result.Passed-and$result.Log.Contains('KindleGen')-and(Test-Path -LiteralPath $book)) 'A missing re-enabled KindleGen was accepted or lost the original'
'PASS: non-MOBI imports and copied-book conversion ignore inactive KindleGen/JXL paths, preserve them for later and reuse verified bundles; switching to MOBI restores the dependency without losing originals.'
[IO.File]::WriteAllText((Join-Path (Split-Path $copy.KccExe) 'future'),'unapproved update')
$result=[KCCAutomate.SetupChecks]::ConvertTest($copy,$book,(Join-Path $PSScriptRoot 'dist\KCCAutomate'))
Assert (-not$result.Passed-and$result.Log.Contains('requires the approved KCC')-and(Test-Path -LiteralPath $book)) 'Conversion worker accepted an unapproved replacement tool or lost the original'
'PASS: app-managed scheduled/normal conversion settings also reject an unapproved replacement executable before conversion; originals stay in place.'
"Test fixtures retained at: $root"
