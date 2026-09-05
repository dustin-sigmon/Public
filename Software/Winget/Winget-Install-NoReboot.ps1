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

# Ensure PowerShell can install scripts without prompting for the NuGet provider.
$requiredNuGetVersion = [version]'2.8.5.201'
$nuGetProvider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
    Where-Object { $_.Version -ge $requiredNuGetVersion } |
    Select-Object -First 1

if (-not $nuGetProvider) {
    Install-PackageProvider -Name NuGet -MinimumVersion $requiredNuGetVersion -Force -Scope AllUsers -Confirm:$false -ErrorAction Stop | Out-Null
}

$nuGetProvider = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
    Where-Object { $_.Version -ge $requiredNuGetVersion } |
    Select-Object -First 1

if (-not $nuGetProvider) {
    throw "NuGet package provider $requiredNuGetVersion or newer could not be installed."
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

$powershellPath = Join-Path $PSHOME 'powershell.exe'
& $powershellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -Force -GHtoken $GHtoken

if ($LASTEXITCODE -ne 0) {
    throw "winget-install.ps1 failed with exit code $LASTEXITCODE."
}

Write-Host "=== winget-install run completed ==="
