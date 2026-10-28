param([string]$ToolSettingsPath,[string]$FixtureRoot,[switch]$Volumes,[switch]$ReadableLabels)
$ErrorActionPreference='Stop'
if (-not $ToolSettingsPath) { 'SKIP: native chapter conversion requires -ToolSettingsPath with an existing, user-acquired tool setup. Offline grouping checks run in Test-ChapterBundles.ps1.'; return }
$tools=Get-Content -LiteralPath $ToolSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceDigest=(Get-FileHash -LiteralPath $tools.KccExe -Algorithm SHA256).Hash
foreach ($name in @('KindlegenExe','SevenZipExe')) { if (-not (Test-Path -LiteralPath $tools.$name -PathType Leaf)) { throw ('Missing tool: '+$name) } }
if (-not $FixtureRoot) { $FixtureRoot=Join-Path $PSScriptRoot ('test-results\native-'+[Guid]::NewGuid().ToString('N').Substring(0,8)) }
$root=[IO.Path]::GetFullPath($FixtureRoot)
if (Test-Path -LiteralPath $root) { throw 'Use a new fixture folder; existing files are never overwritten.' }
New-Item -ItemType Directory -Path $root | Out-Null
# The standalone CLI is self-contained. A temporary copy keeps its working
# directory inside the fixture and avoids touching the user's managed tools.
$toolCopy=Join-Path $root 'kcc-c2e.exe';Copy-Item -LiteralPath $tools.KccExe -Destination $toolCopy
if((Get-FileHash -LiteralPath $toolCopy -Algorithm SHA256).Hash -ne $sourceDigest){throw 'The copied test tool did not match its source hash.'}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
$config=[ordered]@{WatchFolder=(Join-Path $root 'in');ConvertedFolder=(Join-Path $root 'out');ArchiveFolder=(Join-Path $root 'orig');WorkFolder=(Join-Path $root 'w');KccExe=$tools.KccExe;KindlegenExe=$tools.KindlegenExe;SevenZipExe=$tools.SevenZipExe;DjxlExe=$tools.DjxlExe;QuietMinutes=0;Profile='KS';Format='MOBI';MangaStyle=$true;Cropping=0;Splitter=0;ConvertJxl=$true;InputExtensions=@('.cbz');DuplicateAction='Review';NotificationMode='Off';BundleChapters=$true;BundleTargetPages=50;ChapterPageThreshold=50;BundleMaxMiB=10;HoldShortBundles=$false}
$config.KccExe=$toolCopy
if($Volumes){$config.BundleChapters=$false;$config.BundleVolumes=$true;$config.VolumeTargetPages=100}
if($ReadableLabels){$config.BookTitleStyle='NumberFirst';$config.SeriesAliases=@{'Smoke'='SM'};$config.CoverNumberBadge=$true}
$series=Join-Path $config.WatchFolder 'Smoke';New-Item -ItemType Directory -Path $series -Force | Out-Null
$hashes=@{}
foreach ($chapter in 1..2) {
    $unit=if($Volumes){'Vol.'}else{'Ch.'}
    $path=Join-Path $series ('Smoke '+$unit+' '+$chapter+'.cbz')
    $zip=[IO.Compression.ZipFile]::Open($path,'Create')
    try {
        foreach($page in 1..25){
            $bitmap=New-Object Drawing.Bitmap(240,360);$graphics=[Drawing.Graphics]::FromImage($bitmap);$font=New-Object Drawing.Font('Arial',18)
            try {
                $graphics.Clear([Drawing.Color]::White)
                $graphics.DrawRectangle([Drawing.Pens]::Black,10,10,219,339)
                $graphics.DrawString(('Chapter '+$chapter+"`nPage "+$page),$font,[Drawing.Brushes]::Black,20,40)
                $stream=$zip.CreateEntry(('{0:000}.jpg' -f $page)).Open()
                try {$bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Jpeg)}finally{$stream.Dispose()}
            }finally{$font.Dispose();$graphics.Dispose();$bitmap.Dispose()}
        }
        $writer=New-Object IO.StreamWriter($zip.CreateEntry('ComicInfo.xml').Open())
        try {$writer.Write('<ComicInfo><Series>Smoke</Series><Writer>KCCAutomate generated fixture</Writer><Pages><Page Image="2" Type="FrontCover"/></Pages></ComicInfo>')}finally{$writer.Dispose()}
    }finally{$zip.Dispose()}
    $hashes[$path]=(Get-FileHash -LiteralPath $path).Hash
}
$configPath=Join-Path $root 'settings.json';$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
# Keep KCC/PyInstaller temporary cleanup inside this disposable fixture. Only
# tool locations are copied; real books/settings/schedules are never used.
$temp=Join-Path $root 'temp';New-Item -ItemType Directory -Path $temp | Out-Null
$savedTemp=$env:TEMP;$savedTmp=$env:TMP;$savedPreference=$ErrorActionPreference
try {
    $env:TEMP=$temp;$env:TMP=$temp;$ErrorActionPreference='Continue'
    $log=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Convert-Manga.ps1') -ConfigPath $configPath 2>&1)
    $code=$LASTEXITCODE
}finally{$env:TEMP=$savedTemp;$env:TMP=$savedTmp;$ErrorActionPreference=$savedPreference}
$log | Out-File -LiteralPath (Join-Path $root 'run.txt') -Encoding UTF8
if($code -ne 0){throw ('Native conversion failed. Inspect '+$root+'\run.txt and w/*/*/kcc.log.')}
$title=if($ReadableLabels){'001-002 - SM ('+$unit+')'}else{'Smoke - '+$unit+' 001-002'}
$output=Join-Path $config.ConvertedFolder ('Smoke\'+$title+'.mobi')
$bytes=[IO.File]::ReadAllBytes($output)
if($bytes.Length -lt 100 -or [Text.Encoding]::ASCII.GetString($bytes,60,8) -ne 'BOOKMOBI' -or -not [Text.Encoding]::UTF8.GetString($bytes).Contains($title)){throw 'The native output did not have a MOBI header and expected title.'}
foreach($path in $hashes.Keys){$archived=Join-Path $config.ArchiveFolder $path.Substring($config.WatchFolder.Length+1);if((Get-FileHash -LiteralPath $archived).Hash -ne $hashes[$path]){throw 'The native test original was not preserved.'}}
if(Test-Path -LiteralPath $series){throw 'Successful native fixture was not archived.'}
'PASS: selected real KCC + KindleGen generated one 50-page '+$unit+' MOBI bundle with the expected title; archived CBZ hashes match.'
'Fixture: '+$root
'Rendering and library-cover appearance on the physical Kindle still require reader acceptance.'
