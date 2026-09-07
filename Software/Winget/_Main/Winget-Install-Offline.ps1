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
      DesktopAppInstaller_Dependencies.zip
      License1.xml
      vc_redist.x64.exe / vc_redist.x86.exe

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
$depsZip      = Join-Path $DownloadDir 'DesktopAppInstaller_Dependencies.zip'
$licenseFile  = Join-Path $DownloadDir 'License1.xml'

foreach ($f in @($msixBundle, $depsZip, $licenseFile)) {
    if (-not (Test-Path $f)) { throw "Required asset missing: $f" }
}

$arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
Write-Host "Architecture: $arch"

# --- Dependencies: VCLibs.140.00.UWPDesktop + UI.Xaml.2.8 from the zip -----------
Write-Host "Installing dependencies from $depsZip ..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tempDir = Join-Path $env:TEMP ("winget_deps_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($depsZip)
    $entries = $zip.Entries | Where-Object { $_.FullName -match ".*$arch\.appx$" }
    if (-not $entries) { throw "No dependency packages found for $arch in $depsZip" }

    foreach ($entry in $entries) {
        $dest = Join-Path $tempDir $entry.Name
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)

        # Install only if not already present at an equal-or-newer version
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $pkgZip = [System.IO.Compression.ZipFile]::OpenRead($dest)
        $manifestEntry = $pkgZip.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' }
        $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
        [xml]$manifest = $reader.ReadToEnd()
        $reader.Close(); $pkgZip.Dispose()

        $pkgName = $manifest.Package.Identity.Name
        $pkgVersion = [version]$manifest.Package.Identity.Version
        $installed = Get-AppxPackage -AllUsers -Name $pkgName -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending | Select-Object -First 1

        if ($installed -and [version]$installed.Version -ge $pkgVersion) {
            Write-Host "  $pkgName $($installed.Version) already installed; skipping."
        } else {
            Write-Host "  Installing $pkgName $pkgVersion ..."
            Add-ProvisionedAppxPackage -Online -SkipLicense -PackagePath $dest | Out-Null
        }
    }
    $zip.Dispose()
} finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

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
Write-Host "Installing winget (provisioned, all users) ..."
Add-AppxProvisionedPackage -Online -PackagePath $msixBundle -LicensePath $licenseFile | Out-Null

# --- PATH + permissions fix -------------------------------------------------------
$wingetFolder = Get-ChildItem -Path (Join-Path $env:ProgramFiles 'WindowsApps') -Directory -Filter "Microsoft.DesktopAppInstaller_*_${arch}__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -Last 1

if ($wingetFolder) {
    Write-Host "Granting Administrators full control of $($wingetFolder.FullName) ..."
    $acl = Get-Acl $wingetFolder.FullName
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.SetAccessRule($rule)
    try { Set-Acl $wingetFolder.FullName $acl } catch { Write-Warning "ACL set failed: $($_.Exception.Message)" }

    $sysPath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    if (($sysPath -split ';') -notcontains $wingetFolder.FullName) {
        [Environment]::SetEnvironmentVariable('PATH', "$sysPath;$($wingetFolder.FullName)", 'Machine')
        Write-Host "Added $($wingetFolder.FullName) to system PATH."
    }
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
