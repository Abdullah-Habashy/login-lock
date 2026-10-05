<#
    Login Lock - simple terminal setup (English). Asks for the daily lock
    window and the date range, shows a summary, and (after you confirm)
    registers the SYSTEM task. Run elevated by LoginLock.bat. Nothing changes
    until you type Y to confirm.
#>
. (Join-Path $PSScriptRoot 'schedule.ps1')

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'This must run as administrator. Close this and open LoginLock.bat (it will ask for elevation).' -ForegroundColor Red
    return
}

function Set-BigConsoleFont {
    # Bigger, clearer font (Consolas) for this console window, set at runtime.
    if (-not ('LLFont' -as [type])) {
        Add-Type -Namespace '' -Name 'LLFont' -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetCurrentConsoleFontEx(IntPtr h, bool max, ref FONT f);
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public struct FONT {
  public uint cbSize; public uint nFont; public short sizeX; public short sizeY;
  public int family; public int weight;
  [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst=32)] public string face;
}
'@
    }
    try {
        $h = [LLFont]::GetStdHandle(-11)   # STD_OUTPUT_HANDLE
        $f = New-Object LLFont+FONT
        $f.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($f)
        $f.sizeX = 0; $f.sizeY = 30       # cell height in pixels (bigger = larger text)
        $f.family = 54; $f.weight = 400; $f.face = 'Consolas'
        [void][LLFont]::SetCurrentConsoleFontEx($h, $false, [ref]$f)
    } catch {}
    try {
        $raw = $Host.UI.RawUI
        $sz = $raw.WindowSize; $sz.Width = 78; $sz.Height = 30
        $buf = $raw.BufferSize; $buf.Width = 78; if ($buf.Height -lt 300) { $buf.Height = 300 }
        $raw.BufferSize = $buf; $raw.WindowSize = $sz
    } catch {}
}

function Read-TimeValue($label, $default) {
    while ($true) {
        $v = Read-Host "$label (24-hour, e.g. 22:00) [$default]"
        if ([string]::IsNullOrWhiteSpace($v)) { $v = $default }
        if ($v -match '^([01]?\d|2[0-3]):([0-5]\d)$') {
            $p = $v.Split(':'); return ('{0:00}:{1:00}' -f [int]$p[0], [int]$p[1])
        }
        Write-Host '  Invalid. Use HH:MM (e.g. 08:00 or 22:30).' -ForegroundColor Yellow
    }
}

function Read-DateValue($label, [datetime]$default, [datetime]$notBefore) {
    while ($true) {
        $v = Read-Host "$label (YYYY-MM-DD) [$($default.ToString('yyyy-MM-dd'))]"
        if ([string]::IsNullOrWhiteSpace($v)) { return $default.Date }
        try {
            $d = [datetime]::ParseExact($v, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date
            if ($notBefore -and $d -lt $notBefore.Date) {
                Write-Host "  Cannot be before $($notBefore.ToString('yyyy-MM-dd'))." -ForegroundColor Yellow
                continue
            }
            return $d
        } catch {
            Write-Host '  Invalid. Use YYYY-MM-DD (e.g. 2026-10-05).' -ForegroundColor Yellow
        }
    }
}

function To12Text($hhmm) {
    $p = $hhmm.Split(':'); $h = [int]$p[0]
    $ap = if ($h -ge 12) { 'PM' } else { 'AM' }; $h12 = $h % 12; if ($h12 -eq 0) { $h12 = 12 }
    return '{0}:{1} {2}' -f $h12, $p[1], $ap
}

Set-BigConsoleFont
Clear-Host
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host '                 Login Lock' -ForegroundColor Cyan
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Logs off all users during the window you set, every day, between a'
Write-Host 'start and end date. Nothing changes until you confirm with Y.'
Write-Host ''

$existing = Get-ActiveConfig
if ($existing) {
    Write-Host "A schedule is already active ($($existing.startTime)-$($existing.endTime), $($existing.startDate) to $($existing.endDate)) and will be replaced." -ForegroundColor Yellow
    Write-Host ''
}

while ($true) {
    $startTime = Read-TimeValue 'Lock start time' '22:00'
    $endTime = Read-TimeValue 'Lock end time' '08:00'
    $startDate = Read-DateValue 'Start date' (Get-Date) (Get-Date)
    $endDate = Read-DateValue 'End date' (Get-Date).Date.AddMonths(1) $startDate

    $firstStart = [datetime]::ParseExact("$($startDate.ToString('yyyy-MM-dd')) $startTime", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    $lastEnd = [datetime]::ParseExact("$($endDate.ToString('yyyy-MM-dd')) $endTime", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)

    $problem = ''
    if ($startTime -eq $endTime) { $problem = 'Start time must differ from end time.' }
    elseif ($lastEnd -le $firstStart) { $problem = 'The end must be after the start.' }
    elseif ($lastEnd -le (Get-Date)) { $problem = 'The end is already in the past.' }

    Write-Host ''
    Write-Host '-----------------------------------------------' -ForegroundColor DarkGray
    Write-Host "The computer will lock every day from $(To12Text $startTime) to $(To12Text $endTime)"
    Write-Host "From $($startDate.ToString('yyyy-MM-dd'))  to  $($endDate.ToString('yyyy-MM-dd'))"
    Write-Host '-----------------------------------------------' -ForegroundColor DarkGray

    if ($problem) {
        Write-Host "x $problem Try again." -ForegroundColor Red
        Write-Host ''
        continue
    }

    $ans = Read-Host 'Activate the lock with these times? (Y = yes / anything else = redo)'
    if ($ans -match '^(y|Y)$') {
        try {
            Install-LoginLock -Config @{ startTime = $startTime; endTime = $endTime; startDate = $startDate.ToString('yyyy-MM-dd'); endDate = $endDate.ToString('yyyy-MM-dd') } -SourceDir $PSScriptRoot
            Write-Host ''
            Write-Host 'OK - the lock is active.' -ForegroundColor Green
            Write-Host '  To cancel anytime: run Remove-Lock.bat as administrator.'
        } catch {
            Write-Host ''
            Write-Host "x Activation failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        break
    }
    Write-Host ''
}
