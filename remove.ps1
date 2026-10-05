# Login Lock - cancel/remove (run elevated by Remove-Lock.bat).
. (Join-Path $PSScriptRoot 'schedule.ps1')
Remove-LoginLock
Add-Type -AssemblyName System.Windows.Forms
[void][System.Windows.Forms.MessageBox]::Show('تم إلغاء قفل الدخول.', 'قفل الدخول', 'OK', 'Information')
