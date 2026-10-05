<#
    Login Lock - simple terminal setup. Asks for the lock window and the date
    range, shows a summary, and (after you confirm) registers the SYSTEM task.
    Run elevated by LoginLock.bat. Changes nothing until you type Y to confirm.
#>
$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
. (Join-Path $PSScriptRoot 'schedule.ps1')

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'لازم تشغّل البرنامج بصلاحية مسؤول. اقفل ده وافتح LoginLock.bat (هيطلب الصلاحية لوحده).' -ForegroundColor Red
    return
}

function Read-TimeValue($label, $default) {
    while ($true) {
        $v = Read-Host "$label (بنظام 24 ساعة، مثال 22:00) [$default]"
        if ([string]::IsNullOrWhiteSpace($v)) { $v = $default }
        if ($v -match '^([01]?\d|2[0-3]):([0-5]\d)$') {
            $p = $v.Split(':'); return ('{0:00}:{1:00}' -f [int]$p[0], [int]$p[1])
        }
        Write-Host "  صيغة غلط. اكتب الوقت بالشكل HH:MM (مثال 08:00 أو 22:30)." -ForegroundColor Yellow
    }
}

function Read-DateValue($label, [datetime]$default, [datetime]$notBefore) {
    while ($true) {
        $v = Read-Host "$label (بالشكل YYYY-MM-DD) [$($default.ToString('yyyy-MM-dd'))]"
        if ([string]::IsNullOrWhiteSpace($v)) { return $default.Date }
        try {
            $d = [datetime]::ParseExact($v, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date
            if ($notBefore -and $d -lt $notBefore.Date) {
                Write-Host "  التاريخ ماينفعش يكون قبل $($notBefore.ToString('yyyy-MM-dd'))." -ForegroundColor Yellow
                continue
            }
            return $d
        } catch {
            Write-Host "  صيغة غلط. اكتب التاريخ بالشكل YYYY-MM-DD (مثال 2026-10-05)." -ForegroundColor Yellow
        }
    }
}

function To12Text($hhmm) {
    $p = $hhmm.Split(':'); $h = [int]$p[0]
    $ap = if ($h -ge 12) { 'م' } else { 'ص' }; $h12 = $h % 12; if ($h12 -eq 0) { $h12 = 12 }
    return '{0}:{1} {2}' -f $h12, $p[1], $ap
}

Clear-Host
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host '            قفل الدخول (Login Lock)' -ForegroundColor Cyan
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'بيعمل تسجيل خروج تلقائي للمستخدمين في الفترة اللي تحددها كل يوم،'
Write-Host 'من تاريخ لتاريخ. مابيتغيّرش أي حاجة غير لما تأكد بـ Y في الآخر.'
Write-Host ''

$existing = Get-ActiveConfig
if ($existing) {
    Write-Host "⚠ فيه جدول شغّال دلوقتي ($($existing.startTime)–$($existing.endTime)، من $($existing.startDate) لـ $($existing.endDate)) وهيتستبدل." -ForegroundColor Yellow
    Write-Host ''
}

while ($true) {
    $startTime = Read-TimeValue 'وقت بداية القفل' '22:00'
    $endTime = Read-TimeValue 'وقت نهاية القفل' '08:00'
    $startDate = Read-DateValue 'تاريخ البداية' (Get-Date) (Get-Date)
    $endDate = Read-DateValue 'تاريخ النهاية' (Get-Date).Date.AddMonths(1) $startDate

    $firstStart = [datetime]::ParseExact("$($startDate.ToString('yyyy-MM-dd')) $startTime", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    $lastEnd = [datetime]::ParseExact("$($endDate.ToString('yyyy-MM-dd')) $endTime", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)

    $problem = ''
    if ($startTime -eq $endTime) { $problem = 'وقت البداية لازم يكون غير وقت النهاية.' }
    elseif ($lastEnd -le $firstStart) { $problem = 'ميعاد النهاية لازم يكون بعد ميعاد البداية.' }
    elseif ($lastEnd -le (Get-Date)) { $problem = 'ميعاد النهاية عدّى خلاص.' }

    Write-Host ''
    Write-Host '-----------------------------------------------' -ForegroundColor DarkGray
    Write-Host "الجهاز هيتقفل كل يوم من $(To12Text $startTime) لـ $(To12Text $endTime)"
    Write-Host "من $($startDate.ToString('yyyy-MM-dd'))  إلى  $($endDate.ToString('yyyy-MM-dd'))"
    Write-Host '-----------------------------------------------' -ForegroundColor DarkGray

    if ($problem) {
        Write-Host "✗ $problem حاول تاني." -ForegroundColor Red
        Write-Host ''
        continue
    }

    $ans = Read-Host 'تفعيل القفل بالمواعيد دي؟ (Y = نعم / أي حاجة تانية = إعادة)'
    if ($ans -match '^(y|Y|نعم)$') {
        try {
            Install-LoginLock -Config @{ startTime = $startTime; endTime = $endTime; startDate = $startDate.ToString('yyyy-MM-dd'); endDate = $endDate.ToString('yyyy-MM-dd') } -SourceDir $PSScriptRoot
            Write-Host ''
            Write-Host '✓ تم تفعيل القفل.' -ForegroundColor Green
            Write-Host '  للإلغاء في أي وقت: شغّل Remove-Lock.bat بصلاحية مسؤول.'
        } catch {
            Write-Host ''
            Write-Host "✗ حصل خطأ أثناء التفعيل: $($_.Exception.Message)" -ForegroundColor Red
        }
        break
    }
    Write-Host ''
}
