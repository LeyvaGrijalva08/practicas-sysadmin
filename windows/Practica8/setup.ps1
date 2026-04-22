$DomainName         = "practica8_repo.com"      # Nombre DNS del dominio
                                                 # ALTERNATIVA SIN PROBLEMAS: "practica8repo.com"
$DomainNetbios      = "PRACTICA8"                # Nombre NetBIOS (max 15 chars, sin guion bajo)
$DomainDN           = "DC=practica8_repo,DC=com" # DN del dominio
$SafeModePassword   = "Leyvagrijalva08*"         # Contrasena de modo seguro (DSRM)
                                                 # Usando la misma que el Administrator del servidor

# Configuracion de red - Adaptador 3
$TargetIP           = "192.168.56.100"   # IP estatica para el adaptador 3
$PrefixLength       = 24                 # /24 = mascara 255.255.255.0
$DefaultGateway     = "192.168.56.1"     # Gateway de la red host-only de VirtualBox
$DNSServer          = "192.168.56.100"   # El propio servidor sera su DNS despues de ser DC
$DNSAlternate       = "8.8.8.8"          # DNS alternativo para resolver internet

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

Write-Log "CONFIGURANDO IP ESTATICA EN ADAPTADOR 3" -Tipo TITULO

# Obtener todos los adaptadores de red activos ordenados por indice de interfaz
$Adaptadores = Get-NetAdapter | Where-Object { $_.Status -ne "Not Present" } |
               Sort-Object -Property InterfaceIndex

Write-Log "Adaptadores de red detectados:" -Tipo INFO
$Adaptadores | ForEach-Object {
    Write-Log "  Indice $($_.InterfaceIndex): '$($_.Name)' - Estado: $($_.Status) - MAC: $($_.MacAddress)" -Tipo INFO
}

# Seleccionar el tercer adaptador (posicion 2 en indice 0)
if ($Adaptadores.Count -lt 3) {
    Write-Log "Solo se detectaron $($Adaptadores.Count) adaptadores. Se necesitan al menos 3." -Tipo ERROR
    Write-Log "Verifica que VirtualBox tenga los 3 adaptadores habilitados y que el servidor este encendido." -Tipo ERROR
    exit 1
}

$Adaptador3 = $Adaptadores[2]  # Indice 0 = primero, 1 = segundo, 2 = TERCERO
Write-Log "Adaptador 3 seleccionado: '$($Adaptador3.Name)' (Indice $($Adaptador3.InterfaceIndex))" -Tipo INFO

# Verificar si ya tiene la IP correcta configurada
$IPActual = Get-NetIPAddress -InterfaceIndex $Adaptador3.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

if ($IPActual -and $IPActual.IPAddress -eq $TargetIP) {
    Write-Log "El adaptador '$($Adaptador3.Name)' ya tiene la IP '$TargetIP'. No se hacen cambios." -Tipo WARN
} else {
    # Eliminar configuraciones IP existentes en este adaptador
    Get-NetIPAddress -InterfaceIndex $Adaptador3.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    # Eliminar gateway existente si hay
    Get-NetRoute -InterfaceIndex $Adaptador3.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    # Asignar la IP estatica
    New-NetIPAddress -InterfaceIndex  $Adaptador3.InterfaceIndex `
                     -IPAddress       $TargetIP `
                     -PrefixLength    $PrefixLength `
                     -DefaultGateway  $DefaultGateway `
                     -ErrorAction     Stop

    Write-Log "IP estatica '$TargetIP/$PrefixLength' asignada al adaptador '$($Adaptador3.Name)'." -Tipo OK
}

# Configurar servidores DNS
Set-DnsClientServerAddress -InterfaceIndex $Adaptador3.InterfaceIndex `
                            -ServerAddresses @($DNSServer, $DNSAlternate)
Write-Log "DNS configurado: Primario=$DNSServer, Alternativo=$DNSAlternate" -Tipo OK

# Verificar la configuracion de red final
Write-Log "Configuracion de red del adaptador 3:" -Tipo INFO
Get-NetIPAddress -InterfaceIndex $Adaptador3.InterfaceIndex -AddressFamily IPv4 |
    Select-Object IPAddress, PrefixLength, AddressState | Format-Table -AutoSize


Write-Log "INSTALANDO ROL AD DS" -Tipo TITULO

$ADDSFeature = Get-WindowsFeature -Name "AD-Domain-Services"

if ($ADDSFeature.Installed) {
    Write-Log "El rol AD-Domain-Services ya esta instalado." -Tipo WARN
} else {
    Write-Log "Instalando AD DS y herramientas de administracion..." -Tipo INFO
    Install-WindowsFeature -Name AD-Domain-Services `
                           -IncludeManagementTools `
                           -IncludeAllSubFeature | Out-Null
    Write-Log "Rol AD DS instalado correctamente." -Tipo OK
}

# Importar el modulo de despliegue de AD DS
Import-Module ADDSDeployment -ErrorAction Stop
Write-Log "Modulo ADDSDeployment importado." -Tipo OK


Write-Log "PROMOVIENDO SERVIDOR A CONTROLADOR DE DOMINIO" -Tipo TITULO
Write-Log "Dominio objetivo: $DomainName" -Tipo INFO
Write-Log "NetBIOS: $DomainNetbios" -Tipo INFO
Write-Log "Esta operacion puede tardar varios minutos y reiniciara el servidor..." -Tipo WARN

$SecurePass = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

try {
    Install-ADDSForest `
        -DomainName                    $DomainName `
        -DomainNetbiosName             $DomainNetbios `
        -DomainMode                    "WinThreshold" `
        -ForestMode                    "WinThreshold" `
        -SafeModeAdministratorPassword $SecurePass `
        -InstallDns                    `
        -CreateDnsDelegation:$false    `
        -DatabasePath                  "C:\Windows\NTDS" `
        -LogPath                       "C:\Windows\NTDS" `
        -SysvolPath                    "C:\Windows\SYSVOL" `
        -NoRebootOnCompletion:$false   `
        -Force                         `
        -WarningAction                 Continue   # Continua aunque haya advertencia de DNS por el underscore

} catch {
    Write-Log "Error durante la promocion: $_" -Tipo ERROR
    Write-Log "Si el error menciona DNS o nombre de dominio invalido, cambia DomainName a 'practica8repo.com'" -Tipo WARN
    exit 1
}
