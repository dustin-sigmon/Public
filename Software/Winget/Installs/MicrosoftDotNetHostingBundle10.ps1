#Software
$softwareID = "Microsoft.DotNet.HostingBundle.10"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --silent --accept-package-agreements --accept-source-agreements