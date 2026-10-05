<#
    Login Lock - install / remove the SYSTEM scheduled task.
    Dot-sourced by gui.ps1 (Activate) and Remove-Lock.bat (Cancel). Both need
    an elevated (admin) session; the task itself runs as SYSTEM.
#>

$script:InstallRoot = "$env:ProgramData\LoginLock"
$script:TaskName = 'LoginLock'

function Install-LoginLock {
    param([Parameter(Mandatory)] $Config, [string] $SourceDir = $PSScriptRoot)

    New-Item -ItemType Directory -Force -Path $script:InstallRoot | Out-Null

    # Lock the folder to SYSTEM + Administrators so a standard user cannot edit
    # the schedule or delete the enforcer behind the lock's back.
    & icacls $script:InstallRoot /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' /Q | Out-Null

    foreach ($f in 'enforce.ps1', 'schedule.ps1', 'notify.ps1', 'remove.ps1', 'Remove-Lock.bat', 'RECOVERY.txt') {
        $src = Join-Path $SourceDir $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $script:InstallRoot $f) -Force }
    }

    $data = [ordered]@{
        startTime = $Config.startTime
        endTime   = $Config.endTime
        startDate = $Config.startDate
        endDate   = $Config.endDate
    }
    # Optional Telegram notification settings (chatId, tokenEnc, heartbeatHours).
    # Present only when the user set them up.
    if ($Config.notify) { $data.notify = $Config.notify }
    $json = $data | ConvertTo-Json
    # UTF-8 without BOM so ConvertFrom-Json never chokes on it.
    [IO.File]::WriteAllText((Join-Path $script:InstallRoot 'config.json'), $json, (New-Object Text.UTF8Encoding $false))

    $enforce = Join-Path $script:InstallRoot 'enforce.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$enforce`""

    # Every minute (indefinitely), plus at startup and at every logon, so a
    # login during the window is caught within a minute and on the way in.
    $minuteTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date
    $minuteTrigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
            -RepetitionInterval (New-TimeSpan -Minutes 1) `
            -RepetitionDuration (New-TimeSpan -Days 3650)).Repetition
    $atStartup = New-ScheduledTaskTrigger -AtStartup
    $atLogon = New-ScheduledTaskTrigger -AtLogOn

    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -RunLevel Highest -LogonType ServiceAccount
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

    Register-ScheduledTask -TaskName $script:TaskName -Action $action `
        -Trigger $minuteTrigger, $atStartup, $atLogon -Principal $principal -Settings $settings -Force | Out-Null
}

function Remove-LoginLock {
    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path $script:InstallRoot) { Remove-Item $script:InstallRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

function Get-ActiveConfig {
    $f = Join-Path $script:InstallRoot 'config.json'
    if (Test-Path $f) { try { return Get-Content $f -Raw | ConvertFrom-Json } catch { return $null } }
    return $null
}

function Test-LoginLockActive {
    return [bool](Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue)
}
