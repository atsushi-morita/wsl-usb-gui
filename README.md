# wsl-usb-gui

[usbipd-win](https://github.com/dorssel/usbipd-win) で USB デバイスを WSL2 にアタッチするための、シンプルな GUI フロントエンドです。
`usbipd list` → `usbipd bind` → `usbipd attach --wsl` を毎回 CLI で打つ手間をなくします。

PowerShell + WinForms だけで動くので、ビルドや追加ランタイムは不要です。

## 機能

- 接続中の USB デバイスを一覧表示 (BUSID / VID:PID / デバイス名 / 状態)
- 3 秒ごとに自動更新し、抜き差しを反映
- **ダブルクリックでアタッチ / デタッチを切り替え**
- 未共有のデバイスは、アタッチ時に `bind` してから `attach` (`bind` のときだけ UAC 確認)
- 自動再アタッチ (`--auto-attach`) に対応。リセットや抜き差しが多いマイコンボードに便利
- 共有の解除 (`unbind`)。接続されていない共有済みデバイスも解除可能
- アタッチ先の WSL ディストリビューションを選択可能

## 必要なもの

- Windows 10 / 11
- WSL2
- [usbipd-win](https://github.com/dorssel/usbipd-win) 4.x 以降 (`usbipd state` コマンドを使います。5.3.0 で動作確認)

```powershell
winget install usbipd
```

## 使い方

1. このリポジトリをクローンするか、ZIP をダウンロードして展開します。
2. デスクトップにショートカットを作成します (任意)。

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install-Shortcut.ps1
   ```

3. ショートカットから起動します。ショートカットを使わない場合は次のコマンドで起動できます。

   ```powershell
   powershell -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File .\UsbipGui.ps1
   ```

| 操作 | 内容 |
| --- | --- |
| ダブルクリック | アタッチ / デタッチの切り替え |
| アタッチ | 選択したデバイスを WSL にアタッチ (未共有なら bind も実行) |
| デタッチ | WSL からデタッチ (自動再アタッチも停止) |
| 共有解除 | `usbipd unbind` を実行し、Windows 専用に戻す |
| 自動再アタッチ | チェックしてアタッチすると `--auto-attach` で常駐。アプリを閉じると停止 |

## 注意

- アタッチ中のデバイスは Windows からは使えなくなります。キーボード、マウス、指紋センサーなどを誤ってアタッチしないよう注意してください。
- アタッチするには、WSL ディストリビューションが起動している必要があります。
- 一部のデバイスは `usbipd bind --force` が必要な場合があります。その場合は CLI から実行してください。
