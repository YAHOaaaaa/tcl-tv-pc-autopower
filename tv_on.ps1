# PC startup / logon / resume: wake the TCL TV over ADB, switch it to the PC's HDMI input
# and make sure tvwatch.sh runs on the TV.
# Runs as SYSTEM from the "TV-Power-On" scheduled task, so it uses its own adb server port
# and the adb key named in config.ps1.
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\config.ps1"
$log = "$PSScriptRoot\tv_on.log"
$env:ADB_VENDOR_KEYS = $AdbKey
$P = '5039'
function Log($m) { "$(Get-Date -Format s) $m" | Out-File $log -Append -Encoding utf8 }
function Adb { & $Adb -P $P @args 2>&1 }

Log "start (user=$env:USERNAME)"

# Wake-on-LAN magic packet, in case the TV went into deep standby
if ($TvMac) {
  try {
    $bytes = [byte[]](,0xFF * 6) + ((1..16) | ForEach-Object { $TvMac.Split('-:') | ForEach-Object { [Convert]::ToByte($_, 16) } })
    $udp = New-Object Net.Sockets.UdpClient; $udp.EnableBroadcast = $true
    [void]$udp.Send($bytes, $bytes.Length, '255.255.255.255', 9); $udp.Close()
  } catch { Log "WoL failed: $_" }
}

# The network may not be up yet right after boot: retry for about two minutes
$ok = $false
for ($i = 0; $i -lt 40; $i++) {
  Adb connect $TvAddress | Out-Null
  $w = Adb -s $TvAddress shell "dumpsys power | grep -o 'mWakefulness=[A-Za-z]*'"
  if ($w -match 'mWakefulness=(\w+)') { $ok = $true; break }
  Start-Sleep 3
}
if (-not $ok) { Log "TV not reachable"; Adb kill-server | Out-Null; exit 1 }

$state = $matches[1]
Log "TV state: $state"

# Start the watcher first so it sees the SignalLock that follows the wake-up / input switch
$running = Adb -s $TvAddress shell "ps -A -o ARGS | grep -c '^sh /data/local/tmp/tvwatch.sh'"
if ("$running".Trim() -eq '0') {
  Adb -s $TvAddress push "$PSScriptRoot\tvwatch.sh" /data/local/tmp/tvwatch.sh | Out-Null
  Adb -s $TvAddress shell "chmod 755 /data/local/tmp/tvwatch.sh; setsid nohup sh /data/local/tmp/tvwatch.sh $HdmiHardwareId $NoSignalDelay >/dev/null 2>&1 </dev/null &" | Out-Null
  Start-Sleep 2
  Log "tvwatch started"
}

if ($state -ne 'Awake') { Adb -s $TvAddress shell "input keyevent KEYCODE_WAKEUP" | Out-Null; Start-Sleep 4 }
Adb -s $TvAddress shell "am start -a android.intent.action.VIEW -d content://android.media.tv/passthrough/com.tcl.tvinput%2F.TvPassThroughService%2FHW$HdmiHardwareId" | Out-Null
Log "done: woke TV and switched to HW$HdmiHardwareId"
Adb kill-server | Out-Null
