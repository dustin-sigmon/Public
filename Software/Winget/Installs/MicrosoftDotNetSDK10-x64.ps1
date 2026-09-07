#Software
$softwareID = "Microsoft.DotNet.SDK.10"
$architecture = "x64"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements