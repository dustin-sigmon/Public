[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    # Find the newest installed Desktop App Installer package
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

    # Capture all output including stderr
    $raw = & $Winget upgrade `
        --accept-source-agreements `
        --disable-interactivity 2>&1

    # Remove common winget header/footer noise
    $lines = $raw | Where-Object {
        $_ -and
        $_.ToString().Trim() -ne '' -and
        $_ -notmatch '^Name\s+' -and
        $_ -notmatch '^Id\s+' -and
        $_ -notmatch '^Version\s+' -and
        $_ -notmatch '^Available\s+' -and
        $_ -notmatch '^Source\s+' -and
        $_ -notmatch '^-{5,}' -and
        $_ -notmatch '^The following packages have upgrades available'
    }

    # Extract package names
    $pendingWingetUpdate = foreach ($line in $lines) {

        $text = $line.ToString()

        # Skip known informational messages
        if (
            $text -match 'No installed package found' -or
            $text -match 'No applicable upgrade found' -or
            $text -match 'upgrades available' -or
            $text -match 'upgrades unavailable'
        ) {
            continue
        }

        # Typical winget output format:
        # Package Name   Id   Current   Available   Source
        if ($text -split '\s{2,}') {
            ($text -split '\s{2,}')[0].Trim()
        }
    }

    $pendingWingetUpdate = $pendingWingetUpdate |
        Where-Object { $_ } |
        Sort-Object -Unique

    if (-not $pendingWingetUpdate) {
        $pendingWingetValue = "No available updates"
    }
    else {
        $pendingWingetValue = $pendingWingetUpdate -join "`n"
    }
}
catch {
    $pendingWingetValue = "Winget Error: $($_.Exception.Message)"
}

Write-Host $pendingWingetValue

Ninja-Property-Set `
    -Name 'pendingwingetupdates' `
    -Value $pendingWingetValue