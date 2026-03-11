#requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

# =========================================================
# N3Z OPTIMIZER
# Windows 10 / 11
# Competitive Focused Edition
# GitHub One-Line Ready
# =========================================================

$Script:ScriptRoot         = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Script:AppName            = "N3Z OPTIMIZER"
$Script:Version            = "2.5"
$Script:BaseDir            = Join-Path $env:ProgramData "N3Z-Optimizer"
$Script:LogFile            = Join-Path $Script:BaseDir "n3z-optimizer.log"
$Script:ConfigDir          = Join-Path $Script:BaseDir "backup"
$Script:AssetsDir          = Join-Path $Script:ScriptRoot "assets"
$Script:PowerPlanFile      = Join-Path $Script:AssetsDir "N3Z-Optimized.pow"
$Script:TempPowerPlanFile  = Join-Path $env:TEMP "N3Z-Optimized.pow"
$Script:PowerPlanUrl       = "https://raw.githubusercontent.com/Pooluser/N3Z-Optimizer/main/assets/N3Z-Optimized.pow"

New-Item -ItemType Directory -Path $Script:BaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $Script:ConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $Script:AssetsDir -Force | Out-Null

# =========================================================
# UI / LOG
# =========================================================

function Write-Log {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $Script:LogFile -Value "$time | $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
    Write-Log "OK - $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
    Write-Log "WARN - $Message"
}

function Write-Err {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
    Write-Log "ERR - $Message"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
    Write-Log "INFO - $Message"
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
}

function Pause-Continue {
    Write-Host ""
    Read-Host "Presiona Enter para continuar"
}

function Show-Banner {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host "                    N3Z OPTIMIZER v$($Script:Version)" -ForegroundColor Magenta
    Write-Host "       Windows 10 / 11 | Competitive / Gaming Edition" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host ""
}

# =========================================================
# CORE
# =========================================================

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        Write-Err "Ejecuta PowerShell como administrador."
        Pause-Continue
        exit 1
    }
}

function Get-OSInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

    $buildNumber = 0
    [int]::TryParse($os.BuildNumber, [ref]$buildNumber) | Out-Null

    $realProductName = $cv.ProductName
    if ($buildNumber -ge 22000) {
        if ($realProductName -match '^Windows 10') {
            $realProductName = $realProductName -replace '^Windows 10', 'Windows 11'
        }
        elseif ($realProductName -notmatch '^Windows 11') {
            $realProductName = "Windows 11"
        }
    }
    else {
        if ($realProductName -notmatch '^Windows 10') {
            $realProductName = "Windows 10"
        }
    }

    [PSCustomObject]@{
        ProductName = $realProductName
        Version     = $os.Version
        Build       = $os.BuildNumber
        DisplayVer  = $cv.DisplayVersion
    }
}

function Show-SystemInfo {
    $info = Get-OSInfo
    Write-Host "Sistema : $($info.ProductName)" -ForegroundColor White
    Write-Host "Version : $($info.Version)" -ForegroundColor White
    Write-Host "Build   : $($info.Build)" -ForegroundColor White
    Write-Host "Display : $($info.DisplayVer)" -ForegroundColor White
    Write-Host "Script  : $($Script:ScriptRoot)" -ForegroundColor DarkGray
    Write-Host ""
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-ServiceExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Service -Name $Name -ErrorAction SilentlyContinue)
}

function Get-ServicesByPattern {
    param([Parameter(Mandatory)][string]$Pattern)
    return @(Get-Service -Name $Pattern -ErrorAction SilentlyContinue)
}

function Test-TaskExists {
    param(
        [Parameter(Mandatory)][string]$TaskPath,
        [Parameter(Mandatory)][string]$TaskName
    )
    return [bool](Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue)
}

function Test-ProcessExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue)
}

function Get-GpuVendor {
    try {
        $gpuNames = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        $text = ($gpuNames -join " ")
        if ($text -match "NVIDIA") { return "NVIDIA" }
        if ($text -match "AMD|Radeon") { return "AMD" }
        if ($text -match "Intel") { return "INTEL" }
    } catch {}
    return "UNKNOWN"
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet("String","ExpandString","Binary","DWord","MultiString","QWord")]
        [string]$Type = "DWord"
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force | Out-Null
        } else {
            New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
        }

        return $true
    } catch {
        return $false
    }
}

function Set-RegistryValuesBatch {
    param([array]$Items)

    foreach ($item in $Items) {
        $ok = Set-RegistryValue -Path $item.Path -Name $item.Name -Value $item.Value -Type $item.Type
        if ($ok) {
            Write-Ok "Registro aplicado: $($item.Path) -> $($item.Name)"
        } else {
            Write-Warn "No se pudo aplicar registro: $($item.Path) -> $($item.Name)"
        }
    }
}

function Set-ServiceManualSafe {
    param([string]$Name)

    if (-not (Test-ServiceExists -Name $Name)) {
        Write-Info "Servicio no existe en este sistema: $Name"
        return
    }

    try {
        Set-Service -Name $Name -StartupType Manual
        Write-Ok "Servicio en manual: $Name"
    } catch {
        Write-Warn "No se pudo poner en manual: $Name"
    }
}

