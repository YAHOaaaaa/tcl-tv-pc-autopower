# tcl-tv-pc-autopower

TCL の Google TV（85T8B で確認）を PC モニターとして使うときに、

- **PC を起動したら、テレビが自動でオンになって PC の画面が出る**（テレビを最後に PC の HDMI 入力で使っていた場合だけ）
- **PC をシャットダウン／スリープしたらテレビが自動でスタンバイになる**

入力の強制切り替えはしません。Google TV のアプリや HDMI2 などを見ているときに PC を起動しても、テレビの画面はそのままです。

ようにするスクリプトです。

NVIDIA などの PC 用 GPU は HDMI-CEC を出せないので、テレビの「電源オン連動／電源オフ連動」は PC には反応しません。
このリポジトリでは CEC の代わりに **ADB（ネットワークデバッグ）** を使います。追加のハードウェアは要りません。

## しくみ

| 動作 | どこで動くか | 内容 |
| --- | --- | --- |
| テレビをオン | PC（`tv_on.ps1`） | 起動・ログオン・スリープ復帰時にタスク スケジューラ（SYSTEM）から実行。`adb connect`（届かなければ Wake-on-LAN を送りながら約 3 分リトライ）→ スタンバイ前の入力が PC の HDMI なら `KEYCODE_WAKEUP` |
| テレビをオフ | テレビ（`tvwatch.sh`） | テレビ内で常駐し、HDMI の信号イベントを `logcat` で監視。PC の信号が `NoSignalDelay` 秒（既定 20 秒）途絶えたら `KEYCODE_SLEEP` |
| テレビをオン（即時） | テレビ（`tvwatch.sh`） | スタンバイ中に PC の HDMI ホットプラグ（`TclHdmiControlService` の `onHotplug`）を検知したら `KEYCODE_WAKEUP`（スタンバイ前の入力が PC の HDMI だった場合だけ） |

`tv_on.ps1` の判断：

| テレビの状態 | 動作 |
| --- | --- |
| スタンバイ中・直前に PC の HDMI を表示 | 起動する（PC の画面に戻る） |
| スタンバイ中・直前に別の入力やアプリ | 何もしない |
| 起動中 | 何もしない（入力は切り替えない） |

スタンバイ中のテレビは入力 ID を返さないので、スタンバイに入る直前の入力を `tvwatch.sh` が `/data/local/tmp/tvwatch.input` に記録しています。

Wake-on-LAN でテレビが画面ごと起きてしまい、しかも直前の入力が PC 以外だった場合は、`tv_on.ps1` がすぐスタンバイに戻します（数秒だけ画面が点きます）。

### テレビが点くまでの速さ

PC の電源を入れると、GPU は起動画面（POST）の段階で HDMI のホットプラグ信号を出します。Windows が動き出すより 20 秒ほど前です。

| テレビの状態 | テレビを起こすもの | 目安 |
| --- | --- | --- |
| 浅いスタンバイ（PC を切ってから約 90 秒以内。再起動など） | `tvwatch.sh` がホットプラグを検知 | PC の電源投入から数秒（検知から約 1 秒） |
| 深いスタンバイ（それ以降） | Windows 起動後に `tv_on.ps1` が Wake-on-LAN | Windows が起動してネットワークがつながり次第 |

深いスタンバイ中のテレビは CPU が止まっていてホットプラグを処理しません。TCL の電源管理には「画面だけ消して本体は動かし続ける」フェイクスタンバイもありますが、システム権限（`tcl.permission.ACCESS_EXTENDED_POWER`）が必要で、ADB のシェルからは使えません。

深いスタンバイからさらに速くするには：

- PC の BIOS/UEFI で Fast Boot を有効にする（POST の短縮）
- PC を有線 LAN にする（Wi-Fi は起動後の接続に時間がかかります）
- PC の電源投入と同時に CEC を出せる USB-CEC アダプター（Pulse-Eight など）を使う

`tvwatch.sh` は次の場合は何もしません。

- テレビで別の入力（Google TV のアプリや HDMI2 など）を見ているとき
- PC が切れている状態で、リモコンでテレビをつけたとき（それまでに PC の信号を一度も受けていない場合）

