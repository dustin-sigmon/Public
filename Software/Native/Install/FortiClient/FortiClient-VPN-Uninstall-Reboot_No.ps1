taskkill -im forti* /f
$forticlient = Get-CimInstance Win32_Product | Where-Object {$_.Name -like "FortiClient*"}
msiexec /uninstall $forticlient.IdentifyingNumber /quiet /norestart