#Start-Sleep -Seconds ([System.Random]::new().Next(1, 15)*60)

#$softwareUpdateTimestamp = Get-Date -Format 'yyyy-MM-dd'
#$softwareUpdateTimestamp | & "$env:NINJARMMCLI" set --stdin softwareLastUpdateDate

############################################################ DO NOT CHANGE START ############################################################
##Open TLS and configure network settings

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
#[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
[Net.ServicePointManager]::Expect100Continue = $false
[Net.ServicePointManager]::UseNagleAlgorithm = $false

# Verbose log setup
$logDir = "C:\Source\PCT-Logs"
$logFile = Join-Path $logDir "Software-Version-Check.txt"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting Software Version Check..." | Set-Content $logFile

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp $Message" | Add-Content $logFile
}

##Azure DevOps base information for url and token

function Invoke-WebRequestWithRetry {
    [cmdletbinding()]
    param(
        [string]$Uri,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5,
        [int]$TimeoutSeconds = 30
    )
    
    $retryCount = 0
    $lastException = $null
    
    while ($retryCount -le $MaxRetries) {
        try {
            Write-Log "Attempt $($retryCount + 1) of $($MaxRetries + 1) for URI: $Uri"
            
            # Use Invoke-RestMethod with proper error handling and User-Agent
            $response = Invoke-RestMethod -Uri $Uri -TimeoutSec $TimeoutSeconds -UserAgent "PowerShell-Script/1.0" -ErrorAction Stop
            
            Write-Log "Successfully downloaded content from: $Uri"
            return $response
        }
        catch {
            $lastException = $_.Exception
            $retryCount++
            
            if ($retryCount -le $MaxRetries) {
                $delay = $RetryDelaySeconds * [Math]::Pow(2, $retryCount - 1) # Exponential backoff
                Write-Log "Attempt $retryCount failed: $($_.Exception.Message). Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
            }
            else {
                Write-Log "All retry attempts failed for URI: $Uri. Last error: $($_.Exception.Message)"
            }
        }
    }
    
    throw $lastException
}

function RunScript {
    [cmdletbinding()]
    param(
        $FilePath
    )
    
    # Define primary and fallback URLs
    $primaryUrl = "https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/[path]"
    $fallbackUrl = "https://source-west-scripts.s3.us-west-or.io.cloud.ovh.us/_Software/[path]"

    $primaryRestUrl = $primaryUrl.Replace("[path]", $FilePath)
    $fallbackRestUrl = $fallbackUrl.Replace("[path]", $FilePath)
    
    Write-Log "Running script from primary URL: $primaryRestUrl"
    
    try {
        # Try primary URL first
        $content = Invoke-WebRequestWithRetry -Uri $primaryRestUrl -MaxRetries 2 -RetryDelaySeconds 3 -TimeoutSeconds 30
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw "Downloaded content from primary URL is empty or null"
        }
        
        Write-Log "Successfully downloaded script content from primary URL (Length: $($content.Length) characters)."
        Invoke-Expression $content
        Write-Log "Successfully executed script: $FilePath"
    }
    catch {
        Write-Log ("Primary URL failed for script {0}: {1}" -f $FilePath, $_.Exception.Message)
        Write-Log "Attempting fallback URL: $fallbackRestUrl"
        
        try {
            # Try fallback URL
            $content = Invoke-WebRequestWithRetry -Uri $fallbackRestUrl -MaxRetries 3 -RetryDelaySeconds 5 -TimeoutSeconds 30
            
            if ([string]::IsNullOrWhiteSpace($content)) {
                throw "Downloaded content from fallback URL is empty or null"
            }
            
            Write-Log "Successfully downloaded script content from fallback URL (Length: $($content.Length) characters)."
            Invoke-Expression $content
            Write-Log "Successfully executed script from fallback: $FilePath"
        }
        catch {
            Write-Log ("Both primary and fallback URLs failed for script {0}" -f $FilePath)
            Write-Log ("Primary URL error: {0}" -f $_.Exception.Message)
            Write-Log ("Fallback URL error: {0}" -f $_.Exception.Message)
            Write-Log ("Stack trace: {0}" -f $_.ScriptStackTrace)
            throw
        }
    }
}

