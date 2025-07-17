# Registry Path
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$regName = 'CachedLogonsCount'

# Check if the value exists and equals 10
if (Test-Path $regPath) {
    $value = Get-ItemPropertyValue -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    if ($value -eq '10') {
        Write-Output "Compliant"
        exit 0
    }
}

Write-Output "Non-Compliant"
exit 1
