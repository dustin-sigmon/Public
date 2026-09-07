#Software
$softwareID = "Python.Python.3.14"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --silent --accept-package-agreements --accept-source-agreements
