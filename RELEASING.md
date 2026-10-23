# Publishing a MangaFlow release

The default updater repository is `squishysquidly/KCCAutomate`. The updater
reads public stable GitHub Releases, not the repository's current source files.
The current app version is **0.2.0**.

1. Put the project sources into the repository, including `app/`, the root
   PowerShell scripts, `README.md` and `.github/workflows/release.yml`.
   Exclude `dist/`, `test-results/` and the generated test fixtures; `.gitignore`
   already covers those paths. Don't upload personal settings or manga files.
2. Run `Build-App.ps1`, `Test-Workflow.ps1`, `Test-JxlPreprocessing.ps1` and
   `Test-Upgrades.ps1` on Windows. Run the desktop `--self-test` described in the
   README. Test at least one real conversion on your own installation too.
3. Optionally run the **Build and package MangaFlow** workflow manually to check
   the hosted Windows build. A manual run does not publish a release.
4. Create and publish a GitHub release with tag **v0.2.0** on the commit containing
   these sources. The workflow checks that the tag matches the compiled version,
   runs the tests and attaches `MangaFlow-Windows.zip` plus `SHA256SUMS`.
5. Wait for the workflow to finish and confirm both assets appear on the release.
   Then test **Check GitHub for updates** from an older local app version, or
   check the current release and download/reinstall the same version as a test.
   Keep the previous version and settings backup until you verify conversion.

If using manual uploads, run `Package-App.ps1` and attach the two files from
`dist/` to a GitHub release. The ZIP must keep the `MangaFlow/` top-level folder.
GitHub must expose the asset's SHA-256 digest; the updater blocks assets without
one. SHA-256 protects download integrity. Signing the executable/package with a
publisher certificate is a separate future step.

For a later release, update the assembly/file versions and
`ReleaseClient.AppVersion` in `app/Services.cs`, the manifest version in
`app/app.manifest`, and release notes, then publish a matching tag. The updater
only installs the known portable package files; if a later version adds runtime
files, update both `RequiredFiles` and the installer's file list as part of that
release design.

Nothing in the local build or package scripts pushes source, creates tags or
publishes a release. The included GitHub workflow performs uploads only after
someone explicitly publishes a release on GitHub.
