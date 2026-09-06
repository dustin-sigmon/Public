#Software
$softwareID = "Microsoft.PowerBI"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --silent --accept-package-agreements --accept-source-agreements