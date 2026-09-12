# ============================================
# WinGet Update Process Killer + User Warning
# ============================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- CONFIGURATION ---

$IncludeList = @(
    "teams",
    "slack",
    "zoom",
    "notepad++"
)

$ExcludeList = @(
    "explorer",
    "onedrive",
    "ninjarmm"
)

$ProcessAliasMap = @{
    "Notepad++.Notepad++" = @("notepad++", "npp")
    "Microsoft.Office"    = @(
        "WINWORD",
        "EXCEL",
        "OUTLOOK",
        "POWERPNT",
        "ONENOTE",
        "MSACCESS",
        "MSPUB",
        "OfficeClickToRun"
    )
}

$SkipUpgradeIds = @(
    "Microsoft.Office"
)

$WarningDelaySeconds = 20

# --- FIND WINGET ---

$DesktopAppInstaller = Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $DesktopAppInstaller) {
    Write-Error "Microsoft.DesktopAppInstaller not found."
    return
}

$Winget = Join-Path $DesktopAppInstaller.InstallLocation "winget.exe"

if (-not (Test-Path $Winget)) {
    Write-Error "winget.exe not found at: $Winget"
    return
}

Write-Host "Using WinGet: $Winget"

# --- CHECK USER LOGIN & ACTIVITY ---

$activeSessions = foreach ($line in @(query.exe user 2>$null)) {

    if ($line -match '^\s*>?(\S+)\s+(?:(\S+)\s+)?(\d+)\s+(Active)\b') {

        [PSCustomObject]@{
            UserName  = $matches[1]
            SessionId = $matches[3]
        }
    }
}

if (@($activeSessions).Count -gt 0) {

    Write-Host "Active user session(s): $(@($activeSessions | ForEach-Object UserName) -join ', ')"

    $msg = "Software updates are preparing to run. Some applications may close automatically."
    $title = "System Maintenance Notice"

    foreach ($activeSession in $activeSessions) {
        msg.exe $activeSession.SessionId "$title`n`n$msg" | Out-Null
    }

    Write-Host "Warning displayed. Waiting $WarningDelaySeconds seconds..."
    Start-Sleep -Seconds $WarningDelaySeconds
}
else {
    Write-Host "No active user session detected. Proceeding silently."
}

# --- GET WINGET UPDATE LIST ---

Write-Host "Collecting WinGet updates..."

