if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))  {
    Write-Warning "Este script necesita permisos de Administrador. Ejecutalo como Administrador."
    Break
}

function Validar-IP {
    param ([string]$ip)
    if ($ip -notmatch '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') { return $false }
    if ($ip -eq "0.0.0.0" -or $ip -eq "127.0.0.1" -or $ip -eq "255.255.255.255") { Write-Host "[ERROR] IP reservada." ; return $false }
    return $true
}

function Pedir-IP {
    param ([string]$mensaje)
    do {
        $inputIP = Read-Host "$mensaje"
        $inputIP = $inputIP.Trim()
        if (Validar-IP $inputIP) { return $inputIP }
        else { Write-Host "IP invalida."}
    } while ($true)
}

function Calcular-Siguiente-IP {
    param ([string]$ip)
    $octetos = $ip.Split('.')
    $nuevoUltimo = [int]$octetos[3] + 1
    return "$($octetos[0]).$($octetos[1]).$($octetos[2]).$nuevoUltimo"
}

function Obtener-SubnetID {
    param ([string]$ip)
    $octetos = $ip.Split('.')
    return "$($octetos[0]).$($octetos[1]).$($octetos[2]).0"
}

function Comparar-IPs {
    param ($ipFin, $ipInicio)
    $v1 = [Version]$ipFin; $v2 = [Version]$ipInicio
    return $v1 -gt $v2
}

# MENU

function Opcion-Instalacion {
    Write-Host "`nINSTALACION"
    $check = Get-WindowsFeature -Name DHCP
    if ($check.Installed) {
        Write-Host "El rol ya esta instalado." 
        $resp = Read-Host "Reinstalar? (s/n)"
        if ($resp -ne "s") { return }
        Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools -Confirm:$false
    }
    Install-WindowsFeature -Name DHCP -IncludeManagementTools
    Write-Host "Instalado." -ForegroundColor Green
}

function Opcion-Verificar {
    $check = Get-WindowsFeature -Name DHCP
    if ($check.Installed) { Write-Host "ESTADO: INSTALADO"} else { Write-Host "ESTADO: NO INSTALADO"}
}

function Opcion-Configuracion {
    Write-Host "`nCONFIGURACION " 
    
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    if (-not $adapters) { Write-Host "[ERROR] Sin interfaces."; return }
    
    $adapters | Select-Object Name, InterfaceDescription, MacAddress | Format-Table -AutoSize
    
    Write-Host "ATENCION: 'Ethernet' suele ser Internet. 'Ethernet 2' suele ser Red Interna." 
    $ifaceName = Read-Host "Nombre de Interfaz (Ej: Ethernet 2)"
    
    if (-not (Get-NetAdapter -Name $ifaceName -ErrorAction SilentlyContinue)) {
        Write-Host "Interfaz no encontrada." 
        return
    }

    $ipServidor = Pedir-IP "IP Inicio (Servidor)"
    $rangoInicio = Calcular-Siguiente-IP $ipServidor
    
    Write-Host "Configurando IP estatica en $ifaceName..."
    
    Try {
        Remove-NetIPAddress -InterfaceAlias $ifaceName -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $ifaceName -IPAddress $ipServidor -PrefixLength 24 -AddressFamily IPv4 -ErrorAction Stop | Out-Null
    } Catch {
        Write-Host "ERROR al asignar IP: $($_.Exception.Message)"
        Write-Host "Intente ejecutar: Remove-NetIPAddress -InterfaceAlias '$ifaceName' manualmente antes."
        return
    }

    # 3. Rango DHCP
    do {
        $ipFinal = Pedir-IP "IP Final (Mayor a $rangoInicio)"
        if (Comparar-IPs $ipFinal $rangoInicio) { break }
        Write-Host "Error: IP final debe ser mayor."
    } while ($true)

    do {
        $leaseStr = Read-Host "Tiempo concesion (segundos)"
        if ($leaseStr -match '^\d+$' -and [int]$leaseStr -gt 0) {
            $timespan = New-TimeSpan -Seconds $leaseStr
            break
        }
    } while ($true)
    
    $gw = Read-Host "Gateway (Enter vacio)"
    if ($gw -ne "" -and -not (Validar-IP $gw)) { $gw = "" }
    
    $dns = Read-Host "DNS (Enter vacio)"
    if ($dns -ne "" -and -not (Validar-IP $dns)) { $dns = "" }
    
    $nombreScope = Read-Host "Nombre Scope"
    if ($nombreScope -eq "") { $nombreScope = "Scope_Auto" }

    # 4. Crear Scope
    Write-Host "Configurando DHCP..."
    $scopeID = Obtener-SubnetID $ipServidor
    
    Try {
        if (Get-DhcpServerv4Scope -ScopeId $scopeID -ErrorAction SilentlyContinue) {
            Remove-DhcpServerv4Scope -ScopeId $scopeID -Force
        }

        Add-DhcpServerv4Scope -Name $nombreScope -StartRange $rangoInicio -EndRange $ipFinal -SubnetMask 255.255.255.0 -LeaseDuration $timespan -State Active
        
        if ($gw -ne "") { Set-DhcpServerv4OptionValue -ScopeId $scopeID -OptionId 3 -Value $gw }
        if ($dns -ne "") { Set-DhcpServerv4OptionValue -ScopeId $scopeID -OptionId 6 -Value $dns }
        
        Restart-Service dhcpserver -Force
        Write-Host "EXITO: DHCP configurado y activo." -ForegroundColor Green

    } Catch {
        Write-Host "ERROR CRITICO DHCP: $($_.Exception.Message)"
    }
}

function Opcion-Monitorear {
    Write-Host "`nMONITOREO"
    $svc = Get-Service dhcpserver -ErrorAction SilentlyContinue
    if ($svc) { Write-Host "Servicio: $($svc.Status)"}
    
    Write-Host "`nCLIENTE ACTUALMENTE CONECTADO"
    Try {
        $leases = Get-DhcpServerv4Scope | Get-DhcpServerv4Lease | Where-Object { $_.AddressState -like "Active" }
        
        if ($leases) { 
            $leases | Group-Object ClientId | ForEach-Object { 
                $_.Group | Sort-Object LeaseExpiryTime -Descending | Select-Object -First 1 
            } | Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime | Format-Table -AutoSize 
        } else { 
            Write-Host "No hay clientes activos en este momento."
        }
    } Catch { Write-Host "Error leyendo leases." }
}

# --- BUCLE ---
do {
    Write-Host "`n1.Instalar 2.Verificar 3.Configurar 4.Monitorear 5.Salir"
    $sel = Read-Host "Opcion"
    Switch ($sel) {
        "1" { Opcion-Instalacion }
        "2" { Opcion-Verificar }
        "3" { Opcion-Configuracion }
        "4" { Opcion-Monitorear }
        "5" { Break }
    }
} while ($sel -ne "5")