# KCCAutomate platform-parity plan

Planning baseline: 2026-10-24, app 0.1.18. Current app: 0.1.20.
Status: proposed architecture and implementation sequence; no additional
platform is certified by this document. Linux x86_64 is the first delivery target.

Phase one is implemented in the [platform inventory](platforms/README.md),
[shared contracts](contracts/README.md), reference validators and reusable
Windows behavior replay. Native tool/OS gates remain open; the next phase is
the Linux x86_64 conversion worker.

## Compatibility boundary

KCC is the authority for operating systems and processor architectures.
KCCAutomate may certify a target only when the corresponding KCC conversion
path works there. An application starting successfully is insufficient evidence.
Do not add a platform because a UI toolkit happens to support it.

Users choose KCC from its upstream releases page. Runtime checks validate the
selected CLI without pinning a release. New KCC releases do not automatically
replace a user's tools or certify additional KCCAutomate operating systems.
The inventory's dated release evidence remains a platform research snapshot.

| Target | Upstream evidence | KCCAutomate delivery |
| --- | --- | --- |
| Linux x86_64 | `kcc_linux-VERSION-x86_64.AppImage` | First new platform; portable GUI and unattended worker. |
| Linux aarch64 / ARM64 | `kcc_linux-VERSION-aarch64.AppImage` | Reuse the Linux implementation; build and test natively for ARM64. |
| Windows ARM64 | `KCC_ARM64_VERSION.exe`, `tool_cli_c2e_VERSION_ARM64.exe` | Native host and tools; no assumption that x64 emulation establishes parity. |
| macOS ARM64 | `kcc_macos_arm_VERSION.dmg` | Apple Silicon application and worker, with native helper checks. |
| macOS Intel | `kcc_macos_i386_VERSION.dmg` | Intel build; inspect the Mach-O architecture and minimum OS of the actual upstream asset before declaring its floor. |
| Windows 7 legacy | `kcc_win7_legacy_VERSION.exe` | Retain the existing WPF base; repair and test the compatibility gaps below. Inspect the upstream PE architecture; do not imply 32-bit support from the legacy filename. |
| Windows x64 | `KCC_VERSION.exe`, `tool_cli_c2e_VERSION_AMD64.exe` | Preserve the existing product and its tested conversion settings. |

Here, the requested Linux "x86" means KCC's published x86_64 target. No true
32-bit Linux build is included. KCC's macOS "i386" filename is an upstream
label; it is not authority for a new 32-bit Mac target. Release recipes and
binary inspection determine the actual CPU and OS requirements.

The older Intel Mac recipe is evidence of an intended legacy target, not proof
that the currently published Intel DMG runs on 10.14. The inspected release
lists no separately named legacy Mac DMG. Verify the actual download and all
bundled framework minimums before including that older OS in the support table.

For every row, record the selected KCC version, upstream asset/source hash,
actual executable architecture, OS minimum, runtime/dependency versions,
working command-line invocation, tested output formats and test evidence.
On Linux, include the libc/loader baseline and required CPU instructions.
Use the oldest verified environment that runs the corresponding KCC build;
do not raise the OS floor just to use a newer application framework.

## Recommended bases

Use one shared automation engine, a portable desktop interface, and the
existing WPF interface for the Windows compatibility path. Share behavior and
data contracts; allow different runtimes and dependency pins per platform.

**Shared worker: Python with a platform-neutral core.** Move queue planning,
conversion order, receipts, output verification, duplicate policies, JXL
preparation, archival, cleanup and retry behavior into one headless worker.
Keep Python 3.8-compatible core syntax/APIs while Windows 7 parity requires
that runtime. Run newer tested Python versions on other targets. Bundle the
app's runtime so users do not have to configure Python or edit PATH.

The worker launches KCC as a separate process. KCC dependencies must not be
installed into the UI's environment. A native KCC CLI can use its own bundled
runtime; a source-based CLI needs a separately managed, approved environment.
Images remain the responsibility of KCC and validated helper tools, avoiding
unnecessary native Python dependencies in the shared automation core.

