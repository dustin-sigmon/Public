# ============================================
# WinGet Update Process Killer + User Warning
# ============================================

# --- CONFIGURATION ---

# Additional executables you ALWAYS want to force-close
$IncludeList = @(
    "teams",
    "slack",
    "zoom",
    "notepad++"
)

# Executables you NEVER want to force-close
$ExcludeList = @(
    "explorer",
    "onedrive",
    "ninjarmm"
)

# WinGet package IDs do not always match the executable that must be closed.
$ProcessAliasMap = @{
    "Notepad++.Notepad++" = @("notepad++", "npp")
    "Microsoft.Office"    = @("WINWORD", "EXCEL", "OUTLOOK", "POWERPNT", "ONENOTE", "MSACCESS", "MSPUB", "OfficeClickToRun")
}

# Packages managed by another update mechanism or tenant policy.
$SkipUpgradeIds = @(
    "Microsoft.Office"
)

# Seconds to wait after warning before closing apps
$WarningDelaySeconds = 20

$wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $wingetCommand) {
    Write-Error "WinGet (winget.exe) is not installed or is not available in PATH."
    return
}


# --- CHECK USER LOGIN & ACTIVITY ---

# Win32_ComputerSystem.UserName can be empty for active RDP sessions.
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

    # Display warning message on screen
    $msg = "Software updates are preparing to run. Some applications may close automatically."
    $title = "System Maintenance Notice"

    # Send the warning to each active session rather than relying on broadcast behavior.
    foreach ($activeSession in $activeSessions) {
        msg.exe $activeSession.SessionId "$title`n`n$msg" | Out-Null
    }

    Write-Host "Warning displayed. Waiting $WarningDelaySeconds seconds..."
    Start-Sleep -Seconds $WarningDelaySeconds
} else {
    Write-Host "No active user session detected. Proceeding silently."
}


# --- GET WINGET UPDATE LIST ---

Write-Host "Collecting WinGet updates..."
$updateListOutput = & $wingetCommand.Source list --upgrade-available --include-unknown `
    --accept-source-agreements --disable-interactivity 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "WinGet could not collect the available updates (exit code $LASTEXITCODE)."
    return
}

$updates = foreach ($line in @($updateListOutput)) {
    if ($line -match '^\s*(Name\s+Id|[-\s]+$|\d+\s+upgrades? available\.)') {
        continue
    }

    $columns = $line -split '\s{2,}'
    if ($columns.Count -ge 2) {
        [PSCustomObject]@{
            Name = $columns[0].Trim()
            Id   = $columns[1].Trim()
        }
    }
}

if ($updates.Count -eq 0) {
    Write-Host "No updates found."
    return
}

$upgradeUpdates = @($updates | Where-Object {
    if ($SkipUpgradeIds -contains $_.Id) {
        Write-Warning "Skipping tenant-managed package $($_.Id)."
        $false
    } else {
        $true
    }
})


# --- BUILD LIST OF TARGET EXECUTABLES ---

$TargetExecutables = @()

foreach ($app in $upgradeUpdates) {
    $name = $app.Name
    $id   = $app.Id

    # Match normalized names, IDs, and known executable aliases.
    $matchNames = (@($name, $id) + @($ProcessAliasMap[$id])) | Where-Object { $_ } | ForEach-Object {
        ($_ -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    } | Where-Object { $_.Length -ge 3 } | Select-Object -Unique

    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $processName = ($_.ProcessName -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
        $matchNames -contains $processName
    }

    foreach ($p in $procs) {
        if ($TargetExecutables -notcontains $p.ProcessName) {
            $TargetExecutables += $p.ProcessName
        }
    }
}

# Add include list
foreach ($inc in $IncludeList) {
    if ($TargetExecutables -notcontains $inc -and $ExcludeList -notcontains $inc) {
        $TargetExecutables += $inc
    }
}

# Remove exclude list
$TargetExecutables = $TargetExecutables | Where-Object {
    $ExcludeList -notcontains $_
}


# --- FORCE CLOSE PROCESSES ---

if ($TargetExecutables.Count -gt 0) {
    Write-Host "Force-closing processes:"
    $TargetExecutables | ForEach-Object { Write-Host " - $_" }

    foreach ($exe in $TargetExecutables) {
        $processes = @(Get-Process -Name $exe -ErrorAction SilentlyContinue)
        foreach ($process in $processes) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning "Could not stop $exe (PID $($process.Id)): $($_.Exception.Message)"
            }

            if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
                Write-Warning "Using taskkill fallback for $exe (PID $($process.Id))."
                & taskkill.exe /PID $process.Id /T /F | Out-Null
            }

            if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
                Write-Error "Could not close $exe (PID $($process.Id)). WinGet may fail while this application is running."
            }
        }
    }
} else {
    Write-Host "No processes need to be closed."
}


# --- RUN WINGET UPGRADES ---

if ($upgradeUpdates.Count -eq 0) {
    Write-Host "No eligible WinGet upgrades remain after exclusions."
    return
}

$failedUpgrades = @()
foreach ($app in $upgradeUpdates) {
    Write-Host "Upgrading $($app.Name) [$($app.Id)]..."
    & $wingetCommand.Source upgrade --id $app.Id --exact --include-unknown `
        --accept-source-agreements --accept-package-agreements --disable-interactivity

    if ($LASTEXITCODE -ne 0) {
        $failedUpgrades += $app.Id
        Write-Warning "Upgrade failed for $($app.Id) with exit code $LASTEXITCODE."
    }
}

if ($failedUpgrades.Count -eq 0) {
    Write-Host "Eligible WinGet upgrades completed successfully."
} else {
    Write-Error "WinGet upgrades failed for: $($failedUpgrades -join ', ')"
}
