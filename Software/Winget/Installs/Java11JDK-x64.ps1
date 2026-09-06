#Software
$softwareID = "EclipseAdoptium.Temurin.11.JDK"
$architecture = "x64"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --architecture $architecture --silent --accept-package-agreements --accept-source-agreements