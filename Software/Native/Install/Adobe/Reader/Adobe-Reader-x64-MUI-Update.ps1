#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Downloads and installs Adobe-Reader-x64-MUI-Update using data from Software-Versions.json
    
.DESCRIPTION
    This script downloads and installs Adobe-Reader-x64-MUI-Update following these steps:
    1. Checks if Adobe-Reader-x64-MUI-Update is already installed and compares version
    2. Downloads the installer from specified URLs
    3. Verifies download using hash or file size
    4. Kills specified processes if provided
    5. Installs Adobe-Reader-x64-MUI-Update with specified arguments
    6. Verifies installation success
    7. Cleans up download directory on success
#>

# Set error action preference
$ErrorActionPreference = "Stop"

# Debug flags - set to $true to disable
$DisableInstall = $false
$DisableCleanup = $false
$DisableReDownload = $false

# Software configuration
$SoftwareName = "Adobe-Reader-x64-MUI-Update"
$JsonUrls = @(
    "https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/_Main/Software-Versions.json",
    "https://source-west-scripts.s3.us-west-or.io.cloud.ovh.us/_Software/_Main/Software-Versions.json"
)

# Configure TLS for better compatibility - Windows 11 specific fixes
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls

# Additional Windows 11 compatibility settings
[Net.ServicePointManager]::CheckCertificateRevocationList = $false
[Net.ServicePointManager]::Expect100Continue = $false
[Net.ServicePointManager]::UseNagleAlgorithm = $false

# Force .NET to use TLS 1.2 for better Windows 11 compatibility
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to apply Windows 11 specific TLS fixes
function Set-Windows11TLSCompatibility {
    try {
        $osVersion = [System.Environment]::OSVersion.Version
        $isWindows11 = $osVersion.Major -eq 10 -and $osVersion.Build -ge 22000
        
        if ($isWindows11) {
            Write-ColorOutput "Detected Windows 11 - applying additional TLS compatibility fixes..." "Yellow"
            
            # Additional Windows 11 specific TLS settings
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false
            [System.Net.ServicePointManager]::Expect100Continue = $false
            [System.Net.ServicePointManager]::UseNagleAlgorithm = $false
            
            # Set cipher suite preferences for Windows 11
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Cryptography\Configuration\Local\SSL\00010002"
                if (Test-Path $regPath) {
                    Set-ItemProperty -Path $regPath -Name "Functions" -Value "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256" -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-ColorOutput "Could not set cipher suite preferences (non-critical): $($_.Exception.Message)" "Yellow"
            }
            
            Write-ColorOutput "Windows 11 TLS compatibility fixes applied" "Green"
        }
        else {
            Write-ColorOutput "Not Windows 11 - using standard TLS configuration" "White"
        }
    }
    catch {
        Write-ColorOutput "Error applying Windows 11 TLS fixes: $($_.Exception.Message)" "Yellow"
    }
}

# Function to check if software is installed and get version
function Get-InstalledSoftwareVersion {
    param([object]$SoftwareConfig)
    
    try {
        # Get registry pattern from JSON configuration
        $RegistryPattern = $SoftwareConfig.registry
        
        # Use the registry pattern provided from JSON
        if ([string]::IsNullOrWhiteSpace($RegistryPattern)) {
            Write-ColorOutput "No registry pattern provided from JSON - cannot check installed software" "Yellow"
            return $null
        }
        
        # Check registry for installed software
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($path in $registryPaths) {
            $installed = Get-ItemProperty $path | Where-Object { 
                Invoke-Expression $RegistryPattern 
            } | Select-Object DisplayName, DisplayVersion
            
            if ($installed) {
                return $installed.DisplayVersion
            }
        }
        
        return $null
    }
    catch {
        Write-ColorOutput "Error checking installed software: $($_.Exception.Message)" "Red"
        return $null
    }
}

# Function to compare versions
function Compare-Versions {
    param(
        [string]$InstalledVersion,
        [string]$RequiredVersion
    )
    
    try {
        $installed = [System.Version]::Parse($InstalledVersion)
        $required = [System.Version]::Parse($RequiredVersion)
        
        return $installed -lt $required
    }
    catch {
        Write-ColorOutput "Error comparing versions: $($_.Exception.Message)" "Red"
        return $true # Assume update needed if version comparison fails
    }
}

