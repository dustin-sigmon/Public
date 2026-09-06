#Software
$softwareID = "Microsoft.Teams.Classic"
$architecture = "x86"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements