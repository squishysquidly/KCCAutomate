# KCCAutomate for Windows

Convert downloaded comics with your existing KCC tools, preserve folder
structure, and archive originals after verified conversion. Local and UNC
network folders are supported, including processing on a network share.

## What's new in 0.7.0

Guided setup now presents **one tool per page**, in dependency order:

1. Choose your reader, format and reading direction.
2. Detect and test **7-Zip** archive support.
3. Select the approved **KCC 12.0.0 CLI**.
4. Locate **KindleGen** for MOBI output.
5. Add **JPEG XL/djxl** support, or turn it off for now.
6. Optionally test a copied book.
7. Optionally choose scheduled check times.
8. See the automatically prepared **Incoming, Converted and Originals** folders.

Each tool page explains its purpose, the expected file, how to get it, and how
to complete the step. Automatic checks focus on the active page and its required
archive helper. **Find installed copy** and **Check again** apply to the current
tool. Completed pages keep their results; a missing required tool blocks only
its own page. Extra explanations are in expandable questions. Existing checks
for working KindleGen builds, archive imports and approved KCC versions remain.
Selected tools are copied and rechecked after the last tool page, before the
optional sample conversion.

The final page explains where completed source books belong, where converted
books go, and how verified originals move. Folder paths are shown for reference;
choose **Open Folders & tools after I finish** to customize them in the app.
Default installed book folders are under **Documents\KCCAutomate**; portable
defaults are under **data\Books**. Existing local and network selections remain.
If final folder preparation fails, setup offers to open the folder settings and
does not enable a new schedule. Existing files are never replaced by folder
creation. In the app, **Create & check folders** saves chosen paths, creates
missing folders and verifies read/write/rename/delete access without converting
books. Startup availability checks remain read-only.

Both installer and portable packages are provided. Setup progress is still
saved when you finish; resuming an unfinished wizard is a possible later
improvement. Tray controls remain a separate future build.

## What's new in 0.6.1

New setups supply and create Incoming, Converted, Originals and Working folders
automatically on reaching the Folders page. Installed defaults are in
**Documents\KCCAutomate**; portable defaults are in **data\Books**. Existing
saved paths, including network locations, are preserved. You can change any
folder in Folders & tools. Missing incoming folders can
now be created during setup as well as the other three folders.

Each tool entry checks automatically after you choose or paste an executable
or its containing folder. Completed checks stay green while another entry is
edited; an older result cannot validate a path changed during the check.
**Check tools** remains available for a manual recheck. JXL ZIP/7z packages
are prepared and tested automatically after selection.

7-Zip is detected in Program Files and PATH before asking for a location.
Detection tests CLI archive creation and extraction, including its runtime DLL.
A working detected installation completes that checklist item automatically;
the manual picker is collapsed until needed. KindleGen is checked without input
first. Amazon builds reporting `kindlgen` and the expected `E30010` unsupported
`-help` response are recognized instead of being incorrectly rejected. Other
unexpected KindleGen errors still fail validation.

