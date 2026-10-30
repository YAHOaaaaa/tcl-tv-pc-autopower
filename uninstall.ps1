# Removes the scheduled task, stops tvwatch.sh on the TV and deletes the installed files.
# Run from an elevated PowerShell.
param([string]$InstallDir = (Join-Path $env:ProgramFiles 'tcl-tv-pc-autopower'))
. "$PSScriptRoot\config.ps1"
schtasks /delete /tn 'TV-Power-On' /f
& $Adb connect $TvAddress | Out-Null
& $Adb -s $TvAddress shell "pkill -f '[t]vwatch.sh'; pkill -f '[l]ogcat -T 1 -s VCodecHdmi'; rm -f /data/local/tmp/tvwatch.*"
& (Join-Path $InstallDir 'platform-tools\adb.exe') -P 5039 kill-server 2>$null
Remove-Item -Recurse -Force $InstallDir, (Join-Path $env:ProgramData 'tcl-tv-pc-autopower') -ErrorAction SilentlyContinue
