$DomainDN = "DC=practica8_repo,DC=com"
$HomePath = "C:\Carpetas"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Mensaje, [ValidateSet("OK","INFO","WARN","ERROR","TITULO")][string]$Tipo = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    switch ($Tipo) {
        "OK"     { Write-Host "[$ts] [+] $Mensaje" -ForegroundColor Green }
        "INFO"   { Write-Host "[$ts] [i] $Mensaje" -ForegroundColor Cyan }
        "WARN"   { Write-Host "[$ts] [!] $Mensaje" -ForegroundColor Yellow }
        "ERROR"  { Write-Host "[$ts] [X] $Mensaje" -ForegroundColor Red }
        "TITULO" { Write-Host "`n[$ts] ===== $Mensaje =====" -ForegroundColor Magenta }
    }
}

# --- INSTALAR FSRM ---
Write-Log "INSTALANDO FSRM" -Tipo TITULO
if (-not (Get-WindowsFeature "FS-Resource-Manager").Installed) {
    Install-WindowsFeature -Name "FS-Resource-Manager" -IncludeManagementTools | Out-Null
    Write-Log "FSRM instalado." -Tipo OK
    Start-Sleep -Seconds 5
} else { Write-Log "FSRM ya instalado." -Tipo INFO }

Import-Module FileServerResourceManager -ErrorAction Stop
Import-Module ActiveDirectory           -ErrorAction Stop

# --- PLANTILLAS DE CUOTA (HARD LIMIT - bloqueo real) ---
Write-Log "CREANDO PLANTILLAS DE CUOTA HARD LIMIT" -Tipo TITULO
# CRITICO: Sin -SoftLimit = HARD quota (bloquea). Con -SoftLimit = solo avisa.
@(
    @{ Nombre = "Cuota_Cuates_10MB";  Tamano = [int64](10MB); Grupo = "Cuates"   },
    @{ Nombre = "Cuota_NoCuates_5MB"; Tamano = [int64](5MB);  Grupo = "NoCuates" }
) | ForEach-Object {
    $P = $_
    if (-not (Get-FsrmQuotaTemplate -Name $P.Nombre -ErrorAction SilentlyContinue)) {
        New-FsrmQuotaTemplate -Name $P.Nombre -Size $P.Tamano -Description "Cuota HARD para $($P.Grupo)"
        Write-Log "Plantilla '$($P.Nombre)' ($([math]::Round($P.Tamano/1MB)) MB HARD) creada." -Tipo OK
    } else {
        Set-FsrmQuotaTemplate -Name $P.Nombre -Size $P.Tamano
        Write-Log "Plantilla '$($P.Nombre)' actualizada." -Tipo WARN
    }
}

# --- GRUPO DE ARCHIVOS PROHIBIDOS ---
Write-Log "GRUPO DE ARCHIVOS PROHIBIDOS" -Tipo TITULO
$GrupoNombre = "Archivos_Prohibidos_Usuarios"
$Extensiones = @("*.mp3", "*.mp4", "*.exe", "*.msi")

if (-not (Get-FsrmFileGroup -Name $GrupoNombre -ErrorAction SilentlyContinue)) {
    New-FsrmFileGroup -Name $GrupoNombre -IncludePattern $Extensiones -Description "Prohibidos en carpetas de usuario"
    Write-Log "Grupo '$GrupoNombre' creado: $($Extensiones -join ', ')" -Tipo OK
} else {
    Set-FsrmFileGroup -Name $GrupoNombre -IncludePattern $Extensiones
    Write-Log "Grupo '$GrupoNombre' actualizado." -Tipo WARN
}

# --- PLANTILLA DE FILE SCREEN ACTIVO ---
Write-Log "FILE SCREEN ACTIVO (bloqueo real)" -Tipo TITULO
# CRITICO: -Active = bloquea el guardado. SIN -Active = solo registra (Passive).
$ScreenNombre = "Screen_Activo_Prohibidos"
if (-not (Get-FsrmFileScreenTemplate -Name $ScreenNombre -ErrorAction SilentlyContinue)) {
    New-FsrmFileScreenTemplate -Name $ScreenNombre -Active -IncludeGroup @($GrupoNombre) `
        -Description "ACTIVE: bloquea mp3, mp4, exe, msi en carpetas de usuario"
    Write-Log "Plantilla '$ScreenNombre' creada en modo ACTIVE." -Tipo OK
} else {
    Set-FsrmFileScreenTemplate -Name $ScreenNombre -Active -IncludeGroup @($GrupoNombre)
    Write-Log "Plantilla '$ScreenNombre' actualizada a modo ACTIVE." -Tipo WARN
}

# --- APLICAR A CARPETAS DE CADA USUARIO ---
Write-Log "APLICANDO CUOTAS Y FILE SCREENS POR USUARIO" -Tipo TITULO

@(
    @{ GrupoAD = "GRP_Cuates";   Plantilla = "Cuota_Cuates_10MB";  Limite = "10 MB" },
    @{ GrupoAD = "GRP_NoCuates"; Plantilla = "Cuota_NoCuates_5MB"; Limite = "5 MB"  }
) | ForEach-Object {
    $Cfg = $_
    Get-ADGroupMember -Identity $Cfg.GrupoAD | Where-Object { $_.objectClass -eq "user" } | ForEach-Object {
        $UserPath = "$HomePath\$($_.SamAccountName)"
        if (-not (Test-Path $UserPath)) {
            Write-Log "  Carpeta '$UserPath' no existe. Ejecuta primero el script 01." -Tipo WARN
            return
        }

        # Cuota
        if (-not (Get-FsrmQuota -Path $UserPath -ErrorAction SilentlyContinue)) {
            New-FsrmQuota -Path $UserPath -Template $Cfg.Plantilla
        } else {
            Set-FsrmQuota -Path $UserPath -Template $Cfg.Plantilla
        }
        Write-Log "  [$($Cfg.GrupoAD)] Cuota $($Cfg.Limite) -> '$UserPath'" -Tipo OK

        # File Screen
        if (-not (Get-FsrmFileScreen -Path $UserPath -ErrorAction SilentlyContinue)) {
            New-FsrmFileScreen -Path $UserPath -Template $ScreenNombre
        } else {
            Set-FsrmFileScreen -Path $UserPath -Template $ScreenNombre
        }
        Write-Log "  [$($Cfg.GrupoAD)] File Screen ACTIVO -> '$UserPath'" -Tipo OK
    }
}

Write-Log "VERIFICACION FINAL:" -Tipo TITULO
Get-FsrmQuota     | Select-Object Path, Size, SoftLimit | Format-Table -AutoSize
Get-FsrmFileScreen | Select-Object Path, Active, Template | Format-Table -AutoSize

Write-Log "SCRIPT 02 COMPLETADO. Ejecuta ahora el script 03." -Tipo TITULO
Write-Log "Eventos de bloqueo FSRM: Visor de Eventos > Aplicaciones y Servicios > FSRM" -Tipo INFO
