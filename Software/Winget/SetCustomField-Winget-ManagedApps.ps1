[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Get installed software that winget recognizes
$raw = winget list

# Filter out header/footer lines
$lines = $raw | Where-Object {
    $_.Trim() -ne '' -and
    $_ -notmatch '^-{5,}' -and
    $_ -notmatch 'Name' -and
    $_ -notmatch 'Id' -and
    $_ -notmatch 'Version' -and
    $_ -notmatch 'Source'
}

# Parse each line and keep only items with a winget source
$wingetManagedSoftware = foreach ($line in $lines) {

    $cols = $line -split '\s{2,}'

    if ($cols.Count -ge 4) {
        $name   = $cols[0].Trim()
        $source = $cols[3].Trim()

        if ($source -eq 'winget') {
            $name
        }
    }
}

# Convert sorted, unique software names to newline-delimited text
$wingetManagedValue = ($wingetManagedSoftware | Sort-Object -Unique) -join "`n"

# Show output correctly in console
Write-Host $wingetManagedValue

# Send to Ninja custom field
#Ninja-Property-Set -Name 'wingetManagedSoftware' -Value $wingetManagedValue