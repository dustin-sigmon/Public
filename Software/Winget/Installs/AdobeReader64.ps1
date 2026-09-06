#Software
$softwareID = "Adobe.Acrobat.Reader.64-bit"
$type = "install" #install, update, uninstall

winget $type --id $softwareID --exact --silent --accept-package-agreements --accept-source-agreements