Setup downloads the exact approved **Windows command-line executable**:
[tool_cli_c2e_12.0.0_AMD64.exe](https://github.com/ciromattia/kcc/releases/download/v12.0.0/tool_cli_c2e_12.0.0_AMD64.exe).
The GUI download `KCC_12.0.0.exe` is a separate application and is unnecessary
for KCCAutomate. You may select the CLI's original filename or rename it to
`kcc-c2e.exe`.

The Python dependencies are still needed, and the approved standalone `.exe`
already includes them. The Debian `apt-get` instructions apply to an unbundled
Python/source installation. Here is their equivalent for this Windows setup:

| Dependency | How it is supplied |
| --- | --- |
| Python (`python3`) | CPython 3.11 bundled inside the approved CLI |
| Pillow (`python3-pil`) | Bundled in the CLI |
| psutil (`python3-psutil`) | Bundled in the CLI |
| python-slugify (`python3-slugify`) | Bundled in the CLI |
| 7-Zip (`p7zip-full`) | Separate Windows 7-Zip download; select `7z.exe` in setup |
| KindleGen | Separate selection for MOBI; follow KCC's linked guide |
| JPEG XL decoding | Separate Windows libjxl/djxl download; imported in setup |

KCC's [Windows packaging workflow](https://github.com/ciromattia/kcc/blob/v12.0.0/.github/workflows/package-windows.yml)
installs its Python requirements before building the
[standalone c2e executable](https://github.com/ciromattia/kcc/blob/v12.0.0/kcc-c2e.spec).
We also checked the exact release download's SHA-256 and bundled runtime,
then converted a generated two-page CBZ into EPUB with Python absent from PATH
and Python environment overrides cleared. This verifies a real CLI startup
and conversion, rather than relying only on the presence of a Python install.
MOBI output and visual quality still need testing with KindleGen and a reader.

**KCC stays on approved version 12.0.0.** Guided setup checks the version, the
updater queries the approved release tag instead of GitHub's newest KCC release,
and download/use checks enforce its exact asset and SHA-256. App-saved settings
also carry this approval to normal and scheduled conversions; a different
reported KCC version is rejected before conversion, retaining incoming originals.
Legacy standalone script configurations without an approval field retain their
existing behavior. App and JXL update checks continue to use stable releases.

After a new KCC version has been manually tested, update the approval policy
and publish a new KCCAutomate release as described in [RELEASING.md](RELEASING.md).
Pushing source commits alone does not deliver an update to installed apps.

## What's new in 0.6.0

Setup now explains **MOBI (AZW3/kindle compatible)** and the purpose of each
book folder. KCC and JPEG XL paths start empty until selected; existing saved
selections, including KindleGen, are retained when setup is reopened.

The Tools page has a separate checklist for KCC c2e, JPEG XL decoding,
KindleGen and optional 7-Zip. Red crosses mean missing, unchecked or failed;
green checks mean the executable started and identified itself. Optional tools
are marked with a gray circle. These checks do not replace trying a book.
KCC must be **kcc-c2e.exe** or the release's **tool_cli_c2e_…_AMD64.exe**,
rather than the graphical KCC application or c2c tool.

The setup links to the [approved 12.0.0 CLI release](https://github.com/ciromattia/kcc/releases/tag/v12.0.0),
[KCC's dependency and KindleGen guide](https://github.com/ciromattia/kcc/wiki/Installation),
[Windows JPEG XL tools](https://github.com/libjxl/libjxl/releases) and
[official 7-Zip downloads](https://www.7-zip.org/). Version 12.0.0 is the known
working version reported for this workflow, not a guarantee for all machines.
The 12.1.1 c2e package reported a missing PySide6 module in this workflow.
Packaged Windows executables include Python; installing Python separately
does not repair missing modules in a frozen executable. Starting with 0.6.1,
newer KCC versions need maintainer approval in a KCCAutomate release.

Select **djxl.exe**, a **.zip**, or a **.7z** Windows JXL package. 7-Zip's
**7z.exe** is required for .7z imports; .zip imports use Windows/.NET support.
Setup automatically checks for an existing 7-Zip installation. Follow the
official download link to install it if needed, then search again. KCC can
use 7-Zip for archive and metadata support; it is optional for the usual CBZ
workflow. No software is installed automatically or added to the system PATH.
Archive imports reject unsafe paths, links, duplicate entries and oversized
packages. A package must contain one Windows djxl.exe; use the package for
your Windows architecture, or manually extract and select the correct decoder.

**Continue on the Tools page copies and checks the tools again**. KCCAutomate
preserves accompanying DLLs, common runtime folders and license files. For
JXL package imports it preserves the package layout, including sibling libraries.
Standalone executables must remain beside the runtime files supplied by their
author when selected. Copied programs are hash-verified before being selected;
the original downloads are neither moved nor deleted. Successful imports have
a file-hash manifest, and a verified bundle is reused on returning to this page.
Failed imports retain a diagnostic folder without changing saved settings.

Installed tools live in **%LOCALAPPDATA%\KCCAutomate\Tools**. Portable tools
live in **data\Tools** beside the portable settings. These folders are retained
by app updates; uninstall retains user tools and settings. The app uses the
copied paths only after finishing setup. Advanced path editing still uses the
locations you enter directly; use guided setup to copy external tools.
Selected KindleGen and 7-Zip folders are passed only to conversion processes.
Books, archive and working folders remain wherever you choose, including a
network share.

Both installer and portable downloads are provided. Tray controls remain the
next separate improvement.

## What's new in 0.5.0

This build adds duplicate handling and a startup folder availability check.
Tray controls are next, followed by a reassessment. Archive versioning is
deferred; sample-page preview is lower priority and automatic network retries
are at the bottom of the backlog.

In **Conversion**, choose what to do when converted output already exists:

| Choice | Result |
| --- | --- |
| Review conflicts (default) | Preserve different existing output and incoming originals for review. Identical output can be reused after hash verification. |
| Replace | Publish the newly converted output over existing files, verify it, then archive eligible originals. |
| Keep both | Preserve different existing output and publish the new book with a free number, such as `Book (2).mobi`. All split parts share the same number. |
| Skip | Keep existing output and incoming originals in place. A folder stays incoming until every selected input has a verified conversion. |

The policy is available in both Simple and Advanced views. Earlier replacement
preferences are preserved. Duplicates are detected at planned output paths;
verification uses hashes. Separate input folders remain independent.

For a conflict in **Queue dashboard**, select the affected rows, choose an
**On retry** action, and click **Retry selected**. A one-run choice does not
change the saved default and resets after starting. It applies only to the
selected output conflicts. Two incoming files targeting one output name must
be renamed or separated; even replacement cannot silently combine them.

Valid conversion receipts are reused, including receipts for numbered output.
Changed or missing output can be explicitly regenerated with Replace or Keep
both. Skip avoids conversion when the primary output already exists. For split
books, conversion may be needed to identify all output-part names before skipping.
Unverified skipped originals are retained, with no automatic archival.

At startup, the app checks whether the four saved folders exist and can be
listed, using the same check for local and remote locations. An inline error
identifies unavailable paths and offers **Open folders** and **Check saved
folders again**. The check runs in the background, has a timeout, and creates
or moves no book folders. Guided setup still checks write access. Automatic
network retries are not added.

## What's new in 0.4.0

This build adds **Simple and Advanced views**, the second priority. It includes
both the Windows installer and portable ZIP.

- **Simple** is the default. It keeps reader selection, reading direction,
  spread handling, cropping, enlargement, input formats, presets, queue,
  schedule, notifications, appearance and updates available.
- **Advanced** shows the full tool paths, working-folder editor, image
  adjustments and stretching, filename and replacement controls, preset
  import/export, folder rules, retention, quiet hours, update-source editor and
  app rollback.
- Switch at the top of any page. Your current page, unfinished edits, preset
  choices and conversion settings remain intact. Switching does not save a
  draft, change a schedule or start a conversion.
- Hidden options keep applying. Simple view summarizes image processing, file
  replacement, naming, rules, working location and background preferences.
  **Show image and file settings**, **Show tool settings** and **Show all
  preferences** open the appropriate Advanced section.
- The view choice is remembered separately in `interface.json` beside your
  settings, even before setup is complete. It is not included in exported
  conversion presets. Missing or unreadable view preferences fall back to Simple.
- With configured folders, Simple view opens on the queue dashboard. Guided
  setup remains available from Folders & tools.

The conversion engine and your existing conversion options were unchanged by
the 0.4.0 release.

## What's new in 0.3.0

This build delivers the installer, portable package, and the first priority:
guided first-run setup. Further interface improvements are separate builds.

- **Windows installer:** `KCCAutomate-Setup.exe` installs for your account without
  elevation, creates a Start menu shortcut, optionally creates a desktop shortcut,
  and adds an uninstall entry in Windows Settings. KCC, KindleGen and djxl are
  selected separately; they are not bundled.
- **Portable ZIP:** extract `KCCAutomate-Windows.zip` and open `KCCAutomate.exe`.
  Keep `portable.flag` and the companion files in place. Settings, presets,
  downloaded tools and update backups live in the app's `data` subfolder.
- **Guided setup:** six steps cover the reader, folders, installed tools, an
  optional test conversion, daily check times and a final review. Reopen it with
  **Guided setup** under Folders & tools. Access checks create missing destination
  folders and tiny temporary probes, then remove the probes.
- **Safe test book:** a verified copy is converted in an isolated `SetupTests`
  area inside the chosen working folder. The selected original and normal
  incoming/output/archive folders are untouched. Results remain there for review
  and manual removal. Use a short working path for older tools such as KindleGen.
- **KindleGen picker:** select its executable directly. Its folder is added to
  conversion processes only, without changing the Windows PATH.

The wizard saves only when you finish. **Set up later** discards draft settings;
completed folder probes and optional test files remain as described above.
Automatic checks are opt-in. Leaving the checkbox clear preserves any existing
schedule. Preview the queue before starting a normal run.

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
2. **Download & verify selected** stages the asset under your local KCCAutomate
   settings folder. The size and SHA-256 digest supplied by GitHub must match.
   Assets without a digest are blocked. This verifies download integrity, not a
   publisher code signature; the current app build is unsigned.
3. Tool downloads must pass a `--help` smoke test before **Install / use verified
   version** can select them. This catches startup/dependency errors but does
   not prove full book conversion compatibility. Old paths remain available
   through **Restore previous version**. Original tool installations are untouched.
4. App installation closes and relaunches KCCAutomate, checks staged file hashes,
   obtains the conversion lock, backs up installed files and applies the update
   at the same path. Settings, presets, external tools and scheduled-task paths
   stay in place. If a conversion is active, installation is canceled; retry
   later. A failed installation attempts to restore the original files.
5. To roll back the app, select KCCAutomate after checking releases and click
   **Restore previous version**. The latest backup is verified before restoration.
   Installation needs write access to the portable app folder. No automatic
   administrator elevation is attempted.

Updates require published release assets; merely pushing source changes does
not make an app update available. This project includes
`.github/workflows/release.yml`, which builds and tests on Windows and attaches
`KCCAutomate-Setup.exe`, `KCCAutomate-Windows.zip` and `SHA256SUMS` when a release is
published. The release tag must match the compiled version, currently `v0.7.0`. A manual workflow run
builds/tests/packages without publishing. No GitHub release has been published
by the local build scripts.

Keep `AssemblyVersion`, `AssemblyFileVersion`, `ReleaseClient.AppVersion`, the
manifest version and the release tag aligned when preparing a later version.
`Package-App.ps1` builds the portable ZIP from an explicit file list, excluding
test fixtures and settings. The updater checks this package layout before use.

## Open the app

Choose one distribution:

- **Installed:** run `KCCAutomate-Setup.exe`, then open KCCAutomate from Start.
  The default location is `%LOCALAPPDATA%\Programs\KCCAutomate`.
- **Portable:** extract the entire ZIP to a permanent, writable local folder,
  then double-click **KCCAutomate.exe**. Keep the accompanying files beside it.
  Do not run directly inside the ZIP or use a protected Program Files folder.

Windows 11 includes
the .NET Framework and Windows PowerShell used by the app; no Python or .NET SDK
is needed to run it. Both distributions are currently unsigned.

The first launch opens guided setup. You can also configure everything manually:

1. **Folders & tools:** choose a watch folder, converted-books folder and archive.
   Local and UNC network paths are supported. A separate working folder is
   suggested beside the watch folder. Choose a different location in the
   Working folder section if needed. None of the four folders may overlap.
2. Select the KCC **c2e command-line executable**, not the graphical application.
   For MOBI output, select KindleGen or ensure KCC already finds it. Select libjxl's
   **djxl.exe** if JPEG XL conversion is enabled. Companion files supplied with
   these tools should stay together. Tools are not bundled; downloads under
   Settings & updates are explicit.
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

Installed-mode settings are stored in `%LOCALAPPDATA%\KCCAutomate\settings.json`;
portable-mode settings are in `<app folder>\data\settings.json`. Each retains a
backup from the previous save. Keep the portable folder together when moving it.
Paths to books and external tools remain absolute; moving the app does not move
those folders or make those paths portable across PCs.

Earlier test builds used the working name MangaFlow. Installed KCCAutomate
imports `settings.json`, `presets.json` and their save backups from
`%LOCALAPPDATA%\MangaFlow` when no KCCAutomate settings exist. The old files are
kept, and existing KCCAutomate settings are never replaced.

To reuse an earlier ZIP copy's configuration, close the app and copy those two
JSON files from its `data` folder (or `%LOCALAPPDATA%\MangaFlow` for version 0.2)
into the new portable copy's `data` subfolder before opening it. Disable any
schedule created under the earlier name before enabling the KCCAutomate schedule.
Use the new installer or portable ZIP for this naming correction; the earlier
working-name updater expects the old package filename.

Updating conversion settings affects future scheduled checks; changing the check
times or wake option requires clicking **Save & enable schedule** again.

To remove an installed copy, close KCCAutomate and use **Settings > Apps > Installed
apps > KCCAutomate > Uninstall**. It removes its application files, owned shortcuts
and the schedule pointing to that installation. Books, settings, external tools
and unknown files are retained. Reconnect the working share before uninstalling
so the conversion lock can be checked. For a portable copy, disable its schedule
before removing its folder; preserve `data` if you want to keep the configuration.

## Scheduling and operation

- Scheduled checks work with the app closed while your Windows account remains
  signed in, including with the screen locked. The machine must be powered on
  and the share reachable. Wake is subject to Windows hardware/power settings.
- The task name starts with `KCCAutomate-`, followed by your account SID. There is
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
- Converted books use your chosen duplicate policy: review, replace, keep both
  or skip. Two selected inputs that would produce the same book name are stopped
  for review, including loose inputs of different formats.
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

- [Approved KCC CLI 12.0.0 release](https://github.com/ciromattia/kcc/releases/tag/v12.0.0)
- [KCC KindleGen and 7-Zip setup](https://github.com/ciromattia/kcc/wiki/Installation)
- [libjxl Windows tools](https://github.com/libjxl/libjxl/releases): choose
  `jxl-x64-windows-static.zip`, extract it, and locate `djxl.exe`.

Device codes, options and the current approval policy use KCC v12.0.0.
The v12.1.1 c2e executable reported a missing PySide6 module during the original
setup. The exact 12.0.0 Windows CLI now passes a real generated-CBZ-to-EPUB
check without Python on PATH. This does not establish compatibility with every
device, book or tool version; test MOBI output and visual quality on the reader.

## Build and verify

Run in Windows PowerShell from the source folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-App.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Workflow.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-JxlPreprocessing.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Upgrades.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Duplicates.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Package-App.ps1 -SkipBuild
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Installer.ps1 -SkipPackage
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-Installation.ps1
```

Distributable files are `dist\KCCAutomate-Windows.zip`, `dist\KCCAutomate-Setup.exe`
and `dist\SHA256SUMS`. `Build-Installer.ps1` alone builds and packages both.
The extracted portable build is `dist\KCCAutomate\KCCAutomate.exe`. It uses Windows' .NET
Framework C# compiler and WPF, without fetching build packages. An offscreen
desktop check can be run with `KCCAutomate.exe --self-test <absolute-report-path>`;
the report's parent folder must exist. It validates settings and renders screens.

Tests cover settings validation, rendering, ordered format phases, previews,
archive merges, output conflicts, stopping and mocked scheduler registration.
Upgrade tests also cover selective retries, preset rules, retention boundaries,
conversion/update locking, installing/rolling back fixture app files, checksum
validation and rejection of tampered staged files and unsafe ZIP entries.
External converters are test doubles. Real KCC/KindleGen/JXL conversion and real
scheduled execution with your network credentials still require a local test.
Installation tests exercise embedded-payload verification, install/upgrade/remove
in disposable fixtures, user-file preservation, unsafe targets, and an isolated
wizard conversion. They do not register an application, shortcuts or tasks on
the test PC; those Windows integration paths need a manual installation check.
Test fixtures are retained in the test report folders or `%TEMP%` for inspection.
The original standalone `Convert-Manga.ps1` remains usable with its old defaults,
or accepts `-ConfigPath` for the app's saved settings.

The source repository's `ROADMAP.md` tracks the current build order. Tray
controls are next. Archive versioning is deferred; reassessment follows tray work.

## Repository license notice

The repository's existing ISC notice is retained below and in `license.txt`.

Copyright (c) 2012-2025 Ciro Mattia Gonano <ciromattia@gmail.com>
Copyright (c) 2013-2019 Paweł Jastrzębski <pawelj@iosphe.re>
Copyright (c) 2021-2023 Darodi (https://github.com/darodi)
Copyright (c) 2023-2025 Alex Xu (https://github.com/axu2)

Permission to use, copy, modify, and/or distribute this software for
any purpose with or without fee is hereby granted, provided that the
above copyright notice and this permission notice appear in all
copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA
OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
