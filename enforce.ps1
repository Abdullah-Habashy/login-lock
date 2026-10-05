<#
    Login Lock - the enforcer.

    Registered as a SYSTEM scheduled task (LoginLock) that runs every minute,
    at startup, and at every logon. It reads the schedule and, during the
    locked window, logs off every interactive session. When the schedule's end
    date passes it removes the task and the install folder (self-cleanup).

    Testing (changes nothing):
        powershell -File enforce.ps1 -DryRun
        powershell -File enforce.ps1 -DryRun -Now '2026-10-08 07:59'
        powershell -File enforce.ps1 -DryRun -ConfigPath .\config.json -Now '2026-10-06 03:00'
#>
param(
    [switch] $DryRun,
    [datetime] $Now = (Get-Date),
    [string] $ConfigPath = "$env:ProgramData\LoginLock\config.json",
    [string] $TaskName = 'LoginLock'
)

function Get-MinutesOfDay([string] $hhmm) {
    $p = $hhmm.Split(':')
    return [int]$p[0] * 60 + [int]$p[1]
}

# NONE (no/invalid config) | FREE | WARN (block starts within 5 min) |
# BLOCKED | EXPIRED (past the end - time to self-remove).
function Get-Decision($cfg, [datetime] $now) {
    if (-not $cfg) { return [pscustomobject]@{ decision = 'NONE'; nextBlockStart = $null } }
    try {
        $firstStart = [datetime]::ParseExact("$($cfg.startDate) $($cfg.startTime)", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        $lastEnd = [datetime]::ParseExact("$($cfg.endDate) $($cfg.endTime)", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        $startMin = Get-MinutesOfDay $cfg.startTime
        $endMin = Get-MinutesOfDay $cfg.endTime
    } catch {
        return [pscustomobject]@{ decision = 'NONE'; nextBlockStart = $null }
    }

    if ($now -ge $lastEnd) { return [pscustomobject]@{ decision = 'EXPIRED'; nextBlockStart = $null } }

    # Is the time-of-day inside the daily window?
    $nowMin = $now.Hour * 60 + $now.Minute
    if ($startMin -eq $endMin) {
        $inWindow = $false
    } elseif ($startMin -lt $endMin) {
        $inWindow = ($nowMin -ge $startMin -and $nowMin -lt $endMin)
    } else {
        # crosses midnight
        $inWindow = ($nowMin -ge $startMin -or $nowMin -lt $endMin)
    }

    $blocked = ($now -ge $firstStart) -and ($now -lt $lastEnd) -and $inWindow
    if ($blocked) { return [pscustomobject]@{ decision = 'BLOCKED'; nextBlockStart = $null } }

    # Next time the daily window starts (today at startMin, else tomorrow),
    # but never before firstStart and never at/after lastEnd.
    $todayStart = $now.Date.AddMinutes($startMin)
    $nextStart = if ($todayStart -gt $now) { $todayStart } else { $todayStart.AddDays(1) }
    if ($nextStart -lt $firstStart) { $nextStart = $firstStart }
    if ($nextStart -ge $lastEnd) { return [pscustomobject]@{ decision = 'FREE'; nextBlockStart = $null } }

    $mins = ($nextStart - $now).TotalMinutes
    if ($mins -gt 0 -and $mins -le 5) { return [pscustomobject]@{ decision = 'WARN'; nextBlockStart = $nextStart } }
    return [pscustomobject]@{ decision = 'FREE'; nextBlockStart = $nextStart }
}

function Get-InteractiveSessionIds {
    # explorer.exe runs once per interactive desktop; its SessionId is the one
    # to log off. SYSTEM's own session 0 has no explorer, so it is never hit.
    Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty SessionId -Unique |
        Where-Object { $_ -ne 0 }
}

# --- load config ------------------------------------------------------------
$cfg = $null
try { if (Test-Path $ConfigPath) { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json } } catch { $cfg = $null }

$result = Get-Decision $cfg $Now
$decision = $result.decision

if ($DryRun) {
    "{0}" -f $decision
    if ($result.nextBlockStart) { "nextBlockStart: {0:yyyy-MM-dd HH:mm}" -f $result.nextBlockStart }
    return
}

$logDir = Split-Path $ConfigPath -Parent
$logFile = Join-Path $logDir 'loginlock.log'
function Write-Log($msg) {
    try { "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg | Add-Content -Path $logFile -Encoding UTF8 } catch {}
}

# --- Telegram heartbeat ------------------------------------------------------
# Tells the accountability friend the program is still here. A gap in these
# (or the "removed" message) means it was deleted / the machine is off.
$notifyFile = Join-Path $PSScriptRoot 'notify.ps1'
$machine = $env:COMPUTERNAME
function Send-Heartbeat($text) {
    if (-not ($cfg.notify -and $cfg.notify.chatId -and $cfg.notify.tokenEnc)) { return }
    if (-not (Test-Path $notifyFile)) { return }
    . $notifyFile
    $r = Send-TelegramMessage -TokenEnc $cfg.notify.tokenEnc -ChatId ([string]$cfg.notify.chatId) -Text $text
    Write-Log ("telegram: " + $(if ($r.ok) { 'sent' } else { "failed - $($r.error)" }))
}

if ($cfg -and $cfg.notify -and $cfg.notify.chatId -and $cfg.notify.tokenEnc -and $decision -ne 'EXPIRED') {
    $hours = if ($cfg.notify.heartbeatHours) { [double]$cfg.notify.heartbeatHours } else { 3 }
    $hbFile = Join-Path $logDir 'heartbeat.txt'
    $last = $null
    try { if (Test-Path $hbFile) { $last = [datetime]::Parse((Get-Content $hbFile -Raw).Trim()) } } catch {}
    if (-not $last -or ($Now - $last).TotalHours -ge $hours) {
        $state = switch ($decision) { 'BLOCKED' { 'locked now' } 'WARN' { 'locking in 5 min' } default { 'active, not locking now' } }
        Send-Heartbeat ("Login Lock is still on $machine. Status: $state. Schedule: $($cfg.startTime)-$($cfg.endTime), until $($cfg.endDate).")
        try { (Get-Date $Now -Format 'o') | Set-Content -Path $hbFile -Encoding ascii } catch {}
    }
}

switch ($decision) {
    'EXPIRED' {
        Write-Log 'schedule expired - removing task and folder'
        Send-Heartbeat "Login Lock schedule ended on $machine and removed itself (normal end, not deleted)."
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        # Remove the folder last; keep the log by copying nothing - it goes too.
        try { Remove-Item $logDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    'BLOCKED' {
        $ids = @(Get-InteractiveSessionIds)
        foreach ($id in $ids) {
            Write-Log "locked window - logging off session $id"
            & logoff.exe $id 2>$null
        }
    }
    'WARN' {
        $flag = Join-Path $logDir 'warned.flag'
        $key = '{0:yyyy-MM-dd HH:mm}' -f $result.nextBlockStart
        $already = (Test-Path $flag) -and ((Get-Content $flag -Raw -ErrorAction SilentlyContinue).Trim() -eq $key)
        if (-not $already) {
            Set-Content -Path $flag -Value $key -Encoding ascii -ErrorAction SilentlyContinue
            & msg.exe * /TIME:280 "Login Lock: this computer will lock in 5 minutes. Save your work and sign out." 2>$null
            Write-Log "warned: block starts $key"
        }
    }
    default { }
}
