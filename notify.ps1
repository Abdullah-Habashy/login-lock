<#
    Login Lock - Telegram notifications (heartbeat to the accountability friend).
    Dot-sourced by enforce.ps1 (SYSTEM task), setup.ps1 and remove.ps1.
    The bot token is DPAPI-encrypted with LocalMachine scope, so the admin who
    sets it and the SYSTEM task can both decrypt it on this machine, and it is
    useless if the config file is copied elsewhere.
#>
Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

function Protect-Secret([string] $plain) {
    if ([string]::IsNullOrEmpty($plain)) { return '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
    $enc = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Convert]::ToBase64String($enc)
}

function Unprotect-Secret([string] $b64) {
    if ([string]::IsNullOrEmpty($b64)) { return '' }
    try {
        $enc = [Convert]::FromBase64String($b64)
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch { return '' }
}

# Sends a Telegram message. $TokenEnc is the DPAPI-encrypted bot token.
function Send-TelegramMessage {
    param(
        [Parameter(Mandatory)] [string] $TokenEnc,
        [Parameter(Mandatory)] [string] $ChatId,
        [Parameter(Mandatory)] [string] $Text
    )
    try {
        $token = Unprotect-Secret $TokenEnc
        if ([string]::IsNullOrEmpty($token)) { return @{ ok = $false; error = 'no token' } }
        $uri = "https://api.telegram.org/bot$token/sendMessage"
        $body = @{ chat_id = $ChatId; text = $Text; disable_web_page_preview = $true }
        $r = Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 20
        if ($r.ok) { return @{ ok = $true } }
        return @{ ok = $false; error = 'telegram returned not-ok' }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

# Used during setup with the PLAIN token to validate it and discover chat ids
# of anyone who has messaged the bot. Returns @{ ok; botName; chats=@(@{id;name}) }.
function Test-TelegramToken([string] $token) {
    try {
        $me = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/getMe" -TimeoutSec 20
        if (-not $me.ok) { return @{ ok = $false; error = 'invalid token' } }
        $chats = @()
        try {
            $upd = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/getUpdates" -TimeoutSec 20
            foreach ($u in $upd.result) {
                $c = $u.message.chat
                if ($c -and $c.id) {
                    $name = @($c.title, (($c.first_name, $c.last_name) -join ' ').Trim(), $c.username) | Where-Object { $_ } | Select-Object -First 1
                    $chats += [pscustomobject]@{ id = [string]$c.id; name = $name }
                }
            }
        } catch {}
        $chats = $chats | Sort-Object id -Unique
        return @{ ok = $true; botName = $me.result.username; chats = $chats }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}
