[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
mkdir "C:\TempDeploy\Adobe-Flash-Player-Uninstaller"
Invoke-WebRequest -UseBasicParsing -Uri "https://source-east.s3.us-east-va.io.cloud.ovh.us/_Software/Adobe-Flash-Player-Uninstaller/uninstall_flash_player.exe" -OutFile "C:\TempDeploy\Adobe-Flash-Player-Uninstaller\uninstall_flash_player.exe"
Set-Location "C:\TempDeploy\Adobe-Flash-Player-Uninstaller"
.\uninstall_flash_player.exe -uninstall
cmd.exe Shutdown /r /f /t 120