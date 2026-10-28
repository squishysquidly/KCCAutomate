# Developing KCCAutomate

For installation and everyday use, start with the [user guide](../README.md)
and [published releases](https://github.com/squishysquidly/KCCAutomate/releases).
The current version is **0.1.20**.
It adds Stop and optional Scribe compatibility, improves Microsoft Store KindleGen setup and removes the KCC version pin; the
[release overview](RELEASE-NOTES.md) describes the update from 0.1.19.

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

The supplied application artwork is kept as `app/assets/KCCAutomate.png`; its
multi-size Windows icon is `app/assets/KCCAutomate.ico`. Both are source assets.
To rebuild the ICO after replacing the artwork, run `development/Build-Icon.ps1`.
This uses Windows System.Drawing, preserves the full artwork and transparency,
fits rectangular images inside a square without stretching/cropping, and requires no
additional image packages. The app, installer and uninstaller embed the icon;
the app and setup/help windows use it, and installed shortcuts select it from
KCCAutomate.exe. It adds no runtime sidecar files to the established update set.
`Test-AppIcon.ps1` checks the executable resources and actual Windows shell
extraction, as well as the embedded window icon.

Windows can retain the previous artwork when an EXE is replaced at the same path.
The installer sends an item-specific shell refresh for the app and saved shortcuts;
normal app startup also refreshes its own EXE before opening the window. This covers
portable replacements, updates and rollbacks applied by older updaters without
changing the runtime file set or resetting unrelated Windows icons. Test/self-test
launches bypass the normal startup notification. `Test-TaskbarIcon.ps1` exercises
an icon change at the same path using only a disposable fixture.

## Build the installer and portable version

Completed conversion scratch is removed after verifying its exact published
outputs; compact result markers, logs and completion receipts remain. The same
cleanup handles older single-book receipts and the chapter ledger under the
workflow lock. `Test-WorkspaceCleanup.ps1` covers automatic cleanup with optional
expiry disabled, older data, output verification, retry records and retention.
Its `-RequireLinkTest` switch requires the native Windows junction-safety check
instead of allowing it to be skipped when the environment denies link creation.

Use Windows with the .NET Framework C# compiler/WPF assemblies and Windows
PowerShell 5.1 available. This project uses the Windows Framework compiler;
an additional dotnet SDK is not required. KCC binaries are not bundled.
The foundation test suite additionally needs Python 3.8 or newer for developers
and CI. This is not a new requirement for the installed Windows app.

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

## Generated material

`Test-ToolSetup.ps1` covers classic and Store KindleGen layouts, versioned
packages, registered-location fallback, private-copy validation and failed-copy
cleanup. Its optional `-CheckInstalledStorePreviewer` also checks a real
current-user Store installation using a disposable copy. No app settings,
installed tools or folder permissions are changed.

Keep the current installer, portable ZIP, checksums and unpacked application in
`development/dist`. Historical local builds and backup copies are not required.
The packaging script removes its temporary `package-*` directory on success or
failure, checking the path before removal. Installer build intermediates such as
`Uninstall-KCCAutomate.exe` and `payload.sha256` are recreated by the build.

Generated reports, archive/JXL fixtures and Python caches can be discarded after
verification. Keep the test scripts, shared contracts, replay examples and platform
inventory: they protect current behavior and support the planned Linux worker.
Build the installer again before running checks that use generated executables.

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

`Test-ChapterBundles.ps1` additionally exercises page-based grouping, whole-chapter
size retries, completed-group stability, pending/released remainders, source
hashes, metadata-selected covers, natural page ordering, JXL preparation, unclear
or duplicate identities, output conflicts and loose chapters. Its converter is
a fixture; real KCC/MOBI appearance and the chosen size budget need reader tests.

`Test-BookLabels.ps1` checks title/filename agreement, aliases, unchanged cover
art proportions and output collisions. `Test-WholeVolumes.ps1` checks whole-unit
rounding, chapter/volume separation, size retries and immediate leftovers.
`Test-OriginalHandling.ps1` uses only disposable generated inputs to check
explicit deletion acknowledgement, source/output verification, failure/Skip
retention, unconverted accompanying files and read-only preview. Never point
these tests at a personal library.

`Test-FilenameMarkers.ps1` covers the user's compact `v01`/`ch001` release-name
example, exact clean titles, filename-before-metadata classification, explicit
chapters above the page-count threshold, short explicit volumes, aliases,
fractions, whole ranges, safe no-marker fallback and duplicate release collisions.
The Clean title style is opt-in; existing naming preferences remain unchanged.

`Test-OutputFolders.ps1` exercises matching series folder cleanup, aliases, nested
paths, chapter/volume bundles, preview/publication agreement, duplicate policies,
cross-folder collisions and destination-aware completion records. Unmatched folder
names and original/archive paths are preserved. Only generated fixtures are used.

`Test-LeadingTags.ps1` checks complete leading square-bracketed release tags,
repeated/adjacent prefixes, aliases, preserved interior text, no-marker/empty-name
fallbacks, matching folders, chapter/volume grouping and collisions before conversion.

`Test-FolderSeries.ps1` checks v/ch-only source names under artist/series folders,
series separation, aliases, metadata priority, naming modes, MOBI/CBZ output,
preview/history agreement, original preservation, grouping and collision handling.

Source-only Book-Labels.ps1, Chapter-Support.ps1 and Originals-Handling.ps1 are
combined into packaged Workflow-Support.ps1. Keep the established runtime
payload so the original 0.1.18 updater can copy every required file.
Grouping completion records are kept separately in Working/chapter-receipts.json;
all members of a bundle are committed together, with a .bak copy on replacement.
The chapter helper is kept separately in app/ for development and combined into
the packaged Workflow-Support.ps1 during builds. This preserves the exact runtime
file list understood by the published 0.1.18 updater.

The optional `Test-NativeChapterBundles.ps1 -ToolSettingsPath <settings.json>`
uses only the selected tool locations and generated images in a new fixture.
It checks the selected KCC binary, runs a real MOBI conversion and compares
archived source hashes. It neither reads real books nor changes the provided
settings or schedule. Use `-FixtureRoot <new-short-path>` when a long checkout
path would exceed legacy tool path limits. Without a tool-settings argument,
this optional native test is skipped.

Actual Previewer detection on different PCs, MOBI/EPUB appearance on a reader,
normal installer integration and signed-in network access still need manual
acceptance testing before publication.

## KCC compatibility

`Test-ImmediateStop.ps1` launches only generated converter/child-process fixtures
and checks immediate cancellation, unchanged originals in Archive/Delete modes,
no partial publication, lock/run-record cleanup and successful retry. The shared
run record is `Working/active-run.json`; requests use its unique run identifier.
The UI never kills a PID from that record. The worker owns converter termination,
using a Windows job object with a scoped process-tree fallback on legacy hosts.
`app/Run-Control.ps1` is merged into the existing packaged Workflow-Support.ps1;
the established updater file list is retained.

`Test-ScribeCompatibility.ps1` checks the optional effective image settings,
scope, folder presets and restoration of stored choices when switched off.
Native Kindle appearance still needs a physical-reader check.

The app accepts working KCC c2e CLI versions without a compiled version or asset
hash pin. Setup verifies the executable identity, startup and required options;
the worker checks startup before converting. Legacy saved version-pin fields are
ignored. Users acquire KCC from its
[releases page](https://github.com/ciromattia/kcc/releases); the app does not
fetch KCC binaries directly or silently replace the selected converter.

`app/ToolUpdates.cs` schedules a release check after startup/setup and saved tool
changes. It waits while other work is active and applies results only if the tool
selection still matches. Desktop self-tests inject release/version readers to
check notices, offline behavior and disabled JPEG XL without network requests.
They also exercise replacement setup starting at the converter page. Checks
never import or replace tools; an explicit user-selected setup performs that work.

`Test-KccCompatibility.ps1` defaults to offline policy checks. A maintainer may
pass `-OfficialKccExe <downloaded-cli.exe>` to check startup and run a generated
CBZ-to-EPUB test, optionally adding `-ExpectedSha256 <upstream hash>`, or use
`-CheckLiveRelease` to check the latest GitHub release metadata.
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
- [KCC platform-parity plan](PLATFORM-PARITY-PLAN.md): Linux x86_64 first,
  shared worker/interface contracts, platform-specific runtimes, and the
  Windows 7 compatibility audit. Additional targets remain planned until tested.
- [Shared worker contracts and replay corpus](contracts/README.md): executable
  validators, lossless Windows settings import and cross-platform behavior cases.
- [Platform inventory](platforms/README.md): pinned upstream evidence and the
  [Windows 7 audit](platforms/WINDOWS7-AUDIT.md). Unknown native requirements
  remain explicit; this inventory does not grant new converter approvals.

## Copyright and attribution

KCCAutomate remains under ISC, with `squishysquidly` credited for its own work.
The existing KCC copyright notices and permission text remain in license.txt.
Credit in the user guide explains which separate tools do the conversion work.
Third-party tools retain their own licence terms and are not part of the app
release payload. Do not remove upstream notices from any reused source.