テレビを再起動すると `tvwatch.sh` は止まりますが、次に PC が起動したときに `tv_on.ps1` が自動で入れ直します。

## 必要なもの

- Windows 10 / 11
- [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools)（`adb.exe`）
- テレビ側で **開発者向けオプション → ネットワーク デバッグ（ADB）** を有効にしておく
- テレビの **設定 → システム → 電源と省エネ設定 → クイックスタート** をオン
- テレビの **設定 → ネットワークとインターネット → ネットワーク常時待機** をオン（**必須**）

  テレビはスタンバイから約 90 秒で深いスタンバイ（STR）に入り、Wi-Fi が止まります。ネットワーク常時待機がオフだと、この状態のテレビには PC から何も届きません（Wake-on-LAN も効きません）。オンにすると、ADB の接続や Wake-on-LAN が届いたときにテレビのネットワークが復帰します（ログでは `mWakeupTypeWOW`）。
- 電源オン時の画面は「前回使用した入力の画面」がおすすめです

## セットアップ

1. PC から一度テレビに接続し、テレビに出る「USB デバッグを許可しますか？」で **常に許可** を選びます。

   ```bash
   adb connect 192.168.0.100:5555
   ```

2. `config.example.ps1` を `config.ps1` にコピーして、自分の環境に合わせて書き換えます。

   - `TvAddress`：テレビの IP:ポート
   - `TvMac`：テレビの MAC アドレス（Wake-on-LAN 用、不要なら空）
   - `Adb`：`adb.exe` のパス
   - `AdbKey`：手順 1 で許可された adb の秘密鍵（例 `C:\Users\あなた\.android\adbkey`）
   - `HdmiHardwareId`：PC をつないだ HDMI 端子（TCL は HDMI1=15, HDMI2=16, HDMI3=17, HDMI4=18）

3. 管理者の PowerShell で実行します。

   ```bash
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

   `C:\Program Files\tcl-tv-pc-autopower` にインストールされ、タスク「TV-Power-On」が登録されて、すぐに 1 回実行されます。
   `config.ps1` を変えたときは、もう一度 `install.ps1` を実行してください。

### セキュリティ

タスクは SYSTEM 権限で動きます。実行するファイルを一般ユーザーが書き換えられると、管理者でなくても SYSTEM 権限でコードを実行できてしまいます。
そこで `install.ps1` は、タスクが実行・読み込みするもの（`tv_on.ps1`、生成した `config.ps1`、`tvwatch.sh`、`adb.exe` とその DLL、adb の秘密鍵）をすべて `C:\Program Files\tcl-tv-pc-autopower` にコピーし、次のアクセス権にします。

| 対象 | SYSTEM・Administrators | Users |
| --- | --- | --- |
| `C:\Program Files\tcl-tv-pc-autopower` | フルコントロール | 読み取りと実行のみ |
| その中の `adbkey`（秘密鍵） | フルコントロール | アクセス不可 |
| `C:\ProgramData\tcl-tv-pc-autopower`（ログ） | フルコントロール | 読み取りのみ |

ダウンロードしたフォルダ（`config.ps1` を書いた場所）は、インストール後はタスクから使われません。

## 確認

- PC 側のログ：`C:\ProgramData\tcl-tv-pc-autopower\tv_on.log`
- テレビ側の状態：

  ```bash
  adb shell cat /data/local/tmp/tvwatch.state /data/local/tmp/tvwatch.log
  ```

## アンインストール

管理者の PowerShell で実行します。タスク、テレビ上の `tvwatch.sh`、`C:\Program Files\tcl-tv-pc-autopower` と `C:\ProgramData\tcl-tv-pc-autopower` を削除します。

```bash
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## 注意

- TCL のテレビ（MediaTek 系）のログ文字列（`VCodecHdmi` の `signalChangeHandler`、`TvPassThroughSession` の `SignalLock`）に依存しています。ファームウェアが変わると動かなくなる可能性があります。
- 入力の切り替えには `com.tcl.tvinput/.TvPassThroughService/HW<id>` を使っています。他社のテレビでは ID が異なります。

## ライセンス

MIT
