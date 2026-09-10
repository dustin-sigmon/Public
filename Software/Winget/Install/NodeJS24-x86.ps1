#Software
$softwareID = "OpenJS.NodeJS"
$minimumVersion = [version]"24.0.0"
$architecture = "x86"
$type = "install" #install, update, uninstall

$availableVersions = @(winget show --id $softwareID --exact --versions --accept-source-agreements 2>$null | ForEach-Object {
	if ($_ -match '^\s*(\d+(?:\.\d+){2,3})\s*$') {
		[version]$matches[1]
	}
} | Where-Object { $_.Major -eq $minimumVersion.Major -and $_ -ge $minimumVersion } | Sort-Object -Descending)

if ($availableVersions.Count -eq 0) {
	throw "No Node.js version $minimumVersion or newer was found for major version $($minimumVersion.Major)."
}

$softwareVersion = $availableVersions[0].ToString()
winget $type --id $softwareID --version $softwareVersion --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements