# Copy this file to config.ps1 and fill in your values.
# tv_on.ps1 runs as SYSTEM, so every path here must be absolute (no $env:USERPROFILE).

# adb.exe from Android SDK Platform-Tools
$Adb = 'C:\platform-tools\adb.exe'

# TV IP address and ADB port (Settings > System > Developer options > Network debugging)
$TvAddress = '192.168.0.100:5555'

# TV MAC address for Wake-on-LAN (optional, '' to skip)
$TvMac = 'AA-BB-CC-DD-EE-FF'

# Private key of the adb client the TV has already authorized (the user who ran "adb connect" first)
$AdbKey = 'C:\Users\YOUR_NAME\.android\adbkey'

# TV input hardware id of the HDMI port the PC is on (TCL: HDMI1=15, HDMI2=16, HDMI3=17, HDMI4=18)
$HdmiHardwareId = 15

# Seconds without PC signal before the TV goes to standby
$NoSignalDelay = 20
