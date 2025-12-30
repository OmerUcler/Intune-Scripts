#This script deletes the GRS value of an application by using its ID if a Win32App fails.

$AppId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' 
$Root  = 'HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'

# 1) AppId geçen key'leri reg.exe ile bul (çıktı satırlarından key path çekiyoruz)
$lines = & reg.exe query "$Root" /s /f "$AppId" 2>$null

# 2) Sadece GRS altında olan KEY satırlarını al
$grsKeys = $lines | Where-Object { $_ -match '\\GRS\\' -and $_ -match '^HKEY_' } | Sort-Object -Unique

"Bulunan GRS key sayısı: $($grsKeys.Count)"
$grsKeys | ForEach-Object { "  $_" }

# 3) Sil
foreach ($k in $grsKeys) {
  "SİL -> $k"
  & reg.exe delete "$k" /f | Out-Null
}

