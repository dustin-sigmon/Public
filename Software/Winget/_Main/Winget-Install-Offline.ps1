<#
.SYNOPSIS
    Installs winget from a pre-downloaded asset bundle. No GitHub API, no PAT required.

.DESCRIPTION
    Self-contained replacement for Winget-Install-NoReboot.ps1. Downloads the
    WingetAssets.zip bundle from the mirror URL to C:\TempDeploy\Winget (created
    if missing), extracts it, and installs winget from the local files.
    Designed for RMM deployment as SYSTEM.

    Bundle contents (from winget-cli v1.29.290, aka.ms VC++ redist):
      Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
      License1.xml
      vc_redist.x64.exe / vc_redist.x86.exe
      arm64/, x64/, x86/  (per-arch VCLibs + WindowsAppRuntime .appx dependencies)

.PARAMETER AssetsUrl
    URL of the WingetAssets.zip bundle. Defaults to the OVH mirror.

.PARAMETER DownloadDir
    Folder to download/extract into. Defaults to C:\TempDeploy\Winget.
#>
[CmdletBinding()]
param(
    [string]$AssetsUrl = 'https://source-east.s3.us-east-va.io.cloud.ovh.us/_Software/Winget/WingetAssets.zip',
    [string]$DownloadDir = 'C:\TempDeploy\Winget'
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host "=== WinGet offline install (mirrored assets) ==="

# No pre-install check: winget may exist for an interactive user but not be
# provisioned for SYSTEM, so we always run the full provisioning install.

# --- Download + extract asset bundle --------------------------------------------
if (Test-Path $DownloadDir) {
    Write-Host "Removing existing $DownloadDir ..."
    Remove-Item -Path $DownloadDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
$bundleZip = Join-Path $DownloadDir 'WingetAssets.zip'

Write-Host "Downloading asset bundle from $AssetsUrl ..."
Invoke-WebRequest -Uri $AssetsUrl -OutFile $bundleZip -UseBasicParsing

Write-Host "Extracting bundle to $DownloadDir ..."
Expand-Archive -Path $bundleZip -DestinationPath $DownloadDir -Force
Remove-Item -Path $bundleZip -Force
Write-Host "Deleted $bundleZip"

# --- Validate assets ------------------------------------------------------------
$msixBundle   = Join-Path $DownloadDir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
$licenseFile  = Join-Path $DownloadDir 'License1.xml'

foreach ($f in @($msixBundle, $licenseFile)) {
    if (-not (Test-Path $f)) { throw "Required asset missing: $f" }
}

$arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
Write-Host "Architecture: $arch"

# --- Dependencies: VCLibs.140.00 / VCLibs.140.00.UWPDesktop / WindowsAppRuntime.1.8 --
# WingetAssets.zip now ships these pre-extracted under a per-arch folder
# (arm64\, x64\, x86\) rather than as a nested DesktopAppInstaller_Dependencies.zip.
$depDir = Join-Path $DownloadDir $arch
if (-not (Test-Path $depDir)) { throw "Dependency folder missing: $depDir" }
$depPaths = @(Get-ChildItem -Path $depDir -Filter '*.appx' -File | ForEach-Object { $_.FullName })
if (-not $depPaths) { throw "No dependency packages found for $arch in $depDir" }
$depPaths | ForEach-Object { Write-Host "  Dependency: $_" }

# Files downloaded via Invoke-WebRequest carry the Mark-of-the-Web (Zone.Identifier
# ADS); DISM's Appx provider can fail to open zoned .msixbundle/.appx files with a
# generic "Unspecified error" / ERROR_PATH_NOT_FOUND, so strip it before installing.
Unblock-File -Path (@($msixBundle, $licenseFile) + $depPaths) -ErrorAction SilentlyContinue


# --- Visual C++ Redistributable (only if v14 not present) ------------------------
$vcRegPath = 'HKLM:\SOFTWARE\{0}\Microsoft\VisualStudio\14.0\VC\Runtimes\X{1}' -f `
    $(if ([Environment]::Is64BitOperatingSystem) { 'WOW6432Node' } else { '' }), `
    $(if ([Environment]::Is64BitOperatingSystem) { '64' } else { '86' })
$vcInstalled = (Test-Path $vcRegPath) -and
    ((Get-ItemProperty $vcRegPath -Name 'Major' -ErrorAction SilentlyContinue).Major -eq 14) -and
    (Test-Path "$env:windir\system32\concrt140.dll")

if ($vcInstalled) {
    Write-Host "Visual C++ Redistributable v14 already installed; skipping."
} else {
    $vcRedist = Join-Path $DownloadDir "vc_redist.$arch.exe"
    if (-not (Test-Path $vcRedist)) { throw "VC++ Redist asset missing: $vcRedist" }
    Write-Host "Installing Visual C++ Redistributable ($arch) ..."
    $proc = Start-Process -FilePath $vcRedist -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    if ($proc.ExitCode -notin 0, 3010) { throw "vc_redist exited with code $($proc.ExitCode)" }
}

# --- winget itself ---------------------------------------------------------------
# DesktopAppInstaller is an OS-protected inbox package: Remove-AppxPackage/
# Remove-AppxProvisionedPackage reliably fail on it (0x80070032 ERROR_NOT_SUPPORTED),
# and Add-AppxProvisionedPackage's implicit supersede-existing-version step then fails
# too (stale stub package source path -> ERROR_PATH_NOT_FOUND). So instead of trying
# to remove what's there, just skip the install if an adequate version already exists.
# Note: the bundle's own AppxBundleManifest.xml uses the neutral stub's calendar
# version (e.g. 2026.728.1707.0), which is NOT comparable to the per-arch package's
# semantic version (e.g. 1.29.290.0) that Get-AppxPackage reports - read the version
# from the per-arch msix inside the bundle instead so the comparison is apples-to-apples.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$bundleZipObj = [System.IO.Compression.ZipFile]::OpenRead($msixBundle)
$archMsixEntry = $bundleZipObj.Entries | Where-Object { $_.FullName -eq "AppInstaller_$arch.msix" }
$archMsixTemp = Join-Path $env:TEMP ("appinstaller_$arch" + [guid]::NewGuid().ToString('N') + '.msix')
[System.IO.Compression.ZipFileExtensions]::ExtractToFile($archMsixEntry, $archMsixTemp, $true)
$bundleZipObj.Dispose()

$archMsixZip = [System.IO.Compression.ZipFile]::OpenRead($archMsixTemp)
$archManifestEntry = $archMsixZip.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' }
$reader = New-Object System.IO.StreamReader($archManifestEntry.Open())
[xml]$archManifest = $reader.ReadToEnd()
$reader.Close(); $archMsixZip.Dispose()
Remove-Item -Path $archMsixTemp -Force -ErrorAction SilentlyContinue
$bundleVersion = [version]$archManifest.Package.Identity.Version
Write-Host "Bundle version ($arch): $bundleVersion"

$existingBest = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1

if ($existingBest -and [version]$existingBest.Version -ge $bundleVersion) {
    Write-Host "Microsoft.DesktopAppInstaller $($existingBest.Version) already installed; skipping provisioning install."
} else {
Write-Host "Installing winget (provisioned, all users) ..."
$dismLog = Join-Path $DownloadDir 'dism-appx.log'
if (Test-Path $dismLog) { Remove-Item $dismLog -Force }
try {
    Add-AppxProvisionedPackage -Online -PackagePath $msixBundle -DependencyPackagePath $depPaths -LicensePath $licenseFile -LogPath $dismLog -LogLevel WarningsInfo | Out-Null
} catch {
    # The PowerShell COMException hides the real DISM failure reason; the log has it.
    if (Test-Path $dismLog) {
        Write-Warning "Add-AppxProvisionedPackage failed. Last log lines from $dismLog :"
        Get-Content $dismLog -Tail 40 | ForEach-Object { Write-Warning "  $_" }
    }
    throw
}
}

# --- PATH + permissions fix -------------------------------------------------------
# Multiple side-by-side version folders can accumulate under WindowsApps across
# installs/upgrades; sort by parsed version (not name string) to pick the newest,
# and strip any *other* DesktopAppInstaller version folder from PATH so `winget`
# doesn't resolve to a stale/older copy.
$wingetFolders = Get-ChildItem -Path (Join-Path $env:ProgramFiles 'WindowsApps') -Directory -Filter "Microsoft.DesktopAppInstaller_*_${arch}__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $ver = ($_.Name -split '_')[1]
        [pscustomobject]@{ Folder = $_; Version = [version]$ver }
    } | Sort-Object Version
$wingetFolder = ($wingetFolders | Select-Object -Last 1).Folder
$staleFolders = ($wingetFolders | Select-Object -SkipLast 1).Folder

if ($wingetFolder) {
    Write-Host "Granting Administrators full control of $($wingetFolder.FullName) ..."
    $acl = Get-Acl $wingetFolder.FullName
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.SetAccessRule($rule)
    try { Set-Acl $wingetFolder.FullName $acl } catch { Write-Warning "ACL set failed: $($_.Exception.Message)" }

    $sysPath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $pathEntries = $sysPath -split ';'
    if ($staleFolders) {
        $stalePaths = $staleFolders | ForEach-Object { $_.FullName }
        Write-Host "Removing stale DesktopAppInstaller PATH entries: $($stalePaths -join ', ')"
        $pathEntries = $pathEntries | Where-Object { $stalePaths -notcontains $_ }
    }
    if ($pathEntries -notcontains $wingetFolder.FullName) {
        $pathEntries += $wingetFolder.FullName
        Write-Host "Added $($wingetFolder.FullName) to system PATH."
    }
    [Environment]::SetEnvironmentVariable('PATH', ($pathEntries -join ';'), 'Machine')
} else {
    Write-Warning "winget folder not found under WindowsApps; PATH not updated."
}

# --- Verify ----------------------------------------------------------------------
$installed = $null -ne (Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)
if ($installed) {
    Write-Host "=== winget installed successfully (offline) ==="
    Write-Host "Note: under SYSTEM, a reboot or new session may be needed before winget works."
} else {
    throw "winget package not found after installation."
}