# Function to calculate file hash
function Get-FileHashValue {
    param([string]$FilePath)
    
    try {
        # Check if file exists first
        if (-not (Test-Path $FilePath)) {
            Write-ColorOutput "Error calculating file hash: File does not exist: $FilePath" "Red"
            return $null
        }
        
        # Get file info for debugging
        $fileInfo = Get-Item -Path $FilePath -ErrorAction SilentlyContinue
        if (-not $fileInfo) {
            Write-ColorOutput "Error calculating file hash: Cannot get file info for: $FilePath" "Red"
            return $null
        }
        
        Write-ColorOutput "Calculating hash for file: $FilePath (Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB)" "Cyan"
        
        # Try to calculate hash with error handling
        try {
            $hash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop
            
            # Check if hash object is null
            if ($null -eq $hash) {
                Write-ColorOutput "Error calculating file hash: Get-FileHash returned null" "Red"
                return $null
            }
            
            # Check if Hash property exists and is not null
            if ($hash.PSObject.Properties.Name -contains "Hash" -and $null -ne $hash.Hash) {
                return $hash.Hash.ToUpper()
            }
            else {
                Write-ColorOutput "Error calculating file hash: Hash property is null or missing" "Red"
                Write-ColorOutput "Hash object properties: $($hash.PSObject.Properties.Name -join ', ')" "Red"
                return $null
            }
        }
        catch {
            Write-ColorOutput "Error calculating file hash with Get-FileHash: $($_.Exception.Message)" "Red"
            return $null
        }
    }
    catch {
        Write-ColorOutput "Error calculating file hash: $($_.Exception.Message)" "Red"
        return $null
    }
}

# Function to get file size in MB
function Get-FileSizeMB {
    param([string]$FilePath)
    
    try {
        $file = Get-Item -Path $FilePath
        return [math]::Round($file.Length / 1MB, 2)
    }
    catch {
        Write-ColorOutput "Error getting file size: $($_.Exception.Message)" "Red"
        return $null
    }
}

