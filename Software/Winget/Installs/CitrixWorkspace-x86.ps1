#Software
$softwareID = "Citrix.Workspace"
$architecture = "x86"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements