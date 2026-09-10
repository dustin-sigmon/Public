[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    # Find newest Desktop App Installer
    $DesktopAppInstaller = Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $DesktopAppInstaller) {
        throw "Microsoft.DesktopAppInstaller not found."
    }

    # Build winget path
    $Winget = Join-Path $DesktopAppInstaller.InstallLocation "winget.exe"

    if (-not (Test-Path $Winget)) {
        throw "winget.exe not found at: $Winget"
    }

    Write-Host "Using Winget: $Winget"

    # Get installed software recognized by winget
    $raw = & $Winget list `
        --accept-source-agreements `
        --disable-interactivity 2>&1

    # Remove headers and other noise
    $lines = $raw | Where-Object {
        $_ -and
        $_.ToString().Trim() -ne '' -and
        $_ -notmatch '^Name\s+' -and
        $_ -notmatch '^Id\s+' -and
        $_ -notmatch '^Version\s+' -and
        $_ -notmatch '^Source\s+' -and
        $_ -notmatch '^-{5,}'
    }

    # Extract App IDs for winget-managed applications
    $wingetAppIdList = foreach ($line in $lines) {

        $cols = $line.ToString() -split '\s{2,}'

        if ($cols.Count -ge 4) {

            # Source is reliably the last column
            $source = $cols[$cols.Count - 1].Trim()

            # ID is typically the second column
            $id = $cols[1].Trim()

            if ($source -eq 'winget' -and $id) {
                $id
            }
        }
    }

    $wingetAppIdList = $wingetAppIdList |
        Where-Object { $_ } |
        Sort-Object -Unique

    if (-not $wingetAppIdList) {
        $wingetManagedValue = "No winget-managed application IDs found"
    }
    else {
        $wingetManagedValue = $wingetAppIdList -join "`n"
    }
}
catch {
    $wingetManagedValue = "Winget Error: $($_.Exception.Message)"
}

Write-Host $wingetManagedValue

# Send to Ninja custom field
Ninja-Property-Set `
    -Name 'wingetAppIdList' `
    -Value $wingetManagedValue