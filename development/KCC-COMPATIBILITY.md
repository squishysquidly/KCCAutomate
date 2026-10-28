# KCC compatibility policy

Users obtain the Windows x64 c2e CLI from
[KCC releases](https://github.com/ciromattia/kcc/releases). KCCAutomate accepts
working CLI versions without a version allowlist or a fixed upstream asset hash.
There is no recommendation to remain on a particular KCC release.

Setup checks the selected executable name, a successful `--help` startup,
`comic2ebook` identity and the required `--profile` / `--format` options. The
conversion worker also checks startup before touching queued originals. Actual
startup or conversion failures remain visible and preserve unconverted inputs.
Legacy `ApprovedKccVersion` fields in saved settings are ignored and are no
longer written by the app.

Update checks query the latest upstream release. Acquisition buttons open KCC's
releases page; users download and choose their own converter. The selected tool
is never silently upgraded. Managed copies are verified against their source,
and existing SHA-256 verification for app/JXL downloads remains in place.

Release checks run automatically after startup/setup and saved tool changes,
including after installing an app update. The notice shows selected/latest KCC
versions and instructions. Choose downloaded KCC opens a file picker and starts
setup at the converter page. The user finishes validation/import before settings
select the new managed copy. Failed checks do not claim a tool is up to date.

`Test-KccCompatibility.ps1` covers version-independent CLI validation, latest
release lookup, tool/architecture selection and manual-only acquisition.
`Test-ToolSetup.ps1` checks newer-version conversion, legacy settings and real
startup-failure handling using generated fixtures. Optional native tests use a
user-provided CLI and can check its upstream SHA-256 before running.

The platform inventory contains dated upstream evidence for future OS work.
Those recorded release numbers are evidence snapshots, not runtime restrictions
or instructions to download an older version.
