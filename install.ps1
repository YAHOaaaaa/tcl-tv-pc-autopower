# Registers the "TV-Power-On" scheduled task (runs tv_on.ps1 as SYSTEM at boot, logon and resume)
# and runs it once. Run from an elevated PowerShell.
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this from an elevated (Administrator) PowerShell.'
}
if (-not (Test-Path "$PSScriptRoot\config.ps1")) { throw 'Create config.ps1 from config.example.ps1 first.' }

# tvwatch.sh runs under the TV's sh: make sure it has LF line endings
$sh = "$PSScriptRoot\tvwatch.sh"
[IO.File]::WriteAllText($sh, ([IO.File]::ReadAllText($sh) -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))

$script = "$PSScriptRoot\tv_on.ps1"
$event = { param($provider, $id) "&lt;QueryList&gt;&lt;Query Id=`"0`" Path=`"System`"&gt;&lt;Select Path=`"System`"&gt;*[System[Provider[@Name='$provider'] and EventID=$id]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;" }
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Wake the TCL TV over ADB and switch to the PC's HDMI input ($script)</Description></RegistrationInfo>
  <Triggers>
    <BootTrigger><Enabled>true</Enabled></BootTrigger>
    <LogonTrigger><Enabled>true</Enabled></LogonTrigger>
    <EventTrigger><Enabled>true</Enabled><Subscription>$(& $event 'Microsoft-Windows-Power-Troubleshooter' 1)</Subscription></EventTrigger>
    <EventTrigger><Enabled>true</Enabled><Subscription>$(& $event 'Microsoft-Windows-Kernel-General' 12)</Subscription></EventTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec><Command>powershell.exe</Command><Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$script"</Arguments></Exec>
  </Actions>
</Task>
"@
$tmp = Join-Path $env:TEMP 'TV-Power-On.xml'
[IO.File]::WriteAllText($tmp, $xml, [Text.Encoding]::Unicode)
schtasks /create /tn 'TV-Power-On' /xml $tmp /f
Remove-Item $tmp
schtasks /run /tn 'TV-Power-On'
