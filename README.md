# MangaFlow for Windows

Version 0.2.0 adds a queue dashboard, selected retries, detailed preview, saved
presets, folder rules, naming templates, retention cleanup, notifications,
light/dark appearance and verified GitHub release updates.

## What's new in 0.2.0

- **Queue dashboard:** inspect each book's stage, JXL-page count, final path,
  failure details and suggested fix. Refresh also reads the next Windows
  scheduled check. Recent conversion history refreshes about every 20 seconds
  while the app is open. Preview scans ZIP directories without decoding images;
  it can still take time on large collections and slow network shares.
- **Selected retries:** select failed/conflicting book rows and retry only those
  inputs. Unfinished inputs in the same folder prevent the batch from being
  archived. Successful conversions remain recognized by receipts.
- **Presets:** save, apply, import and export conversion options. They never
  include folders, executable paths, schedule details or credentials. Presets
  live beside settings in `presets.json` and retain a previous-save backup.
- **Folder rules:** add a relative path pattern such as `Series A\*` and the
  exact preset name. The first matching rule wins. Patterns use PowerShell
  wildcards. Save settings to embed the rule's conversion options for scheduled
  workers, so the app does not have to stay open.
- **Output naming:** use `{name}`, `{profile}` and `{format}`; the extension is
  added automatically. Preview shows planned names. Name collisions remain
  protected. Naming changes produce new completion receipts.
- **Cleanup:** opt in under Settings & updates. Defaults retain successful
  attempt subfolders for 7 days and failed attempts for 30 days. Cleanup runs
  after checks or on demand under the conversion lock. Only recognized hash/job
  and GUID/attempt subfolders are eligible. Receipt files, job logs, original
  books and converted books are never cleanup targets. Older attempts without
  result markers use the longer failure retention period.
- **Notifications:** off by default, with errors-only or every-check options and
  optional quiet hours. These are local Windows notification balloons, subject
  to Windows notification preferences and the signed-in desktop session. No
  external messaging service is used. Preview and setup checks do not notify.

## Updates from GitHub

