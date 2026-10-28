$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Workflow-Support.ps1')
$root=Join-Path $PSScriptRoot ('test-results\scribe-'+[guid]::NewGuid().ToString('N').Substring(0,8));$incoming=Join-Path $root 'in';New-Item -ItemType Directory -Path $incoming -Force|Out-Null;$path=Join-Path $incoming 'Series v01.cbz';[IO.File]::WriteAllText($path,'original fixture');$file=Get-Item -LiteralPath $path
function Require($ok,$message){if(-not$ok){throw $message}}
$config=[pscustomobject]@{Profile='KS';Format='MOBI';Cropping=2;Splitter=0;ForcePng=$true;MangaStyle=$true;Upscale=$true;Stretch=$false;Gamma=0;ScribeCompatibility=$true;OutputNaming='{name}';FolderRules=@()}
Select-Conversion $file
Require ($arguments[[Array]::IndexOf($arguments,'--profile')+1]-eq'KS1860'-and$arguments[[Array]::IndexOf($arguments,'--cropping')+1]-eq'0'-and'--forcepng'-notin$arguments-and'--manga-style'-in$arguments-and'--upscale'-in$arguments-and'--stretch'-notin$arguments) 'Scribe compatibility arguments were not applied as specified'
Require ($config.Profile-eq'KS'-and$config.Cropping-eq2-and$config.ForcePng-and$activeProfile-eq'KS') 'Compatibility overwrote the saved reader/image choices or naming profile'
$config.ScribeCompatibility=$false;Select-Conversion $file
Require ($arguments[[Array]::IndexOf($arguments,'--profile')+1]-eq'KS'-and$arguments[[Array]::IndexOf($arguments,'--cropping')+1]-eq'2'-and'--forcepng'-in$arguments) 'Turning compatibility off did not restore saved choices'
foreach($choice in @(@('KS','PDF'),@('KoL','EPUB'),@('KS3','MOBI'))){$config.Profile=$choice[0];$config.Format=$choice[1];$config.ScribeCompatibility=$true;Select-Conversion $file;Require ($arguments[[Array]::IndexOf($arguments,'--profile')+1]-eq$choice[0]-and'--forcepng'-in$arguments) 'Compatibility changed an unrelated reader or PDF conversion'}
$config.Profile='KS';$config.Format='MOBI';$config.ScribeCompatibility=$false;$config.FolderRules=@([pscustomobject]@{Pattern='*';Options=[pscustomobject]@{ScribeCompatibility=$true}});Select-Conversion $file
Require ($arguments[[Array]::IndexOf($arguments,'--profile')+1]-eq'KS1860'-and-not$config.ScribeCompatibility) 'Folder-specific compatibility was ignored or changed global preferences'
'PASS: optional Scribe JPEG/no-crop/1860x1920 settings apply only to Scribe 2022/2024 MOBI/EPUB; RTL, proportional fit, saved choices and unrelated devices remain intact; folder presets work.'
