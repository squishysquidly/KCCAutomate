param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$Repository,
    [Parameter(Mandatory=$true)][string]$Commit,
    [string]$DistributionPath = (Join-Path $PSScriptRoot 'dist')
)
$ErrorActionPreference = 'Stop'

$Version = $Version.Trim()
if ($Version -notmatch '^v?((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))$') {
    throw 'Use a three-part release version such as 0.1.19 (an initial v is optional).'
}
$number = $Matches[1]
$tag = 'v' + $number
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $Commit -notmatch '^[a-fA-F0-9]{40}$') {
    throw 'A repository owner/name and full source commit SHA are required.'
}
$head = & git rev-parse HEAD
if ($LASTEXITCODE -or $head -ne $Commit) { throw 'The release must use the exact checked-out source commit.' }

$app = Join-Path $DistributionPath 'KCCAutomate\KCCAutomate.exe'
$assembly = [Reflection.AssemblyName]::GetAssemblyName($app).Version
$expected = '{0}.{1}.{2}' -f $assembly.Major, $assembly.Minor, $assembly.Build
if ($number -ne $expected -or $assembly.Revision -ne 0) {
    throw "Requested $tag does not match the built app ($assembly). Update the app version and rebuild first."
}
$assets = @('KCCAutomate-Setup.exe','KCCAutomate-Windows.zip','SHA256SUMS')
foreach ($name in $assets) {
    if ((Get-Item -LiteralPath (Join-Path $DistributionPath $name)).Length -eq 0) { throw "Empty release file: $name" }
}
$hashes = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $DistributionPath 'SHA256SUMS')) {
    if ($line -notmatch '^([a-fA-F0-9]{64})  (KCCAutomate-(?:Windows\.zip|Setup\.exe))$') { throw 'Unexpected checksum entry.' }
    $digest = $Matches[1]
    $name = $Matches[2]
    if ($hashes.ContainsKey($name)) { throw 'Duplicate checksum entry.' }
    if ((Get-FileHash -LiteralPath (Join-Path $DistributionPath $name) -Algorithm SHA256).Hash -ne $digest) {
        throw "Checksum mismatch: $name"
    }
    $hashes[$name] = $digest
}
if ($hashes.Count -ne 2) { throw 'Both distribution checksums are required.' }

# Read all releases, including drafts, before any GitHub mutation.
$existing = @(& gh api --paginate "repos/$Repository/releases?per_page=100" --jq '.[].tag_name')
if ($LASTEXITCODE) { throw 'Could not check existing GitHub releases. No release was prepared.' }
if ($tag -in $existing) { throw "Release $tag already exists. Existing releases are never replaced; use a new version." }
$remoteTags = @(& git ls-remote ("https://github.com/$Repository.git") ("refs/tags/$tag") ("refs/tags/$tag^{}"))
if ($LASTEXITCODE) { throw 'Could not check remote tags. No release was prepared.' }
if ($remoteTags.Count) { throw "Tag $tag already exists. Choose an unused release version; tags are never moved." }

$notes = @"
KCCAutomate $number for Windows.

Download **KCCAutomate-Setup.exe** to install, or extract **KCCAutomate-Windows.zip** for portable use.
KCC and the required conversion tools are obtained separately during guided setup.

[Installation, usage and settings](https://github.com/$Repository/blob/$Commit/README.md)
[Release overview](https://github.com/$Repository/blob/$Commit/development/RELEASE-NOTES.md)

Source commit: $Commit
"@
$notesPath = Join-Path $DistributionPath 'release-notes.md'
[IO.File]::WriteAllText($notesPath,$notes,[Text.UTF8Encoding]::new($false))
$assetPaths = @($assets | ForEach-Object { Join-Path $DistributionPath $_ })
& gh release create $tag @assetPaths --repo $Repository --target $Commit --draft --title "KCCAutomate $number" --notes-file $notesPath
if ($LASTEXITCODE) {
    throw 'Draft preparation failed. A partial draft may remain: inspect it and do not publish until all downloads are present.'
}
$message = "Draft $tag prepared with all three downloads. Review the draft under https://github.com/$Repository/releases before clicking Publish release."
Write-Output $message
if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value @"
## Draft ready: $tag

[$tag release drafts](https://github.com/$Repository/releases)

All tests passed and the installer, portable ZIP and checksums were attached.
Review the draft and its downloads, then click **Publish release** yourself.
No release was published automatically. Existing releases and tags were not changed.
"@
}
