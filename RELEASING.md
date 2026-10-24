# Publishing a KCCAutomate release

The default updater repository is `squishysquidly/KCCAutomate`. The updater
reads public stable GitHub Releases, not the repository's current source files.
The current app version is **0.7.0**.

This release separates the four tools into individual pages, checks only the
active tool and required archive support, imports tools before the optional
sample test, and ends with the folder explanation. The desktop self-test walks
the dependency order, checks required-page gating and stale-result handling,
tests failed final folder preparation without schedule registration, and renders
all eight pages plus the four tool pages in dark mode at minimum size. Review
the app's Create & check folders action using disposable local/UNC paths too.

KCC support is pinned to **12.0.0**. The updater uses that release's tag and
exact Windows x64 CLI filename and SHA-256, not KCC's newest release.
`Test-KccCompatibility.ps1` checks the policy offline. To verify the actual
approved download and a generated CBZ-to-EPUB conversion without Python on
PATH, run it with `-OfficialKccExe <downloaded-cli.exe>`. It does not install
Python or alter the system PATH.

Before approving a future KCC release:

1. Download the official c2e CLI and check its upstream SHA-256. Test startup,
   CBZ/JXL/PDF inputs used by the app, splitting, cropping, output naming and
   failure handling, then inspect real MOBI files on the supported Kindle.
2. Update the `ApprovedKcc*` constants in `app/Services.cs` (version, filename,
   digest, release page and exact download URL). Keep the setup/main-window
   instructions, fixtures and this guide in sync. GUI downloads must not be
   approved as CLI assets. Keep existing users on the previous approval until
   the new version has passed manual testing.
3. Run all checks, bump KCCAutomate's version and publish its matching GitHub
   Release. Installed apps receive the new approval through that app update.
   Merely pushing a commit does not publish a downloadable app update.

This build refines setup and imports conversion tools into managed storage.
It also creates default folders, detects and tests installed 7-Zip CLI support,
validates tool entries automatically and accepts the reported Amazon KindleGen
V2.0 banner/help behavior. The desktop self-test exercises those asynchronous
checks, including changing a path before its older check has completed.
Run `Test-ToolSetup.ps1` with official 7-Zip installed at its default location
to cover real .7z extraction, tool identification, companion-file retention,
unsafe archive rejection and conversion after source downloads are unavailable.

1. Put the project sources into the repository, including `app/`, the root
   PowerShell scripts, `installer/`, `README.md` and `.github/workflows/release.yml`.
   Exclude `dist/`, `test-results/` and the generated test fixtures; `.gitignore`
   already covers those paths. Don't upload personal settings or manga files.
2. Run `Build-App.ps1`, `Test-Workflow.ps1`, `Test-JxlPreprocessing.ps1` and
   `Test-Upgrades.ps1`, `Test-Duplicates.ps1`, `Test-ToolSetup.ps1` and
   `Test-KccCompatibility.ps1` on Windows. Run the desktop `--self-test` described in the
   README. Run `Build-Installer.ps1` and `Test-Installation.ps1`. On a test account,
   check a normal install, Start menu shortcut, optional desktop shortcut,
   Installed apps entry, setup completion, and uninstall. Automated fixture tests
   deliberately skip those Windows integration changes. Switch views with a
   saved preset and an unsaved edit, reopen the app to check the view preference,
   and confirm hidden options survive a save in Simple view. The desktop
   self-test covers these behaviors and renders both views at normal/minimum
   window sizes and in dark mode. Test at least one real conversion on your
   own installation too.
   Check all duplicate policies with disposable books, a selected one-run
   conflict retry, and an unavailable local or remote folder at startup.
3. Optionally run the **Build and package KCCAutomate** workflow manually to check
   the hosted Windows build. A manual run does not publish a release.
4. Create and publish a GitHub release with tag **v0.7.0** on the commit containing
   these sources. The workflow checks that the tag matches the compiled version,
   runs the tests and attaches `KCCAutomate-Setup.exe`, `KCCAutomate-Windows.zip` and
   `SHA256SUMS`.
5. Wait for the workflow to finish and confirm all three assets appear on the release.
   Then test **Check GitHub for updates** from an older local app version, or
   check the current release and download/reinstall the same version as a test.
   Keep the previous version and settings backup until you verify conversion.

If using manual uploads, run `Build-Installer.ps1` and attach the three files from
`dist/` to a GitHub release. The ZIP must keep the `KCCAutomate/` top-level folder.
GitHub must expose the asset's SHA-256 digest; the updater blocks assets without
one. SHA-256 protects download integrity. Signing the executable/package with a
publisher certificate is a separate future step.

For a later release, update the assembly/file versions and
`ReleaseClient.AppVersion` in `app/Services.cs`, the manifest version in
`app/app.manifest`, the version label in `app/MainWindow.xaml`, and release notes,
then publish a matching tag. The updater
only installs the known portable package files; if a later version adds runtime
files, update both `RequiredFiles` and the installer's file list as part of that
release design.

The setup wizard's XAML is embedded in the executable so older updaters can
install this release using the existing ten runtime files. `portable.flag` is
included in fresh ZIP distributions only. The installer excludes it; in-app
updates preserve the target's storage mode. Neither distribution includes
personal settings, manga, converter executables, test fixtures or build sources.
The view implementation is also compiled into the executable. No additional
runtime files are needed; `interface.json` is created only as a user preference.

Nothing in the local build or package scripts pushes source, creates tags or
publishes a release. The included GitHub workflow performs uploads only after
someone explicitly publishes a release on GitHub.
