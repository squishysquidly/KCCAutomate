$ErrorActionPreference = 'Stop'
$errors = $null; $tokens = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Convert-Manga.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false) |
    ForEach-Object { Invoke-Expression $_.Extent.Text }
function Log($Text) { }
# Stub the external decoder, while exercising the actual ZIP preparation.
function Invoke-Converter($Executable, $Options, $LogFile) {
    & $Executable @Options
    [pscustomobject]@{ ExitCode=$LASTEXITCODE; Text='' }
}
$convertJxl = $true
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fixture = Join-Path $PSScriptRoot ('jxl-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
function Make-Zip($Path, $Names) {
    $z = [IO.Compression.ZipFile]::Open($Path,'Create')
    try {
        foreach ($name in $Names) {
            $s = $z.CreateEntry($name).Open()
            try { $s.WriteByte(42) } finally { $s.Dispose() }
        }
    } finally { $z.Dispose() }
}
$plain = Join-Path $fixture 'plain.cbz'
Make-Zip $plain @('001.jpg')
if ((Prepare-Cbz $plain $fixture) -ne $plain) { throw 'Plain CBZ changed' }
$jxl = Join-Path $fixture 'jxl.cbz'
Make-Zip $jxl @('pages/001.jxl','pages/002.jpg','ComicInfo.xml')
$DjxlExe = Join-Path $fixture 'missing.exe'
try { Prepare-Cbz $jxl $fixture; throw 'Missing decoder was accepted' }
catch { if ($_ -notmatch 'Install djxl') { throw } }
# Stub tests archive plumbing only, not real image decoding.
$DjxlExe = Join-Path $fixture 'decoder.ps1'
@'
param($InputPage,$OutputPage)
[IO.File]::WriteAllBytes($OutputPage, [byte[]](137,80,78,71,13,10,26,10))
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $DjxlExe
$originalHash = (Get-FileHash -LiteralPath $jxl).Hash
$prepared = Prepare-Cbz $jxl $fixture
$z = [IO.Compression.ZipFile]::OpenRead($prepared)
try {
    $names = @($z.Entries | ForEach-Object FullName)
    if ($names.Count -ne 3 -or 'pages/001.png' -notin $names -or 'pages/002.jpg' -notin $names -or 'ComicInfo.xml' -notin $names) { throw 'Page or metadata preservation failed' }
} finally { $z.Dispose() }
if ((Get-FileHash -LiteralPath $jxl).Hash -ne $originalHash) { throw 'Original changed' }
$collision = Join-Path $fixture 'collision.cbz'
Make-Zip $collision @('001.jxl','001.png')
$collisionAttempt = Join-Path $fixture 'collision'; New-Item -ItemType Directory -Path $collisionAttempt | Out-Null
try { Prepare-Cbz $collision $collisionAttempt; throw 'Collision accepted' }
catch { if ($_ -notmatch 'Duplicate page filename') { throw } }
'PASS: syntax, plain-CBZ passthrough, missing decoder, mixed pages, metadata, unchanged original, duplicate-page rejection. Real decoding requires djxl.'