**Portable GUI: Python/Qt, using PySide with target-specific pins.** This is
the preferred candidate for Linux first, then macOS and Windows ARM64. Use a
common UI source and the same settings/worker contract as the Windows host.
Choose APIs supported by the oldest approved binding; keep platform-specific
differences in small adapters. Verify a complete Linux and older Intel Mac
prototype before making the framework choice final.

This revises the earlier Avalonia-first suggestion. Modern Avalonia remains
an option for newer systems, but its present support matrix does not establish
Windows 7 or older Intel Mac parity. KCC already maintains separate Qt/Python
dependency sets for legacy targets. Its 12.0.0 recipes use Python 3.8 for
Windows 7 and an Intel Mac legacy deployment target of 10.14 with a separate
dependency file. Those are useful starting points, not certification of our
new UI or worker. Reproduce and test the actual upstream floors first.

**Windows compatibility GUI: retain WPF/.NET Framework.** Keep the familiar
interface, installer and settings locations. Initially retain the current
worker until the shared worker passes equivalence tests. Then have WPF call
the shared worker through the same command/data interface as the portable GUI.
No new feature should acquire a separate, conflicting implementation of the
conversion or archival rules. A separate legacy build is acceptable when a
runtime or tool dependency requires it.

## Shared contracts and operating-system adapters

The shared worker exposes explicit commands for preview, run, tool checks,
cleanup and cooperative stopping, with structured JSON results and stable exit
codes. Settings, presets, queue/history and receipt formats are versioned.
Migrate a copy of existing settings, preserve a recoverable backup, and never
activate a schedule automatically during migration. Keep WPF, portable GUI
and worker protocol versions compatible or report a precise mismatch.

Separate adapters handle:

- Tool launching: executable plus an argument list, optional interpreter or
  launcher prefix, working directory and scoped environment. No constructed
  shell command strings; support spaces, quotes, Unicode and leading dashes.
- Paths: native separators and case rules, existing symlinks, read/write
  permissions and mounted network shares. Never lowercase real paths or assume
  Linux/macOS accept Windows UNC paths directly.
- Scheduling: Windows Task Scheduler; Linux user systemd timers where
  available with a tested cron/session-scheduler fallback; macOS launchd
  LaunchAgents. No root access should be needed for normal per-user scheduling.
  The worker must run with the GUI closed. Check effective times, missed-run
  behavior, login/session requirements and the scheduler's actual environment.
- Process control and locks: prevent overlaps, cooperate with stop-after-file,
  retain originals after failure and distinguish stale state from an active
  conversion. Test locking on the supported network-share configurations.
- Storage and desktop integration: per-user settings/tools, portable storage,
  file pickers, notifications, opening folders and optional startup behavior.
- Packaging and updates: choose assets by OS, architecture, OS minimum and
  runtime family, including the legacy lane. A Windows 7 installation must
  never be offered an incompatible modern Windows package.

Platform-specific limitations must be explained in the UI. For example,
wake-from-sleep behavior depends on the operating system. Do not silently
report a feature as enabled when the selected scheduler cannot provide it.

## KCC and helper acquisition

Maintain a compatibility manifest per target, replacing the current global
AMD64 filename/hash assumptions. Include the official release page, approved
version, executable/launcher identity, distribution mode, hashes and helper
requirements. Keep acceptance tests separate from the approval data.

Users continue to acquire KCC from its own releases page and Amazon tools from
the appropriate official source/instructions. Keep the existing credit and
licence policy. An upstream GUI package is not automatically a usable CLI:

1. Prefer an official, approved CLI when one exists for the target.
2. Verify documented command-line entry points in platform packages, including
   their exit codes, output locations and background/session requirements.
3. Where there is no distributed CLI, test KCC's source c2e entry point in an
   isolated environment for that platform. Do not invent a CLI download URL,
   automate clicks in the KCC GUI, or assume its internal archive layout is a
   stable interface. Resolve a simple, user-obtained source/package setup
   before calling the platform ready.

