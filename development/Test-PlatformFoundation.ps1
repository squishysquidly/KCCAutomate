param([string]$PythonExe='python')
$ErrorActionPreference='Stop'
# Python is a developer/CI prerequisite here, not a new requirement for the
# installed Windows app. This suite performs no conversions or GitHub writes.
& $PythonExe -B (Join-Path $PSScriptRoot 'test_platform_foundation.py')
if ($LASTEXITCODE) { throw 'Platform foundation checks failed.' }
