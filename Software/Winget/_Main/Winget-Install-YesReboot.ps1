[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Set to $false to run the installation even when WinGet is already present.
$CheckIfAlreadyInstalled = $true

# Set GITHUB_TOKEN in the environment before running this script.
$GHtoken = $env:GITHUB_TOKEN
if ([string]::IsNullOrWhiteSpace($GHtoken)) {
    throw 'GITHUB_TOKEN environment variable is required.'
}

Write-Host "=== WinGet via winget-install (SYSTEM) ==="

# Do not download or install WinGet when it is already present.
$wingetInstalled = $null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue) -or
    $null -ne (Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)

if ($CheckIfAlreadyInstalled -and $wingetInstalled) {
    Write-Host "WinGet is already installed; skipping installation."
    return
}

# Install winget-install if missing
if (-not (Get-Command winget-install -ErrorAction SilentlyContinue)) {
    Install-Script winget-install -Force -Confirm:$false
}

# Run the script by full path to avoid auto-import issues under SYSTEM
$scriptPath = Join-Path $env:ProgramFiles "WindowsPowerShell\Scripts\winget-install.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "winget-install.ps1 not found at $scriptPath"
    return
}

try {
    & $scriptPath -Force -GHtoken $GHtoken
    $installSucceeded = $null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue) -or
        $null -ne (Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)
}
catch {
    $installSucceeded = $false
    Write-Host "winget-install failed: $($_.Exception.Message)"
}

if ($installSucceeded) {
    Write-Host "=== winget-install run completed successfully ==="
    shutdown.exe /r /t 120 /c "Device rebooting in 2 minutes please save your work"
}
else {
    Write-Host "=== winget-install did not complete successfully; skipping reboot ==="
}
