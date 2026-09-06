#Software
$softwareID = "Microsoft.DotNet.Runtime.9"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --silent --accept-package-agreements --accept-source-agreements