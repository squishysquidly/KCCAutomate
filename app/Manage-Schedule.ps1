param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [ValidateSet('Enable','Disable','Status')][string]$Action = 'Status'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$taskName = 'MangaFlow-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($Action -eq 'Disable') {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) { Disable-ScheduledTask -TaskName $taskName | Out-Null }
    Write-Output 'Automatic checks are disabled. A conversion already in progress is allowed to finish.'
    return
}
if ($Action -eq 'Status') {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) { Write-Output 'No MangaFlow schedule is installed for this Windows account.'; return }
    $info = Get-ScheduledTaskInfo -TaskName $taskName
    Write-Output "Schedule: $($task.State). Next check: $($info.NextRunTime). Last result: $($info.LastTaskResult)."
    return
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$runner = Join-Path $PSScriptRoot 'Convert-Manga.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw 'Conversion script missing. Keep the portable app folder together.' }
$triggers = @()
foreach ($value in $config.ScheduleTimes.Split(',')) {
    $time = [DateTime]::ParseExact($value.Trim(), 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    $triggers += New-ScheduledTaskTrigger -Daily -At ([DateTime]::Today.Add($time.TimeOfDay))
}
if (-not $triggers.Count) { throw 'Choose at least one daily check time.' }
# Paths are fixed arguments to PowerShell, never an interpolated command body.
if ($ConfigPath.Contains('"') -or $runner.Contains('"')) { throw 'Invalid path.' }
$taskAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$runner`" -ConfigPath `"$ConfigPath`"" `
    -WorkingDirectory $PSScriptRoot
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Days 2) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -WakeToRun:([bool]$config.WakeComputer)
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $triggers -Principal $principal -Settings $settings `
    -Description 'MangaFlow: convert selected comic formats, verify outputs, then archive originals.' -Force | Out-Null
Write-Output "Automatic checks enabled at $($config.ScheduleTimes), while your Windows account is signed in. You may close MangaFlow."
