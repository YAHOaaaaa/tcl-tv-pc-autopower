# PC startup / logon / resume: wake the TCL TV over ADB when its last input is the PC's HDMI port,
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
# Input on screen: HDMI ports report their hardware id, the Google TV home/apps report another id.
# While asleep the TV reports the launcher's id, so use what tvwatch.sh recorded when the TV went to standby
# (falling back to the TV's last-used tuner/HDMI input if the watcher was not running then).
if ($state -eq 'Awake') {
  $lastInput = "$(Adb -s $TvAddress shell 'settings get secure tcl_sys_tv_input_current_device_id')".Trim()
} else {
  $lastInput = "$(Adb -s $TvAddress shell 'cat /data/local/tmp/tvwatch.input 2>/dev/null || settings get secure tcl_sys_tv_input_last_device_id')".Trim()
}
Log "TV state: $state, input: $lastInput"

# Start the watcher first so it sees the SignalLock that follows the wake-up
$running = Adb -s $TvAddress shell "ps -A -o ARGS | grep -c '^sh /data/local/tmp/tvwatch.sh'"
if ("$running".Trim() -eq '0') {
  Adb -s $TvAddress push "$PSScriptRoot\tvwatch.sh" /data/local/tmp/tvwatch.sh | Out-Null
  Adb -s $TvAddress shell "chmod 755 /data/local/tmp/tvwatch.sh; setsid nohup sh /data/local/tmp/tvwatch.sh $HdmiHardwareId $NoSignalDelay >/dev/null 2>&1 </dev/null &" | Out-Null
  Start-Sleep 2
  Log "tvwatch started"
}

# Never change the input: only wake the TV when it will come back on the PC's HDMI port.
# If someone left it on another HDMI port or a Google TV app, leave the TV alone.
if ($lastInput -ne "$HdmiHardwareId") {
  Log "done: last input is not HW$HdmiHardwareId, TV left as is"
} elseif ($state -ne 'Awake') {
  Adb -s $TvAddress shell "input keyevent KEYCODE_WAKEUP" | Out-Null
  Log "done: woke TV on HW$HdmiHardwareId"
} else {
  Log "done: TV already on HW$HdmiHardwareId"
}
Adb kill-server | Out-Null
