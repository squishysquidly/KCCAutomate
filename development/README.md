# Developing KCCAutomate

For installation and everyday use, start with the [user guide](../README.md)
and [published releases](https://github.com/squishysquidly/KCCAutomate/releases).
The current version is **0.1.18**.

## Repository layout

```text
README.md                 User installation, workflow and settings guide
license.txt               ISC terms and copyright notices
app/                      WPF application and runtime PowerShell sources
development/              Build scripts, tests, installer and maintainer notes
  installer/              Windows installer/uninstaller source
  dist/                   Generated builds and packages (ignored by Git)
  test-results/           Generated reports and test fixtures (ignored by Git)
.github/workflows/         GitHub Actions build/release automation
```

The packaged app keeps runtime scripts beside KCCAutomate.exe. Moving source
files into app/ does not change that installed layout or existing settings paths.
Keep generated tools, personal settings and book files out of source control.

## Build the installer and portable version

Use Windows with the .NET Framework C# compiler/WPF assemblies and Windows
PowerShell 5.1 available. This project uses the Windows Framework compiler;
an additional dotnet SDK is not required. KCC binaries are not bundled.

From the repository root, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\development\Build-Installer.ps1
```

This builds the app, creates the portable ZIP and embeds it in the installer.
ExecutionPolicy Bypass applies to this PowerShell process; it does not change
the user's persistent execution-policy settings.

Results are in **development\dist**:

- `KCCAutomate-Setup.exe`
- `KCCAutomate-Windows.zip`
- `SHA256SUMS`
- `KCCAutomate\KCCAutomate.exe` (unpacked portable build)

For a quick app-only build, run `development\Build-App.ps1`. The build scripts
resolve their paths from their own location, so they also work when invoked
from another current directory. `-SkipBuild`/`-SkipPackage` are available on
the package/installer scripts when you deliberately reuse a verified build.

## Run checks

Build the installer first. Install official 7-Zip at its standard Windows
location (`C:\Program Files\7-Zip\7z.exe`); the tool suite tests real CLI
archive creation/extraction. Converter fixtures are generated locally.

From the repository root:

```powershell
Get-ChildItem .\development\Test-*.ps1 | ForEach-Object {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE) { throw "Failed: $($_.Name)" }
}
```

Run the desktop self-test separately:

```powershell
$report = Join-Path $PWD 'development\test-results\desktop.txt'
$app = Join-Path $PWD 'development\dist\KCCAutomate\KCCAutomate.exe'
$process = Start-Process -FilePath $app -ArgumentList @('--self-test', ('"' + $report + '"')) -WindowStyle Hidden -Wait -PassThru
Get-Content -LiteralPath $report
if ($process.ExitCode) { throw 'Desktop tests failed.' }
```

Tests cover conversion order, originals, output verification, duplicates,
JXL preparation, safe tool imports, compatibility gates, presets, updates,
installer transactions and guided setup. Desktop checks render light/dark
views and setup pages. Installer/scheduler fixtures avoid real task, shortcut
and registry registration. Results and disposable fixtures stay under
development/, separate from normal app settings and books.

Actual Previewer detection on different PCs, MOBI/EPUB appearance on a reader,
normal installer integration and signed-in network access still need manual
acceptance testing before publication.

## KCC compatibility

This app verifies KCC **12.0.0 c2e**. Change that approval only after testing
the new upstream Windows CLI and real book conversions. Users acquire it from
[KCC's releases page](https://github.com/ciromattia/kcc/releases); the app does
not fetch KCC binaries directly.

`Test-KccCompatibility.ps1` defaults to offline policy checks. A maintainer may
pass `-OfficialKccExe <downloaded-cli.exe>` to verify the approved file and run
a generated CBZ-to-EPUB test, or `-CheckLiveRelease` to check GitHub metadata.
Those options do not install Python or change the system PATH.

The app source and both build/package workflows must agree on the runtime
file list. `license.txt` is required for updates as well as fresh packages;
portable.flag is included only for fresh portable distributions. It is not
copied into an installed-mode app by an update.

## Maintainer notes

- [Preparing and publishing a release](RELEASING.md): run **Prepare KCCAutomate
  release** in GitHub Actions with a new version matching the app. It builds,
  tests and attaches downloads to a draft; you review and publish it yourself.
  Existing release downloads and tags are retained.
- [Roadmap](ROADMAP.md)

## Copyright and attribution

KCCAutomate remains under ISC, with `squishysquidly` credited for its own work.
The existing KCC copyright notices and permission text remain in license.txt.
Credit in the user guide explains which separate tools do the conversion work.
Third-party tools retain their own licence terms and are not part of the app
release payload. Do not remove upstream notices from any reused source.
