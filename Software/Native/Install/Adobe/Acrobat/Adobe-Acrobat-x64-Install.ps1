#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Downloads and installs Adobe Acrobat using a Customization Wizard package.
    
.DESCRIPTION
    This script downloads and installs Adobe Acrobat following these steps:
    1. Downloads Adobe-Acrobat-x64-Install zip file.
    2. Extracts AcroPro.zip to C:\TempDeploy\Adobe-Acrobat-x64-Install.
    3. Creates a basic setup.ini file.
    4. Kills Adobe processes.
    5. Uninstalls existing Adobe Acrobat.
    6. Installs Adobe Acrobat using the extracted setup files.
    7. Cleans up download directory on success.
#>

# Set error action preference
$ErrorActionPreference = "Stop"

# Debug flags - set to $true to disable
$DisableInstall = $false
$DisableCleanup = $false
$DisableReDownload = $false

# Software configuration
$SoftwareName = "Adobe-Acrobat-x64-Install"
$JsonUrls = @(
    "https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/_Main/Software-Versions.json",
    "https://source-west-scripts.s3.us-west-or.io.cloud.ovh.us/_Software/_Main/Software-Versions.json"
)

# Configure TLS for better compatibility
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

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

# Function to test URL connectivity
function Test-UrlConnectivity {
    param([string]$Url)
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 30
        return $response.StatusCode -eq 200
    }
    catch {
        Write-ColorOutput "Connectivity test failed for $Url : $($_.Exception.Message)" "Yellow"
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

# Function to download file with retry logic
function Download-FileWithRetry {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$ExpectedHash = $null,
        [double]$ExpectedSize = 0
    )
    
    $downloadSuccess = $false
    $maxRetries = 2
    $retryCount = 0
    
    while (-not $downloadSuccess -and $retryCount -le $maxRetries) {
        $retryCount++
        Write-ColorOutput "Download attempt $retryCount of $($maxRetries + 1)..." "White"
        
        Write-ColorOutput "Attempting download from: $Url" "White"
        
        # Test connectivity first
        Write-ColorOutput "Testing connectivity to download URL..." "White"
        if (-not (Test-UrlConnectivity -Url $Url)) {
            Write-ColorOutput "Connectivity test failed, skipping this URL" "Yellow"
            continue
        }
        
        try {
            Write-ColorOutput "Attempting download with TLS configuration..." "White"
            
            # Create web request with additional parameters for better compatibility
            $webRequestParams = @{
                Uri             = $Url
                OutFile         = $OutputPath
                UseBasicParsing = $true
                TimeoutSec      = 300
            }
            
            Invoke-WebRequest @webRequestParams
            
            if (Test-Path $OutputPath) {
                $fileSize = Get-FileSizeMB -FilePath $OutputPath
                Write-ColorOutput "Download completed successfully (Size: $fileSize MB)" "Green"
                
                # Verify hash if provided
                if ($ExpectedHash) {
                    $fileHash = Get-FileHashValue -FilePath $OutputPath
                    if ($fileHash -and $fileHash -eq $ExpectedHash.ToUpper()) {
                        Write-ColorOutput "Hash verification passed" "Green"
                        $downloadSuccess = $true
                    }
                    else {
                        Write-ColorOutput "Hash verification failed. Expected: $ExpectedHash, Got: $fileHash" "Red"
                        Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
                    }
                }
                # Verify size if provided
                elseif ($ExpectedSize -gt 0) {
                    if ($fileSize -ge $ExpectedSize) {
                        Write-ColorOutput "Size verification passed ($fileSize MB >= $ExpectedSize MB)" "Green"
                        $downloadSuccess = $true
                    }
                    else {
                        Write-ColorOutput "Size verification failed. Expected: >= $ExpectedSize MB, Got: $fileSize MB" "Red"
                        Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    $downloadSuccess = $true
                }
            }
        }
        catch {
            $errorDetails = $_.Exception.Message
            if ($_.Exception.InnerException) {
                $errorDetails += " Inner: $($_.Exception.InnerException.Message)"
            }
            Write-ColorOutput "Download failed from $Url" "Red"
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
                
                $webClient.DownloadFile($Url, $OutputPath)
                
                if (Test-Path $OutputPath) {
                    $fileSize = Get-FileSizeMB -FilePath $OutputPath
                    Write-ColorOutput "Alternative download completed successfully (Size: $fileSize MB)" "Green"
                    $downloadSuccess = $true
                }
            }
            catch {
                $webClientError = $_.Exception.Message
                if ($_.Exception.InnerException) {
                    $webClientError += " Inner: $($_.Exception.InnerException.Message)"
                }
                Write-ColorOutput "Alternative download also failed: $webClientError" "Red"
                
                # Try curl as final fallback
                if (Download-WithCurl -Url $Url -OutputPath $OutputPath) {
                    $fileSize = Get-FileSizeMB -FilePath $OutputPath
                    Write-ColorOutput "Curl download completed successfully (Size: $fileSize MB)" "Green"
                    $downloadSuccess = $true
                }
            }
        }
        
        if (-not $downloadSuccess -and $retryCount -le $maxRetries) {
            Write-ColorOutput "All download URLs failed. Retrying in 5 seconds..." "Yellow"
            Start-Sleep -Seconds 5
        }
    }
    
    return $downloadSuccess
}