Validate KindleGen, 7-Zip/archive support and djxl for each OS/CPU combination.
MOBI support needs a proven compiler path. KCC documents legacy KindleGen on
Linux and Rosetta use on Apple Silicon; native ARM KCC alone does not prove
native ARM MOBI compilation. Record any upstream-required translation/runtime
explicitly. Test through the same KCC path users will install.

If a prerequisite is missing, identify the affected formats and leave the
originals in Incoming. Keep formats that do not require that tool usable.
Full parity is not certified until the features available in the selected KCC
configuration have passed the corresponding end-to-end tests.

## Windows 7 audit and repair scope

The current Windows build is not certified for Windows 7. WPF/.NET Framework is a
suitable starting point, but the complete conversion/scheduling setup has
unverified requirements and known incompatible assumptions:

- Manage-Schedule.ps1 uses ScheduledTasks cmdlets, introduced with Windows 8.
  Add a Task Scheduler 2.0 COM/XML backend, available on Windows 7, and test
  enable/disable/status, all daily triggers, overlap prevention and quoted paths.
- The worker requires Windows PowerShell 5.1 features; Windows 7's original
  PowerShell installation is insufficient. Check SP1, WMF 5.1 and a tested
  .NET Framework version during setup. .NET Framework 4.8 is installable on
  Windows 7 SP1; do not require 4.8.1. A later shared-worker build can remove
  the PowerShell requirement once all runtime helpers have been replaced.
- Tool validation currently accepts only the approved modern AMD64 c2e
  download. KCC's Windows 7 download is a separate legacy GUI build, while its
  published release has no separately named Win7 c2e asset. Establish a
  verified legacy command-line acquisition/execution path before offering
  unattended conversions. Do not accept the modern CLI solely by its name.
- Check every helper, including 7-Zip, djxl and KindleGen, for its actual OS
  and CPU requirements; keep known-working dependency versions available in
  the compatibility record rather than selecting latest blindly.
- Build against explicit compatible framework references, audit used APIs,
  check manifest/installer prerequisite messages, and test HTTPS/TLS, hashes,
  archive extraction, settings, notifications and update rollback on the VM.
  No TLS certificate-validation bypass is an acceptable compatibility fix.

Test on an actual Windows 7 SP1 VM with the documented prerequisites, not just
on a modern Windows host that produced a legacy binary. Preserve the current
Windows product line, but ship any repairs in a new version; never replace
the published 0.1.18 downloads. Do not advertise 32-bit Windows 7 until the
upstream converter and every helper have corresponding verified support.

## Delivery order: one reviewable improvement per build

1. **Platform inventory and contracts.** Record real upstream/runtime evidence,
   reproduce the current Windows behavior as reusable scenario fixtures, and
   define the worker/settings protocol. Record Windows 7 gaps without claiming
   they are already repaired. Exit: all target identities and unresolved gates
   are explicit; no new public platform claim.
2. **Linux x86_64 conversion worker.** Prove selected KCC execution, tool checks,
   CBZ/JXL and PDF handling, requested reader settings, output verification,
   failure retention and archival against the shared scenarios. Exit: unattended
   runs work on the verified Linux baseline without altering normal libraries.
3. **Linux x86_64 desktop and scheduling.** Implement guided setup, Simple/
   Advanced settings, presets/rules, queue/history, duplicate handling, tool
   imports, themes and update behavior. Add scheduling with the GUI closed,
   portable packaging and a novice setup walkthrough. Exit: complete Linux
   x86_64 acceptance, including network mounts, before expanding to ARM.
4. **Windows 7 compatibility build.** Repair scheduling and prerequisites on
   the retained WPF base; resolve the legacy CLI/tool chain and test real books
   on Windows 7 SP1. Exit: documented, repeatable compatibility of the complete
   product, or an explicitly recorded remaining blocker. This does not depend
   on finishing either Mac port or Windows ARM64.
5. **Linux aarch64.** Reuse the worker/GUI and certify native KCC, helper tools,
   packaging and scheduling on ARM hardware. Exit: the same acceptance scenarios
   as Linux x86_64, with no reliance on an x64 test passing.
