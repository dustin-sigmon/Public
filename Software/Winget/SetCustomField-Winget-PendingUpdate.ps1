[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Get raw output
$raw = winget upgrade --accept-source-agreements

# Filter out header/footer lines
$lines = $raw | Where-Object {
    $_.Trim() -ne '' -and
    $_ -notmatch '^-{5,}' -and
    $_ -notmatch 'Name' -and
    $_ -notmatch 'Id' -and
    $_ -notmatch 'Version' -and
    $_ -notmatch 'Available' -and
    $_ -notmatch 'Source'
}

# Extract only the human-readable package name from each line
$pendingWingetUpdate = foreach ($line in $lines) {
    $parts = $line -split ' Microsoft\.'
    if ($parts.Count -gt 1) {
        $parts[0].Trim()
    }
}

# If nothing was found, set a friendly message
if (-not $pendingWingetUpdate -or $pendingWingetUpdate.Count -eq 0) {
    $pendingWingetValue = "No available updates"
} else {
    $pendingWingetValue = ($pendingWingetUpdate | Sort-Object -Unique) -join "`n"
}

# Show output correctly in console
Write-Host $pendingWingetValue

# Send to Ninja custom field
Ninja-Property-Set -Name 'pendingwingetupdates' -Value $pendingWingetValue