The default app update source is
[`squishysquidly/KCCAutomate`](https://github.com/squishysquidly/KCCAutomate).
KCC and JPEG XL are checked independently against `ciromattia/kcc` and
`libjxl/libjxl`. Update checks are manual; stable public releases are supported.
Private repositories/authentication and prerelease channels are not implemented.
The update source can be changed in Settings & updates; only choose a repository
whose published software you trust.

1. Click **Check GitHub for updates** and select a component to read its release
   notes. Installed tool versions are detected from help/version information;
   unavailable or unrecognized versions are shown explicitly.
2. **Download & verify selected** stages the asset under your local MangaFlow
   settings folder. The size and SHA-256 digest supplied by GitHub must match.
   Assets without a digest are blocked. This verifies download integrity, not a
   publisher code signature; the current app build is unsigned.
3. Tool downloads must pass a `--help` smoke test before **Install / use verified
   version** can select them. This catches startup/dependency errors but does
   not prove full book conversion compatibility. Old paths remain available
   through **Restore previous version**. Original tool installations are untouched.
4. App installation closes and relaunches MangaFlow, checks staged file hashes,
   obtains the conversion lock, backs up installed files and applies the update
   at the same path. Settings, presets, external tools and scheduled-task paths
   stay in place. If a conversion is active, installation is canceled; retry
   later. A failed installation attempts to restore the original files.
5. To roll back the app, select MangaFlow after checking releases and click
   **Restore previous version**. The latest backup is verified before restoration.
   Installation needs write access to the portable app folder. No automatic
   administrator elevation is attempted.

Updates require published release assets; merely pushing source changes does
not make an app update available. This project includes
`.github/workflows/release.yml`, which builds and tests on Windows and attaches
`MangaFlow-Windows.zip` and `SHA256SUMS` when a release is published. The release
tag must match the compiled version, currently `v0.2.0`. A manual workflow run
builds/tests/packages without publishing. No GitHub release has been published
by the local build scripts.

Keep `AssemblyVersion`, `AssemblyFileVersion`, `ReleaseClient.AppVersion`, the
manifest version and the release tag aligned when preparing a later version.
`Package-App.ps1` builds the portable ZIP from an explicit file list, excluding
test fixtures and settings. The updater checks this package layout before use.

A portable desktop app for converting downloaded comics with your existing KCC
installation. Choose folders, a reader profile and conversion options, then run
the queue manually or let Windows check it on a daily schedule.

## Open the app

Extract the entire portable ZIP to a permanent local folder, then double-click
**MangaFlow.exe**. Keep the accompanying files beside it. Windows 11 includes
the .NET Framework and Windows PowerShell used by the app; no Python or .NET SDK
is needed to run it. This first build is unsigned.

1. **Folders & tools:** choose a watch folder, converted-books folder and archive.
   Local and UNC network paths are supported. A separate working folder is
   suggested beside the watch folder. Choose a different location in the
   Working folder section if needed. None of the four folders may overlap.
2. Select the KCC **c2e command-line executable**, not the graphical application.
   For MOBI output, KindleGen must be available to KCC. Select libjxl's
   **djxl.exe** if JPEG XL conversion is enabled. Companion files supplied with
   these tools should stay together. Tools are not bundled or downloaded.
3. **Conversion:** choose your device, output format and processing settings.
   Defaults match the original workflow: Kindle Scribe 2022/2024, MOBI,
   right-to-left, upscale, no explicit cropping, split wide pages, no autolevel.
4. Click **Check setup**, then **Preview queue**. Setup checks launch tools with
   `--help`; preview only lists batches, selected-file counts and recent files.
   Neither performs a conversion or proves KindleGen can convert a book.
5. Test **Run now** with a copied small batch. Check the book on your device.
6. **Schedule:** choose daily times and click **Save & enable schedule**. The app
   registers a Windows task for your account. Disable any older conversion task
   first. There is no task installed until you click this button.

Settings are stored in `%LOCALAPPDATA%\MangaFlow\settings.json`, with a backup
from the previous save. They are independent of the portable app folder.
Updating conversion settings affects future scheduled checks; changing the check
times or wake option requires clicking **Save & enable schedule** again.

## Scheduling and operation

- Scheduled checks work with the app closed while your Windows account remains
  signed in, including with the screen locked. The machine must be powered on
  and the share reachable. Wake is subject to Windows hardware/power settings.
- The task name starts with `MangaFlow-`, followed by your account SID. There is
  one schedule per account. The app includes enable, disable and status controls.
- The default schedule is 08:00, 14:00 and 20:00, in the PC's local time.
- To run while signed out, open Windows Task Scheduler, find this task, select
  **Run whether user is logged on or not**, and provide the account password.
  Leave **Do not store password** unchecked for network access. Enabling the
  schedule again from the app resets it to the signed-in mode.
- Workers use `-ExecutionPolicy Bypass` for their own PowerShell processes. No
  permanent policy changes are made; organization policy can still take priority.
- Keep the app folder in place after scheduling. If moved, enable the schedule
  again to update its path. Disable it before removing the portable folder.
- **Stop after this file** waits for the active conversion and output verification
  to finish; remaining originals are retained. It controls only a run started
  from this app. Disabling a schedule prevents future checks, not an active run.
- The app prevents overlapping workers sharing the same working folder. The
  activity view shows manual runs. **Load conversion log** loads recent scheduled
  and manual results from the shared `automation.log`.

## File handling

- CBZ is enabled initially. PDF, EPUB, CBR and CB7 can be enabled separately.
  All eligible CBZs run before PDFs, followed by EPUB, CBR and CB7. This workflow
  targets image-based comics, not general prose ebook conversion. CBR/CB7 may
  require 7-Zip as described by KCC.
- A top-level folder is one archival batch. It moves only after all selected
  files in it succeed. Failures in one batch do not block other batches.
- Unselected files inside a successful batch are archived with it. Loose
  unselected files and folders with no selected inputs are left alone.
- Archived folders are merged. Matching archived files are replaced and verified;
  archive-only files are preserved. Source originals are removed after archive
  copies pass SHA-256 verification. This is a verified copy/remove operation,
  not an atomic network transaction. Do not modify active batches.
- Converted books are protected against conflicting existing files by default.
  There is an explicit option to replace them. Two selected inputs that would
  produce the same book name are stopped for review, even with replacement on.
- JPEG XL preprocessing currently applies to **CBZ only**. It creates a new
  CBZ with PNG replacements on the working share, retaining page paths and other
  contents. Original CBZs stay unchanged. A missing decoder, decoding failure
  or duplicate page name stops that batch. Turning JXL conversion off rejects
  JXL-containing CBZs rather than letting KCC omit those pages.
- Main KCC scratch directories and conversion staging remain on your chosen
  share when the source and working folders are on it. External tools may use
  Windows temp independently. Staged output uses short names to accommodate
  KindleGen; published books regain the source filename.
- Completion receipts verify earlier outputs on retries. Settings changes can
  cause reconversion; existing output-conflict rules still apply.
- The quiet period (30 minutes by default) and open-file probes are safeguards,
  not proof of download completion. Download elsewhere and move finished batches
  into the watch folder. Linked files/folders are rejected. Don't use `KCC-` as
  a top-level batch prefix; it is reserved for KCC scratch folders.
- Attempt files consume space until your configured cleanup runs. Cleanup is
  disabled initially. Job-level KCC logs and completion receipts are retained.

## Tool sources and compatibility

- [KCC releases](https://github.com/ciromattia/kcc/releases)
- [KCC KindleGen and 7-Zip setup](https://github.com/ciromattia/kcc/wiki/Installation)
- [libjxl Windows tools](https://github.com/libjxl/libjxl/releases): choose
  `jxl-x64-windows-static.zip`, extract it, and locate `djxl.exe`.

Device codes and exposed options are based on KCC v12.0.0. Check setup with the
version you install. The v12.1.1 c2e executable reported a missing PySide6 module
during the original setup; v12.0.0 was the suggested workaround. GUI/engine tests
here do not establish compatibility with every device or tool version.

## Build and verify

Run in Windows PowerShell from the source folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-App.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Workflow.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-JxlPreprocessing.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Upgrades.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Package-App.ps1 -SkipBuild
```

The portable build is `dist\MangaFlow\MangaFlow.exe`. It uses Windows' .NET
Framework C# compiler and WPF, without fetching build packages. An offscreen
desktop check can be run with `MangaFlow.exe --self-test <absolute-report-path>`;
the report's parent folder must exist. It validates settings and renders screens.

Tests cover settings validation, rendering, ordered format phases, previews,
archive merges, output conflicts, stopping and mocked scheduler registration.
Upgrade tests also cover selective retries, preset rules, retention boundaries,
conversion/update locking, installing/rolling back fixture app files, checksum
validation and rejection of tampered staged files and unsafe ZIP entries.
External converters are test doubles. Real KCC/KindleGen/JXL conversion and real
scheduled execution with your network credentials still require a local test.
The original standalone `Convert-Manga.ps1` remains usable with its old defaults,
or accepts `-ConfigPath` for the app's saved settings.