############################################################ DO NOT CHANGE END ############################################################

function Adobe-Acrobat-2020-Version { try { RunScript -FilePath "_Version-Check/Adobe-Acrobat/Adobe-Acrobat-2020-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Acrobat-x64-Version { try { RunScript -FilePath "_Version-Check/Adobe-Acrobat/Adobe-Acrobat-x64-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Acrobat-x86-Version { try { RunScript -FilePath "_Version-Check/Adobe-Acrobat/Adobe-Acrobat-x86-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Reader-x64-ENU-Version { try { RunScript -FilePath "_Version-Check/Adobe-Reader/Adobe-Reader-x64-ENU-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Reader-x86-ENU-Version { try { RunScript -FilePath "_Version-Check/Adobe-Reader/Adobe-Reader-x86-ENU-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Reader-x64-MUI-Version { try { RunScript -FilePath "_Version-Check/Adobe-Reader/Adobe-Reader-x64-MUI-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Reader-x86-MUI-Version { try { RunScript -FilePath "_Version-Check/Adobe-Reader/Adobe-Reader-x86-MUI-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }

# Update

& 'Adobe-Acrobat-2020-Version'
& 'Adobe-Acrobat-x64-Version'
& 'Adobe-Acrobat-x86-Version'
& 'Adobe-Reader-x64-ENU-Version'
& 'Adobe-Reader-x86-ENU-Version'
& 'Adobe-Reader-x64-MUI-Version'
& 'Adobe-Reader-x86-MUI-Version'

# Update Ninja Custom Fields
try {
    Write-Log "Updating Ninja Custom Fields..."
    
    # Define primary and fallback URLs for custom field script
    $primaryCustomFieldUrl = 'https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Ninja/Fields/SetCustomField-Software/_SetCustomField-Software.ps1'
    $fallbackCustomFieldUrl = 'https://source-west-scripts.s3.us-west-or.io.cloud.ovh.us/_Ninja/Fields/SetCustomField-Software/_SetCustomField-Software.ps1'
    
    Write-Log "Trying primary custom field URL: $primaryCustomFieldUrl"
    
    try {
        # Try primary URL first
        $customFieldScript = Invoke-WebRequestWithRetry -Uri $primaryCustomFieldUrl -MaxRetries 2 -RetryDelaySeconds 3 -TimeoutSeconds 30
        
        if ([string]::IsNullOrWhiteSpace($customFieldScript)) {
            throw "Downloaded custom field script from primary URL is empty or null"
        }
        
        Write-Log "Successfully downloaded custom field script from primary URL (Length: $($customFieldScript.Length) characters)."
        Invoke-Expression $customFieldScript
        Write-Log "Successfully executed custom field script from primary URL."
    }
    catch {
        Write-Log ("Primary custom field URL failed: {0}" -f $_.Exception.Message)
        Write-Log "Attempting fallback custom field URL: $fallbackCustomFieldUrl"
        
        try {
            # Try fallback URL
            $customFieldScript = Invoke-WebRequestWithRetry -Uri $fallbackCustomFieldUrl -MaxRetries 3 -RetryDelaySeconds 5 -TimeoutSeconds 30
            
            if ([string]::IsNullOrWhiteSpace($customFieldScript)) {
                throw "Downloaded custom field script from fallback URL is empty or null"
            }
            
            Write-Log "Successfully downloaded custom field script from fallback URL (Length: $($customFieldScript.Length) characters)."
            Invoke-Expression $customFieldScript
            Write-Log "Successfully executed custom field script from fallback URL."
        }
        catch {
            Write-Log ("Both primary and fallback custom field URLs failed")
            Write-Log ("Primary URL error: {0}" -f $_.Exception.Message)
            Write-Log ("Fallback URL error: {0}" -f $_.Exception.Message)
            # Don't throw here as this is not critical to the main functionality
        }
    }
}
catch {
    Write-Log ("ERROR updating Ninja Custom Fields: {0}" -f $_.Exception.Message)
    Write-Log ("Stack trace: {0}" -f $_.ScriptStackTrace)
    # Don't throw here as this is not critical to the main functionality
}