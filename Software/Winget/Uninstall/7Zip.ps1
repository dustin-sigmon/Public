[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Software
$softwareID = "7zip.7zip"

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

	Write-Host "7-Zip uninstall completed successfully."
}
catch {
	Write-Error $_.Exception.Message
	exit 1
}
