#Software
$softwareID = "OpenJS.NodeJS"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --silent --accept-package-agreements --accept-source-agreements