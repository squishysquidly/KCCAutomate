# KCCAutomate: current status

**Current version: 0.1.19** Windows release candidate.
This is the first update from 0.1.18, described in the
[consolidated release overview](RELEASE-NOTES.md).

## Implemented

- Windows installer and portable ZIP, with a guided first-run setup.
- Supplied app artwork embedded in the app, installer and uninstaller, with
  matching window, taskbar and shortcut icons at multiple Windows display sizes.
- Reader profiles, conversion options and persistent Simple/Advanced views.
- Optional CBZ chapter grouping with page and converted-size budgets, stable
  chapter-range titles, metadata/first-image covers, whole-chapter size retries,
  pending remainders and atomic completion records for every bundle member.
- Optional whole-volume grouping with a separate page target, whole-unit size
  retries and immediate leftovers; chapter/volume groups remain distinct.
- Readable embedded titles and filenames, short series aliases, optional
  leading numbers and a number strip above existing cover art.
- Opt-in filename cleaning through v/ch numbers, with explicit markers taking
  priority over page counts and conflicting metadata when grouping inputs.
- Leading square-bracketed release-tag cleanup in generated clean filenames,
  book titles and matching series folders, including repeated tags and aliases.
- Series titles inferred from the immediate parent folder for v/ch-only CBZ
  filenames, preserving artist/collection nesting and per-series grouping.
- Clean series folder names in Converted, with aliases, nested path preservation
  and collision checks shared by preview and conversion.
- Archive originals by default, or explicitly acknowledge permanent deletion
  after conversion verification; unconverted accompanying files stay put.
- User-supplied KCC CLI, currently verified against version 12.0.0; acquisition
  links open KCC's own GitHub releases page.
- Automatic checks for installed 7-Zip CLI and likely Kindle Previewer/
  KindleGen locations, with post-install rechecking and illustrated help.
- Optional JPEG XL preparation, including selective ZIP/7z decoder imports
  which retain runtime companions and licence material.
- Conditional setup pages, an optional copied-book test, automatic default
  folders and a final explanation of scheduled operation and book handling.
- Separate Incoming, Converted, Originals and Working locations on local
  drives or network shares; folder validation and an availability banner.
- Scheduled checks using Windows Task Scheduler, quiet periods, overlap
  prevention and stop-after-file behavior.
- Selected input formats, CBZ-before-PDF processing, preserved subfolders,
  verified output and archival only after a successful batch.
- Existing-output policies: review, replace, keep both or skip; selected retries.
- Saved presets, per-folder rules, filename templates, queue/history views,
  Activity logs, optional attempt cleanup, notifications and light/dark themes.
- User-triggered app/JXL updates with hash checks and rollback; KCC downloads
  remain manual. Licence notices are included in fresh packages and updates.

## Acceptance before publication

Automated workflow, tool-import, compatibility, duplicate, update, installer
fixture and desktop tests are available in development/. Real book appearance,
different Previewer installations, normal Windows installation/uninstallation,
actual scheduled runs and network-account access still need manual acceptance.
Linux and macOS builds are not implemented.

## Current priority: KCC platform parity

The first stage, platform inventory and shared contracts, is implemented:
see the [inventory](platforms/README.md) and [contract/replay guide](contracts/README.md).
The next implementation stage is the Linux x86_64 conversion worker. Native
platform certification remains separate from these source/fixture checks.

Follow the [platform-parity plan](PLATFORM-PARITY-PLAN.md). Linux x86_64 is
the first new platform, followed by Windows 7 compatibility repair, Linux
aarch64, macOS Intel/ARM64 and Windows ARM64. Preserve Windows x64 throughout.
The platform boundary follows KCC's own verified targets; no extra 32-bit Linux
or Mac support is implied by ambiguous upstream filenames.

Use a shared conversion worker with portable and legacy desktop/runtime
adapters as needed. The existing WPF base is retained for the Windows
compatibility path. Windows 7 support needs scheduler, prerequisites and legacy
converter verification before it can be claimed. These are planned changes;
The current Windows build has not gained additional platform compatibility.

## UX backlog after platform work

Book organization follow-ups: a cover image chooser/preview, optional reviewed
database matching, and explicit per-book chapter/volume overrides. Page-count
classification cannot establish official published volume boundaries. Kindle
collection membership remains managed through the reader's own controls.

1. **Consistent readiness checks.** Guided setup identifies KindleGen, while
   the main Check setup action checks KCC/JXL startup without establishing that
   MOBI's compiler is available. Present one precise readiness result, with a
   direct route to any setting that needs attention. Keep startup folder checks
   read-only and distinguish tool startup from a real book test.
2. **Effective schedule status.** Read the actual Windows task at startup,
   show its enabled state, effective times, next check and last result, and
   detect paths broken by moving a portable app. General settings saves and
   schedule registration are currently separate actions.
3. **Settings recovery.** Saves keep a backup, but invalid primary settings
   currently prevent startup. Offer restoration or a fresh configuration while
   preserving the damaged file and requiring review before automatic operation.
4. **Cancel a stuck conversion safely.** The worker waits for the current
   converter; Stop after this file cannot interrupt a frozen process. Provide
   an app-owned process cancellation path that retains originals and makes the
   affected book retryable, without imposing a short timeout on large books.
5. **Tray controls.** Show progress, open the app and request stop-after-file.

Keep one improvement per build with review before the next one. These are
proposed improvements, not behavior claimed by the current release.

## Deferred

- Archive versioning: existing archive merge/overwrite behavior remains.
- Sample-page visual preview: lower priority.
- Network reconnection/retries: basic accessibility checks are the intended
  current scope; local drives and remote shares remain equally supported.
