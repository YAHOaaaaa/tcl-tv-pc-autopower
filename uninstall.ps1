# Removes the scheduled task and stops tvwatch.sh on the TV. Run from an elevated PowerShell.
. "$PSScriptRoot\config.ps1"
schtasks /delete /tn 'TV-Power-On' /f
& $Adb connect $TvAddress | Out-Null
& $Adb -s $TvAddress shell "pkill -f '[t]vwatch.sh'; pkill -f '[l]ogcat -T 1 -s VCodecHdmi'; rm -f /data/local/tmp/tvwatch.*"
