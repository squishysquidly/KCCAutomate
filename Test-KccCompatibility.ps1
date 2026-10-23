param([string]$OfficialKccExe,[switch]$CheckLiveRelease)
$ErrorActionPreference='Stop'
[void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'dist\KCCAutomate\KCCAutomate.exe'))
function Assert($condition,$message){if(-not$condition){throw $message}}
$approved=[KCCAutomate.ReleaseClient]::ApprovedKccVersion
$metadata=@{tag_name='v'+$approved;body='Fixture notes';assets=@(@{name=[KCCAutomate.ReleaseClient]::ApprovedKccAsset;browser_download_url=[KCCAutomate.ReleaseClient]::ApprovedKccDownload;digest=[KCCAutomate.ReleaseClient]::ApprovedKccDigest;size=89546400})}
function Parse-Release($data,$installed=$approved){[KCCAutomate.ReleaseClient]::Parse('KCC','ciromattia/kcc',$installed,($data|ConvertTo-Json -Depth 5))}
$row=Parse-Release $metadata
Assert ($row.Asset-and$row.Status-eq'Approved version selected') 'Approved KCC release selection failed'
Assert ((Parse-Release $metadata 'Unknown').Status-eq'Approved version available') 'Approved KCC version was not offered for an unknown installation'
Assert ([KCCAutomate.ReleaseClient]::ReleaseApiUrl('KCC','ciromattia/kcc')-eq('https://api.github.com/repos/ciromattia/kcc/releases/tags/v'+$approved)) 'KCC update check uses latest instead of its approved tag'
Assert ([KCCAutomate.ReleaseClient]::ReleaseApiUrl('KCCAutomate','squishysquidly/KCCAutomate').EndsWith('/releases/latest')) 'App update checks stopped using latest'
[KCCAutomate.ReleaseClient]::ValidateKccHelp('comic2ebook v12.0.0 --profile --format')
foreach($version in @('12.1.1','13.0.0','12.0.0-rc1','12.0.0.1')) {
 try{[KCCAutomate.ReleaseClient]::ValidateKccHelp(('comic2ebook v'+$version+' --profile --format'));throw 'Unapproved help accepted'}catch{Assert ($_.Exception.Message.Contains('approved')) ('Unexpected version rejection: '+$_.Exception.Message)}
}
'PASS: approved CLI help is accepted; newer, prerelease and unknown versions are rejected; KCC queries the pinned tag while app updates query latest.'
$metadata.tag_name='v12.1.1';$rejected=Parse-Release $metadata
Assert (-not$rejected.Asset-and$rejected.Status-eq'KCC release not approved') 'A newer release was offered as approved'
$metadata.tag_name='v'+$approved;$metadata.assets[0].digest='sha256:'+('0'*64)
Assert (-not(Parse-Release $metadata).Asset) 'A replacement binary with a different digest was offered'
$metadata.assets[0].digest=[KCCAutomate.ReleaseClient]::ApprovedKccDigest;$metadata.assets[0].name='KCC_12.0.0.exe'
Assert (-not(Parse-Release $metadata).Asset) 'The GUI download was offered as the CLI'
$bad=New-Object KCCAutomate.UpdateRow;$bad.Component='KCC';$bad.Repository='ciromattia/kcc';$bad.Latest='v12.1.1';$bad.Asset=$row.Asset
$unused=Join-Path $PSScriptRoot ('test-results\must-not-download-'+[guid]::NewGuid().ToString('N'))
try{[void][KCCAutomate.ReleaseClient]::Download($bad,$unused);throw 'Unapproved download allowed'}catch{Assert ($_.Exception.Message.Contains('approved')) 'Download approval gate did not reject the release'}
Assert (-not(Test-Path -LiteralPath $unused)) 'Rejected KCC download created staging files'
'PASS: future tags, changed checksums and GUI assets are blocked; direct downloads recheck approval before network or filesystem changes.'
if($CheckLiveRelease){
 $live=[KCCAutomate.ReleaseClient]::Check('KCC','ciromattia/kcc',$approved)
 Assert ($live.Asset-and$live.Status-eq'Approved version selected'-and$live.Asset.Name-eq[KCCAutomate.ReleaseClient]::ApprovedKccAsset) 'Live GitHub metadata did not match the approved CLI'
 'PASS: live GitHub API check offers the approved CLI tag and matching asset/checksum instead of the newest KCC release.'
}
if(-not$OfficialKccExe){'Real binary checks: supply -OfficialKccExe with the approved release download.';return}
$OfficialKccExe=(Resolve-Path -LiteralPath $OfficialKccExe).Path
[KCCAutomate.ReleaseClient]::Verify($OfficialKccExe,[KCCAutomate.ReleaseClient]::ApprovedKccDigest)
# Read PyInstaller's one-file archive without requiring Python or extra packages.
$bytes=[IO.File]::ReadAllBytes($OfficialKccExe);$magic=[byte[]](77,69,73,12,11,10,11,14);$cookie=-1
for($index=$bytes.Length-88;$index-ge[Math]::Max(0,$bytes.Length-1048576);$index--){$match=$true;for($n=0;$n-lt8;$n++){if($bytes[$index+$n]-ne$magic[$n]){$match=$false;break}};if($match){$cookie=$index;break}}
Assert ($cookie-ge0) 'The approved binary has no PyInstaller one-file cookie'
function Read-BigEndian($offset){[uint32]$bytes[$offset]*16777216+[uint32]$bytes[$offset+1]*65536+[uint32]$bytes[$offset+2]*256+[uint32]$bytes[$offset+3]}
$packageLength=Read-BigEndian ($cookie+8);$tocOffset=Read-BigEndian ($cookie+12);$tocLength=Read-BigEndian ($cookie+16)
$archiveStart=$cookie+88-$packageLength;$offset=$archiveStart+$tocOffset;$end=$offset+$tocLength;$names=@()
Assert ($archiveStart-ge0-and$offset-ge0-and$end-le$cookie) 'Invalid PyInstaller archive offsets'
while($offset-lt$end){$length=Read-BigEndian $offset;Assert ($length-ge19-and$offset+$length-le$end) 'Invalid PyInstaller table entry';$names+=[Text.Encoding]::UTF8.GetString($bytes,$offset+18,$length-18).TrimEnd([char]0);$offset+=$length}
Assert (@($names|Where-Object{$_-match'(^|[\\/])python311\.dll$'}).Count-eq1) 'Bundled Python DLL missing'
Assert (@($names|Where-Object{$_-match'PIL[\\/]_imaging.*\.pyd$'}).Count-gt0) 'Bundled Pillow extension missing'
Assert (@($names|Where-Object{$_-match'psutil[\\/].*\.pyd$'}).Count-gt0) 'Bundled psutil extension missing'
$results=Join-Path $PSScriptRoot 'test-results';New-Item -ItemType Directory -Path $results -Force|Out-Null
$names|Set-Content -LiteralPath (Join-Path $results 'kcc-bundled-files.txt')
$start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$OfficialKccExe;$start.Arguments='--help';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
$start.EnvironmentVariables['PATH']=(Join-Path $env:WINDIR 'System32')+';'+$env:WINDIR
foreach($name in @('PYTHONHOME','PYTHONPATH','PYTHONSTARTUP','VIRTUAL_ENV','CONDA_PREFIX','CONDA_DEFAULT_ENV','QT_PLUGIN_PATH')){$start.EnvironmentVariables.Remove($name)}
$process=New-Object Diagnostics.Process;$process.StartInfo=$start
try{[void]$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not$process.WaitForExit(60000)){$process.Kill();throw 'Approved CLI startup timed out'};$text=$stdout.Result+"`n"+$stderr.Result;$text|Set-Content -LiteralPath (Join-Path $results 'official-kcc-help.txt');Assert ($process.ExitCode-eq0) ('Official CLI startup failed: '+$text);[KCCAutomate.ReleaseClient]::ValidateKccHelp($text)}finally{$process.Dispose()}
'PASS: the checksum-verified official Windows CLI contains Python 3.11, Pillow and psutil, and starts with Python removed from PATH and Python environment overrides cleared.'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fixture=Join-Path $results ('official-kcc-'+[guid]::NewGuid().ToString('N').Substring(0,10));$pages=Join-Path $fixture 'pages';New-Item -ItemType Directory -Path $pages -Force|Out-Null
foreach($number in 1..2){$bitmap=New-Object Drawing.Bitmap(600,900);$graphics=[Drawing.Graphics]::FromImage($bitmap);try{$graphics.Clear([Drawing.Color]::White);$graphics.DrawRectangle([Drawing.Pens]::Black,30,30,540,840);$graphics.DrawString(('KCCAutomate test page '+$number),[Drawing.SystemFonts]::DefaultFont,[Drawing.Brushes]::Black,60,60);$bitmap.Save((Join-Path $pages ('00'+$number+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}}
$book=Join-Path $fixture 'sample.cbz';[IO.Compression.ZipFile]::CreateFromDirectory($pages,$book);$before=(Get-FileHash -LiteralPath $book).Hash;$output=Join-Path $fixture 'sample.epub'
$arguments=@('--profile','KS','--format','EPUB','--manga-style','--upscale','--cropping','0','--splitter','0','--tempdir','--output',$output,$book)
$start.Arguments=(@($arguments|ForEach-Object{[KCCAutomate.Desktop]::Quote($_)})-join' ')
$start.EnvironmentVariables['PYTHONIOENCODING']='utf-8'
$process=New-Object Diagnostics.Process;$process.StartInfo=$start
try{[void]$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not$process.WaitForExit(60000)){$process.Kill();throw 'Official CLI sample conversion timed out'};$text=$stdout.Result+"`n"+$stderr.Result;$text|Set-Content -LiteralPath (Join-Path $results 'official-kcc-conversion.txt');Assert ($process.ExitCode-eq0-and(Test-Path -LiteralPath $output)) ('Official CLI EPUB conversion failed: '+$text)}finally{$process.Dispose()}
Assert ((Get-FileHash -LiteralPath $book).Hash-eq$before) 'Official CLI sample conversion changed the input'
$epub=[IO.Compression.ZipFile]::OpenRead($output);try{Assert (@($epub.Entries|Where-Object{$_.FullName-match'(?i)\.(png|jpe?g)$'}).Count-ge2) 'Official CLI sample EPUB is missing its images'}finally{$epub.Dispose()}
'PASS: the real approved CLI converts a generated two-page CBZ into an EPUB with Python absent from PATH; its input remains unchanged. MOBI/Kindle output still requires manual device testing.'
