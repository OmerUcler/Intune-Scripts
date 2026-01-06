<#
.SYNOPSIS
  Non-compliant koşulları:
   1) Win32Apps\<UserKey>\<AppKey>\EnforcementStateMessage içinde EnforcementState=5000
   2) Reporting altında (ReportCache/Application dahil) sorunlu AppId'ye ait kayıt kalıntısı
   3) OperationalState altında sorunlu AppId'ye ait kayıt kalıntısı

  Bulursa exit 1, yoksa exit 0.
#>

$ErrorActionPreference = 'SilentlyContinue'
$TARGET_ENF = 5000

function Try-GetEnforcementFromJson {
    param([string]$JsonText)
    if ([string]::IsNullOrWhiteSpace($JsonText)) { return $null }
    if ($JsonText -match '"EnforcementState"\s*:\s*(\d+)') { return [int]$Matches[1] }
    try {
        $obj = $JsonText | ConvertFrom-Json
        if ($obj -and ($obj.PSObject.Properties.Name -contains 'EnforcementState')) { return [int]$obj.EnforcementState }
    } catch {}
    return $null
}

function Get-AppIdPlain {
    param([string]$AppKeyName, [object]$RootProps)
    try {
        if ($RootProps -and ($RootProps.PSObject.Properties.Name -contains 'AppId') -and $RootProps.AppId) {
            return $RootProps.AppId.ToString().ToLower()
        }
    } catch {}
    if ($AppKeyName -match '^([0-9a-fA-F-]{36})_\d+$') { return $Matches[1].ToLower() }
    if ($AppKeyName -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { return $AppKeyName.ToLower() }
    return $null
}

# Base path
$pathsToCheck = @(
    'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\IntuneManagementExtension\Win32Apps'
)
$basePath = $pathsToCheck | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $basePath) { exit 0 }

$reportingBase = Join-Path $basePath 'Reporting'
$opBase        = Join-Path $basePath 'OperationalState'

Write-Host "BasePath: $basePath" -ForegroundColor Cyan

# 1) Win32Apps altında EnforcementState=5000 olan app'leri bul
$problemAppIds = New-Object System.Collections.Generic.HashSet[string]
$problemAppKeys = @()

$userKeys = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue
foreach ($userKey in $userKeys) {
    $userName = Split-Path $userKey.Name -Leaf
    if ($userName -in @('GRS','Reporting','OperationalState')) { continue }

    $appKeys = Get-ChildItem -Path $userKey.PSPath -ErrorAction SilentlyContinue | Where-Object {
        $leaf = (Split-Path $_.Name -Leaf)
        $leaf -ne 'GRS' -and $leaf -ne 'Reporting' -and $leaf -ne 'OperationalState'
    }

    foreach ($appKey in $appKeys) {
        $appKeyName = $appKey.PSChildName
        $appRoot    = $appKey.PSPath

        $esmPath = Join-Path $appRoot 'EnforcementStateMessage'
        if (-not (Test-Path $esmPath)) { continue }

        $rootProps = $null
        try { $rootProps = Get-ItemProperty -Path $appRoot -ErrorAction SilentlyContinue } catch {}
        $esmJson = $null
        try { $esmJson = (Get-ItemProperty -Path $esmPath).EnforcementStateMessage } catch {}

        $enf = Try-GetEnforcementFromJson -JsonText $esmJson
        if ($enf -eq $TARGET_ENF) {
            $appId = Get-AppIdPlain -AppKeyName $appKeyName -RootProps $rootProps
            if ($appId) { [void]$problemAppIds.Add($appId) }

            $problemAppKeys += [PSCustomObject]@{
                UserKey    = $userName
                AppKeyName = $appKeyName
                AppId      = $appId
                AppRoot    = $appRoot
            }
        }
    }
}

if ($problemAppKeys.Count -gt 0) {
    Write-Host "Win32Apps altında EnforcementState=5000 bulundu: $($problemAppKeys.Count)" -ForegroundColor Yellow
    $problemAppKeys | Format-Table -AutoSize
    exit 1
}

# 2) Eğer Win32Apps'te 5000 yoksa bile, Reporting/OperationalState'de “kalıntı” var mı?
#    (Bu bölüm ancak sen bunu da non-compliant saymak istiyorsan anlamlıdır.)

$leftovers = @()

# Reporting: ReportCache/Application dahil AppId ile biten keyleri bulmak için tüm reporting ağacını tarıyoruz
if (Test-Path $reportingBase) {
    $repHits = Get-ChildItem -Path $reportingBase -Recurse -ErrorAction SilentlyContinue |
               Where-Object {
                   # Sadece leaf GUID gibi görünenleri raporla (appId formatında)
                   $_.PSChildName -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
               } |
               Select-Object -ExpandProperty PSPath

    # İstersen burada repHits'i "kalan kalıntı" olarak sayabiliriz,
    # ama genelde sadece 5000 sonrası kalıntı aramak istendiği için bu kısmı istersen kapatabiliriz.
    # Şimdilik: hiç 5000 yokken bile reporting'de app kayıtları normaldir.
}

# OperationalState: yine normalde her app için kayıt olabilir. Bu yüzden kalıntıyı "5000 ile ilişkili" ölçmek gerekir.
# Senin senaryonda: non-compliant sadece 5000 ise -> buraya girmeye gerek yok.

Write-Host "EnforcementState=5000 bulunamadı. Compliant." -ForegroundColor Green
exit 0
