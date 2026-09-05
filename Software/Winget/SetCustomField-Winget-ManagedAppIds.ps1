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
$wingetAppIdList = foreach ($line in $lines) {

    $cols = $line -split '\s{2,}'

    if ($cols.Count -ge 4) {
        $id     = $cols[1].Trim()
        $source = $line.TrimEnd() -match '\swinget$'

        if ($source) {
            $id
        }
    }
}

# Convert sorted, unique IDs to newline-delimited text
$wingetManagedValue = ($wingetAppIdList | Sort-Object -Unique) -join "`n"

# Show output correctly in console
Write-Host $wingetManagedValue

# Send to Ninja custom field
Ninja-Property-Set -Name 'wingetAppIdList' -Value $wingetManagedValue