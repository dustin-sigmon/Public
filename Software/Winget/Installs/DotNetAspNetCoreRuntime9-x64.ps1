#Software
$softwareID = "Microsoft.DotNet.AspNetCore.9"
$architecture = "x64"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements