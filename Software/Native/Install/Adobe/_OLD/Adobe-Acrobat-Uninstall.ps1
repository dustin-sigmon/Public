#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Uninstalls Adobe Acrobat (64-Bit) from the system
    
.DESCRIPTION
    This script uninstalls Adobe Acrobat (64-Bit) following these steps:
    1. Kills Adobe processes to prevent conflicts
    2. Searches for Adobe Acrobat (64-Bit) installations in registry
    3. Uninstalls each found installation using msiexec
    4. Waits for uninstall to complete
    5. Verifies uninstall success
#>

# Set error action preference
$ErrorActionPreference = "Stop"

# Debug flags - set to $true to disable
$DisableUninstall = $false

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
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

# Function to check if Adobe Acrobat is installed
function Test-AdobeAcrobatInstalled {
    try {
        $Apps = @()
        $Apps += Get-ItemProperty "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
        $Apps += Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
        
        # Look for various Adobe Acrobat installation names
        $adobeInstallations = ($apps | Where-Object { 
                $_.DisplayName -match "Adobe Acrobat" -and 
                ($_.DisplayName -match "64-bit" -or $_.DisplayName -match "64 bit" -or $_.DisplayName -notmatch "32-bit")
            })
        
        # Debug: Show all Adobe-related installations
        $allAdobe = ($apps | Where-Object { $_.DisplayName -match "Adobe" })
        if ($allAdobe) {
            Write-ColorOutput "All Adobe installations found:" "Cyan"
            foreach ($adobe in $allAdobe) {
                Write-ColorOutput "  - $($adobe.DisplayName) (Version: $($adobe.DisplayVersion))" "Cyan"
            }
        }
        
        if ($adobeInstallations) {
            Write-ColorOutput "Found Adobe Acrobat installations:" "Yellow"
            foreach ($installation in $adobeInstallations) {
                Write-ColorOutput "  - $($installation.DisplayName) (Version: $($installation.DisplayVersion))" "Yellow"
            }
            return $adobeInstallations
        }
        else {
            Write-ColorOutput "No Adobe Acrobat installations found." "Green"
            return $null
        }
    }
    catch {
        Write-ColorOutput "Error checking for Adobe Acrobat installations: $($_.Exception.Message)" "Red"
        return $null
    }
}

# Main script execution
try {
    Write-ColorOutput "=== Adobe Acrobat Uninstall Script ===" "Cyan"
    if ($DisableUninstall) {
        Write-ColorOutput "MODE: DRY-RUN (No actual uninstall will be performed)" "Yellow"
    }
    else {
        Write-ColorOutput "MODE: UNINSTALLATION (Actual uninstall will be performed)" "Green"
    }
    
    Write-ColorOutput "Starting Adobe Acrobat uninstall process..." "White"
    
    # Check if Adobe Acrobat is installed
    Write-ColorOutput "Checking for Adobe Acrobat installations..." "White"
    $adobeInstallations = Test-AdobeAcrobatInstalled
    
    if (-not $adobeInstallations) {
        Write-ColorOutput "Adobe Acrobat is not installed. Nothing to uninstall." "Green"
        return 0
    }
    
    # Kill Adobe processes
    Write-ColorOutput "Killing Adobe processes..." "White"
    
    if ($DisableUninstall) {
        Write-ColorOutput "[DRY-RUN] Would kill processes: Adobe*, Acro*, Outlook*" "Cyan"
    }
    else {
        Stop-SoftwareProcesses -ProcessNames "'Adobe*', 'Acro*', 'Outlook*'"
        Write-ColorOutput "Adobe processes stopped." "Green"
    }
    
    # Uninstall Adobe Acrobat
    Write-ColorOutput "Uninstalling Adobe Acrobat..." "White"
    
    if ($DisableUninstall) {
        Write-ColorOutput "[DRY-RUN] Would uninstall Adobe Acrobat installations" "Cyan"
        foreach ($installation in $adobeInstallations) {
            Write-ColorOutput "[DRY-RUN] Would uninstall: $($installation.DisplayName) (Product Code: $($installation.PSChildName))" "Cyan"
        }
    }
    else {
        # ------------------------------------------------
        # Uninstall
        # ------------------------------------------------
        
        $uninstallCount = 0
        $totalInstallations = $adobeInstallations.Count
        
        foreach ($installation in $adobeInstallations) {
            $uninstallCount++
            Write-ColorOutput "Uninstalling $($installation.DisplayName) ($uninstallCount of $totalInstallations)..." "White"
            Write-ColorOutput "Product Code: $($installation.PSChildName)" "Cyan"
            
            try {
                $processArgs = @{
                    FilePath     = "msiexec.exe"
                    ArgumentList = "/x", $installation.PSChildName, "/qn", "/norestart"
                    Wait         = $true
                    PassThru     = $true
                }
                
                $uninstallProcess = Start-Process @processArgs
                
                if ($uninstallProcess.ExitCode -eq 0) {
                    Write-ColorOutput "Successfully uninstalled $($installation.DisplayName)" "Green"
                }
                else {
                    Write-ColorOutput "Uninstall completed with exit code: $($uninstallProcess.ExitCode) for $($installation.DisplayName)" "Yellow"
                }
            }
            catch {
                Write-ColorOutput "Error uninstalling $($installation.DisplayName): $($_.Exception.Message)" "Red"
            }
        }
        
        Write-ColorOutput "Waiting for uninstall to complete..." "White"
        Start-Sleep -Seconds 30
        
        #endregion
    }
    
    # Verify uninstall
    Write-ColorOutput "Verifying uninstall..." "White"
    
    if ($DisableUninstall) {
        Write-ColorOutput "[DRY-RUN] Would verify uninstall success" "Cyan"
    }
    else {
        $remainingInstallations = Test-AdobeAcrobatInstalled
        
        if (-not $remainingInstallations) {
            Write-ColorOutput "Adobe Acrobat uninstall verification successful - no installations remain." "Green"
        }
        else {
            Write-ColorOutput "Warning: Some Adobe Acrobat installations may still be present." "Yellow"
            foreach ($installation in $remainingInstallations) {
                Write-ColorOutput "  - $($installation.DisplayName) (Version: $($installation.DisplayVersion))" "Yellow"
            }
        }
    }
    
    Start-Sleep -Seconds 120

    # Check if msiexec.exe is running and kill it if found
    $processName = "msiexec"

    # Get the process if it exists
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue

    if ($process) {
        Write-Host "msiexec.exe is running. Attempting to kill it..." -ForegroundColor Yellow
        try {
            Stop-Process -Name $processName -Force
            Write-Host "msiexec.exe has been terminated." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to terminate msiexec.exe: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "msiexec.exe is not running." -ForegroundColor Cyan
    }

    Write-ColorOutput "=== Adobe Acrobat Uninstall Completed Successfully ===" "Green"
    return 0
}
catch {
    Write-ColorOutput "=== Adobe Acrobat Uninstall Failed ===" "Red"
    Write-ColorOutput "Error: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack Trace: $($_.ScriptStackTrace)" "Red"
    return 1
} 