# デスクトップに「WSL USB アタッチ」ショートカットを作成する
$script = Join-Path $PSScriptRoot 'UsbipGui.ps1'
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'WSL USB アタッチ.lnk'))
$lnk.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.IconLocation = "$env:WINDIR\System32\DDORes.dll,2"
$lnk.Save()
Write-Host "ショートカットを作成しました: $($lnk.FullName)"