6. **macOS Intel and ARM.** Resolve the older Intel runtime/Qt floor and Apple
   Silicon compiler/runtime requirements; implement LaunchAgents, macOS storage,
   permissions, app bundles and target-specific updates. Test both architectures
   and the verified minimum OS, including the legacy Intel lane when required.
7. **Windows ARM64.** Build the portable interface/worker natively, use the
   approved ARM64 converter, and test every helper and scheduled background run.
   Preserve current Windows x64 operation and the Windows 7 compatibility lane.

Linux x86_64 remains ahead of all new architecture ports. Break each phase
into individual builds for review; this sequence is not a request to publish
all targets in the next version. Existing UX proposals remain a later backlog.

## Acceptance and release gates

Use the same scenario definitions on every target: identical source fixtures,
chosen options, queue outcomes and archive/output expectations. Compare rendered
pages, dimensions, spread order and e-reader behavior rather than expecting
byte-identical ebooks across operating systems.

Cover installer/portable startup, clean setup, every required helper, a real
CBZ-to-EPUB and CBZ-to-MOBI conversion where supported upstream, JXL preparation,
CBZ-before-PDF order, Unicode/long/special paths, local and mounted network
folders, nested-path rejection, downloads still changing, existing outputs,
archive merges, partial failures, cross-filesystem archival, restart recovery,
concurrent runs, presets, per-folder rules, naming, cleanup, notifications,
scheduled execution with the GUI closed, and update/rollback without data loss.

Do not move originals until all selected books in their batch have verified
output. Across filesystems, copy and verify before removing the source. Existing
archive merge/overwrite semantics remain; platform work does not add versioned
backups or silently change duplicate policy.

Native runtime tests are required. Cross-compilation and emulated smoke tests
alone are insufficient. Old-OS tests may run inside VMs controlled by a supported
host; do not assume a current GitHub runner can be installed on Windows 7 or
the oldest Intel macOS. Record tested Linux display/session environments.

For releases, aggregate artifacts built from the same source commit into one
draft, with target-specific filenames, hashes and a compatibility manifest.
Preserve existing updater filenames for the current Windows lane until it has
a tested migration. The draft must accurately distinguish available targets
from planned or experimental targets. Partial platform rollouts may be shipped
as clearly identified previews; do not label them complete KCC platform parity.
The maintainer reviews and publishes only after the promised targets are ready.
Future corrections use a new 0.1.x version; published assets and tags stay intact.

## Primary evidence

- [KCC 12.0.0 release assets](https://github.com/ciromattia/kcc/releases/expanded_assets/v12.0.0)
  and [12.1.1 release assets](https://github.com/ciromattia/kcc/releases/expanded_assets/v12.1.1).
- KCC 12.0.0 build recipes: [Linux](https://github.com/ciromattia/kcc/blob/v12.0.0/.github/workflows/package-linux.yml),
  [macOS](https://github.com/ciromattia/kcc/blob/v12.0.0/.github/workflows/package-macos.yml),
  [older Intel macOS](https://github.com/ciromattia/kcc/blob/v12.0.0/.github/workflows/package-osx-legacy.yml),
  [Windows](https://github.com/ciromattia/kcc/blob/v12.0.0/.github/workflows/package-windows.yml),
  [Windows 7](https://github.com/ciromattia/kcc/blob/v12.0.0/.github/workflows/package-windows7.yml)
  and [CLI build entry points](https://github.com/ciromattia/kcc/blob/v12.0.0/setup.py).
- [KCC tool installation and KindleGen notes](https://github.com/ciromattia/kcc/wiki/Installation).
- [Microsoft: ScheduledTasks module introduced with Windows 8](https://learn.microsoft.com/en-us/windows/win32/taskschd/what-s-new-in-task-scheduler)
  and [Task Scheduler 2.0 OS requirements](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page).
- [Microsoft: .NET Framework OS requirements](https://learn.microsoft.com/en-us/dotnet/framework/get-started/system-requirements).
- [Python: Windows 7 requires the Python 3.8 line](https://docs.python.org/3.13/using/windows.html).
- [Avalonia: current platform support](https://docs.avaloniaui.net/docs/supported-platforms).

Review the evidence again when an upstream release changes its platform matrix.
