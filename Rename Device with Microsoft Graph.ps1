Install-Module -Name Microsoft.Graph.DeviceManagement -Force

Install-Module -Name Microsoft.Graph.Beta.DeviceManagement.Actions -AllowClobber -Force

Import-Module -Name Microsoft.Graph.DeviceManagement

Import-Module -Name Microsoft.Graph.Beta.DeviceManagement.Actions -Force

Connect-MgGraph -Scopes DeviceManagementManagedDevices.PrivilegedOperations.All, DeviceManagementManagedDevices.Read.All, DeviceManagementManagedDevices.ReadWrite.All
 
$Device = Get-MgDeviceManagementManagedDevice -Filter  "contains(serialNumber,'7RXXXXX')"
 
Set-MgBetaDeviceManagementManagedDeviceName -ManagedDeviceId $Device.Id -DeviceName "YYXXXXX"

Restart-MgBetaDeviceManagementManagedDeviceNow  -ManagedDeviceId $Device.Id
 
Disconnect-MgGraph

