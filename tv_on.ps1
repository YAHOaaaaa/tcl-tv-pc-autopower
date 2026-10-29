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

# Wake-on-LAN magic packet. About 90 s into standby the TV suspends to RAM and drops off Wi-Fi;
# with "ネットワーク常時待機" on, this packet resumes it (fully, screen on, back on its last input).
$tvIp = $TvAddress.Split(':')[0]
function Wol {
  if (-not $TvMac) { return }
  try {
    $bytes = [byte[]](,0xFF * 6) + ((1..16) | ForEach-Object { $TvMac.Split('-:') | ForEach-Object { [Convert]::ToByte($_, 16) } })
    $udp = New-Object Net.Sockets.UdpClient; $udp.EnableBroadcast = $true
    foreach ($dst in '255.255.255.255', ($tvIp -replace '\.\d+$', '.255'), $tvIp) { [void]$udp.Send($bytes, $bytes.Length, $dst, 9) }
    $udp.Close()
  } catch { }
}

# Probe the ADB port with a short timeout (adb connect to an unreachable host waits for seconds).
# Open at once: the TV is awake or in light standby. Otherwise it is in deep standby, or the PC's
# network is not up yet right after boot: send WoL every second until the port answers (about 3 minutes).
$tvPort = [int]$TvAddress.Split(':')[1]
function PortOpen {
  $c = New-Object Net.Sockets.TcpClient
  try { $t = $c.ConnectAsync($tvIp, $tvPort); return ($t.Wait(800) -and $c.Connected) } catch { return $false } finally { $c.Close() }
}
$ok = $false; $wolSent = $false
for ($i = 0; $i -lt 180; $i++) {
  if (PortOpen) {
    Adb connect $TvAddress | Out-Null
    $w = Adb -s $TvAddress shell "dumpsys power | grep -o 'mWakefulness=[A-Za-z]*'"
    if ($w -match 'mWakefulness=(\w+)') { $ok = $true; break }
  }
  Wol; $wolSent = $true
  Start-Sleep -Milliseconds 200
}
Log "TV reachable after $i probe(s)"
if (-not $ok) { Log "TV not reachable"; Adb kill-server | Out-Null; exit 1 }

$state = $matches[1]
# Woken by our WoL just now? (TCL logs the resume reason as mWakeupTypeWOW)
$wokeByWol = $false
if ($wolSent -and $state -eq 'Awake') {
  $info = "$(Adb -s $TvAddress shell "logcat -d | grep -E 'mWakeupType' | tail -1; dumpsys power | grep -o 'mLastWakeTime=[0-9]* ([0-9]* ms ago)'")"
  if ($info -match 'mWakeupTypeWOW' -and $info -match '\((\d+) ms ago\)' -and [int64]$matches[1] -lt 180000) {
    $wokeByWol = $true
    Start-Sleep 4   # let the TV bring its last screen back before reading the input
  }
}
# Input on screen: HDMI ports report their hardware id, the Google TV home/apps report another id.
# While asleep the TV reports the launcher's id, so use what tvwatch.sh recorded when the TV went to standby
# (falling back to the TV's last-used tuner/HDMI input if the watcher was not running then).
if ($state -eq 'Awake') {
  $lastInput = "$(Adb -s $TvAddress shell 'settings get secure tcl_sys_tv_input_current_device_id')".Trim()
} else {
  $lastInput = "$(Adb -s $TvAddress shell 'cat /data/local/tmp/tvwatch.input 2>/dev/null || settings get secure tcl_sys_tv_input_last_device_id')".Trim()
}
Log "TV state: $state, input: $lastInput$(if ($wokeByWol) { ' (woken by WoL)' })"

# Start the watcher first so it sees the SignalLock that follows the wake-up.
# Replace it when the copy on the TV differs from this one (after an update).
$localHash = (Get-FileHash "$PSScriptRoot\tvwatch.sh" -Algorithm MD5).Hash.ToLower()
$tvHash = "$(Adb -s $TvAddress shell 'md5sum /data/local/tmp/tvwatch.sh 2>/dev/null')".Split(' ')[0]
$running = Adb -s $TvAddress shell "ps -A -o ARGS | grep -c '^sh /data/local/tmp/tvwatch.sh'"
if ("$running".Trim() -ne '0' -and $tvHash -ne $localHash) {
  # [t]vwatch / [l]ogcat: the patterns do not match this pkill's own command line
  Adb -s $TvAddress shell "pkill -f '[t]vwatch.sh'; pkill -f '[l]ogcat -T 1 -s VCodecHdmi'" | Out-Null
  $running = '0'
  Log "tvwatch outdated, restarting"
}
if ("$running".Trim() -eq '0') {
  Adb -s $TvAddress push "$PSScriptRoot\tvwatch.sh" /data/local/tmp/tvwatch.sh | Out-Null
  Adb -s $TvAddress shell "chmod 755 /data/local/tmp/tvwatch.sh; setsid nohup sh /data/local/tmp/tvwatch.sh $HdmiHardwareId $NoSignalDelay >/dev/null 2>&1 </dev/null &" | Out-Null
  Start-Sleep 2
  Log "tvwatch started"
}

# Never change the input: only wake the TV when it will come back on the PC's HDMI port.
# If someone left it on another HDMI port or a Google TV app, leave the TV alone.
if ($wokeByWol -and $lastInput -ne "$HdmiHardwareId") {
  # WoL had to wake it to reach it, but it was on something else: put it back to standby
  Adb -s $TvAddress shell "input keyevent KEYCODE_SLEEP" | Out-Null
  Log "done: woken by WoL onto HW$lastInput, put back to standby"
} elseif ($lastInput -ne "$HdmiHardwareId") {
  Log "done: last input is not HW$HdmiHardwareId, TV left as is"
} elseif ($state -ne 'Awake') {
  Adb -s $TvAddress shell "input keyevent KEYCODE_WAKEUP" | Out-Null
  Log "done: woke TV on HW$HdmiHardwareId"
} else {
  Log "done: TV on HW$HdmiHardwareId$(if ($wokeByWol) { ' (woken by WoL)' } else { ' already' })"
}
Adb kill-server | Out-Null
