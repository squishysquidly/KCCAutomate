$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot ('test-results\release-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$fixtureSource = Join-Path $root 'Fixture.cs'
$fixtureExe = Join-Path $root 'Fixture.exe'
Set-Content -LiteralPath $fixtureSource -Encoding utf8 -Value '[assembly: System.Reflection.AssemblyVersion("0.1.19.0")] class Fixture { static void Main() {} }'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:exe ("/out:" + $fixtureExe) $fixtureSource
if ($LASTEXITCODE) { throw 'Release-version fixture compilation failed.' }
$savedSummary = $env:GITHUB_STEP_SUMMARY
$env:GITHUB_STEP_SUMMARY = Join-Path $root 'summary.md'
$global:ReleasePreparationTestState = @{}

# Only these mock commands can be reached by the preparation script during tests.
function git {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'rev-parse') { return $global:ReleasePreparationTestState.head }
    if ($args[0] -eq 'ls-remote') {
        $global:LASTEXITCODE = $global:ReleasePreparationTestState.tagExit
        return $global:ReleasePreparationTestState.tags
    }
    throw 'Unexpected Git operation in release test.'
}
function gh {
    $call = @($args)
    $global:ReleasePreparationTestState.calls += ,$call
    $global:LASTEXITCODE = 0
    if ($call[0] -eq 'api') {
        $global:LASTEXITCODE = $global:ReleasePreparationTestState.apiExit
        return $global:ReleasePreparationTestState.releases
    }
    if ($call[0] -eq 'release' -and $call[1] -eq 'create') {
        $global:LASTEXITCODE = $global:ReleasePreparationTestState.createExit
        return
    }
    throw 'Unexpected GitHub operation in release test.'
}
function Reset-Case([string]$Name) {
    $global:ReleasePreparationTestState.dist = Join-Path $root $Name
    New-Item -ItemType Directory -Path (Join-Path $global:ReleasePreparationTestState.dist 'KCCAutomate') -Force | Out-Null
    Copy-Item -LiteralPath $fixtureExe -Destination (Join-Path $global:ReleasePreparationTestState.dist 'KCCAutomate\KCCAutomate.exe')
    foreach ($name in @('KCCAutomate-Setup.exe','KCCAutomate-Windows.zip')) {
        Set-Content -LiteralPath (Join-Path $global:ReleasePreparationTestState.dist $name) -Value ('fixture ' + $name)
    }
    $manifest = @(foreach ($name in @('KCCAutomate-Setup.exe','KCCAutomate-Windows.zip')) {
        (Get-FileHash -LiteralPath (Join-Path $global:ReleasePreparationTestState.dist $name) -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $name
    })
    Set-Content -LiteralPath (Join-Path $global:ReleasePreparationTestState.dist 'SHA256SUMS') -Value $manifest
    $global:ReleasePreparationTestState.head = '1' * 40
    $global:ReleasePreparationTestState.commit = $global:ReleasePreparationTestState.head
    $global:ReleasePreparationTestState.releases = @()
    $global:ReleasePreparationTestState.tags = @()
    $global:ReleasePreparationTestState.calls = @()
    $global:ReleasePreparationTestState.apiExit = 0
    $global:ReleasePreparationTestState.tagExit = 0
    $global:ReleasePreparationTestState.createExit = 0
}
function Invoke-Check([string]$Failure, [string]$RequestedVersion = '0.1.19') {
    $caught = $null
    try {
        & (Join-Path $PSScriptRoot 'Prepare-Release.ps1') -Version $RequestedVersion -Repository 'example/KCCAutomate' -Commit $global:ReleasePreparationTestState.commit -DistributionPath $global:ReleasePreparationTestState.dist | Out-Null
    } catch { $caught = $_.Exception.Message }
    if ($Failure) {
        if (!$caught -or $caught -notmatch $Failure) { throw "Expected '$Failure'; got '$caught'." }
        if (@($global:ReleasePreparationTestState.calls | Where-Object { $_[0] -ne 'api' }).Count) { throw 'Rejected preparation attempted a GitHub mutation.' }
    } elseif ($caught) { throw $caught }
}

try {
    Reset-Case 'new'
    Invoke-Check -RequestedVersion 'v0.1.19'
    $create = @($global:ReleasePreparationTestState.calls | Where-Object { $_[0] -eq 'release' })
    if ($create.Count -ne 1) { throw 'Expected one new draft creation.' }
    $arguments = @($create[0])
    if ($arguments[1] -ne 'create' -or $arguments[2] -ne 'v0.1.19' -or '--draft' -notin $arguments -or '--clobber' -in $arguments) { throw 'Release was not created strictly as a new draft.' }
    if ($arguments[[Array]::IndexOf($arguments,'--target') + 1] -ne $global:ReleasePreparationTestState.commit) { throw 'Draft did not target the checked-out commit.' }
    foreach ($name in @('KCCAutomate-Setup.exe','KCCAutomate-Windows.zip','SHA256SUMS')) {
        if ((Join-Path $global:ReleasePreparationTestState.dist $name) -notin $arguments) { throw "Missing draft download: $name" }
    }
    if ((Get-Content -LiteralPath (Join-Path $global:ReleasePreparationTestState.dist 'release-notes.md') -Raw) -notmatch [regex]::Escape('/blob/' + $global:ReleasePreparationTestState.commit + '/README.md')) { throw 'Guide does not link to the released source.' }
    'PASS: a new version creates only a draft with all downloads, an exact source commit and review instructions.'

    Reset-Case 'existing-release'; $global:ReleasePreparationTestState.releases = @('v0.1.18','v0.1.19')
    Invoke-Check 'Release v0.1.19 already exists'
    Reset-Case 'existing-tag'; $global:ReleasePreparationTestState.tags = @((('2' * 40) + "`trefs/tags/v0.1.19"))
    Invoke-Check 'Tag v0.1.19 already exists'
    'PASS: existing releases (including drafts) and tags are never replaced or moved.'

    Reset-Case 'wrong-version'; Invoke-Check 'does not match the built app' '0.1.20'
    Reset-Case 'bad-version'; Invoke-Check 'three-part release version' '0.1.19; unexpected-command'
    Reset-Case 'wrong-commit'; $global:ReleasePreparationTestState.commit = '2' * 40; Invoke-Check 'exact checked-out source commit'
    'PASS: mismatched versions, unsafe version input and mismatched source commits stop before any upload.'

    Reset-Case 'tampered'; Add-Content -LiteralPath (Join-Path $global:ReleasePreparationTestState.dist 'KCCAutomate-Setup.exe') -Value 'changed'
    Invoke-Check 'Checksum mismatch'
    Reset-Case 'missing-hash'; $manifest = Get-Content -LiteralPath (Join-Path $global:ReleasePreparationTestState.dist 'SHA256SUMS'); Set-Content -LiteralPath (Join-Path $global:ReleasePreparationTestState.dist 'SHA256SUMS') -Value $manifest[0]
    Invoke-Check 'Both distribution checksums'
    'PASS: altered downloads and incomplete checksums cannot become release assets.'

    Reset-Case 'api-failed'; $global:ReleasePreparationTestState.apiExit = 1; Invoke-Check 'Could not check existing GitHub releases'
    Reset-Case 'tags-failed'; $global:ReleasePreparationTestState.tagExit = 128; Invoke-Check 'Could not check remote tags'
    'PASS: failed remote checks stop preparation without GitHub mutations.'

    Reset-Case 'upload-failed'; $global:ReleasePreparationTestState.createExit = 1
    $caught = $null
    try { Invoke-Check } catch { $caught = $_.Exception.Message }
    if (!$caught -or $caught -notmatch 'partial draft may remain') { throw 'Partial-upload failure was not reported.' }
    if (@($global:ReleasePreparationTestState.calls | Where-Object { $_[0] -eq 'release' }).Count -ne 1) { throw 'Upload failure attempted another release mutation.' }
    'PASS: failed draft upload reports the incomplete draft and never publishes or deletes it.'
    $global:LASTEXITCODE = 0
} finally {
    $env:GITHUB_STEP_SUMMARY = $savedSummary
    Remove-Variable -Name ReleasePreparationTestState -Scope Global
}
