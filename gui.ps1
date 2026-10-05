<#
    Login Lock - the configuration window (Arabic, RTL).
    Launched elevated by LoginLock.bat. Sets a daily lock window + a date range
    and registers the SYSTEM task. Changes nothing until you press "تفعيل".
    Flat layout (all controls at script scope) so event handlers reach them.
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $PSScriptRoot 'schedule.ps1')

$ui = [System.Drawing.Color]::FromArgb(37, 99, 235)
$white = [System.Drawing.Color]::White
$black = [System.Drawing.Color]::Black
$font = New-Object System.Drawing.Font('Segoe UI', 10)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'قفل الدخول'
$form.Size = New-Object System.Drawing.Size(560, 560)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.RightToLeft = 'Yes'
$form.RightToLeftLayout = $true
$form.Font = $font
$form.BackColor = $white

function Add-Label($text, $x, $y, $w) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, 24)
    $form.Controls.Add($l); return $l
}
function New-Combo($x, $y, $w, $items, $sel) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($w, 28)
    $items | ForEach-Object { [void]$c.Items.Add($_) }
    $c.SelectedItem = $sel
    $form.Controls.Add($c); return $c
}
function New-Btn($text, $x, $y, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, 28); $b.FlatStyle = 'Flat'
    $form.Controls.Add($b); return $b
}

$warn = New-Object System.Windows.Forms.Label
$warn.Location = New-Object System.Drawing.Point(20, 12)
$warn.Size = New-Object System.Drawing.Size(500, 36)
$warn.ForeColor = [System.Drawing.Color]::FromArgb(180, 120, 0)
$warn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$warn.Visible = $false
$form.Controls.Add($warn)

# --- start time row ---
Add-Label 'وقت البداية' 20 60 120 | Out-Null
$startHour = New-Combo 150 60 60 (1..12 | ForEach-Object { '{0:00}' -f $_ }) '10'
Add-Label ':' 214 60 10 | Out-Null
$startMin = New-Combo 230 60 60 @('00', '15', '30', '45') '00'
$startAmBtn = New-Btn 'AM' 310 60 55
$startPmBtn = New-Btn 'PM' 370 60 55
$script:startIsPm = $true

# --- end time row ---
Add-Label 'وقت النهاية' 20 105 120 | Out-Null
$endHour = New-Combo 150 105 60 (1..12 | ForEach-Object { '{0:00}' -f $_ }) '08'
Add-Label ':' 214 105 10 | Out-Null
$endMin = New-Combo 230 105 60 @('00', '15', '30', '45') '00'
$endAmBtn = New-Btn 'AM' 310 105 55
$endPmBtn = New-Btn 'PM' 370 105 55
$script:endIsPm = $false

# --- dates ---
Add-Label 'تاريخ البداية' 20 155 120 | Out-Null
$startDate = New-Object System.Windows.Forms.DateTimePicker
$startDate.Format = 'Short'; $startDate.Location = New-Object System.Drawing.Point(150, 155)
$startDate.Size = New-Object System.Drawing.Size(150, 28)
$startDate.MinDate = (Get-Date).Date; $startDate.Value = (Get-Date).Date
$form.Controls.Add($startDate)

Add-Label 'تاريخ النهاية' 20 200 120 | Out-Null
$endDate = New-Object System.Windows.Forms.DateTimePicker
$endDate.Format = 'Short'; $endDate.Location = New-Object System.Drawing.Point(150, 200)
$endDate.Size = New-Object System.Drawing.Size(150, 28)
$endDate.Value = (Get-Date).Date.AddMonths(1)
$form.Controls.Add($endDate)

$qMonth = New-Btn 'شهر' 310 200 60
$q2Month = New-Btn 'شهرين' 373 200 60
$q6Month = New-Btn '6 شهور' 436 200 70

$summary = New-Object System.Windows.Forms.Label
$summary.Location = New-Object System.Drawing.Point(20, 255)
$summary.Size = New-Object System.Drawing.Size(500, 80)
$summary.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
$summary.Padding = New-Object System.Windows.Forms.Padding(10)
$form.Controls.Add($summary)

$err = New-Object System.Windows.Forms.Label
$err.Location = New-Object System.Drawing.Point(20, 345)
$err.Size = New-Object System.Drawing.Size(500, 36)
$err.ForeColor = [System.Drawing.Color]::FromArgb(200, 30, 30)
$err.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($err)

$activate = New-Btn 'تفعيل' 150 420 120
$activate.Size = New-Object System.Drawing.Size(120, 40)
$activate.BackColor = $ui; $activate.ForeColor = $white
$cancel = New-Btn 'إلغاء' 290 420 120
$cancel.Size = New-Object System.Drawing.Size(120, 40)

$script:valid = $false

function Paint-AmPm {
    if ($script:startIsPm) { $startPmBtn.BackColor = $ui; $startPmBtn.ForeColor = $white; $startAmBtn.BackColor = $white; $startAmBtn.ForeColor = $black }
    else { $startAmBtn.BackColor = $ui; $startAmBtn.ForeColor = $white; $startPmBtn.BackColor = $white; $startPmBtn.ForeColor = $black }
    if ($script:endIsPm) { $endPmBtn.BackColor = $ui; $endPmBtn.ForeColor = $white; $endAmBtn.BackColor = $white; $endAmBtn.ForeColor = $black }
    else { $endAmBtn.BackColor = $ui; $endAmBtn.ForeColor = $white; $endPmBtn.BackColor = $white; $endPmBtn.ForeColor = $black }
}

