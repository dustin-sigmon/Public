#Software
$softwareID = "Microsoft.DotNet.DesktopRuntime.9"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --silent --accept-package-agreements --accept-source-agreements