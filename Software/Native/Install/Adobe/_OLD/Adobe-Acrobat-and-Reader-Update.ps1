#Start-Sleep -Seconds ([System.Random]::new().Next(1, 15)*60)

$softwareUpdateTimestamp = Get-Date -Format 'yyyy-MM-dd'
#$softwareUpdateTimestamp | & "$env:NINJARMMCLI" set --stdin softwareLastUpdateDate

############################################################ DO NOT CHANGE START ############################################################
##Open TLS

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Verbose log setup
$logDir = "C:\Source\PCT-Logs"
$logFile = Join-Path $logDir "Software-Version-Check.txt"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting Software Version Check..." | Set-Content $logFile

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp $Message" | Add-Content $logFile
}

##Azure DevOps base information for url and token

function RunScript {
    [cmdletbinding()]
    param(
        $FilePath
    )
    $baseurl = "https://source-east-scripts.s3.us-east-va.io.cloud.ovh.us/_Software/[path]"
    $path = $FilePath;
    $resturl = $baseurl.Replace("[path]", $path)
    Write-Log "Running script from: $resturl"
    try {
        $content = Invoke-RestMethod $resturl
        Write-Log "Successfully downloaded script content."
        Invoke-Expression $content
        Write-Log "Successfully executed script: $FilePath"
    }
    catch {
        Write-Log ("ERROR running script {0}: {1}" -f $FilePath, $_)
        throw
    }
}

############################################################ DO NOT CHANGE END ############################################################

function Adobe-Acrobat-2020-Version { try { RunScript -FilePath "_Version-Check/Adobe-Acrobat/Adobe-Acrobat-2020-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }

function Adobe-Acrobat-x64-Version { try { RunScript -FilePath "_Version-Check/Adobe-Acrobat/Adobe-Acrobat-x64-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Acrobat-x86-Version { try { RunScript -FilePath "_Version-Check/Adobe-Acrobat/Adobe-Acrobat-x86-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }

function Adobe-Reader-x64-ENU-Version { try { RunScript -FilePath "_Version-Check/Adobe-Reader/Adobe-Reader-x64-ENU-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Reader-x86-ENU-Version { try { RunScript -FilePath "_Version-Check/Adobe-Reader/Adobe-Reader-x86-ENU-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }

function Adobe-Reader-x64-MUI-Version { try { RunScript -FilePath "_Version-Check/Adobe-Reader/Adobe-Reader-x64-MUI-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }
function Adobe-Reader-x86-MUI-Version { try { RunScript -FilePath "_Version-Check/Adobe-Reader/Adobe-Reader-x86-MUI-Version.ps1" } catch { Write-Host "Install failed: $($_)" } }

& 'Adobe-Acrobat-2020-Version'

& 'Adobe-Acrobat-x64-Version'
& 'Adobe-Acrobat-x86-Version'

& 'Adobe-Reader-x64-ENU-Version'
& 'Adobe-Reader-x86-ENU-Version'

& 'Adobe-Reader-x64-MUI-Version'
& 'Adobe-Reader-x86-MUI-Version'

