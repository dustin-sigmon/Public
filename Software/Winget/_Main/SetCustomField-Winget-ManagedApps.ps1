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

    # Keep only software whose source is winget
    $wingetManagedSoftware = foreach ($line in $lines) {

        $cols = $line.ToString() -split '\s{2,}'

        if ($cols.Count -ge 4) {

            $name = $cols[0].Trim()

            # Source is typically the last column
            $source = $cols[$cols.Count - 1].Trim()

            if ($source -eq 'winget') {
                $name
            }
        }
    }

    $wingetManagedSoftware = $wingetManagedSoftware |
        Where-Object { $_ } |
        Sort-Object -Unique

    if (-not $wingetManagedSoftware) {
        $wingetManagedValue = "No winget-managed software found"
    }
    else {
        $wingetManagedValue = $wingetManagedSoftware -join "`n"
    }
}
catch {
    $wingetManagedValue = "Winget Error: $($_.Exception.Message)"
}

Write-Host $wingetManagedValue

# Send to Ninja custom field
Ninja-Property-Set -Name 'wingetManagedSoftware' -Value $wingetManagedValue