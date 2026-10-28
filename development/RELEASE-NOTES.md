# KCCAutomate 0.1.20

This update from **0.1.19** makes KindleGen easier to find, accepts working KCC
CLI releases without a version pin and shows when newer tools are available.
It also adds Stop and an optional workaround for Scribe rendering problems.

## Easier KindleGen setup

- Step 4 checks Microsoft Store Kindle Previewer installations as well as
  existing desktop installation locations.
- Setup finds versioned WindowsApps packages and checks registered installation
  locations when Windows blocks folder browsing. The post-install check uses
  the same search, and users can also select a package folder manually.
- Store KindleGen compilers are copied into KCCAutomate's tools folder and
  validated there, because Windows may block running them directly inside
  WindowsApps. The installed Previewer files and permissions are left intact.

## Reader compatibility and stopping

- Successful conversions now clear their large temporary files immediately,
  including grouped books, regardless of the diagnostic-expiry preference.
  Logs and completion receipts remain; old completed files can be cleared from
  Settings in either view. Failed/stopped work and unverifiable output copies
  are retained. Optional retention applies to old logs and unsuccessful attempts.

- A visible **Stop** button halts the active converter tree, including a
  scheduled/background run on the same Working folder. Unconverted originals
  are retained, partial book output is not published, and stopped books can resume.
- An optional Scribe compatibility switch uses JPEG, no cropping and an
  1860 × 1920 limit for Scribe 2022/2024 MOBI/EPUB. It is off by default and
  can be switched off after a KCC or firmware fix; usual image choices are retained.

## Use your preferred KCC release

- Choose a working Windows x64 c2e CLI from KCC's releases page without waiting
  for a KCCAutomate update to approve a particular version.
- Setup still checks tool identity, startup and required conversion options.
  Scheduled conversions also check startup and retain unconverted originals
  if the tool fails.
- Old saved version-pin settings are ignored, so users do not need to recreate
  their setup or schedule.
- Update checks show the latest KCC release. Downloads remain user-managed
  through KCC's GitHub releases page; selected tools are not silently replaced.
- The app checks releases when it opens, including after installation or an app
  update, and checks JPEG XL when enabled. A visible notice shows selected/latest
  versions, download instructions and actions to choose the replacement KCC.
- Choosing a new KCC download starts setup at its converter page, validates and
  copies the tools, and retains folders, conversion options and schedule choices.
- Offline checks and unknown installed versions are reported without claiming
  the tools are current or interrupting conversions.

Download **KCCAutomate-Setup.exe** for installation or
**KCCAutomate-Windows.zip** for portable use from the
[releases page](https://github.com/squishysquidly/KCCAutomate/releases).
**SHA256SUMS** lists both downloads. Updating preserves settings and installation
mode. KCC and Amazon's KindleGen remain separately obtained tools.
