$ErrorActionPreference = 'Stop'
$fixture = Join-Path $PSScriptRoot ('test-results\workflow-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$mockSource = Join-Path $fixture 'MockConverter.cs'
@'
using System;
using System.IO;
public class MockConverter {
    public static int Main(string[] args) {
        if (Array.IndexOf(args,"--help") >= 0) { Console.WriteLine("Mock help"); return 0; }
        int index = Array.IndexOf(args,"--output");
        if (index < 0) return 1;
        string source = args[args.Length-1];
        File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"order.txt"),Path.GetExtension(source)+Environment.NewLine);
        Console.Error.WriteLine("Normal progress written to stderr");
        if (Path.GetFileName(source).Contains("fail")) return 1;
        File.WriteAllText(args[index+1], "converted " + Path.GetFileName(source));
        return 0;
    }
}
'@ | Set-Content -LiteralPath $mockSource
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$mockExe = Join-Path $fixture 'mock.exe'
& $compiler /nologo /target:exe "/out:$mockExe" $mockSource
if ($LASTEXITCODE) { throw 'Mock compilation failed' }
$incoming = Join-Path $fixture 'in'
$converted = Join-Path $fixture 'out'
$archive = Join-Path $fixture 'archive'
$work = Join-Path $fixture 'work'
foreach ($path in @($incoming,$converted,$archive,$work)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
$config = [ordered]@{
    WatchFolder=$incoming; ConvertedFolder=$converted; ArchiveFolder=$archive; WorkFolder=$work
    KccExe=$mockExe; DjxlExe=''; QuietMinutes=0; Profile='KS'; Format='MOBI'; Cropping=0; Splitter=0
    MangaStyle=$true; Upscale=$true; ConvertJxl=$true; OverwriteConverted=$false
    InputExtensions=@('.cbz','.pdf'); ScheduleTimes='08:00, 14:00, 20:00'; WakeComputer=$false
}
$configPath = Join-Path $fixture 'settings.json'
function Save-Config { $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8 }
function Run-Engine([string[]]$Extra) {
    Save-Config
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $script:engineOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Convert-Manga.ps1') -ConfigPath $configPath @Extra 2>&1
        $script:engineExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Write-Cbz($Path) {
    $zip = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try { $s = $zip.CreateEntry('001.jpg').Open(); try { $s.WriteByte(42) } finally { $s.Dispose() } }
    finally { $zip.Dispose() }
}
$series = Join-Path $incoming 'Series [A]'
$bad = Join-Path $incoming 'Bad'
New-Item -ItemType Directory -Path $series,$bad -Force | Out-Null
Write-Cbz (Join-Path $series 'Volume 01.cbz')
[IO.File]::WriteAllText((Join-Path $series 'Volume 02.pdf'), 'PDF mock')
[IO.File]::WriteAllText((Join-Path $series 'notes.txt'), 'notes')
[IO.File]::WriteAllText((Join-Path $incoming 'Loose.pdf'), 'PDF mock')
Write-Cbz (Join-Path $bad 'fail.cbz')
$archivedSeries = Join-Path $archive 'Series [A]'
New-Item -ItemType Directory -Path $archivedSeries -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $archivedSeries 'Volume 01.cbz'), 'stale copy')
[IO.File]::WriteAllText((Join-Path $archivedSeries 'keep.txt'), 'keep')
Run-Engine
if ($engineExit -ne 1) { throw "Expected one failed batch. $engineOutput" }
if ((Test-Path -LiteralPath $series) -or -not (Test-Path -LiteralPath (Join-Path $archive 'Loose.pdf')) -or -not (Test-Path -LiteralPath (Join-Path $bad 'fail.cbz'))) { throw "Batch archival or error isolation failed. $engineOutput" }
foreach ($file in @('Volume 01.cbz','Volume 02.pdf','notes.txt','keep.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $archivedSeries $file))) { throw "Missing archive file $file" }
}
if (-not (Test-Path -LiteralPath (Join-Path $converted 'Series [A]\Volume 02.mobi'))) { throw 'Mixed-format output missing' }
$order = @(Get-Content -LiteralPath (Join-Path $fixture 'order.txt'))
if (($order -join ',') -ne '.cbz,.cbz,.pdf,.pdf') { throw "Incorrect format order: $order" }
'PASS: CBZ before PDF, mixed folders, loose PDF, archive overwrite, archive-only preservation, failure isolation and native stderr handling.'
Run-Engine @('-Preview')
if ($engineExit -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $bad 'fail.cbz'))) { throw 'Preview failed' }
'PASS: preview keeps originals.'
New-Item -ItemType Directory -Path $series -Force | Out-Null
Write-Cbz (Join-Path $series 'Volume 01.cbz')
$existingOutput = Join-Path $converted 'Series [A]\Volume 01.mobi'
[IO.File]::WriteAllText($existingOutput, 'different output')
Run-Engine
if (-not (Test-Path -LiteralPath (Join-Path $series 'Volume 01.cbz')) -or [IO.File]::ReadAllText($existingOutput) -ne 'different output') { throw 'Output collision overwrote data' }
'PASS: converted-output conflicts retain originals.'
$config.OverwriteConverted = $true
Run-Engine
if ((Test-Path -LiteralPath $series) -or [IO.File]::ReadAllText($existingOutput) -eq 'different output') { throw "Opt-in replacement failed. $engineOutput" }
'PASS: optional converted-output replacement.'
$stop = Join-Path $fixture 'stop'
[IO.File]::WriteAllText($stop, 'stop')
Run-Engine @('-StopFile',$stop)
if ($engineExit -ne 2 -or -not (Test-Path -LiteralPath $bad)) { throw 'Graceful stop failed' }
'PASS: graceful stop retains pending batches.'
$config.ArchiveFolder = Join-Path $incoming 'unsafe'
Run-Engine
if ($engineExit -eq 0 -or (Test-Path -LiteralPath $config.ArchiveFolder)) { throw 'Nested path guard failed' }
'PASS: unsafe nested paths blocked before mutation.'
# Mock scheduler cmdlets: validate registration arguments without creating tasks.
$registered = @{}
function New-ScheduledTaskTrigger { param([switch]$Daily,$At) [pscustomobject]@{ At=$At } }
function New-ScheduledTaskAction { param($Execute,$Argument,$WorkingDirectory) [pscustomobject]@{ Execute=$Execute; Argument=$Argument } }
function New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel) [pscustomobject]@{ LogonType=$LogonType; RunLevel=$RunLevel } }
function New-ScheduledTaskSettingsSet { param([switch]$StartWhenAvailable,$MultipleInstances,$ExecutionTimeLimit,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries,[switch]$WakeToRun) [pscustomobject]@{ MultipleInstances=$MultipleInstances } }
function Register-ScheduledTask { param($TaskName,$Action,$Trigger,$Principal,$Settings,$Description,[switch]$Force) $registered['Action']=$Action; $registered['Trigger']=$Trigger; $registered['Principal']=$Principal; $registered['Settings']=$Settings }
# Test against packaged scripts, which have the conversion script beside them.
& (Join-Path $PSScriptRoot 'dist\KCCAutomate\Manage-Schedule.ps1') -ConfigPath $configPath -Action Enable | Out-Null
if ($registered.Trigger.Count -ne 3 -or $registered.Principal.LogonType -ne 'Interactive' -or $registered.Settings.MultipleInstances -ne 'IgnoreNew' -or $registered.Action.Argument -notmatch 'ExecutionPolicy Bypass') { throw ('Scheduler registration arguments failed: ' + ($registered | ConvertTo-Json -Depth 5)) }
'PASS: three scheduled triggers, least-privileged signed-in account, overlap prevention and per-process script policy.'
