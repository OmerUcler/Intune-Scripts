# Uygulamanın MSI Product Code'u
$msiProductCode = "{3B470952-1C80-4CB9-AE32-B0DB80913D24}"

# Sessiz kaldırma komutu
Start-Process "msiexec.exe" -ArgumentList "/x $msiProductCode /qn" -Wait -NoNewWindow
