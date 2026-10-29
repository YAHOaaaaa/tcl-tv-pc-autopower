# Removes the scheduled task and stops tvwatch.sh on the TV. Run from an elevated PowerShell.
. "$PSScriptRoot\config.ps1"
schtasks /delete /tn 'TV-Power-On' /f
& $Adb connect $TvAddress | Out-Null
& $Adb -s $TvAddress shell "for p in `$(ps -A -o PID,ARGS | grep -E 'tvwatch.sh|logcat -T 1 -s VCodecHdmi' | grep -v grep | cut -c1-6); do kill `$p; done; rm -f /data/local/tmp/tvwatch.*"
