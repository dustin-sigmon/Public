#Software
$softwareID = "Microsoft.DotNet.HostingBundle.10"
$architecture = "x86"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements