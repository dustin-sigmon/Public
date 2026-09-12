[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Software
$softwareID = "Google.Chrome"

try {
	# Find newest Desktop App Installer
	$DesktopAppInstaller = Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller -ErrorAction Stop |
		Sort-Object Version -Descending |
		Select-Object -First 1

	if (-not $DesktopAppInstaller) {
		throw "Microsoft.DesktopAppInstaller not found."
	}

	$Winget = Join-Path $DesktopAppInstaller.InstallLocation "winget.exe"

	if (-not (Test-Path $Winget)) {
		throw "winget.exe not found at: $Winget"
	}

	Write-Host "Using Winget: $Winget"

	# Check whether application is installed and get its version
	$UninstallKeys = @(
		'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
		'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
		'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
	)

	$InstalledApp = Get-ItemProperty $UninstallKeys -ErrorAction SilentlyContinue |
		Where-Object { $_.DisplayName -like "Google Chrome*" } |
		Select-Object -First 1

	if (-not $InstalledApp) {
		Write-Host "Google Chrome is not installed. Skipping uninstall."
		exit 0
	}

	Write-Host "$($InstalledApp.DisplayName) is installed. Version: $($InstalledApp.DisplayVersion)"

	& $Winget uninstall `
		--id $softwareID `
		--exact `
		--source winget `
		--silent `
		--accept-source-agreements `
		--disable-interactivity

	if ($LASTEXITCODE -ne 0) {
		throw "Winget exited with code $LASTEXITCODE"
	}

	Write-Host "Google Chrome uninstall completed successfully."
}
catch {
	Write-Error $_.Exception.Message
	exit 1
}