# Main script execution
try {
    Write-ColorOutput "=== Adobe Acrobat Installation Script ===" "Cyan"
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
    
    Write-ColorOutput "Starting Adobe Acrobat installation process..." "White"
    
    # Load JSON data from online source with fallback URLs
    Write-ColorOutput "Loading software configuration from online JSON..." "White"
    $jsonContent = $null
    $jsonLoaded = $false
    
    foreach ($jsonUrl in $JsonUrls) {
        try {
            Write-ColorOutput "Attempting to load JSON from: $jsonUrl" "White"
            $jsonContent = Invoke-RestMethod -Uri $jsonUrl -UseBasicParsing
            Write-ColorOutput "Successfully loaded JSON configuration from: $jsonUrl" "Green"
            $jsonLoaded = $true
            break
        }
        catch {
            Write-ColorOutput "Failed to load JSON from $jsonUrl : $($_.Exception.Message)" "Yellow"
            continue
        }
    }
    
    if (-not $jsonLoaded) {
        throw "Failed to load JSON configuration from all URLs: $($JsonUrls -join ', ')"
    }
    
    # Get software configurations
    $customizationConfig = $jsonContent.$SoftwareName
    
    if (-not $customizationConfig) {
        throw "Customization package configuration not found in JSON"
    }
    
    Write-ColorOutput "Software: Adobe Acrobat" "Green"
    Write-ColorOutput "Customization Package Version: $($customizationConfig.version)" "Green"
    
    # Create download directory
    $downloadDir = "C:\TempDeploy\Adobe-Acrobat-x64-Install"
    Write-ColorOutput "Creating download directory: $downloadDir" "White"
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $downloadDir)) {
        New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        Write-ColorOutput "Created directory: $downloadDir" "Green"
    }
    else {
        Write-ColorOutput "Directory already exists: $downloadDir" "Yellow"
    }
    
    # Download customization package
    Write-ColorOutput "Downloading Adobe Acrobat Customization Package..." "White"
    
    $publisherName = $customizationConfig.publisher
    $customizationFile = $customizationConfig.file
    $customizationUrls = $customizationConfig.download_urls
    
    Write-ColorOutput "Customization File: $customizationFile" "White"
    
    # Display the actual URLs that will be used
    Write-ColorOutput "Customization Package Download URLs to be used:" "White"
    foreach ($url in $customizationUrls) {
        $actualUrl = $url -replace '\$\{PublisherName\}', $publisherName -replace '\$\{SoftwareName\}', $SoftwareName -replace '\$\{DownloadFile\}', $customizationFile
        Write-ColorOutput "  - $actualUrl" "Cyan"
    }
    
    $customizationPath = Join-Path $downloadDir $customizationFile
    
    # Download customization package
    $customizationDownloadSuccess = $false
    foreach ($url in $customizationUrls) {
        $downloadUrl = $url -replace '\$\{PublisherName\}', $publisherName -replace '\$\{SoftwareName\}', $SoftwareName -replace '\$\{DownloadFile\}', $customizationFile
        
        $customizationDownloadSuccess = Download-FileWithRetry -Url $downloadUrl -OutputPath $customizationPath -ExpectedHash $customizationConfig.hash -ExpectedSize $customizationConfig.size
        if ($customizationDownloadSuccess) {
            break
        }
    }
    
    if (-not $customizationDownloadSuccess) {
        throw "Failed to download Adobe Acrobat Customization Package"
    }
    
    # Extract AcroPro.zip
    Write-ColorOutput "Extracting AcroPro.zip..." "White"
    
    if ($DisableInstall) {
        Write-ColorOutput "[DRY-RUN] Would extract AcroPro.zip to $downloadDir" "Cyan"
    }
    else {
        try {
            # Extract the zip file
            Expand-Archive -Path $customizationPath -DestinationPath $downloadDir -Force
            Write-ColorOutput "Successfully extracted AcroPro.zip" "Green"
            
            # Clean up the zip file
            Remove-Item -Path $customizationPath -Force
            Write-ColorOutput "Cleaned up AcroPro.zip file" "Green"
        }
        catch {
            Write-ColorOutput "Error extracting AcroPro.zip: $($_.Exception.Message)" "Red"
            throw "Failed to extract AcroPro.zip"
        }
    }
    
    # Create setup.ini file
    Write-ColorOutput "Creating setup.ini file..." "White"
    
    if ($DisableInstall) {
        Write-ColorOutput "[DRY-RUN] Would create setup.ini file" "Cyan"
    }
    else {
        # ------------------------------------------------
        #region Create setup.ini File
        # ------------------------------------------------
        
        # Define the target file path
        $iniFilePath = "C:\TempDeploy\Adobe-Acrobat-x64-Install\setup.ini"
        
        # Ensure the directory exists
        $iniDir = Split-Path $iniFilePath
        if (-not (Test-Path $iniDir)) {
            New-Item -Path $iniDir -ItemType Directory -Force | Out-Null
        }
        
        # Define the content
        $iniContent = @"
[Startup]
RequireOS=Windows 7
RequireOS64=Windows 10
RequireMSI=3.1
RequireIE=7.0.0000.0

[Product]
msi=AcroPro.msi
Languages=2052;1028;1029;1030;1043;1033;1035;1036;1031;1038;1040;1041;1042;1044;1045;1046;1049;1051;1060;1034;1053;1055;1058;1025;1037;6156
2052=Chinese Simplified
1028=Chinese Traditional
1029=Czech
1030=Danish
1043=Dutch (Netherlands)
1033=English (United States)
1035=Finnish
1036=French (France)
1031=German (Germany)
1038=Hungarian
1040=Italian (Italy)
1041=Japanese
1042=Korean
1044=Norwegian (Bokmal)
1045=Polish
1046=Portuguese (Brazil)
1049=Russian
1051=Slovak
1060=Slovenian
1034=Spanish (Traditional Sort)
1053=Swedish
1055=Turkish
1058=Ukrainian
1025=English with Arabic support
1037=English with Hebrew support
6156=French (Morocco)

[Windows 7]
PlatformID=2
MajorVersion=6
MinorVersion=1

[Windows 10]
PlatformID=2
MajorVersion=10
"@
        
        # Write the content to the file
        $iniContent | Set-Content -Path $iniFilePath -Encoding UTF8
        
        Write-ColorOutput "INI file created at: $iniFilePath" "Green"
        
        #endregion
    }
    
    # Kill Adobe processes
    Write-ColorOutput "Killing Adobe processes..." "White"
    
    if ($DisableInstall) {
        Write-ColorOutput "[DRY-RUN] Would kill processes: Adobe*, Acro*, Outlook*" "Cyan"
    }
    else {
        Stop-SoftwareProcesses -ProcessNames "'Adobe*', 'Acro*', 'Outlook*'"
    }
    
    # Uninstall existing Adobe Acrobat
    Write-ColorOutput "Uninstalling existing Adobe Acrobat..." "White"
    
    if ($DisableInstall) {
        Write-ColorOutput "[DRY-RUN] Would uninstall existing Adobe Acrobat" "Cyan"
    }
    else {
        # ------------------------------------------------
        # Uninstall
        # ------------------------------------------------
        
        $Apps = @()
        $Apps += Get-ItemProperty "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        $Apps += Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        $uninstall = ($apps | Where-Object { $_.DisplayName -like "Adobe Acrobat (64-bit)*" })
        foreach ($adobe in $uninstall.PSChildName) {
            Start-Process -Wait msiexec.exe -ArgumentList "/x $adobe /qn" -PassThru
        }
        
        Start-Sleep -Seconds 30
        
        #endregion
    }
    
    # Install Adobe Acrobat
    Write-ColorOutput "Installing Adobe Acrobat..." "White"
    
    if ($DisableInstall) {
        Write-ColorOutput "[DRY-RUN] Would install Adobe Acrobat using Setup.exe" "Cyan"
        Write-ColorOutput "[DRY-RUN] Would use installer directory: $downloadDir" "Cyan"
    }
    else {
        # ------------------------------------------------
        # Install
        # ------------------------------------------------
        Write-ColorOutput "Installing Adobe Acrobat from $downloadDir ..." "White"
        Set-Location $downloadDir
        Start-Process -FilePath ".\Setup.exe" -ArgumentList "/sAll /rs" -Wait
        
        Write-ColorOutput "Adobe Acrobat installation complete." "Green"

        # Define the target registry path
        $regPath = "HKLM:\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown"

        # Define the registry settings to be applied in a hashtable
        $regSettings = @{
            "bAcroSuppressUpsell"        = 1
            "bIsSCReducedModeEnforced"   = 0
            "bIsSCReducedModeEnforcedEx" = 1
        }

        try {
            # Create the registry path if it does not already exist.
            # The -Force switch creates parent keys as needed.
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
                Write-Host "Successfully created registry path: $regPath"
            }

            # Iterate through the hashtable and set each registry value
            foreach ($setting in $regSettings.GetEnumerator()) {
                Set-ItemProperty -Path $regPath -Name $setting.Name -Value $setting.Value -Type DWord -Force -ErrorAction Stop
                Write-Host "Set Value: $($setting.Name) = $($setting.Value)"
            }

            Write-Host "`n✅ All registry settings applied successfully." -ForegroundColor Green
        }
        catch {
            # Display an error message if something goes wrong
            Write-Error "❌ Failed to apply registry settings. Please ensure you are running PowerShell as an Administrator. Error: $_"
        }

        Write-ColorOutput "Script completed successfully." "Green"
        
        #endregion
    }
    
    Start-Sleep -Seconds 10

    # Check for armsvc and msiexec processes
    $processes = @("armsvc", "msiexec")
    $running = @()

    # Find which processes are running
    foreach ($proc in $processes) {
        if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
            Write-Host "Found running process: $proc" -ForegroundColor Yellow
            $running += $proc
        }
    }

    # If no processes running, exit
    if ($running.Count -eq 0) {
        Write-Host "No target processes running. Exiting." -ForegroundColor Green
        exit 0
    }

    # Wait up to 5 minutes for processes to end naturally
    Write-Host "Waiting up to 5 minutes for processes to end naturally..." -ForegroundColor Cyan
    $startTime = Get-Date
    $timeout = 300 # 5 minutes

    while (((Get-Date) - $startTime).TotalSeconds -lt $timeout) {
        $stillRunning = @()
        foreach ($proc in $running) {
            if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
                $stillRunning += $proc
            }
            else {
                Write-Host "Process $proc ended naturally" -ForegroundColor Green
            }
        }
    
        if ($stillRunning.Count -eq 0) {
            Write-Host "All processes ended naturally." -ForegroundColor Green
            exit 0
        }
    
        $running = $stillRunning
        Start-Sleep -Seconds 5
    }

    # Time limit reached, kill remaining processes
    Write-Host "Time limit reached. Forcefully terminating processes..." -ForegroundColor Red
    foreach ($proc in $running) {
        try {
            Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
            Write-Host "Terminated process: $proc" -ForegroundColor Red
        }
        catch {
            Write-Host "Error terminating $proc : $($_.Exception.Message)" -ForegroundColor Red
        }
    } 

    Start-Sleep -Seconds 10

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
    
    Write-ColorOutput "=== Adobe Acrobat Installation Completed Successfully ===" "Green"
    return 0
}
catch {
    Write-ColorOutput "=== Adobe Acrobat Installation Failed ===" "Red"
    Write-ColorOutput "Error: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" "Red"
    return 1
}