function Disable-ServiceSafe {
    param([string]$Name)

    if (-not (Test-ServiceExists -Name $Name)) {
        Write-Info "Servicio no existe en este sistema: $Name"
        return
    }

    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $Name -StartupType Disabled
        Write-Ok "Servicio deshabilitado: $Name"
    } catch {
        Write-Warn "No se pudo deshabilitar servicio: $Name"
    }
}

function Set-ServiceManualByPatternSafe {
    param([string]$Pattern)

    $services = Get-ServicesByPattern -Pattern $Pattern
    if (-not $services -or $services.Count -eq 0) {
        Write-Info "No existen servicios para patron: $Pattern"
        return
    }

    foreach ($svc in $services) {
        try {
            Set-Service -Name $svc.Name -StartupType Manual
            Write-Ok "Servicio en manual: $($svc.Name)"
        } catch {
            Write-Warn "No se pudo poner en manual: $($svc.Name)"
        }
    }
}

function Disable-ServiceByPatternSafe {
    param([string]$Pattern)

    $services = Get-ServicesByPattern -Pattern $Pattern
    if (-not $services -or $services.Count -eq 0) {
        Write-Info "No existen servicios para patron: $Pattern"
        return
    }

    foreach ($svc in $services) {
        try {
            if ($svc.Status -eq "Running") {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name $svc.Name -StartupType Disabled
            Write-Ok "Servicio deshabilitado: $($svc.Name)"
        } catch {
            Write-Warn "No se pudo deshabilitar: $($svc.Name)"
        }
    }
}

function Disable-ScheduledTaskSafe {
    param([string]$TaskPath, [string]$TaskName)

    if (-not (Test-TaskExists -TaskPath $TaskPath -TaskName $TaskName)) {
        Write-Info "Tarea no existe en este sistema: $TaskPath$TaskName"
        return
    }

    try {
        Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName | Out-Null
        Write-Ok "Tarea deshabilitada: $TaskPath$TaskName"
    } catch {
        Write-Warn "No se pudo deshabilitar tarea: $TaskPath$TaskName"
    }
}

function Stop-ProcessSafe {
    param([string]$Name)

    if (-not (Test-ProcessExists -Name $Name)) {
        Write-Info "Proceso no activo o no existe: $Name"
        return
    }

    try {
        $procs = Get-Process -Name $Name -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 300
        Write-Ok "Proceso detenido: $Name"
    } catch {
        Write-Warn "No se pudo detener proceso: $Name"
    }
}

function Get-GuidFromText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $guidMatch = [regex]::Match($Text, '[0-9A-Fa-f-]{36}')
    if ($guidMatch.Success) {
        return $guidMatch.Value
    }

    return $null
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    Write-Section $Name
    Write-Log "STEP START - $Name"

    try {
        & $Action
        Start-Sleep -Milliseconds 250
        Write-Log "STEP END - $Name"
    } catch {
        Write-Warn "Fallo el paso: $Name"
        Write-Log "STEP FAIL - $Name"
    }
}

# =========================================================
# BACKUP / RESTORE
# =========================================================

function Create-SystemRestorePoint {
    if (-not (Test-CommandExists -Name "Checkpoint-Computer")) {
        Write-Info "Restore Point no disponible en este sistema."
        return
    }

    try {
        Enable-ComputerRestore -Drive "C:\" | Out-Null
        Checkpoint-Computer -Description "N3Z OPTIMIZER - Before Changes" -RestorePointType "MODIFY_SETTINGS" | Out-Null
        Write-Ok "Punto de restauracion creado."
    } catch {
        Write-Warn "No se pudo crear el punto de restauracion."
    }
}

function Backup-RegistryKey {
    param(
        [string]$NativePath,
        [string]$FileName
    )

    if (-not (Test-CommandExists -Name "reg")) {
        Write-Info "Comando reg no disponible."
        return
    }

    try {
        $file = Join-Path $Script:ConfigDir $FileName
        reg export $NativePath $file /y | Out-Null
        Write-Ok "Backup exportado: $FileName"
    } catch {
        Write-Warn "No se pudo exportar backup: $FileName"
    }
}

function Backup-ImportantSettings {
    Backup-RegistryKey -NativePath "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -FileName "ContentDeliveryManager.reg"
    Backup-RegistryKey -NativePath "HKCU\Control Panel\Desktop" -FileName "Desktop.reg"
    Backup-RegistryKey -NativePath "HKCU\Software\Microsoft\GameBar" -FileName "GameBar.reg"
    Backup-RegistryKey -NativePath "HKCU\System\GameConfigStore" -FileName "GameConfigStore.reg"
    Backup-RegistryKey -NativePath "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -FileName "DataCollection.reg"
}

# =========================================================
# OPTIMIZATION MODULES
# =========================================================

function Apply-PrivacyTweaks {
    $regItems = @(
        @{ Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name="AllowTelemetry"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name="Enabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name="TailoredExperiencesWithDiagnosticDataEnabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Siuf\Rules"; Name="NumberOfSIUFInPeriod"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="ContentDeliveryAllowed"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="FeatureManagementEnabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="OemPreInstalledAppsEnabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="PreInstalledAppsEnabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="PreInstalledAppsEverEnabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SilentInstalledAppsEnabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SoftLandingEnabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338388Enabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338389Enabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-353694Enabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-353696Enabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SystemPaneSuggestionsEnabled"; Value=0; Type="DWord" }
    )

    Set-RegistryValuesBatch -Items $regItems

    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Application Experience\" -TaskName "Microsoft Compatibility Appraiser"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Application Experience\" -TaskName "ProgramDataUpdater"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Customer Experience Improvement Program\" -TaskName "Consolidator"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Customer Experience Improvement Program\" -TaskName "UsbCeip"

    Set-ServiceManualSafe "DiagTrack"
    Set-ServiceManualSafe "dmwappushservice"

    Write-Ok "Privacidad optimizada."
}

