[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Software
$SoftwareID = "Google.Chrome"

try {
    # Find newest Desktop App Installer
    $DesktopAppInstaller = Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller |
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

    # Check whether application is already installed
    & $Winget list `
        --id $SoftwareID `
        --exact `
        --accept-source-agreements `
        --disable-interactivity *> $null

    if ($LASTEXITCODE -eq 0) {

        Write-Host "$SoftwareID is installed. Upgrading..."

        & $Winget upgrade `
            --id $SoftwareID `
            --exact `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity
    }
    else {

        Write-Host "$SoftwareID is not installed. Installing..."

        & $Winget install `
            --id $SoftwareID `
            --exact `
            --silent `
            --accept-package-agreements `
            --accept-source-agreements `
            --disable-interactivity
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Winget exited with code $LASTEXITCODE"
    }

    Write-Host "Operation completed successfully."
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}