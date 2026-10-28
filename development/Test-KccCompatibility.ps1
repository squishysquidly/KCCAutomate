param([string]$OfficialKccExe,[string]$ExpectedSha256,[switch]$CheckLiveRelease)
$ErrorActionPreference='Stop'
[void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'dist\KCCAutomate\KCCAutomate.exe'))
function Assert($condition,$message){if(-not$condition){throw $message}}
$metadata=@{tag_name='v23.4.5';body='Fixture notes';assets=@(@{name='tool_cli_c2e_23.4.5_AMD64.exe';browser_download_url='https://github.com/ciromattia/kcc/releases/download/v23.4.5/tool_cli_c2e_23.4.5_AMD64.exe';digest='sha256:'+('a'*64);size=123})}
function Parse-Release($data,$installed='22.0.0'){[KCCAutomate.ReleaseClient]::Parse('KCC','ciromattia/kcc',$installed,($data|ConvertTo-Json -Depth 5))}
$row=Parse-Release $metadata
Assert ($row.Asset-and$row.Status-eq'Update available') 'Latest c2e release was not offered'
Assert ((Parse-Release $metadata '23.4.5').Status-eq'Up to date') 'Selected version comparison failed'
Assert ((Parse-Release $metadata 'Unknown').Asset) 'Unknown installed version hid the latest CLI'
Assert ((Parse-Release $metadata 'Unknown').Status-eq'Installed version unknown') 'An unknown installed version was presented as up to date'
Assert ([KCCAutomate.ReleaseClient]::VersionFromHelp('comic2ebook v23.4.5 - comic converter')-eq'23.4.5') 'KCC help version was not identified'
Assert ([KCCAutomate.ReleaseClient]::VersionFromHelp('JPEG XL decoder v0.11.2 [AVX]')-eq'0.11.2') 'JPEG XL help version was not identified'
Assert ([KCCAutomate.ReleaseClient]::VersionFromHelp('comic2ebook v23.4.5-rc1')-eq'23.4.5-rc1') 'A prerelease was incorrectly identified as a stable version'
Assert ([KCCAutomate.ReleaseClient]::VersionFromHelp('Python 3.13.7')-eq'Unknown') 'A Python runtime version was presented as the converter version'
Assert ([KCCAutomate.ReleaseClient]::KccUpdateInstructions($row).Contains('tool_cli_c2e_23.4.5_AMD64.exe')) 'KCC update instructions omitted the offered CLI filename'
Assert ([KCCAutomate.ReleaseClient]::ReleaseApiUrl('KCC','ciromattia/kcc').EndsWith('/releases/latest')) 'KCC update check still uses a version-pinned endpoint'
foreach($version in @('12.0.0','13.0.0','23.4.5','23.4.5-rc1','23.4.5.1','future')){[KCCAutomate.ReleaseClient]::ValidateKccHelp(('comic2ebook v'+$version+' --profile --format'))}
foreach($bad in @('','unrelated tool --profile --format','comic2ebook --format','comic2ebook --profile')){
 $rejected=$false;try{[KCCAutomate.ReleaseClient]::ValidateKccHelp($bad)}catch{$rejected=$true};Assert $rejected 'Unrelated/incomplete converter help passed'
}
Assert ([KCCAutomate.ToolValidation]::IsC2E('tool_cli_c2e_23.4.5_AMD64.exe')-and-not[KCCAutomate.ToolValidation]::IsC2E('KCC_23.4.5.exe')-and-not[KCCAutomate.ToolValidation]::IsC2E('tool_cli_c2p_23.4.5_AMD64.exe')) 'CLI identity checks changed'
'PASS: working CLI help is accepted independently of version; required options and tool identity remain checked; latest-release lookup and version comparisons work.'
foreach($name in @('KCC_23.4.5.exe','tool_cli_c2p_23.4.5_AMD64.exe','tool_cli_c2e_23.4.5_ARM64.exe')){
 $metadata.assets[0].name=$name;Assert (-not(Parse-Release $metadata).Asset) 'Wrong program or architecture was offered'
}
$unused=Join-Path $PSScriptRoot ('test-results\must-not-download-'+[guid]::NewGuid().ToString('N'))
foreach($candidate in @($row,(New-Object KCCAutomate.UpdateRow -Property @{Component='KCC'}))){
 $blocked=$false;try{[void][KCCAutomate.ReleaseClient]::Download($candidate,$unused)}catch{$blocked=$_.Exception.Message.Contains('user-managed')};Assert $blocked 'KCC acquisition stopped being manual-only'
}
Assert (-not(Test-Path -LiteralPath $unused)) 'Manual-only KCC download created staging files'
'PASS: GUI/c2p/ARM64 assets are excluded from this x64 app; KCC downloads remain user-managed through the upstream releases page.'
if($CheckLiveRelease){$live=[KCCAutomate.ReleaseClient]::Check('KCC','ciromattia/kcc','Unknown');Assert ($live.Asset-and$live.Asset.Name-like'tool_cli_c2e_*_AMD64.exe') 'Live latest release has no matching CLI';'PASS: latest official release metadata supplies the Windows x64 c2e asset.'}
if(-not$OfficialKccExe){'Optional native test: supply -OfficialKccExe and, if desired, -ExpectedSha256 from the upstream release.';return}
$OfficialKccExe=(Resolve-Path -LiteralPath $OfficialKccExe).Path
Assert ([KCCAutomate.ToolValidation]::IsC2E($OfficialKccExe)) 'Choose a c2e executable'
if($ExpectedSha256){[KCCAutomate.ReleaseClient]::Verify($OfficialKccExe,('sha256:'+($ExpectedSha256-replace'^sha256:','')))}
$results=Join-Path $PSScriptRoot 'test-results';New-Item -ItemType Directory -Path $results -Force|Out-Null
$start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$OfficialKccExe;$start.Arguments='--help';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
$start.EnvironmentVariables['PATH']=(Join-Path $env:WINDIR 'System32')+';'+$env:WINDIR
foreach($name in @('PYTHONHOME','PYTHONPATH','PYTHONSTARTUP','VIRTUAL_ENV','CONDA_PREFIX','CONDA_DEFAULT_ENV','QT_PLUGIN_PATH')){$start.EnvironmentVariables.Remove($name)}
$process=New-Object Diagnostics.Process;$process.StartInfo=$start
try{[void]$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not$process.WaitForExit(60000)){$process.Kill();throw 'CLI startup timed out'};$text=$stdout.Result+"`n"+$stderr.Result;$text|Set-Content -LiteralPath (Join-Path $results 'official-kcc-help.txt');Assert ($process.ExitCode-eq0) ('CLI startup failed: '+$text);[KCCAutomate.ReleaseClient]::ValidateKccHelp($text)}finally{$process.Dispose()}
'PASS: selected standalone CLI starts with Python removed from PATH and Python environment overrides cleared.'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fixture=Join-Path $results ('native-'+[guid]::NewGuid().ToString('N').Substring(0,8));$pages=Join-Path $fixture 'pages';New-Item -ItemType Directory -Path $pages -Force|Out-Null
foreach($number in 1..2){$bitmap=New-Object Drawing.Bitmap(600,900);$graphics=[Drawing.Graphics]::FromImage($bitmap);try{$graphics.Clear([Drawing.Color]::White);$graphics.DrawRectangle([Drawing.Pens]::Black,30,30,540,840);$bitmap.Save((Join-Path $pages ('00'+$number+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}}
$book=Join-Path $fixture 'sample.cbz';[IO.Compression.ZipFile]::CreateFromDirectory($pages,$book);$before=(Get-FileHash -LiteralPath $book).Hash;$output=Join-Path $fixture 'sample.epub'
$arguments=@('--profile','KS','--format','EPUB','--manga-style','--upscale','--cropping','0','--splitter','0','--tempdir','--output',$output,$book)
$start.Arguments=(@($arguments|ForEach-Object{[KCCAutomate.Desktop]::Quote($_)})-join' ');$start.EnvironmentVariables['PYTHONIOENCODING']='utf-8'
$process=New-Object Diagnostics.Process;$process.StartInfo=$start
try{[void]$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not$process.WaitForExit(120000)){$process.Kill();throw 'Native conversion timed out'};$text=$stdout.Result+"`n"+$stderr.Result;Assert ($process.ExitCode-eq0-and(Test-Path -LiteralPath $output)-and(Get-Item -LiteralPath $output).Length-gt0) ('Native EPUB conversion failed: '+$text)}finally{$process.Dispose()}
Assert ((Get-FileHash -LiteralPath $book).Hash-eq$before) 'Native test changed its generated input'
'PASS: selected CLI converts a generated CBZ to a nonempty EPUB and preserves the input.'
