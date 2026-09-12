#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Downloads and installs FortiClient-VPN-7.4 using data from Software-Versions.json
    
.DESCRIPTION
    This script downloads and installs FortiClient-VPN-7.4 following these steps:
    1. Checks if FortiClient-VPN-7.4 is already installed and compares version
    2. Downloads the installer from specified URLs
    3. Verifies download using hash or file size
    4. Kills specified processes if provided
    5. Installs FortiClient-VPN-7.4 with specified arguments
    6. Verifies installation success
    7. Cleans up download directory on success
#>

# Set error action preference
$ErrorActionPreference = "Stop"

# Configure TLS for better compatibility
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls

iex (New-Object Net.WebClient).DownloadString('https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/FortiClient/FortiClient-VPN-7.4-Install-Reboot_Yes.ps1')

iex (New-Object Net.WebClient).DownloadString('https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/FortiClient/FortiClient-VPN-7.4-Profiles.ps1')

# Start-Sleep -Seconds 10

# shutdown /r /t 120 /f