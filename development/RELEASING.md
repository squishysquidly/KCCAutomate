# Publishing KCCAutomate

Current version: **0.1.18**. Default repository: **squishysquidly/KCCAutomate**.
The app reads published GitHub Releases, rather than source commits.

## Build and validate

1. From the repository root, run `development\Build-Installer.ps1`. It builds
   the app and produces both distribution types in `development\dist`.
2. Run all seven `development\Test-*.ps1` suites and the desktop `--self-test`
   described in the [development guide](README.md). Test real books on a reader
   and a normal install/uninstall on a test account before publishing.
3. Review `development\dist\KCCAutomate-Setup.exe`,
   `KCCAutomate-Windows.zip` and `SHA256SUMS`. Packages must contain the app,
   its runtime scripts, the user README and licence, without personal settings,
   books, third-party converters, test fixtures or build sources.
4. Verify the compiled assembly/file version, manifest, app label and
   `ReleaseClient.AppVersion` all say **0.1.18** (four-part fields: **0.1.18.0**).
   Future releases must update those fields together.

## Publish

Commit and push the reviewed source, then publish a GitHub Release tagged
**v0.1.18** on that commit. Publishing is a separate maintainer action; local
builds do not push, tag or upload anything.

The `.github/workflows/release.yml` workflow builds from development/, runs
the checks, verifies the tag against the assembly version and attaches:

- `KCCAutomate-Setup.exe`
- `KCCAutomate-Windows.zip`
- `SHA256SUMS`

A manual workflow run saves build artifacts without publishing a release.
The workflow stays under .github/workflows because GitHub requires that path.
All generated build and test directories are ignored by Git.

If uploading manually, attach the three files from development/dist to the
release. Keep the portable ZIP's `KCCAutomate/` top-level folder. Verify that
GitHub supplies the asset's SHA-256 digest, which the updater requires.
The current builds are unsigned; hashes verify file integrity, not publisher
identity. Do not describe them as signed.

## Check installation and updates

Check the installer, Start menu shortcut, optional desktop shortcut, Windows
Installed apps entry, first-run setup and uninstaller on a disposable account.
Automated installer tests deliberately simulate registry/shortcut integration.
Inspect a real converted book and a scheduled run using the intended account
and local/network folders. Confirm that originals are retained on failure.

Test update and rollback with disposable installations and verify preserved
settings, books and storage mode. All eleven runtime files, including license.txt, must
be represented by the updater's verified manifest. Fresh portable packages have
twelve files including portable.flag; installed-mode updates preserve the mode.

Publish **v0.1.18** as the initial release and mark it as Latest. The user guide
describes the current app; a development-build history is not published.

## Approve a later KCC version

Users download KCC themselves from its upstream releases page. The app keeps
KCC release-metadata checks and its converter version policy pinned to 12.0.0.

1. Download the proposed official c2e CLI yourself, verify its upstream hash,
   test startup and representative CBZ/JXL/PDF inputs, then inspect real output
   on supported readers. Check splitting, cropping, names and failure handling.
2. Update the ApprovedKcc constants in `app/Services.cs`, setup guidance and
   compatibility fixtures together. Asset URL/hash constants are metadata;
   acquisition buttons must continue to open KCC's releases page.
3. Run the full checks and ship a new KCCAutomate release carrying the approval.
   A new upstream KCC release alone must not silently change users' converter.

The approved standalone Windows CLI bundles Python and its libraries. Source
or Python-installed KCC has separate dependencies; direct users to KCC's own
instructions for those installations.