function Apply-PerformanceTweaks {
    $regItems = @(
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"; Name="VisualFXSetting"; Value=2; Type="DWord" }
        @{ Path="HKCU:\Control Panel\Desktop"; Name="MenuShowDelay"; Value="20"; Type="String" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"; Name="StartupDelayInMSec"; Value=0; Type="DWord" }
        @{ Path="HKCU:\System\GameConfigStore"; Name="GameDVR_Enabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\GameBar"; Name="ShowStartupPanel"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\GameBar"; Name="AllowAutoGameMode"; Value=1; Type="DWord" }
        @{ Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"; Name="DODownloadMode"; Value=0; Type="DWord" }
    )

    Set-RegistryValuesBatch -Items $regItems

    if (Test-CommandExists -Name "powercfg") {
        try {
            powercfg /hibernate off | Out-Null
            Write-Ok "Hibernacion desactivada."
        } catch {
            Write-Warn "No se pudo desactivar hibernacion."
        }
    }

    Write-Ok "Rendimiento optimizado."
}

function Apply-ExplorerTweaks {
    $regItems = @(
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="Hidden"; Value=1; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="HideFileExt"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="ShowSuperHidden"; Value=1; Type="DWord" }
    )

    Set-RegistryValuesBatch -Items $regItems
    Write-Ok "Explorer ajustado."
}

function Apply-Cleanup {
    if (Test-Path $env:TEMP) {
        try {
            Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Temp de usuario limpiado."
        } catch {
            Write-Warn "No se pudo limpiar temp de usuario completo."
        }
    }

    if (Test-Path "C:\Windows\Temp") {
        try {
            Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Temp del sistema limpiado."
        } catch {
            Write-Warn "No se pudo limpiar temp del sistema completo."
        }
    }

    if (Test-CommandExists -Name "cleanmgr.exe") {
        try {
            Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/VERYLOWDISK" -Wait -NoNewWindow
            Write-Ok "Liberador de espacio ejecutado."
        } catch {
            Write-Warn "No se pudo ejecutar cleanmgr."
        }
    } else {
        Write-Info "cleanmgr no disponible en este sistema."
    }
}

function Apply-NetworkReset {
    if (Test-CommandExists -Name "ipconfig") {
        try {
            ipconfig /flushdns | Out-Null
            Write-Ok "Cache DNS limpiada."
        } catch {
            Write-Warn "No se pudo limpiar DNS."
        }
    }

    if (Test-CommandExists -Name "netsh") {
        try {
            netsh winsock reset | Out-Null
            Write-Ok "Winsock reset aplicado."
        } catch {
            Write-Warn "No se pudo resetear Winsock."
        }

        try {
            netsh int ip reset | Out-Null
            Write-Ok "IP stack reset aplicado."
        } catch {
            Write-Warn "No se pudo resetear IP stack."
        }
    }
}

function Apply-WindowsUpdateSafe {
    $regItems = @(
        @{ Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"; Name="NoAutoRebootWithLoggedOnUsers"; Value=1; Type="DWord" }
        @{ Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"; Name="AUOptions"; Value=3; Type="DWord" }
    )

    Set-RegistryValuesBatch -Items $regItems
    Write-Ok "Windows Update ajustado de forma segura."
}

function Apply-PowerPlan {
    if (-not (Test-CommandExists -Name "powercfg")) {
        Write-Info "powercfg no disponible."
        return
    }

    if (-not (Test-Path $Script:PowerPlanFile)) {
        try {
            Invoke-WebRequest -Uri $Script:PowerPlanUrl -OutFile $Script:TempPowerPlanFile -UseBasicParsing
            if (Test-Path $Script:TempPowerPlanFile) {
                $Script:PowerPlanFile = $Script:TempPowerPlanFile
                Write-Ok "Plan .pow descargado desde GitHub."
            }
        } catch {
            Write-Warn "No se pudo descargar el plan personalizado desde GitHub."
        }
    }

    if (Test-Path $Script:PowerPlanFile) {
        try {
            $before = powercfg /list
            powercfg /import $Script:PowerPlanFile | Out-Null
            Start-Sleep -Seconds 2
            $after = powercfg /list

            $beforeText = ($before | Out-String)
            $newPlan = ($after | Where-Object { $_ -match 'GUID' } | Where-Object { $beforeText -notmatch [regex]::Escape($_) } | Select-Object -First 1)

            if ($newPlan) {
                $guid = Get-GuidFromText -Text ($newPlan | Out-String)
                if ($guid) {
                    powercfg /setactive $guid | Out-Null
                    Write-Ok "Plan .pow importado y activado."
                    return
                }
            }
        } catch {
            Write-Warn "No se pudo importar el plan personalizado."
        }
    }

    try {
        powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
    } catch {}

    try {
        $plans = powercfg /list
        $ultimateLine = $plans | Where-Object { $_ -match "e9a42b02-d5df-448d-aa00-03f14749eb61" }

        if ($ultimateLine) {
            powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
            Write-Ok "Ultimate Performance activado."
            return
        }
    } catch {}

    try {
        powercfg /setactive SCHEME_MIN | Out-Null
        Write-Ok "High Performance activado."
    } catch {
        Write-Warn "No se pudo activar el plan de energia."
    }
}

function Apply-BackgroundReductionSafe {
    $regItems = @(
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarMn"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarDa"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name="SearchboxTaskbarMode"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name="GlobalUserDisabled"; Value=1; Type="DWord" }
    )

    Set-RegistryValuesBatch -Items $regItems

    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Maps\" -TaskName "MapsUpdateTask"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Maps\" -TaskName "MapsToastTask"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Feedback\Siuf\" -TaskName "DmClient"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Feedback\Siuf\" -TaskName "DmClientOnScenarioDownload"

    Set-ServiceManualSafe "MapsBroker"
    Set-ServiceManualSafe "lfsvc"
    Set-ServiceManualSafe "PimIndexMaintenanceSvc"
    Set-ServiceManualSafe "WSearch"
    Set-ServiceManualSafe "PhoneSvc"

    Stop-ProcessSafe "Widgets"
    Stop-ProcessSafe "msedgewebview2"
    Stop-ProcessSafe "OneDrive"
    Stop-ProcessSafe "Teams"
    Stop-ProcessSafe "YourPhone"
    Stop-ProcessSafe "PhoneExperienceHost"
    Stop-ProcessSafe "GameBar"

    Write-Ok "Procesos en segundo plano reducidos (SAFE)."
}

function Apply-BackgroundReductionExtreme {
    Apply-BackgroundReductionSafe

    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\XblGameSave\" -TaskName "XblGameSaveTask"

    Set-ServiceManualSafe "XblAuthManager"
    Set-ServiceManualSafe "XblGameSave"
    Set-ServiceManualSafe "XboxNetApiSvc"

    Stop-ProcessSafe "SearchHost"
    Stop-ProcessSafe "SearchApp"
    Stop-ProcessSafe "XboxAppServices"

    Write-Warn "EXTREME reduce mas procesos, pero puede quitar comodidad del sistema."
    Write-Ok "Procesos en segundo plano reducidos (EXTREME)."
}

function Apply-DebloatOptional {
    $appsToRemove = @(
        "Microsoft.3DBuilder",
        "Microsoft.XboxApp",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.Xbox.TCUI",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Microsoft.BingNews",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.People"
    )

    foreach ($app in $appsToRemove) {
        try {
            $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Write-Ok "App removida: $app"
            } else {
                Write-Info "App no existe o ya fue removida: $app"
            }
        } catch {
            Write-Warn "No se pudo remover app instalada: $app"
        }

        try {
            $prov = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $app
            if ($prov) {
                $prov | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                Write-Ok "Provisioned app removida: $app"
            }
        } catch {
            Write-Warn "No se pudo remover provisioned app: $app"
        }
    }
}

# =========================================================
# KERNEL-LIKE ADDITIONS
# =========================================================

function Remove-AppxPackagesSafe {
    param([string[]]$PackageNames)

    foreach ($app in $PackageNames) {
        try {
            $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Write-Ok "App instalada removida: $app"
            } else {
                Write-Info "App instalada no encontrada: $app"
            }
        } catch {
            Write-Warn "No se pudo remover AppX instalada: $app"
        }

        try {
            $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $app
            if ($prov) {
                $prov | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                Write-Ok "Provisioned app removida: $app"
            } else {
                Write-Info "Provisioned app no encontrada: $app"
            }
        } catch {
            Write-Warn "No se pudo remover provisioned AppX: $app"
        }
    }
}

function Apply-KernelLikePolicies {
    $regItems = @(
        @{ Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name="DisableWindowsConsumerFeatures"; Value=1; Type="DWord" }
        @{ Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name="DisableSoftLanding"; Value=1; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name="GlobalUserDisabled"; Value=1; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarMn"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarDa"; Value=0; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name="SearchboxTaskbarMode"; Value=0; Type="DWord" }
    )

    Set-RegistryValuesBatch -Items $regItems
    Write-Ok "Kernel-like policies aplicadas."
}

function Apply-KernelLikeServiceReduction {
    Disable-ServiceSafe "RemoteRegistry"
    Disable-ServiceSafe "RemoteAccess"
    Disable-ServiceSafe "ssh-agent"
    Disable-ServiceSafe "WMPNetworkSvc"
    Disable-ServiceSafe "PrintNotify"
    Disable-ServiceSafe "DusmSvc"

    Set-ServiceManualSafe "tzautoupdate"
    Set-ServiceManualSafe "lltdsvc"
    Set-ServiceManualSafe "lmhosts"
    Set-ServiceManualSafe "SensrSvc"
    Set-ServiceManualSafe "WSearch"
    Set-ServiceManualSafe "MapsBroker"
    Set-ServiceManualSafe "PhoneSvc"

    Write-Ok "Reduccion de servicios tipo Kernel aplicada."
}

function Apply-KernelLikeTaskReduction {
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Maps\" -TaskName "MapsUpdateTask"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Maps\" -TaskName "MapsToastTask"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Feedback\Siuf\" -TaskName "DmClient"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Feedback\Siuf\" -TaskName "DmClientOnScenarioDownload"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Application Experience\" -TaskName "Microsoft Compatibility Appraiser"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Application Experience\" -TaskName "ProgramDataUpdater"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Customer Experience Improvement Program\" -TaskName "Consolidator"
    Disable-ScheduledTaskSafe -TaskPath "\Microsoft\Windows\Customer Experience Improvement Program\" -TaskName "UsbCeip"

    Write-Ok "Reduccion de tareas tipo Kernel aplicada."
}

function Apply-KernelLikeProcessReduction {
    Stop-ProcessSafe "Widgets"
    Stop-ProcessSafe "msedgewebview2"
    Stop-ProcessSafe "OneDrive"
    Stop-ProcessSafe "Teams"
    Stop-ProcessSafe "YourPhone"
    Stop-ProcessSafe "PhoneExperienceHost"
    Stop-ProcessSafe "GameBar"
    Stop-ProcessSafe "SearchHost"
    Stop-ProcessSafe "SearchApp"
    Stop-ProcessSafe "XboxAppServices"

    Write-Ok "Reduccion de procesos tipo Kernel aplicada."
}

function Apply-KernelLikeAppxReduction {
    $kernelLikeApps = @(
        "Microsoft.3DBuilder",
        "Microsoft.549981C3F5F10",
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal",
        "Microsoft.Office.OneNote",
        "Microsoft.People",
        "Microsoft.SkypeApp",
        "Microsoft.WindowsAlarms",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps",
        "Microsoft.WindowsSoundRecorder",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Clipchamp.Clipchamp",
        "MicrosoftTeams"
    )

    Remove-AppxPackagesSafe -PackageNames $kernelLikeApps
    Write-Ok "Reduccion AppX tipo Kernel aplicada."
}

function Apply-KernelLikeServiceReductionV2 {
    Disable-ServiceSafe "DoSvc"
    Disable-ServiceSafe "DusmSvc"
    Disable-ServiceSafe "TrkWks"

    Set-ServiceManualSafe "AppIDSvc"
    Set-ServiceManualSafe "BDESVC"
    Set-ServiceManualSafe "FontCache"
    Set-ServiceManualSafe "lfsvc"
    Set-ServiceManualSafe "lmhosts"
    Set-ServiceManualSafe "PcaSvc"
    Set-ServiceManualSafe "SysMain"
    Set-ServiceManualSafe "WSearch"

    Disable-ServiceByPatternSafe "OneSyncSvc_*"
    Set-ServiceManualByPatternSafe "CDPUserSvc_*"
    Set-ServiceManualByPatternSafe "WpnUserService_*"
    Set-ServiceManualByPatternSafe "cbdhsvc_*"

    Write-Ok "Reduccion de servicios tipo Kernel V2 aplicada."
}

function Apply-KernelLikeUserServiceReductionV2 {
    Stop-ProcessSafe "SearchHost"
    Stop-ProcessSafe "SearchApp"
    Stop-ProcessSafe "StartMenuExperienceHost"
    Stop-ProcessSafe "ShellExperienceHost"

    Write-Ok "Reduccion adicional V2 aplicada."
}

# =========================================================
# GPU / VENDOR PROFILES
# =========================================================

function Apply-WindowsGraphicsCompetitive {
    $regItems = @(
        @{ Path="HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Name="HwSchMode"; Value=2; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\GameBar"; Name="AutoGameModeEnabled"; Value=1; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\GameBar"; Name="ShowStartupPanel"; Value=0; Type="DWord" }
        @{ Path="HKCU:\System\GameConfigStore"; Name="GameDVR_Enabled"; Value=0; Type="DWord" }
        @{ Path="HKCU:\System\GameConfigStore"; Name="GameDVR_FSEBehaviorMode"; Value=2; Type="DWord" }
        @{ Path="HKCU:\System\GameConfigStore"; Name="GameDVR_HonorUserFSEBehaviorMode"; Value=1; Type="DWord" }
        @{ Path="HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"; Name="DirectXUserGlobalSettings"; Value="VRROptimizeEnable=1;" ; Type="String" }
    )

    Set-RegistryValuesBatch -Items $regItems
    Write-Ok "Windows graphics competitive profile aplicado."
}

function Apply-NvidiaOverlayReduction {
    Stop-ProcessSafe "NVIDIA Share"
    Stop-ProcessSafe "NVIDIA Web Helper"
    Stop-ProcessSafe "nvsphelper64"
    Stop-ProcessSafe "NVIDIA Overlay"
    Stop-ProcessSafe "nvcontainer"
    Write-Info "Si usas NVIDIA App / GeForce Experience overlay, se recomienda desactivar el overlay manualmente."
}

function Apply-AmdOverlayReduction {
    Stop-ProcessSafe "RadeonSoftware"
    Stop-ProcessSafe "AMDRSServ"
    Stop-ProcessSafe "AMDOW"
    Stop-ProcessSafe "atiesrxx"
    Stop-ProcessSafe "atieclxx"
    Write-Info "Si usas AMD Adrenalin overlay, se recomienda desactivar el overlay manualmente."
}

function Open-NvidiaPanel {
    try {
        Start-Process "nvcplui.exe" -ErrorAction SilentlyContinue | Out-Null
        Write-Ok "NVIDIA Control Panel abierto."
    } catch {
        Write-Info "No se pudo abrir NVIDIA Control Panel automaticamente."
    }
}

function Open-AmdSoftware {
    $paths = @(
        "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe",
        "$env:ProgramFiles\AMD\CNext\CNext\cncmd.exe",
        "$env:ProgramFiles\AMD\Performance Profile Client\AMDPerformanceProfileClient.exe"
    )

    $opened = $false
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try {
                Start-Process $p -ErrorAction SilentlyContinue | Out-Null
                Write-Ok "AMD Software abierto."
                $opened = $true
                break
            } catch {}
        }
    }

    if (-not $opened) {
        Write-Info "No se pudo abrir AMD Software automaticamente."
    }
}

function Show-NvidiaRecommendations {
    Write-Section "NVIDIA MANUAL CHECKLIST"
    Write-Host "En NVIDIA Control Panel, para competitivo normalmente conviene:" -ForegroundColor White
    Write-Host " - Low Latency Mode: Ultra" -ForegroundColor Gray
    Write-Host " - Power management mode: Prefer maximum performance" -ForegroundColor Gray
    Write-Host " - Texture filtering - Quality: High performance" -ForegroundColor Gray
    Write-Host " - Vertical sync: Off" -ForegroundColor Gray
    Write-Host " - Threaded optimization: Auto" -ForegroundColor Gray
    Write-Host " - Triple buffering: Off" -ForegroundColor Gray
    Write-Host " - Max Frame Rate: Off o ajustado segun tu monitor" -ForegroundColor Gray
    Write-Host " - Image Scaling / filters: solo si realmente lo necesitas" -ForegroundColor Gray
}

function Show-AmdRecommendations {
    Write-Section "AMD MANUAL CHECKLIST"
    Write-Host "En AMD Adrenalin, para competitivo normalmente conviene:" -ForegroundColor White
    Write-Host " - Radeon Anti-Lag: On" -ForegroundColor Gray
    Write-Host " - Radeon Chill: Off" -ForegroundColor Gray
    Write-Host " - Radeon Boost: Off o probar segun juego" -ForegroundColor Gray
    Write-Host " - Wait for Vertical Refresh: Always Off" -ForegroundColor Gray
    Write-Host " - Texture Filtering Quality: Performance" -ForegroundColor Gray
    Write-Host " - Surface Format Optimization: On" -ForegroundColor Gray
    Write-Host " - Enhanced Sync: Off para competitivo puro, o probar" -ForegroundColor Gray
    Write-Host " - Radeon Super Resolution: solo si la necesitas" -ForegroundColor Gray
}

function Run-NvidiaCompetitiveProfile {
    $vendor = Get-GpuVendor
    if ($vendor -ne "NVIDIA") {
        Write-Warn "No detecte NVIDIA como GPU principal. Aun asi se puede aplicar la parte Windows."
    }

    Invoke-Step -Name "Competitive SAFE Base" -Action { Run-CompetitiveSafe }
    Invoke-Step -Name "Windows Graphics Competitive" -Action { Apply-WindowsGraphicsCompetitive }
    Invoke-Step -Name "NVIDIA Overlay Reduction" -Action { Apply-NvidiaOverlayReduction }
    Invoke-Step -Name "Open NVIDIA Control Panel" -Action { Open-NvidiaPanel }

    Show-NvidiaRecommendations
    Write-Info "Perfil NVIDIA aplicado."
    Write-Info "Reinicia el PC y luego revisa el panel NVIDIA."
}

function Run-AmdCompetitiveProfile {
    $vendor = Get-GpuVendor
    if ($vendor -ne "AMD") {
        Write-Warn "No detecte AMD como GPU principal. Aun asi se puede aplicar la parte Windows."
    }

    Invoke-Step -Name "Competitive SAFE Base" -Action { Run-CompetitiveSafe }
    Invoke-Step -Name "Windows Graphics Competitive" -Action { Apply-WindowsGraphicsCompetitive }
    Invoke-Step -Name "AMD Overlay Reduction" -Action { Apply-AmdOverlayReduction }
    Invoke-Step -Name "Open AMD Software" -Action { Open-AmdSoftware }

    Show-AmdRecommendations
    Write-Info "Perfil AMD aplicado."
    Write-Info "Reinicia el PC y luego revisa AMD Software."
}

function Run-RepairTools {
    if (Test-CommandExists -Name "DISM") {
        try {
            DISM /Online /Cleanup-Image /RestoreHealth
            Write-Ok "DISM completado."
        } catch {
            Write-Warn "No se pudo completar DISM."
        }
    } else {
        Write-Info "DISM no disponible."
    }

    if (Test-CommandExists -Name "sfc") {
        try {
            sfc /scannow
            Write-Ok "SFC completado."
        } catch {
            Write-Warn "No se pudo completar SFC."
        }
    } else {
        Write-Info "SFC no disponible."
    }
}

function Install-BasicApps {
    if (-not (Test-CommandExists -Name "winget")) {
        Write-Warn "winget no esta disponible."
        return
    }

    $apps = @(
        "Google.Chrome",
        "7zip.7zip",
        "VideoLAN.VLC",
        "Notepad++.Notepad++"
    )

    foreach ($app in $apps) {
        try {
            winget install --id $app -e --accept-package-agreements --accept-source-agreements --silent
            Write-Ok "Instalada: $app"
        } catch {
            Write-Warn "No se pudo instalar: $app"
        }
    }
}

# =========================================================
# MAIN PROFILES
# =========================================================

function Run-CompetitiveSafe {
    Invoke-Step -Name "Backup" -Action { Backup-ImportantSettings }
    Invoke-Step -Name "Restore Point" -Action { Create-SystemRestorePoint }
    Invoke-Step -Name "Privacy Tweaks" -Action { Apply-PrivacyTweaks }
    Invoke-Step -Name "Performance Tweaks" -Action { Apply-PerformanceTweaks }
    Invoke-Step -Name "Explorer Tweaks" -Action { Apply-ExplorerTweaks }
    Invoke-Step -Name "Background Reduction SAFE" -Action { Apply-BackgroundReductionSafe }
    Invoke-Step -Name "Power Plan" -Action { Apply-PowerPlan }
    Invoke-Step -Name "Windows Update Safe" -Action { Apply-WindowsUpdateSafe }
    Invoke-Step -Name "Cleanup" -Action { Apply-Cleanup }

    Write-Info "Perfil recomendado para Fortnite y juego competitivo."
    Write-Info "Reinicia el PC al terminar para aplicar todo mejor."
    Write-Ok "COMPETITIVE SAFE completado."
}

function Run-CompetitiveExtreme {
    Invoke-Step -Name "Backup" -Action { Backup-ImportantSettings }
    Invoke-Step -Name "Restore Point" -Action { Create-SystemRestorePoint }
    Invoke-Step -Name "Privacy Tweaks" -Action { Apply-PrivacyTweaks }
    Invoke-Step -Name "Performance Tweaks" -Action { Apply-PerformanceTweaks }
    Invoke-Step -Name "Explorer Tweaks" -Action { Apply-ExplorerTweaks }
    Invoke-Step -Name "Background Reduction EXTREME" -Action { Apply-BackgroundReductionExtreme }
    Invoke-Step -Name "Power Plan" -Action { Apply-PowerPlan }
    Invoke-Step -Name "Windows Update Safe" -Action { Apply-WindowsUpdateSafe }
    Invoke-Step -Name "Cleanup" -Action { Apply-Cleanup }

    Write-Warn "EXTREME prioriza menos procesos y menos fondo."
    Write-Warn "Puede quitar funciones no esenciales de comodidad."
    Write-Info "Reinicia el PC al terminar para ver la reduccion real."
    Write-Ok "COMPETITIVE EXTREME completado."
}

function Run-FullOptimization {
    Invoke-Step -Name "Backup" -Action { Backup-ImportantSettings }
    Invoke-Step -Name "Restore Point" -Action { Create-SystemRestorePoint }
    Invoke-Step -Name "Privacy Tweaks" -Action { Apply-PrivacyTweaks }
    Invoke-Step -Name "Performance Tweaks" -Action { Apply-PerformanceTweaks }
    Invoke-Step -Name "Explorer Tweaks" -Action { Apply-ExplorerTweaks }
    Invoke-Step -Name "Background Reduction EXTREME" -Action { Apply-BackgroundReductionExtreme }
    Invoke-Step -Name "Power Plan" -Action { Apply-PowerPlan }
    Invoke-Step -Name "Windows Update Safe" -Action { Apply-WindowsUpdateSafe }
    Invoke-Step -Name "Network Reset" -Action { Apply-NetworkReset }
    Invoke-Step -Name "Cleanup" -Action { Apply-Cleanup }
    Invoke-Step -Name "Debloat" -Action { Apply-DebloatOptional }

    Write-Warn "FULL es la opcion mas agresiva del script."
    Write-Info "Reinicia el PC al terminar."
    Write-Ok "FULL OPTIMIZATION completado."
}

function Run-RepairAndCleanup {
    Invoke-Step -Name "Cleanup" -Action { Apply-Cleanup }
    Invoke-Step -Name "Network Reset" -Action { Apply-NetworkReset }
    Invoke-Step -Name "Repair Tools" -Action { Run-RepairTools }
    Write-Ok "REPAIR / CLEANUP completado."
}

function Run-KernelLikeReduction {
    Invoke-Step -Name "Backup" -Action { Backup-ImportantSettings }
    Invoke-Step -Name "Restore Point" -Action { Create-SystemRestorePoint }
    Invoke-Step -Name "Kernel-Like Policies" -Action { Apply-KernelLikePolicies }
    Invoke-Step -Name "Kernel-Like Services" -Action { Apply-KernelLikeServiceReduction }
    Invoke-Step -Name "Kernel-Like Tasks" -Action { Apply-KernelLikeTaskReduction }
    Invoke-Step -Name "Kernel-Like Processes" -Action { Apply-KernelLikeProcessReduction }
    Invoke-Step -Name "Kernel-Like AppX Reduction" -Action { Apply-KernelLikeAppxReduction }
    Invoke-Step -Name "Power Plan" -Action { Apply-PowerPlan }
    Invoke-Step -Name "Cleanup" -Action { Apply-Cleanup }

    Write-Warn "Esto intenta acercarse a un Windows mas recortado tipo Kernel."
    Write-Warn "No garantiza menos de 80 procesos."
    Write-Warn "Requiere reinicio para ver el recorte real."
    Write-Ok "KERNEL-LIKE REDUCTION completado."
}

function Run-KernelLikeReductionV2 {
    Invoke-Step -Name "Backup" -Action { Backup-ImportantSettings }
    Invoke-Step -Name "Restore Point" -Action { Create-SystemRestorePoint }
    Invoke-Step -Name "Kernel-Like Policies" -Action { Apply-KernelLikePolicies }
    Invoke-Step -Name "Kernel-Like Services" -Action { Apply-KernelLikeServiceReduction }
    Invoke-Step -Name "Kernel-Like Services V2" -Action { Apply-KernelLikeServiceReductionV2 }
    Invoke-Step -Name "Kernel-Like Tasks" -Action { Apply-KernelLikeTaskReduction }
    Invoke-Step -Name "Kernel-Like Processes" -Action { Apply-KernelLikeProcessReduction }
    Invoke-Step -Name "Kernel-Like User Services V2" -Action { Apply-KernelLikeUserServiceReductionV2 }
    Invoke-Step -Name "Kernel-Like AppX Reduction" -Action { Apply-KernelLikeAppxReduction }
    Invoke-Step -Name "Power Plan" -Action { Apply-PowerPlan }
    Invoke-Step -Name "Cleanup" -Action { Apply-Cleanup }

    Write-Warn "V2 es la capa mas fuerte del script."
    Write-Warn "Puede recortar mas funciones secundarias de Windows."
    Write-Warn "No garantiza menos de 80 procesos."
    Write-Warn "Usalo mejor en instalaciones limpias o de prueba."
    Write-Ok "KERNEL-LIKE REDUCTION V2 completado."
}

function Show-HelpInfo {
    Write-Section "HELP"

    Write-Host "1. COMPETITIVE SAFE" -ForegroundColor White
    Write-Host "2. COMPETITIVE EXTREME" -ForegroundColor White
    Write-Host "3. FULL OPTIMIZATION" -ForegroundColor White
    Write-Host "4. REPAIR / CLEANUP" -ForegroundColor White
    Write-Host "5. INSTALL BASIC APPS" -ForegroundColor White
    Write-Host "6. SHOW HELP" -ForegroundColor White
    Write-Host "7. KERNEL-LIKE REDUCTION" -ForegroundColor White
    Write-Host "8. KERNEL-LIKE REDUCTION V2 (ULTRA)" -ForegroundColor White
    Write-Host "9. NVIDIA COMPETITIVE PROFILE" -ForegroundColor White
    Write-Host "10. AMD COMPETITIVE PROFILE" -ForegroundColor White
    Write-Host ""
    Write-Host "Fuerza de menor a mayor:" -ForegroundColor White
    Write-Host "COMPETITIVE SAFE < COMPETITIVE EXTREME < FULL < KERNEL-LIKE < KERNEL-LIKE V2" -ForegroundColor Gray
    Write-Host ""
    Write-Host "NVIDIA / AMD PROFILE usan base competitiva + tweaks graficos + cierre de overlays." -ForegroundColor Gray
}

# =========================================================
# MENU
# =========================================================

function Show-Menu {
    Show-Banner
    Show-SystemInfo
    Write-Host "1. COMPETITIVE SAFE" -ForegroundColor White
    Write-Host "2. COMPETITIVE EXTREME" -ForegroundColor White
    Write-Host "3. FULL OPTIMIZATION" -ForegroundColor White
    Write-Host "4. REPAIR / CLEANUP" -ForegroundColor White
    Write-Host "5. INSTALL BASIC APPS" -ForegroundColor White
    Write-Host "6. SHOW HELP" -ForegroundColor White
    Write-Host "7. KERNEL-LIKE REDUCTION" -ForegroundColor White
    Write-Host "8. KERNEL-LIKE REDUCTION V2 (ULTRA)" -ForegroundColor White
    Write-Host "9. NVIDIA COMPETITIVE PROFILE" -ForegroundColor White
    Write-Host "10. AMD COMPETITIVE PROFILE" -ForegroundColor White
    Write-Host "0. EXIT" -ForegroundColor White
    Write-Host ""
}

# =========================================================
# START
# =========================================================

Assert-Admin
Write-Log "===== Inicio de $($Script:AppName) v$($Script:Version) ====="
Write-Log "ScriptRoot: $($Script:ScriptRoot)"
Write-Log "AssetsDir: $($Script:AssetsDir)"
Write-Log "PowerPlanFile: $($Script:PowerPlanFile)"
Write-Log "PowerPlanUrl: $($Script:PowerPlanUrl)"

do {
    Show-Menu
    $choice = Read-Host "Selecciona una opcion"

    switch ($choice) {
        "1"  { Run-CompetitiveSafe; Pause-Continue }
        "2"  { Run-CompetitiveExtreme; Pause-Continue }
        "3"  { Run-FullOptimization; Pause-Continue }
        "4"  { Run-RepairAndCleanup; Pause-Continue }
        "5"  { Invoke-Step -Name "Install Basic Apps" -Action { Install-BasicApps }; Pause-Continue }
        "6"  { Show-HelpInfo; Pause-Continue }
        "7"  { Run-KernelLikeReduction; Pause-Continue }
        "8"  { Run-KernelLikeReductionV2; Pause-Continue }
        "9"  { Run-NvidiaCompetitiveProfile; Pause-Continue }
        "10" { Run-AmdCompetitiveProfile; Pause-Continue }
        "0"  { break }
        default {
            Write-Warn "Opcion invalida."
            Pause-Continue
        }
    }
} while ($true)

Write-Log "===== Fin de ejecucion ====="




