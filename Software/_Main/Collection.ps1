############################################################ DO NOT CHANGE START ############################################################
##Open TLS

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

##Azure DevOps base information for url and token

function RunScript
{
    [cmdletbinding()]
    param(
        $FilePath
    )
    $baseurl = "https://raw.githubusercontent.com/dustin-sigmon/Public/refs/heads/main/[path]"
    $path = [URI]::EscapeDataString($FilePath);
    $resturl =  $baseurl.Replace("[path]", $path)
    #Write-Host $resturl
    $content = Invoke-RestMethod $resturl
    Invoke-Expression $content
}

############################################################ DO NOT CHANGE END ############################################################


$Software = 'GoogleChrome'


switch ($Software) {
"GoogleChrome" { RunScript -FilePath "Software/GoogleChrome.ps1"  ;break }
}