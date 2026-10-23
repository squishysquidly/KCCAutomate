param([string]$ConfigPath,[switch]$Failed)
$ErrorActionPreference = 'Stop'
try {
    $settings=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($settings.NotificationMode -eq 'Off' -or ($settings.NotificationMode -eq 'Errors only' -and -not $Failed)) { return }
    $now=(Get-Date).TimeOfDay
    $start=[TimeSpan]::Parse($settings.QuietHoursStart); $end=[TimeSpan]::Parse($settings.QuietHoursEnd)
    if ($settings.QuietHoursEnabled -and (($start -lt $end -and $now -ge $start -and $now -lt $end) -or ($start -gt $end -and ($now -ge $start -or $now -lt $end)))) { return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $icon=New-Object Windows.Forms.NotifyIcon
    try {
        $icon.Icon=[Drawing.SystemIcons]::Information; $icon.Visible=$true
        $message=if ($Failed) { 'Some books need attention. Open MangaFlow and refresh the queue for details.' } else { 'The conversion check finished. Open MangaFlow to see the results.' }
        $icon.ShowBalloonTip(4000,'MangaFlow',$message,[Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Seconds 4
    } finally { $icon.Dispose() }
} catch { Write-Host "Desktop notification unavailable: $_" }
