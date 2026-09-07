#Software
$softwareID = "Microsoft.DotNet.AspNetCore.10"
$architecture = "x86"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements