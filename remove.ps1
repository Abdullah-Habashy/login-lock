# Login Lock - cancel/remove (run elevated by Remove-Lock.bat).
. (Join-Path $PSScriptRoot 'schedule.ps1')
Remove-LoginLock
Write-Host ''
Write-Host 'Login Lock has been removed. The lock is off.' -ForegroundColor Green
