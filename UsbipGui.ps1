# WSL USB アタッチ GUI (usbipd-win フロントエンド)
# 起動: powershell -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File UsbipGui.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AutoProcs = @{}   # BusId -> 自動再アタッチ用の常駐 usbipd プロセス

function Invoke-Usbipd([string]$arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'usbipd', $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $out.Trim(); Err = $errTask.Result.Trim() }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# bind/unbind は管理者権限が必要なので、その操作だけ UAC 昇格して実行する
function Invoke-UsbipdElevated([string]$arguments) {
    if (Test-Admin) { return Invoke-Usbipd $arguments }
    try {
        $p = Start-Process usbipd -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        [pscustomobject]@{ ExitCode = $p.ExitCode; Out = ''; Err = '' }
    } catch {
        [pscustomobject]@{ ExitCode = -1; Out = ''; Err = "UAC がキャンセルされました" }
    }
}

function Get-Distros {
    $env:WSL_UTF8 = '1'
    $list = & wsl.exe -l -q 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ }
    @($list)
}

function Get-Devices {
    $r = Invoke-Usbipd 'state'
    if ($r.ExitCode -ne 0) { throw "usbipd state 失敗: $($r.Err)" }
    ($r.Out | ConvertFrom-Json).Devices | ForEach-Object {
        $vidpid = ''
        if ($_.InstanceId -match 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') { $vidpid = "$($Matches[1]):$($Matches[2])".ToLower() }
        $state =
            if (-not $_.BusId) { 'Offline' }
            elseif ($_.ClientIPAddress) { 'Attached' }
            elseif ($_.PersistedGuid) { 'Shared' }
            else { 'NotShared' }
        [pscustomobject]@{
            BusId = $_.BusId; VidPid = $vidpid; Description = $_.Description
            State = $state; Guid = $_.PersistedGuid
        }
    } | Sort-Object @{ e = { $_.State -eq 'Offline' } }, @{ e = { if ($_.BusId) { [version]($_.BusId -replace '-', '.') } } }
}

# ---------------- UI ----------------
$form = New-Object Windows.Forms.Form
$form.Text = 'WSL USB アタッチ'
$form.Size = New-Object Drawing.Size(820, 520)
$form.MinimumSize = New-Object Drawing.Size(640, 360)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Yu Gothic UI', 9.5)

$top = New-Object Windows.Forms.FlowLayoutPanel
$top.Dock = 'Top'; $top.Height = 40; $top.Padding = '6,6,6,0'; $top.WrapContents = $false

$lblDistro = New-Object Windows.Forms.Label
$lblDistro.Text = 'ディストリ:'; $lblDistro.AutoSize = $true; $lblDistro.Margin = '0,6,4,0'
$cmbDistro = New-Object Windows.Forms.ComboBox
$cmbDistro.DropDownStyle = 'DropDownList'; $cmbDistro.Width = 160
$cmbDistro.Items.Add('(既定)') | Out-Null
Get-Distros | ForEach-Object { $cmbDistro.Items.Add($_) | Out-Null }
$cmbDistro.SelectedIndex = 0

function New-Button($text, $width = 90) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text; $b.Width = $width; $b.Height = 28
    $b
}
$btnAttach  = New-Button 'アタッチ'
$btnDetach  = New-Button 'デタッチ'
$btnUnbind  = New-Button '共有解除'
$btnRefresh = New-Button '更新' 70
$chkAuto = New-Object Windows.Forms.CheckBox
$chkAuto.Text = '自動再アタッチ'; $chkAuto.AutoSize = $true; $chkAuto.Margin = '10,6,0,0'

$top.Controls.AddRange(@($lblDistro, $cmbDistro, $btnAttach, $btnDetach, $btnUnbind, $btnRefresh, $chkAuto))

$lv = New-Object Windows.Forms.ListView
$lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false
[void]$lv.Columns.Add('BUSID', 60)
[void]$lv.Columns.Add('VID:PID', 85)
[void]$lv.Columns.Add('デバイス', 450)
[void]$lv.Columns.Add('状態', 160)

