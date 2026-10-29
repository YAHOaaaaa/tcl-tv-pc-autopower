# tcl-tv-pc-autopower

TCL の Google TV（85T8B で確認）を PC モニターとして使うときに、

- **PC を起動したらテレビが自動でオンになり、PC の HDMI 入力に切り替わる**
- **PC をシャットダウン／スリープしたらテレビが自動でスタンバイになる**

ようにするスクリプトです。

NVIDIA などの PC 用 GPU は HDMI-CEC を出せないので、テレビの「電源オン連動／電源オフ連動」は PC には反応しません。
このリポジトリでは CEC の代わりに **ADB（ネットワークデバッグ）** を使います。追加のハードウェアは要りません。

## しくみ

| 動作 | どこで動くか | 内容 |
| --- | --- | --- |
| テレビをオン | PC（`tv_on.ps1`） | 起動・ログオン・スリープ復帰時にタスク スケジューラ（SYSTEM）から実行。Wake-on-LAN → `adb connect` → `KEYCODE_WAKEUP` → HDMI 入力へ切り替え |
| テレビをオフ | テレビ（`tvwatch.sh`） | テレビ内で常駐し、HDMI の信号イベントを `logcat` で監視。PC の信号が `NoSignalDelay` 秒（既定 20 秒）途絶えたら `KEYCODE_SLEEP` |

`tvwatch.sh` は次の場合は何もしません。

- テレビで別の入力（YouTube やチューナーなど）を見ているとき
- PC が切れている状態で、リモコンでテレビをつけたとき（それまでに PC の信号を一度も受けていない場合）

テレビを再起動すると `tvwatch.sh` は止まりますが、次に PC が起動したときに `tv_on.ps1` が自動で入れ直します。

## 必要なもの

- Windows 10 / 11
- [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools)（`adb.exe`）
- テレビ側で **開発者向けオプション → ネットワーク デバッグ（ADB）** を有効にしておく
- テレビの **設定 → システム → 電源と省エネ設定 → クイックスタート** をオン（スタンバイ中も ADB が届くようにするため）
- 電源オン時の画面は「前回使用した入力の画面」がおすすめです

## セットアップ

1. PC から一度テレビに接続し、テレビに出る「USB デバッグを許可しますか？」で **常に許可** を選びます。

   ```bash
   adb connect 192.168.0.100:5555
   ```

2. `config.example.ps1` を `config.ps1` にコピーして、自分の環境に合わせて書き換えます。

   - `TvAddress`：テレビの IP:ポート
   - `TvMac`：テレビの MAC アドレス（Wake-on-LAN 用、不要なら空）
   - `AdbKey`：手順 1 で許可された adb の秘密鍵（例 `C:\Users\あなた\.android\adbkey`）。SYSTEM で動くので絶対パスで書きます
   - `HdmiHardwareId`：PC をつないだ HDMI 端子（TCL は HDMI1=15, HDMI2=16, HDMI3=17, HDMI4=18）

3. 管理者の PowerShell で実行します。

   ```bash
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

   タスク「TV-Power-On」が登録され、すぐに 1 回実行されます。

## 確認

- PC 側のログ：`tv_on.log`
- テレビ側の状態：

  ```bash
  adb shell cat /data/local/tmp/tvwatch.state /data/local/tmp/tvwatch.log
  ```

## アンインストール

管理者の PowerShell で実行します。

```bash
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## 注意

- TCL のテレビ（MediaTek 系）のログ文字列（`VCodecHdmi` の `signalChangeHandler`、`TvPassThroughSession` の `SignalLock`）に依存しています。ファームウェアが変わると動かなくなる可能性があります。
- 入力の切り替えには `com.tcl.tvinput/.TvPassThroughService/HW<id>` を使っています。他社のテレビでは ID が異なります。

## ライセンス

MIT
