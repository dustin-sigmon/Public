[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Random delay (1-4 minutes)
Start-Sleep -Seconds ((Get-Random -Minimum 1 -Maximum 5) * 60)

# Find WinGet
$DesktopAppInstaller = Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $DesktopAppInstaller) {
    Write-Error "Microsoft.DesktopAppInstaller not found."
    exit 1
}

$Winget = Join-Path $DesktopAppInstaller.InstallLocation "winget.exe"

if (-not (Test-Path $Winget)) {
    Write-Error "winget.exe not found at: $Winget"
    exit 1
}

Write-Host "Using WinGet: $Winget"

# Close browsers before updating
$Targets = @(
    "chrome",
    "msedge",
    "firefox"
)

foreach ($Target in $Targets) {

    try {

        Get-Process -Name $Target -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue

        Write-Host "Closed $Target"
    }
    catch {

        Write-Warning "Could not close $Target"
    }
}

# Packages to update
$Packages = @(
    "Google.Chrome",
    "Mozilla.Firefox",
    "Microsoft.Edge"
)

$FailedPackages = @()

foreach ($Package in $Packages) {

    Write-Host "Updating $Package..."

    & $Winget upgrade `
        --id $Package `
        --exact `
        --include-unknown `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity `
        --silent

    if ($LASTEXITCODE -ne 0) {

        Write-Warning "$Package failed with exit code $LASTEXITCODE"

        $FailedPackages += $Package
    }
    else {

        Write-Host "$Package updated successfully"
    }
}

if ($FailedPackages.Count -gt 0) {

    Write-Error "Failed packages: $($FailedPackages -join ', ')"
    exit 1
}

Write-Host "All browser updates completed successfully."