$log = New-Object Windows.Forms.TextBox
$log.Dock = 'Bottom'; $log.Height = 90; $log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'
$log.Font = New-Object Drawing.Font('Consolas', 9)

$status = New-Object Windows.Forms.StatusStrip
$statusLabel = New-Object Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'ダブルクリックでアタッチ/デタッチ切替'
[void]$status.Items.Add($statusLabel)

$form.Controls.Add($lv)
$form.Controls.Add($top)
$form.Controls.Add($log)
$form.Controls.Add($status)

$stateText = @{
    Attached  = '● アタッチ中'
    Shared    = '○ 共有済み'
    NotShared = '－ 未共有'
    Offline   = '× 未接続 (共有設定あり)'
}
$stateColor = @{
    Attached  = [Drawing.Color]::FromArgb(0, 120, 60)
    Shared    = [Drawing.Color]::FromArgb(0, 90, 170)
    NotShared = [Drawing.SystemColors]::ControlText
    Offline   = [Drawing.Color]::Gray
}

function Write-Log([string]$msg) {
    if (-not $msg) { return }
    $log.AppendText("[$(Get-Date -Format HH:mm:ss)] $msg`r`n")
}

$script:LastSnapshot = ''
function Update-List([switch]$Force) {
    try { $devs = @(Get-Devices) } catch { $statusLabel.Text = $_.Exception.Message; return }

    # 自動再アタッチの終了したプロセスを掃除
    foreach ($k in @($script:AutoProcs.Keys)) { if ($script:AutoProcs[$k].HasExited) { $script:AutoProcs.Remove($k) } }

    $snapshot = ($devs | ForEach-Object { "$($_.BusId)|$($_.State)|$($_.Description)" }) -join ';'
    $snapshot += '#' + (($script:AutoProcs.Keys | Sort-Object) -join ',')
    if (-not $Force -and $snapshot -eq $script:LastSnapshot) { return }
    $script:LastSnapshot = $snapshot

    $selKey = if ($lv.SelectedItems.Count) { $lv.SelectedItems[0].Tag.BusId + '|' + $lv.SelectedItems[0].Tag.Guid } else { $null }
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($d in $devs) {
        $text = $stateText[$d.State]
        if ($d.BusId -and $script:AutoProcs.ContainsKey($d.BusId)) { $text += ' [自動]' }
        $item = [Windows.Forms.ListViewItem]::new([string[]]@([string]$d.BusId, $d.VidPid, $d.Description, $text))
        $item.ForeColor = $stateColor[$d.State]
        $item.Tag = $d
        [void]$lv.Items.Add($item)
        if ($selKey -and ($d.BusId + '|' + $d.Guid) -eq $selKey) { $item.Selected = $true }
    }
    $lv.EndUpdate()
    Update-Buttons
}

function Get-Selected { if ($lv.SelectedItems.Count) { $lv.SelectedItems[0].Tag } }

function Update-Buttons {
    $d = Get-Selected
    $btnAttach.Enabled = $d -and $d.State -in 'NotShared', 'Shared'
    $btnDetach.Enabled = $d -and ($d.State -eq 'Attached' -or ($d.BusId -and $script:AutoProcs.ContainsKey($d.BusId)))
    $btnUnbind.Enabled = $d -and $d.State -in 'Shared', 'Offline', 'Attached'
}

