$DomainName     = "practica8_repo.com"
$DomainUser     = "Administrator"           # Usuario admin del dominio (servidor en ingles)
$DomainPassword = "Leyvagrijalva08*"        # Contrasena del Administrator del servidor
$DCIP           = "192.168.56.100"          # IP del servidor Windows Server 2022
$OUParaEquipos  = $null                     # null = CN=Computers por defecto

Set-StrictMode -Version Latest

function Write-Log {
    param([string]$Msg, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor $Color
}

# --- 1. CONFIGURAR IP ESTATICA EN ADAPTADOR 3 DEL CLIENTE ---
Write-Log "CONFIGURANDO IP DEL ADAPTADOR 3 EN EL CLIENTE" -Cyan

$Adaptadores = Get-NetAdapter | Where-Object { $_.Status -ne "Not Present" } | Sort-Object InterfaceIndex

Write-Log "Adaptadores detectados:" -Cyan
$Adaptadores | ForEach-Object {
    Write-Log "  Indice $($_.InterfaceIndex): $($_.Name) - $($_.Status)" -Cyan
}

if ($Adaptadores.Count -lt 3) {
    Write-Log "Solo $($Adaptadores.Count) adaptadores detectados. Se necesitan 3." -Red
    exit 1
}

$Adaptador3 = $Adaptadores[2]
Write-Log "Adaptador 3 seleccionado: '$($Adaptador3.Name)'" -Cyan

# IP del cliente en la misma subred que el servidor (192.168.56.x)
$ClienteIP    = "192.168.56.101"   # IP del cliente Windows 10
$PrefixLength = 24
$Gateway      = "192.168.56.1"
$DNSServer    = "192.168.56.100"   # El DC es el DNS

Get-NetIPAddress -InterfaceIndex $Adaptador3.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
Get-NetRoute -InterfaceIndex $Adaptador3.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceIndex $Adaptador3.InterfaceIndex `
                 -IPAddress      $ClienteIP `
                 -PrefixLength   $PrefixLength `
                 -DefaultGateway $Gateway
Set-DnsClientServerAddress -InterfaceIndex $Adaptador3.InterfaceIndex -ServerAddresses @($DNSServer, "8.8.8.8")

Write-Log "IP cliente: $ClienteIP/24 | DNS: $DNSServer" -Green
Start-Sleep -Seconds 3

# --- 2. VERIFICAR CONECTIVIDAD CON EL DOMINIO ---
Write-Log "Verificando conectividad con $DomainName ($DCIP)..." -Cyan
if (-not (Test-Connection -ComputerName $DCIP -Count 2 -Quiet)) {
    Write-Log "No se puede contactar al servidor en $DCIP. Verifica red y que el servidor este encendido." -Red
    exit 1
}
Write-Log "Servidor contactado exitosamente." -Green

# --- 3. UNIR AL DOMINIO ---
Write-Log "Uniendo '$env:COMPUTERNAME' al dominio '$DomainName'..." -Cyan

$SecurePass = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential("$DomainName\$DomainUser", $SecurePass)

$JoinParams = @{
    DomainName = $DomainName
    Credential = $Credential
    Force      = $true
    PassThru   = $true
}
if ($OUParaEquipos) { $JoinParams["OUPath"] = $OUParaEquipos }

try {
    $Resultado = Add-Computer @JoinParams
    if ($Resultado.HasSucceeded) {
        Write-Log "Equipo unido exitosamente al dominio '$DomainName'." -Green
    }
} catch {
    Write-Log "Error al unir el equipo al dominio: $_" -Red
    exit 1
}

# --- 4. REINICIAR ---
Write-Log "Se requiere reinicio para completar la union al dominio." -Yellow
$R = Read-Host "Reiniciar ahora? (S/N)"
if ($R -eq "S" -or $R -eq "s") {
    Write-Log "Reiniciando en 5 segundos..." -Yellow
    Start-Sleep 5
    Restart-Computer -Force
} else {
    Write-Log "Reinicia manualmente. Despues ejecuta 'gpupdate /force'." -Yellow
}
