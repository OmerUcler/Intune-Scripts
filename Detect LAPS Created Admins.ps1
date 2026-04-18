# Detect-LAPSCreatedAdmins.ps1

# ---- CONFIG ----
$UsersToRemove = @(
  "WLapsAdmin"
)

$ProtectedUsers = @(
  "Administrator",   # built-in (rename ettiysen yeni adını da ekle)
  "DefaultAccount",
  "WDAGUtilityAccount",
  "IntuneUser",
  "LAPSuser"
)

function Get-LocalUserNames {
  try {
    return (Get-LocalUser -ErrorAction Stop | Select-Object -ExpandProperty Name)
  } catch {
    return @()
  }
}

$localUsers = Get-LocalUserNames

$matches = @()
foreach ($u in $localUsers) {
  if ($ProtectedUsers -contains $u) { continue }
  foreach ($p in $UsersToRemove) {
    if ($u -like $p) { $matches += $u; break }
  }
}

if ($matches.Count -gt 0) {
  Write-Output ("Found removable local user(s): " + ($matches -join ", "))
  exit 1
}

Write-Output "No removable local users found."
exit 0
