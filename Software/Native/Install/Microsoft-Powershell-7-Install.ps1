#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Find the latest stable PowerShell release.
$Release = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
$Asset = $Release.assets |
    Where-Object { $_.name -like '*-win-x64.msi' } |
    Select-Object -First 1

if (-not $Asset) {
    throw 'No x64 MSI installer was found for the latest release.'
}

$Installer = Join-Path $env:TEMP $Asset.name

Write-Host "Downloading PowerShell $($Release.tag_name)..."
Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $Installer -UseBasicParsing

Write-Host 'Installing PowerShell 7...'
$Process = Start-Process msiexec.exe -ArgumentList "/i `"$Installer`" /quiet /norestart ADD_PATH=1" -Wait -PassThru

if ($Process.ExitCode -notin 0, 3010) {
    throw "Installation failed with exit code $($Process.ExitCode)."
}

Remove-Item -LiteralPath $Installer -Force
Write-Host 'PowerShell 7 installed successfully.'

if ($Process.ExitCode -eq 3010) {
    Write-Host 'A restart is required to finish installation.'
}