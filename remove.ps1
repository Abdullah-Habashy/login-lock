# Login Lock - cancel/remove (run elevated by Remove-Lock.bat).
. (Join-Path $PSScriptRoot 'schedule.ps1')

# Tell the friend it is being removed, BEFORE deleting (while the token is
# still there). A forced delete that skips this just shows up as a heartbeat
# gap on their side.
$cfg = Get-ActiveConfig
if ($cfg -and $cfg.notify -and $cfg.notify.chatId -and $cfg.notify.tokenEnc -and (Test-Path (Join-Path $PSScriptRoot 'notify.ps1'))) {
    . (Join-Path $PSScriptRoot 'notify.ps1')
    $null = Send-TelegramMessage -TokenEnc $cfg.notify.tokenEnc -ChatId ([string]$cfg.notify.chatId) `
        -Text ("Login Lock was REMOVED from {0} at {1}." -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm'))
}

Remove-LoginLock
Write-Host ''
Write-Host 'Login Lock has been removed. The lock is off.' -ForegroundColor Green