$updateListOutput = & $Winget upgrade `
    --include-unknown `
    --accept-source-agreements `
    --disable-interactivity 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Error "WinGet could not collect available updates (exit code $LASTEXITCODE)."
    return
}

# Find header line and column positions for fixed-width parsing
$headerLine = $null
$idIdx = -1
$verIdx = -1

foreach ($line in $updateListOutput) {
    $str = $line.ToString()
    if ($str -match '^Name\s+Id') {
        $headerLine = $str
        $idIdx = $headerLine.IndexOf('Id')
        $verIdx = $headerLine.IndexOf('Version')
        break
    }
}

$updates = foreach ($line in $updateListOutput) {

    $str = $line.ToString().TrimEnd()

    if ([string]::IsNullOrWhiteSpace($str)) {
        continue
    }

    if ($str -match '^Name\s+Id') {
        continue
    }

    if ($str -match '^-{5,}') {
        continue
    }

    if ($str -match 'upgrades available') {
        continue
    }

    if ($str -match 'No installed package found') {
        continue
    }

    if ($str -match 'No applicable upgrade found') {
        continue
    }

    if ($headerLine -and $idIdx -gt 0 -and $verIdx -gt $idIdx) {

        $name = if ($str.Length -gt 0) { $str.Substring(0, [Math]::Min($str.Length, $idIdx)).Trim() } else { "" }
        $id   = if ($str.Length -gt $idIdx) { $str.Substring($idIdx, [Math]::Min($str.Length - $idIdx, $verIdx - $idIdx)).Trim() } else { "" }

        if ($id -match '\s') {
            $id = ($id -split '\s+')[0]
        }

        if ($name -and $id) {

            [PSCustomObject]@{
                Name = $name
                Id   = $id
            }
            continue
        }
    }

    # Fallback to double-space column splitting
    $columns = $str.Trim() -split '\s{2,}'

    if ($columns.Count -ge 2) {

        [PSCustomObject]@{
            Name = $columns[0].Trim()
            Id   = ($columns[1].Trim() -split '\s+')[0]
        }
    }
}

if (-not $updates -or $updates.Count -eq 0) {
    Write-Host "No updates found."
    return
}

# --- FILTER EXCLUSIONS ---

$upgradeUpdates = @()

foreach ($update in $updates) {

    if ($SkipUpgradeIds -contains $update.Id) {

        Write-Warning "Skipping tenant-managed package $($update.Id)"
        continue
    }

    $upgradeUpdates += $update
}

if ($upgradeUpdates.Count -eq 0) {

    Write-Host "No eligible WinGet upgrades remain after exclusions."
    return
}

# --- BUILD PROCESS LIST ---

$TargetExecutables = @()

foreach ($app in $upgradeUpdates) {

    $matchNames = (
        @($app.Name, $app.Id) +
        @($ProcessAliasMap[$app.Id])
    ) | Where-Object { $_ } |
        ForEach-Object {
            ($_ -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
        } |
        Where-Object {
            $_.Length -ge 3
        } |
        Select-Object -Unique

    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {

        $procName = ($_.ProcessName -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()

        $matchNames -contains $procName
    }

    foreach ($proc in $procs) {

        if ($TargetExecutables -notcontains $proc.ProcessName) {
            $TargetExecutables += $proc.ProcessName
        }
    }
}

foreach ($inc in $IncludeList) {

    if (
        ($TargetExecutables -notcontains $inc) -and
        ($ExcludeList -notcontains $inc)
    ) {
        $TargetExecutables += $inc
    }
}

$TargetExecutables = $TargetExecutables | Where-Object {
    $ExcludeList -notcontains $_
}

# --- FORCE CLOSE APPS ---

if ($TargetExecutables.Count -gt 0) {

    Write-Host "Force-closing processes:"

    foreach ($exe in $TargetExecutables) {

        Write-Host " - $exe"

        $processes = @(Get-Process -Name $exe -ErrorAction SilentlyContinue)

        foreach ($process in $processes) {

            try {

                Stop-Process `
                    -Id $process.Id `
                    -Force `
                    -ErrorAction Stop

                Wait-Process `
                    -Id $process.Id `
                    -Timeout 5 `
                    -ErrorAction SilentlyContinue
            }
            catch {

                Write-Warning "Could not stop $exe (PID $($process.Id)): $($_.Exception.Message)"
            }

            if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {

                Write-Warning "Using taskkill fallback for $exe (PID $($process.Id))."

                & taskkill.exe /PID $process.Id /T /F | Out-Null
            }

            if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {

                Write-Error "Could not close $exe (PID $($process.Id))."
            }
        }
    }
}
else {

    Write-Host "No processes need to be closed."
}

# --- RUN UPGRADES ---

$failedUpgrades = @()

foreach ($app in $upgradeUpdates) {

    Write-Host "Upgrading $($app.Name) [$($app.Id)]..."

    & $Winget upgrade `
        --id $app.Id `
        --exact `
        --include-unknown `
        --accept-source-agreements `
        --accept-package-agreements `
        --disable-interactivity

    if ($LASTEXITCODE -ne 0) {

        $failedUpgrades += $app.Id

        Write-Warning "Upgrade failed for $($app.Id) with exit code $LASTEXITCODE."
    }
}

# --- RESULTS ---

if ($failedUpgrades.Count -eq 0) {

    Write-Host "Eligible WinGet upgrades completed successfully."
}
else {

    Write-Error "WinGet upgrades failed for: $($failedUpgrades -join ', ')"
}