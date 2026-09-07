#Software
$softwareID = "Microsoft.VCRedist.2015+.x64"
$architecture = "x64"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements