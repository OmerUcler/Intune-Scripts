<#
.SYNOPSIS
  EnforcementState=5000 olan Win32App'leri tespit eder ve:
   - Win32Apps\<UserKey>\<AppKeyName> anahtarını (kök) komple siler (ComplianceStateMessage dahil)
   - Reporting altında ilgili AppId/AppKeyName'e ait kayıtları (özellikle ReportCache ve Application) siler
   - OperationalState altında ilgili AppId kayıtlarını siler
   - (Opsiyonel) IME servisini restart eder
#>

$ErrorActionPreference = 'SilentlyContinue'
$TARGET_ENF = 5000

function Try-GetEnforcementFromJson {
    param([string]$JsonText)
    if ([string]::IsNullOrWhiteSpace($JsonText)) { return $null }

    # Regex ile hızlı yakalama: "EnforcementState":5000
    if ($JsonText -match '"EnforcementState"\s*:\s*(\d+)') {
        return [int]$Matches[1]
    }

    try {
        $obj = $JsonText | ConvertFrom-Json
        if ($obj -and ($obj.PSObject.Properties.Name -contains 'EnforcementState')) {
            return [int]$obj.EnforcementState
        }
    } catch {}
    return $null
}

function Get-AppIdPlain {
    param(
        [string]$AppKeyName,
        [object]$RootProps
    )
    # Öncelik: root'ta AppId varsa onu kullan
    try {
        if ($RootProps -and ($RootProps.PSObject.Properties.Name -contains 'AppId') -and $RootProps.AppId) {
            return $RootProps.AppId.ToString().ToLower()
        }
    } catch {}

    # Yoksa AppKeyName'den _1/_2 gibi suffix'i kırp
    if ($AppKeyName -match '^([0-9a-fA-F-]{36})_\d+$') {
        return $Matches[1].ToLower()
    }

    # Son çare: AppKeyName zaten GUID ise
    if ($AppKeyName -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        return $AppKeyName.ToLower()
    }

    return $null
}

function Remove-KeyIfExists {
    param([string]$PsPath)
    if (-not $PsPath) { return $false }
    if (-not (Test-Path $PsPath)) { return $false }

    try {
        Write-Host "SİL -> $PsPath" -ForegroundColor Yellow
        Remove-Item -Path $PsPath -Recurse -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "Silinemedi: $PsPath | $($_.Exception.Message)"
        return $false
    }
}

# Base Win32Apps path seçimi
$pathsToCheck = @(
    'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\IntuneManagementExtension\Win32Apps'
)
$basePath = $pathsToCheck | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $basePath) {
    Write-Host "Win32Apps path bulunamadı. Çıkılıyor." -ForegroundColor Yellow
    exit 0
}

Write-Host "BasePath: $basePath" -ForegroundColor Cyan
Write-Host "Is64BitProcess: $([Environment]::Is64BitProcess)" -ForegroundColor Cyan

$problemApps = @()

# 1) Win32Apps\<UserKey>\<AppKeyName> altında EnforcementState=5000 tespit et
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

        # EnforcementStateMessage JSON oku
        $esmPath = Join-Path $appRoot 'EnforcementStateMessage'
        if (-not (Test-Path $esmPath)) { continue }

        $rootProps = $null
        try { $rootProps = Get-ItemProperty -Path $appRoot -ErrorAction SilentlyContinue } catch {}

        $esmJson = $null
        try { $esmJson = (Get-ItemProperty -Path $esmPath).EnforcementStateMessage } catch {}

        $enf = Try-GetEnforcementFromJson -JsonText $esmJson
        if ($enf -ne $TARGET_ENF) { continue }

        $appIdPlain = Get-AppIdPlain -AppKeyName $appKeyName -RootProps $rootProps

        Write-Host ">> Problemli app: User=$userName AppKey=$appKeyName AppId=$appIdPlain" -ForegroundColor Magenta

        $problemApps += [PSCustomObject]@{
            UserKey    = $userName
            AppKeyName = $appKeyName
            AppId      = $appIdPlain
            AppRoot    = $appRoot
        }
    }
}

if ($problemApps.Count -eq 0) {
    Write-Host "EnforcementState=5000 olan app bulunamadı. Çıkılıyor." -ForegroundColor Green
    exit 0
}

Write-Host "Toplam problemli app: $($problemApps.Count)" -ForegroundColor Cyan

# 2) Silme işlemleri
$reportingBase = Join-Path $basePath 'Reporting'
$opBase        = Join-Path $basePath 'OperationalState'

foreach ($app in ($problemApps | Sort-Object UserKey, AppKeyName -Unique)) {
    Write-Host ""
    Write-Host "=== TEMİZLİK BAŞLADI: $($app.AppKeyName) ===" -ForegroundColor Cyan

    # 2a) Win32Apps altında app kökünü komple sil (ComplianceStateMessage dahil HER ŞEY gider)
    Remove-KeyIfExists -PsPath $app.AppRoot | Out-Null

    # 2b) OperationalState altında bu AppId geçen key’leri sil
    if ($app.AppId -and (Test-Path $opBase)) {
        $opTargets = Get-ChildItem -Path $opBase -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { $_.PSChildName -ieq $app.AppId } |
                     Select-Object -ExpandProperty PSPath -Unique

        foreach ($t in $opTargets) {
            Remove-KeyIfExists -PsPath $t | Out-Null
        }
    }

    # 2c) Reporting altında bu AppId / AppKeyName geçen key’leri sil
    #     - ReportCache ve Application altlarını da kapsayacak şekilde recurse tarar.
    if (Test-Path $reportingBase) {
        $needles = @()
        if ($app.AppId) { $needles += $app.AppId }
        if ($app.AppKeyName) { $needles += $app.AppKeyName }

        if ($needles.Count -gt 0) {
            $repTargets = Get-ChildItem -Path $reportingBase -Recurse -ErrorAction SilentlyContinue |
                          Where-Object {
                              $leaf = $_.PSChildName
                              ($needles | Where-Object { $leaf -ieq $_ }).Count -gt 0
                          } |
                          Select-Object -ExpandProperty PSPath -Unique

            foreach ($t in $repTargets) {
                # Bu key genelde:
                # ...\Reporting\<GUID>\ReportCache\<AppId>
                # ...\Reporting\<GUID>\Application\<AppId>
                # ...\Reporting\<GUID>\<AppId>
                # şeklinde olur. Direkt bunu silmek yeterli.
                Remove-KeyIfExists -PsPath $t | Out-Null
            }

            # İSTEĞE BAĞLI: Eğer "ReportCache\<AppId>" veya "Application\<AppId>" silindi ama parent klasörde boş kalıntı istemiyorsan:
            # (Parent boşsa Windows otomatik silmez; ama istersen boş parent da temizlenebilir.)
        }
    }

    Write-Host "=== TEMİZLİK BİTTİ: $($app.AppKeyName) ===" -ForegroundColor Green
}

# 3) IME restart (önerilir)
try {
    Write-Host ""
    Write-Host "IME servisi yeniden başlatılıyor..." -ForegroundColor Green
    Restart-Service -DisplayName 'Microsoft Intune Management Extension' -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "IME restart başarısız: $($_.Exception.Message)"
}

exit 0