function Get-WslArg {
    if ($cmbDistro.SelectedIndex -le 0) { '--wsl' } else { "--wsl `"$($cmbDistro.SelectedItem)`"" }
}

function Invoke-Busy([scriptblock]$action) {
    $form.Cursor = 'WaitCursor'; $top.Enabled = $false
    try { & $action } finally { $form.Cursor = 'Default'; $top.Enabled = $true; Update-List -Force }
}

function Connect-Device($d) {
    Invoke-Busy {
        if ($d.State -eq 'NotShared') {
            Write-Log "bind $($d.BusId) (管理者権限が必要です)"
            $r = Invoke-UsbipdElevated "bind --busid $($d.BusId)"
            if ($r.ExitCode -ne 0) { Write-Log "bind 失敗 (code $($r.ExitCode)) $($r.Err)"; return }
        }
        $wsl = Get-WslArg
        if ($chkAuto.Checked) {
            $psi = New-Object Diagnostics.ProcessStartInfo 'usbipd', "attach $wsl --busid $($d.BusId) --auto-attach"
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $script:AutoProcs[$d.BusId] = [Diagnostics.Process]::Start($psi)
            Write-Log "自動再アタッチ開始: $($d.BusId) $($d.Description)"
            Start-Sleep -Milliseconds 1500
        } else {
            Write-Log "attach $($d.BusId) $($d.Description)"
            $r = Invoke-Usbipd "attach $wsl --busid $($d.BusId)"
            Write-Log $r.Out; Write-Log $r.Err
            if ($r.ExitCode -eq 0) { Write-Log "→ アタッチしました" } else { Write-Log "→ 失敗 (code $($r.ExitCode))" }
        }
    }
}

function Disconnect-Device($d) {
    Invoke-Busy {
        if ($d.BusId -and $script:AutoProcs.ContainsKey($d.BusId)) {
            $p = $script:AutoProcs[$d.BusId]
            if (-not $p.HasExited) { $p.Kill() }
            $script:AutoProcs.Remove($d.BusId)
            Write-Log "自動再アタッチ停止: $($d.BusId)"
        }
        if ($d.State -eq 'Attached') {
            $r = Invoke-Usbipd "detach --busid $($d.BusId)"
            Write-Log $r.Err
            if ($r.ExitCode -eq 0) { Write-Log "detach $($d.BusId) → デタッチしました" } else { Write-Log "detach 失敗 (code $($r.ExitCode))" }
        }
    }
}

function Remove-Share($d) {
    $res = [Windows.Forms.MessageBox]::Show("「$($d.Description)」の共有を解除しますか？`r`n(管理者権限が必要です)", '共有解除', 'OKCancel', 'Question')
    if ($res -ne 'OK') { return }
    if ($d.State -eq 'Attached' -or ($d.BusId -and $script:AutoProcs.ContainsKey($d.BusId))) { Disconnect-Device $d }
    Invoke-Busy {
        $arg = if ($d.BusId) { "unbind --busid $($d.BusId)" } else { "unbind --guid $($d.Guid)" }
        $r = Invoke-UsbipdElevated $arg
        if ($r.ExitCode -eq 0) { Write-Log "unbind → 共有を解除しました: $($d.Description)" } else { Write-Log "unbind 失敗 (code $($r.ExitCode)) $($r.Err)" }
    }
}

$btnAttach.Add_Click({ $d = Get-Selected; if ($d) { Connect-Device $d } })
$btnDetach.Add_Click({ $d = Get-Selected; if ($d) { Disconnect-Device $d } })
$btnUnbind.Add_Click({ $d = Get-Selected; if ($d) { Remove-Share $d } })
$btnRefresh.Add_Click({ Update-List -Force })
$lv.Add_SelectedIndexChanged({ Update-Buttons })
$lv.Add_DoubleClick({
    $d = Get-Selected
    if (-not $d) { return }
    if ($d.State -eq 'Attached' -or ($d.BusId -and $script:AutoProcs.ContainsKey($d.BusId))) { Disconnect-Device $d }
    elseif ($d.State -in 'NotShared', 'Shared') { Connect-Device $d }
})

# 抜き差しを拾うため定期更新
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ if ($top.Enabled) { Update-List } })

$form.Add_Shown({
    if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
        [Windows.Forms.MessageBox]::Show("usbipd が見つかりません。`r`nwinget install usbipd でインストールしてください。", 'エラー', 'OK', 'Error') | Out-Null
        $form.Close(); return
    }
    Update-List -Force
    $timer.Start()
})
$form.Add_FormClosing({
    $timer.Stop()
    foreach ($p in $script:AutoProcs.Values) { if (-not $p.HasExited) { $p.Kill() } }
})

[void]$form.ShowDialog()