function To24($hourCombo, $minCombo, $isPm) {
    $h = [int]$hourCombo.SelectedItem; $m = [int]$minCombo.SelectedItem
    if ($isPm) { if ($h -ne 12) { $h += 12 } } else { if ($h -eq 12) { $h = 0 } }
    return '{0:00}:{1:00}' -f $h, $m
}
function To12Text($hhmm) {
    $parts = $hhmm.Split(':'); $h = [int]$parts[0]
    $ap = if ($h -ge 12) { 'PM' } else { 'AM' }; $h12 = $h % 12; if ($h12 -eq 0) { $h12 = 12 }
    return '{0}:{1} {2}' -f $h12, $parts[1], $ap
}

function Update-Summary {
    $st = To24 $startHour $startMin $script:startIsPm
    $et = To24 $endHour $endMin $script:endIsPm
    $sd = $startDate.Value.Date; $ed = $endDate.Value.Date
    $sdStr = $sd.ToString('yyyy-MM-dd'); $edStr = $ed.ToString('yyyy-MM-dd')
    $firstStart = [datetime]::ParseExact("$sdStr $st", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    $lastEnd = [datetime]::ParseExact("$edStr $et", 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)

    $summary.Text = "الجهاز هيتقفل كل يوم من $(To12Text $st) لـ $(To12Text $et)`r`nمن $sdStr  إلى  $edStr"

    $msg = ''
    if ($st -eq $et) { $msg = 'وقت البداية لازم يكون غير وقت النهاية.' }
    elseif ($lastEnd -le $firstStart) { $msg = 'ميعاد النهاية لازم يكون بعد ميعاد البداية.' }
    elseif ($lastEnd -le (Get-Date)) { $msg = 'ميعاد النهاية عدّى خلاص.' }
    $err.Text = $msg
    $script:valid = ($msg -eq '')
    $activate.Enabled = $script:valid
}

$startAmBtn.Add_Click({ $script:startIsPm = $false; Paint-AmPm; Update-Summary })
$startPmBtn.Add_Click({ $script:startIsPm = $true; Paint-AmPm; Update-Summary })
$endAmBtn.Add_Click({ $script:endIsPm = $false; Paint-AmPm; Update-Summary })
$endPmBtn.Add_Click({ $script:endIsPm = $true; Paint-AmPm; Update-Summary })
$startHour.Add_SelectedIndexChanged({ Update-Summary })
$startMin.Add_SelectedIndexChanged({ Update-Summary })
$endHour.Add_SelectedIndexChanged({ Update-Summary })
$endMin.Add_SelectedIndexChanged({ Update-Summary })
$startDate.Add_ValueChanged({ Update-Summary })
$endDate.Add_ValueChanged({ Update-Summary })
$qMonth.Add_Click({ $endDate.Value = $startDate.Value.Date.AddMonths(1); Update-Summary })
$q2Month.Add_Click({ $endDate.Value = $startDate.Value.Date.AddMonths(2); Update-Summary })
$q6Month.Add_Click({ $endDate.Value = $startDate.Value.Date.AddMonths(6); Update-Summary })
$cancel.Add_Click({ $form.Close() })

$activate.Add_Click({
        Update-Summary
        if (-not $script:valid) { return }
        $c = @{
            startTime = (To24 $startHour $startMin $script:startIsPm)
            endTime   = (To24 $endHour $endMin $script:endIsPm)
            startDate = $startDate.Value.Date.ToString('yyyy-MM-dd')
            endDate   = $endDate.Value.Date.ToString('yyyy-MM-dd')
        }
        $confirm = [System.Windows.Forms.MessageBox]::Show("$($summary.Text)`r`n`r`nتأكيد تفعيل القفل؟", 'قفل الدخول', 'YesNo', 'Warning', 'Button2')
        if ($confirm -ne 'Yes') { return }
        try {
            Install-LoginLock -Config $c -SourceDir $PSScriptRoot
            [void][System.Windows.Forms.MessageBox]::Show('تم تفعيل القفل.', 'قفل الدخول', 'OK', 'Information')
            $form.Close()
        } catch {
            [void][System.Windows.Forms.MessageBox]::Show("حصل خطأ أثناء التفعيل:`r`n$($_.Exception.Message)", 'قفل الدخول', 'OK', 'Error')
        }
    })

# Prefill from an active schedule.
$existing = Get-ActiveConfig
if ($existing) {
    $warn.Text = 'فيه جدول شغّال دلوقتي، وهيتستبدل لو فعّلت واحد جديد.'
    $warn.Visible = $true
    try {
        $sh = [int]$existing.startTime.Split(':')[0]; $script:startIsPm = ($sh -ge 12); $sh12 = $sh % 12; if ($sh12 -eq 0) { $sh12 = 12 }
        $startHour.SelectedItem = ('{0:00}' -f $sh12); $startMin.SelectedItem = $existing.startTime.Split(':')[1]
        $eh = [int]$existing.endTime.Split(':')[0]; $script:endIsPm = ($eh -ge 12); $eh12 = $eh % 12; if ($eh12 -eq 0) { $eh12 = 12 }
        $endHour.SelectedItem = ('{0:00}' -f $eh12); $endMin.SelectedItem = $existing.endTime.Split(':')[1]
        $startDate.Value = [datetime]::ParseExact($existing.startDate, 'yyyy-MM-dd', $null)
        $endDate.Value = [datetime]::ParseExact($existing.endDate, 'yyyy-MM-dd', $null)
    } catch {}
}

Paint-AmPm
Update-Summary
[void]$form.ShowDialog()
