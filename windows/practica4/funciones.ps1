function Verificar-Administrador {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Por favor, ejecuta PowerShell como Administrador."
        exit
    }
}

$global:INTERFAZ = ""

function Detectar-Interfaz {
    Write-Host "`n--- DETECCION DE RED ---"
    Write-Host "Estas son tus interfaces de red disponibles:"
    
    Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object Name, InterfaceDescription | Format-Table -AutoSize
    
    Write-Host "ATENCION: Verifica cual es tu red interna (usualmente llamada 'Ethernet').`n"
    
    while ($true) {
        $interfazUsr = Read-Host "Escribe EXACTAMENTE la interfaz a usar (ej. Ethernet)"
        
        $iface = Get-NetAdapter -Name $interfazUsr -ErrorAction SilentlyContinue
        if ($iface) {
            $global:INTERFAZ = $interfazUsr
            Write-Host "Usando interfaz: $global:INTERFAZ"
            return
        } else {
            Write-Host "Esa interfaz no existe. Intenta de nuevo."
        }
    }
}

function Validar-FormatoIP {
    param([string]$ip)
    
    if ($ip -notmatch "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") { return $false }
    if ($ip -eq "0.0.0.0" -or $ip -eq "127.0.0.1" -or $ip -eq "255.255.255.255") { return $false }
    
    $octetos = $ip.Split('.')
    if ([int]$octetos[0] -gt 255 -or [int]$octetos[1] -gt 255 -or [int]$octetos[2] -gt 255 -or [int]$octetos[3] -gt 255) {
        return $false
    }
    
    return $true
}

function Solicitar-IP {
    param([string]$mensaje)
    while ($true) {
        $ip_raw = Read-Host "$mensaje"
        $ip_ingresada = $ip_raw.Trim()
        if (Validar-FormatoIP -ip $ip_ingresada) {
            return $ip_ingresada
        } else {
            Write-Host "IP no valida." -ForegroundColor Red
        }
    }
}

function Solicitar-EnteroPositivo {
    param([string]$mensaje)
    while ($true) {
        $valor_raw = Read-Host "$mensaje"
        $valor = $valor_raw.Trim()

        if ($valor -match "^[1-9][0-9]*$") {
            return $valor
        } else {
            Write-Host "ERROR: Ingresa un numero entero positivo valido (sin puntos ni signos)." -ForegroundColor Red
        }
    }
}

function Verificar-Instalaciones {
    Write-Host "--- ESTADO DE SERVICIOS ---"
    $dhcp = Get-WindowsFeature DHCP
    $dns = Get-WindowsFeature DNS
    if ($dhcp.Installed) { Write-Host "[DHCP] INSTALADO" } else { Write-Host "[DHCP] NO INSTALADO" }
    if ($dns.Installed) { Write-Host "[DNS]  INSTALADO" } else { Write-Host "[DNS]  NO INSTALADO" }
}