# Function to kill software processes
function Stop-SoftwareProcesses {
    param([string]$ProcessNames)
    
    if ([string]::IsNullOrWhiteSpace($ProcessNames)) {
        return
    }
    
    try {
        $processList = $ProcessNames.Split(',') | ForEach-Object { $_.Trim("'") }
        
        foreach ($process in $processList) {
            $runningProcesses = Get-Process -Name $process -ErrorAction SilentlyContinue
            if ($runningProcesses) {
                Write-ColorOutput "Stopping software process: $process" "Yellow"
                Stop-Process -Name $process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
    }
    catch {
        Write-ColorOutput "Error stopping software processes: $($_.Exception.Message)" "Red"
    }
}

# Function to test URL connectivity with Windows 11 compatibility
function Test-UrlConnectivity {
    param([string]$Url)
    
    try {
        # Method 1: Try with Invoke-WebRequest
        try {
            $webRequestParams = @{
                Uri             = $Url
                Method          = 'Head'
                UseBasicParsing = $true
                TimeoutSec      = 30
                Headers         = @{
                    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            }
            $response = Invoke-WebRequest @webRequestParams
            return $response.StatusCode -eq 200
        }
        catch {
            Write-ColorOutput "Invoke-WebRequest connectivity test failed for $Url : $($_.Exception.Message)" "Yellow"
            
            # Method 2: Try with WebClient
            try {
                $webClient = New-Object System.Net.WebClient
                $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                # Note: WebClient doesn't have a Timeout property, using default timeout
                
                # Try to download just a small portion
                $webClient.DownloadString($Url) | Out-Null
                return $true
            }
            catch {
                Write-ColorOutput "WebClient connectivity test also failed for $Url : $($_.Exception.Message)" "Yellow"
                return $false
            }
        }
    }
    catch {
        Write-ColorOutput "All connectivity tests failed for $Url : $($_.Exception.Message)" "Yellow"
        return $false
    }
}

# Function to download using curl as fallback
function Download-WithCurl {
    param([string]$Url, [string]$OutputPath)
    
    try {
        # Check if curl is available
        $curlPath = Get-Command curl -ErrorAction SilentlyContinue
        if ($curlPath) {
            Write-ColorOutput "Attempting download with curl..." "Yellow"
            & curl.exe --location --output $OutputPath $Url
            return Test-Path $OutputPath
        }
        return $false
    }
    catch {
        Write-ColorOutput "Curl download failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Function to verify software installation
function Test-SoftwareInstallationSuccess {
    param([string]$RegistryPattern)
    
    try {
        if ([string]::IsNullOrWhiteSpace($RegistryPattern)) {
            return $true
        }
        
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($path in $registryPaths) {
            $installed = Get-ItemProperty $path | Where-Object { 
                Invoke-Expression $RegistryPattern 
            }
            
            if ($installed) {
                return $true
            }
        }
        
        return $false
    }
    catch {
        Write-ColorOutput "Error verifying software installation: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Main script execution
try {
    Write-ColorOutput "=== Adobe-Reader-x64-MUI-Update Installation Script ===" "Cyan"
    
    # Apply Windows 11 specific TLS compatibility fixes
    Set-Windows11TLSCompatibility
    if ($DisableInstall) {
        Write-ColorOutput "MODE: DRY-RUN (No actual installation will be performed)" "Yellow"
    }
    else {
        Write-ColorOutput "MODE: INSTALLATION (Actual installation will be performed)" "Green"
    }
    
    # Display debug flags
    if ($DisableCleanup) {
        Write-ColorOutput "DEBUG: Cleanup disabled - files will be left in download directory" "Yellow"
    }
    if ($DisableReDownload) {
        Write-ColorOutput "DEBUG: Re-download disabled - will use existing file if present" "Yellow"
    }
    
    Write-ColorOutput "Starting Adobe-Reader-x64-MUI-Update installation process..." "White"
    
    # Load JSON data from online source with fallback URLs
    Write-ColorOutput "Loading software configuration from online JSON..." "White"
    $jsonContent = $null
    $jsonLoaded = $false
    
    # Test connectivity to JSON URLs first
    Write-ColorOutput "Testing connectivity to JSON URLs..." "White"
    $availableUrls = @()
    foreach ($jsonUrl in $JsonUrls) {
        if (Test-UrlConnectivity -Url $jsonUrl) {
            Write-ColorOutput "✓ Connectivity test passed for: $jsonUrl" "Green"
            $availableUrls += $jsonUrl
        }
        else {
            Write-ColorOutput "✗ Connectivity test failed for: $jsonUrl" "Red"
        }
    }
    
    if ($availableUrls.Count -eq 0) {
        Write-ColorOutput "Warning: All JSON URLs failed connectivity tests, but will still attempt to load..." "Yellow"
        $availableUrls = $JsonUrls
    }
    else {
        Write-ColorOutput "Found $($availableUrls.Count) accessible JSON URL(s)" "Green"
    }
    
    foreach ($jsonUrl in $availableUrls) {
        try {
            Write-ColorOutput "Attempting to load JSON from: $jsonUrl" "White"
            
            # Method 1: Try Invoke-RestMethod with enhanced parameters for Windows 11
            try {
                $webRequestParams = @{
                    Uri             = $jsonUrl
                    UseBasicParsing = $true
                    TimeoutSec      = 60
                    Headers         = @{
                        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
                        'Accept'     = 'application/json, text/plain, */*'
                        'Accept-Encoding' = 'gzip, deflate, br'
                        'Accept-Language' = 'en-US,en;q=0.9'
                    }
                }
                $jsonContent = Invoke-RestMethod @webRequestParams
                Write-ColorOutput "Successfully loaded JSON configuration from: $jsonUrl" "Green"
                $jsonLoaded = $true
                break
            }
            catch {
                Write-ColorOutput "Invoke-RestMethod failed, trying alternative method..." "Yellow"
                
                # Method 2: Try with WebClient for Windows 11 compatibility
                try {
                    $webClient = New-Object System.Net.WebClient
                    $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                    $webClient.Headers.Add("Accept", "application/json, text/plain, */*")
                    # Note: WebClient doesn't have a Timeout property, using default timeout
                    
                    $jsonString = $webClient.DownloadString($jsonUrl)
                    try {
                        $jsonContent = $jsonString | ConvertFrom-Json
                        Write-ColorOutput "Successfully loaded JSON configuration using WebClient from: $jsonUrl" "Green"
                        $jsonLoaded = $true
                        break
                    }
                    catch {
                        Write-ColorOutput "Failed to parse JSON from WebClient download: $($_.Exception.Message)" "Red"
                        Write-ColorOutput "JSON content preview: $($jsonString.Substring(0, [Math]::Min(200, $jsonString.Length)))..." "Yellow"
                    }
                }
                catch {
                    Write-ColorOutput "WebClient method also failed, trying curl fallback..." "Yellow"
                    
                    # Method 3: Try curl as final fallback
                    try {
                        $curlPath = Get-Command curl -ErrorAction SilentlyContinue
                        if ($curlPath) {
                            Write-ColorOutput "Attempting to download JSON with curl..." "Yellow"
                            $tempJsonFile = [System.IO.Path]::GetTempFileName()
                            
                            $curlArgs = @(
                                "--location"
                                "--silent"
                                "--show-error"
                                "--fail"
                                "--connect-timeout", "30"
                                "--max-time", "60"
                                "--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                                "--output", $tempJsonFile
                                $jsonUrl
                            )
                            
                            $curlProcess = Start-Process -FilePath "curl.exe" -ArgumentList $curlArgs -Wait -PassThru -NoNewWindow
                            
                            if ($curlProcess.ExitCode -eq 0 -and (Test-Path $tempJsonFile)) {
                                $jsonString = Get-Content -Path $tempJsonFile -Raw
                                try {
                                    $jsonContent = $jsonString | ConvertFrom-Json
                                    Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
                                    Write-ColorOutput "Successfully loaded JSON configuration using curl from: $jsonUrl" "Green"
                                    $jsonLoaded = $true
                                    break
                                }
                                catch {
                                    Write-ColorOutput "Failed to parse JSON from curl download: $($_.Exception.Message)" "Red"
                                    Write-ColorOutput "JSON content preview: $($jsonString.Substring(0, [Math]::Min(200, $jsonString.Length)))..." "Yellow"
                                    if (Test-Path $tempJsonFile) {
                                        Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
                                    }
                                }
                            }
                            else {
                                Write-ColorOutput "Curl download failed with exit code: $($curlProcess.ExitCode)" "Red"
                                if (Test-Path $tempJsonFile) {
                                    Remove-Item -Path $tempJsonFile -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    }
                    catch {
                        Write-ColorOutput "Curl fallback also failed: $($_.Exception.Message)" "Red"
                    }
                }
            }
        }
        catch {
            Write-ColorOutput "All methods failed for $jsonUrl : $($_.Exception.Message)" "Yellow"
            continue
        }
    }
    
    if (-not $jsonLoaded) {
        throw "Failed to load JSON configuration from all URLs: $($JsonUrls -join ', ')"
    }
    
    # Debug: Show JSON structure and available keys
    Write-ColorOutput "JSON loaded successfully. Available software keys:" "Cyan"
    if ($jsonContent -is [PSCustomObject]) {
        $availableKeys = $jsonContent.PSObject.Properties.Name
        foreach ($key in $availableKeys) {
            Write-ColorOutput "  - $key" "Cyan"
        }
    }
    else {
        Write-ColorOutput "  JSON content type: $($jsonContent.GetType().Name)" "Cyan"
    }
    
    Write-ColorOutput "Looking for software configuration key: '$SoftwareName'" "Cyan"
    
    # Get software configuration
    $softwareConfig = $jsonContent.$SoftwareName
    if (-not $softwareConfig) {
        # Try case-insensitive search
        Write-ColorOutput "Exact match not found, trying case-insensitive search..." "Yellow"
        $availableKeys = $jsonContent.PSObject.Properties.Name
        $matchingKey = $availableKeys | Where-Object { $_ -like "*$SoftwareName*" -or $SoftwareName -like "*$_*" }
        
        if ($matchingKey) {
            Write-ColorOutput "Found similar key: '$matchingKey'" "Yellow"
            $softwareConfig = $jsonContent.$matchingKey
        }
        else {
            Write-ColorOutput "No matching software configuration found in JSON" "Red"
            Write-ColorOutput "Available keys: $($availableKeys -join ', ')" "Red"
            throw "Software configuration not found in JSON. Looking for: '$SoftwareName'. Available keys: $($availableKeys -join ', ')"
        }
    }
    
    Write-ColorOutput "Software: $($SoftwareName)" "Green"
    Write-ColorOutput "Required Version: $($softwareConfig.version)" "Green"
    Write-ColorOutput "Publisher: $($softwareConfig.publisher)" "Green"
    
    # Check if software is already installed
    Write-ColorOutput "Checking if Adobe-Reader-x64-MUI-Update is already installed..." "White"
    $installedVersion = Get-InstalledSoftwareVersion -SoftwareConfig $softwareConfig
    
    if ($installedVersion) {
        Write-ColorOutput "Installed Version: $installedVersion" "Yellow"
        
        $needsUpdate = Compare-Versions -InstalledVersion $installedVersion -RequiredVersion $softwareConfig.version
        
        if (-not $needsUpdate) {
            Write-ColorOutput "Adobe-Reader-x64-MUI-Update is already up to date. No installation needed." "Green"
            return 0
        }
        else {
            Write-ColorOutput "Update required. Proceeding with installation..." "Yellow"
        }
    }
    else {
        Write-ColorOutput "Adobe-Reader-x64-MUI-Update not found. Proceeding with installation..." "Yellow"
    }
    
    # Create download directory
    $downloadDir = "C:\TempDeploy\$($SoftwareName)"
    Write-ColorOutput "Creating download directory: $downloadDir" "White"
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $downloadDir)) {
        New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        Write-ColorOutput "Created directory: $downloadDir" "Green"
    }
    else {
        Write-ColorOutput "Directory already exists: $downloadDir" "Yellow"
    }
    
    # Prepare download variables
    $publisherName = $softwareConfig.publisher
    
    # Handle version conversion for Adobe-Reader-x64-MUI-Update (remove decimal point)
    $versionConverted = $softwareConfig.version_converted
    if ([string]::IsNullOrWhiteSpace($versionConverted)) {
        $versionConverted = $softwareConfig.version -replace '\.', ''
    }
    
    $downloadFile = $softwareConfig.file -replace '\$\{SoftwareVersionConverted\}', $versionConverted -replace '\$\{SoftwareVersion\}', $softwareConfig.version
    $downloadUrls = $softwareConfig.download_urls
    
    Write-ColorOutput "Download File: $downloadFile" "White"
    Write-ColorOutput "Publisher: $publisherName" "White"
    
    # Display the actual URLs that will be used
    Write-ColorOutput "Download URLs to be used:" "White"
    foreach ($url in $downloadUrls) {
        $actualUrl = $url -replace '\$\{PublisherName\}', $publisherName -replace '\$\{SoftwareName\}', $SoftwareName -replace '\$\{DownloadFile\}', $downloadFile -replace '\$\{SoftwareVersionConverted\}', $versionConverted
        Write-ColorOutput "  - $actualUrl" "Cyan"
    }
    
    # Download file
    $downloadPath = Join-Path $downloadDir $downloadFile
    $downloadSuccess = $false
    $maxRetries = 2
    $retryCount = 0
    
    # Check if file already exists and re-download is disabled (debug mode) - PRIORITY CHECK
    if ($DisableReDownload -and (Test-Path $downloadPath)) {
        Write-ColorOutput "DEBUG: Using existing file (debug mode): $downloadPath" "Yellow"
        $fileSize = Get-FileSizeMB -FilePath $downloadPath
        Write-ColorOutput "Existing file size: $fileSize MB" "Yellow"
        $downloadSuccess = $true
    }
    # Check if file already exists and validate its hash (only if debug mode is not enabled)
    elseif (Test-Path $downloadPath) {
        Write-ColorOutput "Existing file found: $downloadPath" "Yellow"
        $fileSize = Get-FileSizeMB -FilePath $downloadPath
        Write-ColorOutput "Existing file size: $fileSize MB" "Yellow"
        
        # Validate existing file hash if available
        if (-not [string]::IsNullOrWhiteSpace($softwareConfig.hash)) {
            Write-ColorOutput "Validating existing file hash..." "White"
            $existingFileHash = Get-FileHashValue -FilePath $downloadPath
            
            if ($existingFileHash -and $existingFileHash -eq $softwareConfig.hash.ToUpper()) {
                Write-ColorOutput "Existing file hash is valid - skipping download" "Green"
                $downloadSuccess = $true
            }
            else {
                Write-ColorOutput "Existing file hash is invalid - will re-download" "Red"
                if ($existingFileHash) {
                    Write-ColorOutput "Expected: $($softwareConfig.hash), Got: $existingFileHash" "Red"
                }
                Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            # If no hash available, check file size
            if (-not [string]::IsNullOrWhiteSpace($softwareConfig.size)) {
                $expectedSize = [double]$softwareConfig.size
                if ($fileSize -ge $expectedSize) {
                    Write-ColorOutput "Existing file size is valid - skipping download" "Green"
                    $downloadSuccess = $true
                }
                else {
                    Write-ColorOutput "Existing file size is invalid - will re-download" "Red"
                    Write-ColorOutput "Expected: >= $expectedSize MB, Got: $fileSize MB" "Red"
                    Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                Write-ColorOutput "No validation criteria available - will re-download" "Yellow"
                Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    while (-not $downloadSuccess -and $retryCount -le $maxRetries) {
        $retryCount++
        Write-ColorOutput "Download attempt $retryCount of $($maxRetries + 1)..." "White"
        
        foreach ($url in $downloadUrls) {
            $downloadUrl = $url -replace '\$\{PublisherName\}', $publisherName -replace '\$\{SoftwareName\}', $SoftwareName -replace '\$\{DownloadFile\}', $downloadFile -replace '\$\{SoftwareVersionConverted\}', $versionConverted
            
            Write-ColorOutput "Attempting download from: $downloadUrl" "White"
            
            # Test connectivity first
            Write-ColorOutput "Testing connectivity to download URL..." "White"
            if (-not (Test-UrlConnectivity -Url $downloadUrl)) {
                Write-ColorOutput "Connectivity test failed, skipping this URL" "Yellow"
                continue
            }
            
            try {
                Write-ColorOutput "Attempting download with TLS configuration..." "White"
                
                # Create web request with additional parameters for better compatibility
                $webRequestParams = @{
                    Uri             = $downloadUrl
                    OutFile         = $downloadPath
                    UseBasicParsing = $true
                    TimeoutSec      = 300
                }
                
                Invoke-WebRequest @webRequestParams
                
                if (Test-Path $downloadPath) {
                    $fileSize = Get-FileSizeMB -FilePath $downloadPath
                    Write-ColorOutput "Download completed successfully (Size: $fileSize MB)" "Green"
                    $downloadSuccess = $true
                    break
                }
            }
            catch {
                $errorDetails = $_.Exception.Message
                if ($_.Exception.InnerException) {
                    $errorDetails += " Inner: $($_.Exception.InnerException.Message)"
                }
                Write-ColorOutput "Download failed from $downloadUrl" "Red"
                Write-ColorOutput "Error details: $errorDetails" "Red"
                
                # Try alternative approach if first fails
                try {
                    Write-ColorOutput "Attempting alternative download method..." "Yellow"
                    $webClient = New-Object System.Net.WebClient
                    
                    # Configure WebClient with TLS settings and headers
                    $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                    $webClient.Headers.Add("Accept", "*/*")
                    $webClient.Headers.Add("Accept-Language", "en-US,en;q=0.9")
                    
                    # Set timeout
                    $webClient.Timeout = 300000  # 5 minutes in milliseconds
                    
                    $webClient.DownloadFile($downloadUrl, $downloadPath)
                    
                    if (Test-Path $downloadPath) {
                        $fileSize = Get-FileSizeMB -FilePath $downloadPath
                        Write-ColorOutput "Alternative download completed successfully (Size: $fileSize MB)" "Green"
                        $downloadSuccess = $true
                        break
                    }
                }
                catch {
                    $webClientError = $_.Exception.Message
                    if ($_.Exception.InnerException) {
                        $webClientError += " Inner: $($_.Exception.InnerException.Message)"
                    }
                    Write-ColorOutput "Alternative download also failed: $webClientError" "Red"
                    
                    # Try curl as final fallback
                    if (Download-WithCurl -Url $downloadUrl -OutputPath $downloadPath) {
                        $fileSize = Get-FileSizeMB -FilePath $downloadPath
                        Write-ColorOutput "Curl download completed successfully (Size: $fileSize MB)" "Green"
                        $downloadSuccess = $true
                        break
                    }
                }
                continue
            }
        }
        
        if (-not $downloadSuccess -and $retryCount -le $maxRetries) {
            Write-ColorOutput "All download URLs failed. Retrying in 5 seconds..." "Yellow"
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $downloadSuccess) {
        throw "Failed to download Adobe-Reader-x64-MUI-Update installer after $($maxRetries + 1) attempts"
    }
    
    # Verify download
    Write-ColorOutput "Verifying download..." "White"
    $verificationPassed = $false
    
    # Check hash if available
    if (-not [string]::IsNullOrWhiteSpace($softwareConfig.hash)) {
        Write-ColorOutput "Verifying file hash..." "White"
        Write-ColorOutput "File path: $downloadPath" "Cyan"
        Write-ColorOutput "Expected hash: $($softwareConfig.hash)" "Cyan"
        
        $fileHash = Get-FileHashValue -FilePath $downloadPath
        
        if ($fileHash -and $fileHash -eq $softwareConfig.hash.ToUpper()) {
            Write-ColorOutput "Hash verification passed" "Green"
            $verificationPassed = $true
        }
        else {
            if ($fileHash) {
                Write-ColorOutput "Hash verification failed. Expected: $($softwareConfig.hash), Got: $fileHash" "Red"
                Write-ColorOutput "Hash comparison: '$($softwareConfig.hash.ToUpper())' vs '$fileHash'" "Red"
            }
            else {
                Write-ColorOutput "Hash verification failed. Could not calculate file hash." "Red"
            }
            
            # Check if debug mode is enabled - if so, skip retry
            if ($DisableReDownload) {
                Write-ColorOutput "DEBUG: Hash verification failed but re-download is disabled - proceeding with existing file" "Yellow"
                $verificationPassed = $true
            }
            # Retry download if hash doesn't match (only if debug mode is not enabled)
            elseif ($retryCount -lt $maxRetries) {
                Write-ColorOutput "Retrying download due to hash mismatch..." "Yellow"
                Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
                $downloadSuccess = $false
                $retryCount = 0
                
                while (-not $downloadSuccess -and $retryCount -le $maxRetries) {
                    $retryCount++
                    Write-ColorOutput "Hash retry attempt $retryCount of $($maxRetries + 1)..." "White"
                    
                    foreach ($url in $downloadUrls) {
                        $downloadUrl = $url -replace '\$\{PublisherName\}', $publisherName -replace '\$\{SoftwareName\}', $SoftwareName -replace '\$\{DownloadFile\}', $downloadFile -replace '\$\{SoftwareVersionConverted\}', $versionConverted
                        
                        try {
                            Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
                            
                            if (Test-Path $downloadPath) {
                                $fileHash = Get-FileHashValue -FilePath $downloadPath
                                if ($fileHash -and $fileHash -eq $softwareConfig.hash.ToUpper()) {
                                    Write-ColorOutput "Hash verification passed on retry" "Green"
                                    $verificationPassed = $true
                                    $downloadSuccess = $true
                                    break
                                }
                            }
                        }
                        catch {
                            Write-ColorOutput "Download retry failed from $downloadUrl" "Red"
                            continue
                        }
                    }
                    
                    if (-not $downloadSuccess -and $retryCount -le $maxRetries) {
                        Start-Sleep -Seconds 5
                    }
                }
            }
        }
    }
    # Check file size if hash not available
    elseif (-not [string]::IsNullOrWhiteSpace($softwareConfig.size)) {
        Write-ColorOutput "Verifying file size..." "White"
        $fileSize = Get-FileSizeMB -FilePath $downloadPath
        $expectedSize = [double]$softwareConfig.size
        
        if ($fileSize -ge $expectedSize) {
            Write-ColorOutput "File size verification passed ($fileSize MB >= $expectedSize MB)" "Green"
            $verificationPassed = $true
        }
        else {
            Write-ColorOutput "File size verification failed. Expected: >= $expectedSize MB, Got: $fileSize MB" "Red"
            
            # Check if debug mode is enabled - if so, skip retry
            if ($DisableReDownload) {
                Write-ColorOutput "DEBUG: File size verification failed but re-download is disabled - proceeding with existing file" "Yellow"
                $verificationPassed = $true
            }
            # Retry download if size doesn't match (only if debug mode is not enabled)
            elseif ($retryCount -lt $maxRetries) {
                Write-ColorOutput "Retrying download due to size mismatch..." "Yellow"
                Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
                $downloadSuccess = $false
                $retryCount = 0
                
                while (-not $downloadSuccess -and $retryCount -le $maxRetries) {
                    $retryCount++
                    Write-ColorOutput "Size retry attempt $retryCount of $($maxRetries + 1)..." "White"
                    
                    foreach ($url in $downloadUrls) {
                        $downloadUrl = $url -replace '\$\{PublisherName\}', $publisherName -replace '\$\{SoftwareName\}', $SoftwareName -replace '\$\{DownloadFile\}', $downloadFile -replace '\$\{SoftwareVersionConverted\}', $versionConverted
                        
                        try {
                            Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
                            
                            if (Test-Path $downloadPath) {
                                $fileSize = Get-FileSizeMB -FilePath $downloadPath
                                if ($fileSize -ge $expectedSize) {
                                    Write-ColorOutput "File size verification passed on retry ($fileSize MB >= $expectedSize MB)" "Green"
                                    $verificationPassed = $true
                                    $downloadSuccess = $true
                                    break
                                }
                            }
                        }
                        catch {
                            Write-ColorOutput "Download retry failed from $downloadUrl" "Red"
                            continue
                        }
                    }
                    
                    if (-not $downloadSuccess -and $retryCount -le $maxRetries) {
                        Start-Sleep -Seconds 5
                    }
                }
            }
        }
    }
    else {
        Write-ColorOutput "No hash or size verification available. Proceeding with installation..." "Yellow"
        $verificationPassed = $true
    }
    
    if (-not $verificationPassed) {
        throw "Download verification failed after all retry attempts"
    }
    
    # Kill software processes if specified
    if (-not [string]::IsNullOrWhiteSpace($softwareConfig.processes)) {
        Write-ColorOutput "Killing specified Adobe-Reader-x64-MUI-Update processes..." "White"
        if ($DisableInstall) {
            Write-ColorOutput "[DRY-RUN] Would kill processes: $($softwareConfig.processes)" "Cyan"
        }
        else {
            Stop-SoftwareProcesses -ProcessNames $softwareConfig.processes
        }
    }
    
    # Install software
    Write-ColorOutput "Installing Adobe-Reader-x64-MUI-Update..." "White"
    Write-ColorOutput "Installation arguments: $($softwareConfig.arguments)" "White"

    $installSuccess = $false
    $installRetryCount = 0
    $maxInstallRetries = 2

    while (-not $installSuccess -and $installRetryCount -le $maxInstallRetries) {
        $installRetryCount++
        Write-ColorOutput "Installation attempt $installRetryCount of $($maxInstallRetries + 1)..." "White"
        try {
            if ($DisableInstall) {
                Write-ColorOutput "[DRY-RUN] Would install Adobe-Reader-x64-MUI-Update with msiexec /p: $downloadPath $($softwareConfig.arguments)" "Cyan"
                $installSuccess = $true
            }
            else {
                $msiArgs = @("/p", "$downloadPath") + $softwareConfig.arguments.Split(' ')
                $processArgs = @{
                    FilePath     = "msiexec.exe"
                    ArgumentList = $msiArgs
                    Wait         = $true
                    PassThru     = $true
                }
                $installProcess = Start-Process @processArgs
                # Ignore exit code and always check registry for installation success
                Write-ColorOutput "Installer exited with code: $($installProcess.ExitCode) (ignored)" "Yellow"
                $installSuccess = $true
            }
        }
        catch {
            if ($DisableInstall) {
                Write-ColorOutput "[DRY-RUN] Would encounter installation error" "Cyan"
            }
            else {
                Write-ColorOutput "Adobe-Reader-x64-MUI-Update installation error: $($_.Exception.Message)" "Red"
                if ($installRetryCount -le $maxInstallRetries) {
                    Write-ColorOutput "Retrying installation in 10 seconds..." "Yellow"
                    Start-Sleep -Seconds 10
                }
            }
        }
    }
    
    if (-not $installSuccess) {
        Write-ColorOutput "Adobe-Reader-x64-MUI-Update installation failed after $($maxInstallRetries + 1) attempts. Leaving installer in: $downloadDir" "Red"
        throw "Adobe-Reader-x64-MUI-Update installation failed"
    }
    
    # Verify software installation
    Write-ColorOutput "Verifying Adobe-Reader-x64-MUI-Update installation..." "White"
    
    if ($DisableInstall) {
        Write-ColorOutput "[DRY-RUN] Would verify Adobe-Reader-x64-MUI-Update installation" "Cyan"
        
        # Clean up download directory in dry-run mode (unless disabled)
        if (-not $DisableCleanup) {
            Write-ColorOutput "Cleaning up download directory..." "White"
            try {
                Remove-Item -Path $downloadDir -Recurse -Force
                Write-ColorOutput "Download directory cleaned up successfully" "Green"
            }
            catch {
                Write-ColorOutput "Warning: Could not clean up download directory: $($_.Exception.Message)" "Yellow"
            }
        }
        else {
            Write-ColorOutput "DEBUG: Cleanup disabled - leaving files in: $downloadDir" "Yellow"
        }
        
        Write-ColorOutput "=== Adobe-Reader-x64-MUI-Update Installation Completed Successfully (DRY-RUN) ===" "Green"
        return 0
    }
    else {
        $installationVerified = Test-SoftwareInstallationSuccess -RegistryPattern $softwareConfig.registry
        $postInstallVersion = Get-InstalledSoftwareVersion -SoftwareConfig $softwareConfig
        $versionMatch = $false
        if ($installationVerified -and $postInstallVersion) {
            if ($postInstallVersion -eq $softwareConfig.version) {
                $versionMatch = $true
            } else {
                Write-ColorOutput "Post-install version mismatch. Expected: $($softwareConfig.version), Found: $postInstallVersion" "Red"
            }
        }
        if ($installationVerified -and $versionMatch) {
            Write-ColorOutput "Adobe-Reader-x64-MUI-Update installation and version verification successful" "Green"
            # Clean up download directory (unless disabled)
            if (-not $DisableCleanup) {
                Write-ColorOutput "Cleaning up download directory..." "White"
                try {
                    Remove-Item -Path $downloadDir -Recurse -Force
                    Write-ColorOutput "Download directory cleaned up successfully" "Green"
                }
                catch {
                    Write-ColorOutput "Warning: Could not clean up download directory: $($_.Exception.Message)" "Yellow"
                }
            }
            else {
                Write-ColorOutput "DEBUG: Cleanup disabled - leaving files in: $downloadDir" "Yellow"
            }
            Write-ColorOutput "=== Adobe-Reader-x64-MUI-Update Installation Completed Successfully ===" "Green"
            return 0
        } else {
            Write-ColorOutput "Adobe-Reader-x64-MUI-Update installation or version verification failed" "Red"
            Write-ColorOutput "Leaving installer in: $downloadDir" "Yellow"
            throw "Adobe-Reader-x64-MUI-Update installation or version verification failed"
        }
    }
}
catch {
    Write-ColorOutput "=== Adobe-Reader-x64-MUI-Update Installation Failed ===" "Red"
    Write-ColorOutput "Error: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" "Red"
    return 1
}