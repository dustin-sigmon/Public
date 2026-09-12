# Set the security protocol to TLS 1.2 for modern web security
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# A robust function that tries an array of URLs until one succeeds
function Invoke-RemoteScriptWithFallback {
	param(
		[Parameter(Mandatory=$true)]
		[string[]]$UriList
	)

	foreach ($Uri in $UriList) {
		try {
			Write-Host "Attempting to run script from: $Uri"
			# Download the script content and execute it
			Invoke-RestMethod -Uri $Uri -UseBasicParsing | Invoke-Expression
			
			# If the command above succeeds, exit the function
			Write-Host "Successfully executed script from: $Uri"
			return
		} catch {
			# Write a warning and let the loop try the next URL
			Write-Warning "Failed to run script from '$Uri'. Error: $($_.Exception.Message)"
		}
	}

	# If the loop finishes, it means all URLs failed
	Write-Error "FATAL: Could not execute script from any of the provided URLs."
}

# --- Script Execution ---

Write-Host "--- Running Adobe Acrobat Install Script ---"
Invoke-RemoteScriptWithFallback -UriList @(
	'https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/Adobe/Acrobat/Adobe-Acrobat-x64-Install.ps1',
	'https://source-west-scripts.s3.us-west-or.io.cloud.ovh.us/_Software/Adobe/Acrobat/Adobe-Acrobat-x64-Install.ps1'
)

Start-Sleep -Seconds 10

Write-Host "--- Running Adobe Acrobat Update Script ---"
Invoke-RemoteScriptWithFallback -UriList @(
	'https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/Adobe/Acrobat/Adobe-Acrobat-x64-Update.ps1',
	'https://source-west-scripts.s3.us-west-or.io.cloud.ovh.us/_Software/Adobe/Acrobat/Adobe-Acrobat-x64-Update.ps1'
)

Start-Sleep -Seconds 10

Write-Host "--- Running Custom Field Script ---"
Invoke-RemoteScriptWithFallback -UriList @(
	'https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Ninja/Fields/SetCustomField-Software/_SetCustomField-Software.ps1',
	'https://source-west-scripts.s3.us-west-or.io.cloud.ovh.us/_Ninja/Fields/SetCustomField-Software/_SetCustomField-Software.ps1'
)

<#

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-SafeDownload {
	param([string]$url)
	try {
		iex (New-Object Net.WebClient).DownloadString($url)
	} catch {
		Write-Warning "Error running: $url - $($_)"
	}
}

Invoke-SafeDownload 'https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/Adobe/Acrobat/Adobe-Acrobat-x64-Install.ps1'
Start-Sleep -Seconds 10
Invoke-SafeDownload 'https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/Adobe/Acrobat/Adobe-Acrobat-x64-Update.ps1'
Start-Sleep -Seconds 10
iex (New-Object Net.WebClient).DownloadString('https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Ninja/Fields/SetCustomField-Software/_SetCustomField-Software.ps1')

#>