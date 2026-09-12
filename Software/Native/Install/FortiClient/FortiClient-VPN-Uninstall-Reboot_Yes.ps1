$fortiProcesses = Get-Process | Where-Object { $_.ProcessName -like "forti*" }
if ($fortiProcesses) {
    $fortiProcesses | Stop-Process -Force
}
# ...existing code...
$forticlient = Get-CimInstance Win32_Product | Where-Object {$_.Name -like "FortiClient*"}
msiexec /uninstall $forticlient.IdentifyingNumber /quiet /norestart
cmd.exe /c Shutdown /r /d p:0:0 /f /t 300 /c "FortiClient uninstall complete. System will reboot in 5 minutes."