############################################################ DO NOT CHANGE START ############################################################
##Open TLS

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

############################################################ DO NOT CHANGE END ############################################################

Write-Host $env:NINJA_LOCATION_NAME

$VPN_PROFILE = $null;

$location = $env:NINJA_LOCATION_NAME
# Testing
#$location = "Computers - PCT"

$locations = @{
    "Computers - _Deployment"  = "QTS"
    "Computers - PCT"          = "PCT"
    "Computers - KRN"          = "PCT"
    "Computers - PRV"          = "PCT"
    "Computers - PCN"          = "PCT"
    "Computers - PCL"          = "PCT"
    "Computers - PRF"          = "PCT"
    "Computers - UKG"          = "PCT"
    "Computers - MCG"          = "PCT"
    "Computers - MCM"          = "PCT"
    "Computers - PCTMGT"       = "PCT"
    "Computers - ACU"          = "ACU"
    "Computers - ANG"          = "QTS"
    "Computers - ASI"          = "ASI"
    "Computers - BTC"          = "QTS"
    "Computers - CAP"          = "CAP"
    "Computers - CAW"          = "QTS"
    "Computers - CBS"          = "QTS"
    "Computers - CCC"          = "QTS"
    "Computers - EMS"          = "QTS"
    "Computers - GMH"          = "QTS"
    "Computers - HAR"          = "HAR"
    "Computers - HDG"          = "HDG"
    "Computers - HIH"          = "HIH"
    "Computers - HMR"          = "QTS"
    "Computers - ICM"          = "ICM"
    "Computers - INR"          = "INR"
    "Computers - MCP"          = "MCP"
    "Computers - MCS"          = "QTS"
    "Computers - PCU"          = "PCU"
    "Computers - PMC"          = "QTS"
    "Computers - ROC"          = "ROC"
    "Computers - SAL/GLC"      = "SAL"
    "Computers - SEN"          = "QTS"
    "Computers - SHC"          = "SHC"
    "Computers - SPT"          = "SPT"
    "Computers - TRO"          = "TRO"
    "Computers - Test"         = "QTS"
    "Computers - VNO"          = "VNO"
    "Computers - VOA"          = "VOA"
    "Computers - VOA 3447 NHC" = "VOA"
    "Computers - VPR"          = "QTS"
    "VDI - PCT"                = "PCT"
    "VDI - PCTMGT"             = "PCT"
    "VDI - PCL"                = "PCT"
    "VDI - PCN"                = "PCT"
    "VDI - PRV"                = "PCT"
    "VDI - PRF"                = "PCT"
}

$VPN_PROFILE = $locations[$location];
Write-Host $VPN_PROFILE

# Define the registry path
$regPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels"

# Check and create the registry path if it does not exist
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
    Write-Output "Created the registry path: $regPath."
}
else {
    Write-Output "Registry path $regPath already exists."
}

if ($null -ne $VPN_PROFILE) {
    # Create folder if it doesn't exist
    if (-not (Test-Path "C:\TempDeploy\FortiClientVPN")) {
        New-Item -ItemType Directory -Path "C:\TempDeploy\FortiClientVPN" | Out-Null
    }

    Start-Sleep -Seconds 5
    $ProgressPreference = 'SilentlyContinue'

    # Download config file
    Invoke-WebRequest -UseBasicParsing -Uri "https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/FortiClient/Configuration-Files/7.2/$($VPN_PROFILE).conf" `
        -OutFile "C:\TempDeploy\FortiClientVPN\VPN.conf" -ErrorAction Continue
    Start-Sleep -Seconds 5

    # Stop forticlient.exe if running
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'forti*' } | Stop-Process -Force
    Start-Sleep -Seconds 5

    # Execute import
    Start-Process -FilePath "C:\Program Files\Fortinet\FortiClient\FCConfig.exe" -ArgumentList '-m all -f "C:\TempDeploy\FortiClientVPN\VPN.conf" -o import -i 1 -q' -Wait

}
else {
    # If location doesn't match any key in $locations, still create folder
    if (-not (Test-Path "C:\TempDeploy\FortiClientVPN")) {
        New-Item -ItemType Directory -Path "C:\TempDeploy\FortiClientVPN" | Out-Null
    }

    # Download config file
    Invoke-WebRequest -UseBasicParsing -Uri "https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/FortiClient/Configuration-Files/7.2/QTS.conf" `
        -OutFile "C:\TempDeploy\FortiClientVPN\VPN.conf" -ErrorAction Continue
    Start-Sleep -Seconds 5

    # Execute import
    Start-Process -FilePath "C:\Program Files\Fortinet\FortiClient\FCConfig.exe" -ArgumentList '-m all -f "C:\TempDeploy\FortiClientVPN\VPN.conf" -o import -i 1 -q' -Wait

    $ProgressPreference = 'SilentlyContinue'

    Write-Host "Location not found, QTS configuration used.";
}

############################################################ DO NOT CHANGE START ############################################################

Start-Sleep -Seconds 20

# Define the registry path
$regPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels"

# Check and create the registry path if it does not exist
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
    Write-Output "Created the registry path: $regPath."
}
else {
    Write-Output "Registry path $regPath already exists."
}

# Initialize the variable to store the VPN profiles
$vpnprofiles = @()

# Check if the registry path has subkeys
$subKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
if ($subKeys -and $subKeys.Count -gt 0) {
    Write-Output "There are keys within ${regPath}:"
    $subKeys | ForEach-Object {
        $vpnprofiles += $_.PSChildName
        Write-Output $_.PSChildName
    }
}
else {
    Write-Output "There are no keys within ${regPath}."
    Ninja-Property-Set vpnProfiles "No Profiles"
}

# Output the VPN profiles variable for verification
Write-Output "VPN profiles:"

Ninja-Property-Set vpnProfiles $vpnprofiles

############################################################ DO NOT CHANGE END ############################################################
