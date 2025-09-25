####Remotely rename multiple devices in Intune using Microsoft Graph######

# Gerekli modüller
Import-Module -Name Microsoft.Graph.DeviceManagement
Import-Module -Name Microsoft.Graph.Beta.DeviceManagement.Actions -Force

# CSV dosyasını içe aktar (boş satırları filtrele)
$data = Import-Csv -Path "E:\Shared\asset.csv" -Delimiter ';' | Where-Object { $_.Serial -or $_.Asset }

# Microsoft Graph'a bağlan
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "DeviceManagementManagedDevices.ReadWrite.All", "DeviceManagementManagedDevices.PrivilegedOperations.All"

# Tüm cihazları al
$allDevices = Get-MgDeviceManagementManagedDevice -All

foreach ($row in $data) {
    # Değerleri güvenli şekilde al
    $serial = $row.Serial
    $asset = $row.Asset

    # Cihaz eşleşmesini kontrol et
    $device = $allDevices | Where-Object { $_.SerialNumber -eq $serial }

    if ($device) {
        Write-Host "✓ Eşleşti: $($device.DeviceName) (ID: $($device.Id))"

        # Cihaz adını güncelle
       try {
    if ($device.DeviceName -ne $asset) {

        Set-MgBetaDeviceManagementManagedDeviceName -ManagedDeviceId $device.Id -DeviceName $asset

        Write-Host "→ Cihaz adı '$asset' olarak güncellendi."

    } else {
        Write-Host "✓ Zaten doğru ad: $asset"
    }
        } catch {
    Write-Warning "⚠ Ad değiştirilemedi: $($_.Exception.InnerException.Message)"
}

        # Cihazı yeniden başlat
        try {

            Restart-MgBetaDeviceManagementManagedDeviceNow -ManagedDeviceId $device.Id

            Write-Host "↻ Cihaz yeniden başlatıldı."

        } catch {
            Write-Warning "⚠ Yeniden başlatma başarısız: $($_.Exception.Message)"
        }

    } else {
        Write-Warning "✗ Cihaz bulunamadı: $serial"
    }
}
#Toplu parametrelerde Filter parametresi işe yaramıyor. Graph bunu desteklemiyor.
#Contains() gibi fonksiyonlar sınırlı sayıda property üzerinde çalışır. DeviceName ve SerialNumber gibi.
#Biz kod içerisinde allDevice parametresi ile bu değeri alacağız. Serial=Device ID ile eşleşme yapacak.
# Bağlantıyı kes
Disconnect-MgGraph