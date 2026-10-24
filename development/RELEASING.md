# Publishing KCCAutomate

Current version: **0.1.18**. Default repository: **squishysquidly/KCCAutomate**.
The app reads published GitHub Releases, rather than source commits.

## Build and validate

1. From the repository root, run `development\Build-Installer.ps1`. It builds
   the app and produces both distribution types in `development\dist`.
2. Run all `development\Test-*.ps1` suites and the desktop `--self-test`
   described in the [development guide](README.md). Test real books on a reader
   and a normal install/uninstall on a test account before publishing.
3. Review `development\dist\KCCAutomate-Setup.exe`,
   `KCCAutomate-Windows.zip` and `SHA256SUMS`. Packages must contain the app,
   its runtime scripts, the user README and licence, without personal settings,
   books, third-party converters, test fixtures or build sources.
4. Verify the compiled assembly/file version, manifest, app label and
   `ReleaseClient.AppVersion` all say **0.1.18** (four-part fields: **0.1.18.0**).
   Future releases must update those fields together.

## Prepare and publish an immutable release

Each public build uses a new version: for example, 0.1.19 after 0.1.18.
Update the app version fields above and current-version documentation, then
commit and push the reviewed source. Existing releases and tags stay intact.
Local builds do not push, tag, upload or publish anything.

On GitHub, open **Actions > Prepare KCCAutomate release > Run workflow**.
Select the branch containing the reviewed source and enter its new app version,
with or without the leading v. The workflow checks out the commit selected for
that run, builds from development/, runs all checks and saves build artifacts.
It then creates a **draft release**, targeting that exact commit, containing:

- `KCCAutomate-Setup.exe`
- `KCCAutomate-Windows.zip`
- `SHA256SUMS`

The version must match the compiled app. Preparation checks both distribution
hashes, refuses an existing release (including a draft), and refuses a tag that
already exists. It never moves tags, replaces downloads or publishes a release.
Concurrent preparation runs are serialized. The workflow uses GitHub's built-in
token with contents:write; a personal access token is not needed.

After a successful run, follow the draft link in the run summary or open
**Releases**. Review the notes and all three attached downloads. Test them,
then select **Publish release** and mark a normal public release as Latest.
Publication does not start another build. The workflow stays under
.github/workflows because GitHub requires that path; generated directories
remain ignored by Git.

Enable **Settings > General > Releases > Enable release immutability** before
publishing the next release. GitHub then locks its assets and tag at publication.
This setting applies to future releases; it does not make an already published
release immutable retroactively. Titles and notes remain editable. See
[GitHub's immutable release guide](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
and [repository setting](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes).

If preparation fails after creating a draft, that draft may have incomplete
downloads. Do not publish it. Inspect it and, only if it is still unpublished,
remove the unfinished draft before retrying the same source/version. An existing
tag also blocks retries; do not delete a published release or move its tag to
work around the check. Publish a new app version for corrections instead.

If preparing a release manually instead, create it as a draft and attach the
three files from development/dist before publishing. Keep the portable ZIP's
`KCCAutomate/` top-level folder. Verify that
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

The app continues to discover public updates through GitHub's latest release;
unpublished drafts are not offered to users. Keep published downloads intact
and choose a new version for every later public build.

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
