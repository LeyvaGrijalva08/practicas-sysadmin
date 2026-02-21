# Requiere ejecución como Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Por favor, ejecuta PowerShell como Administrador."
    exit
}

$global:INTERFAZ = ""

# FUNCIONES BASE Y DHCP

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

function Calcular-Siguiente {
    param([string]$ip)
    $octetos = $ip.Split('.')
    $nuevo_i4 = [int]$octetos[3] + 1
    return "$($octetos[0]).$($octetos[1]).$($octetos[2]).$nuevo_i4"
}

function Verificar-Rango {
    param([string]$ip_fin, [string]$ip_ini)
    $f = $ip_fin.Split('.')
    $i = $ip_ini.Split('.')
    
    if ([int]$f[3] -gt [int]$i[3]) { 
        return $true 
    } else { 
        return $false 
    }
}

function Instalar-DHCP {
    Write-Host ""
    $estado = Get-WindowsFeature -Name DHCP
    if ($estado.Installed) {
        $resp = Read-Host "El servicio DHCP ya existe. Reinstalar? (s/n)"
        if ($resp -eq "s") {
            Uninstall-WindowsFeature -Name DHCP -Remove -Restart:$false
            Write-Host "Reinicia el servidor y vuelve a ejecutar para instalar."
            return
        } else {
            return
        }
    }
    Write-Host "Instalando DHCP..." -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
    Write-Host "Instalacion completada."
}

function Configurar-DHCP {
    Write-Host ""
    Detectar-Interfaz
    if (-not $global:INTERFAZ) { return }

    $MI_IP = Solicitar-IP "IP Servidor (Inicio)"
    $RANGO_INICIO = Calcular-Siguiente -ip $MI_IP

    Write-Host "Limpiando IP previa en $global:INTERFAZ..."
    Remove-NetIPAddress -InterfaceAlias $global:INTERFAZ -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $global:INTERFAZ -IPAddress $MI_IP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null

    while ($true) {
        $IP_FINAL = Solicitar-IP "IP Final (Mayor a $RANGO_INICIO)"
        if (Verificar-Rango -ip_fin $IP_FINAL -ip_ini $RANGO_INICIO) { break }
        Write-Host "Error: IP final debe ser mayor." -ForegroundColor Red
    }

    
    $TIEMPO = Solicitar-EnteroPositivo "Tiempo concesion (en segundos)"
    
    $GW = Read-Host "Gateway (Enter vacio)"
    $DNS = Solicitar-IP "DNS (Obligatorio)"

    $octetos = $MI_IP.Split('.')
    $SUBNET = "$($octetos[0]).$($octetos[1]).$($octetos[2]).0"
    $NOMBRE_AMBITO = "Red_Automatizada"

    if (Get-DhcpServerv4Scope -ScopeId $SUBNET -ErrorAction SilentlyContinue) {
        Remove-DhcpServerv4Scope -ScopeId $SUBNET -Force
    }

    Add-DhcpServerv4Scope -Name $NOMBRE_AMBITO -StartRange $RANGO_INICIO -EndRange $IP_FINAL -SubnetMask 255.255.255.0 -LeaseDuration (New-TimeSpan -Seconds $TIEMPO)

    if ($GW) { Set-DhcpServerv4OptionValue -ScopeId $SUBNET -Router $GW }
    Set-DhcpServerv4OptionValue -ScopeId $SUBNET -DnsServer $DNS

    Write-Host "Reiniciando DHCP..."
    Restart-Service -Name dhcpserver
    $estado = Get-Service -Name dhcpserver
    if ($estado.Status -eq "Running") {
        Write-Host "EXITO: Servicio activo en interfaz $global:INTERFAZ." -ForegroundColor Green
    } else {
        Write-Host "FALLO: Revisa el servicio dhcpserver." -ForegroundColor Red
    }
}

function Monitorear-DHCP {
    $estado = Get-Service -Name dhcpserver
    Write-Host "Active: $($estado.Status)"
    
    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopes) {
        foreach ($scope in $scopes) {
            Get-DhcpServerv4Lease -ScopeId $scope.ScopeId | Select-Object IPAddress | Sort-Object -Unique
        }
    }
}

# FUNCIONES DNS

function Verificar-Instalaciones {
    Write-Host "--- ESTADO DE SERVICIOS ---"
    $dhcp = Get-WindowsFeature DHCP
    $dns = Get-WindowsFeature DNS
    if ($dhcp.Installed) { Write-Host "[DHCP] INSTALADO" } else { Write-Host "[DHCP] NO INSTALADO" }
    if ($dns.Installed) { Write-Host "[DNS]  INSTALADO" } else { Write-Host "[DNS]  NO INSTALADO" }
}

function Verificar-IP-Fija {
    Write-Host "`n--- VALIDACION DE IP FIJA ---"
    Detectar-Interfaz
    if (-not $global:INTERFAZ) { return }
    
    $ipInfo = Get-NetIPAddress -InterfaceAlias $global:INTERFAZ -AddressFamily IPv4 -ErrorAction SilentlyContinue
    
    if (-not $ipInfo -or $ipInfo.PrefixOrigin -eq "Dhcp") {
        Write-Host "[ALERTA] No hay IP asignada en $global:INTERFAZ."
        $IP_NUEVA = Solicitar-IP "Ingresa la IP fija a asignar para el servidor (ej. 192.168.1.10)"
        
        Remove-NetIPAddress -InterfaceAlias $global:INTERFAZ -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $global:INTERFAZ -IPAddress $IP_NUEVA -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
        
        Write-Host "IP $IP_NUEVA asignada a $global:INTERFAZ." -ForegroundColor Green
    } else {
        Write-Host "La interfaz $global:INTERFAZ ya tiene la IP configurada: $($ipInfo.IPAddress)"
    }
}

function Instalar-DNS {
    Write-Host ""
    $estado = Get-WindowsFeature -Name DNS
    if ($estado.Installed) {
        $resp = Read-Host "El servicio DNS ya existe. Reinstalar? (s/n)"
        if ($resp -eq "s") {
            Uninstall-WindowsFeature -Name DNS -Remove -Restart:$false
            Write-Host "Reinicia el servidor y vuelve a ejecutar para instalar."
            return
        } else {
            return
        }
    }
    Write-Host "Instalando DNS..." 
    Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
    Write-Host "Instalacion de DNS completada." 
}

function Agregar-Dominio {
    Write-Host "`n--- AGREGAR DOMINIO DNS ---"
    $DOMINIO = Read-Host "Ingresa el nombre del dominio (ej. reprobados.com)"
    
    $existe = Get-DnsServerZone -Name $DOMINIO -ErrorAction SilentlyContinue
    if ($existe) {
        Write-Host "El dominio $DOMINIO ya esta registrado." -ForegroundColor Red
        return
    }

    $IP_DOMINIO = Solicitar-IP "Ingresa la IP a la que apuntara el dominio"

    Add-DnsServerPrimaryZone -Name $DOMINIO -ZoneFile "$DOMINIO.dns"
    Add-DnsServerResourceRecordA -ZoneName $DOMINIO -Name "@" -IPv4Address $IP_DOMINIO
    Add-DnsServerResourceRecordCName -ZoneName $DOMINIO -Name "www" -HostNameAlias "$DOMINIO"

    $octetos = $IP_DOMINIO.Split('.')
    $ZONA_INVERSA = "$($octetos[2]).$($octetos[1]).$($octetos[0]).in-addr.arpa"
    $IP_HOST = $octetos[3]

    $existeInversa = Get-DnsServerZone -Name $ZONA_INVERSA -ErrorAction SilentlyContinue
    if (-not $existeInversa) {
        Add-DnsServerPrimaryZone -Name $ZONA_INVERSA -ZoneFile "$ZONA_INVERSA.dns"
    }

    try { Add-DnsServerResourceRecordPtr -ZoneName $ZONA_INVERSA -Name $IP_HOST -PtrDomainName "$DOMINIO." -ErrorAction Stop } catch {}
    try { Add-DnsServerResourceRecordPtr -ZoneName $ZONA_INVERSA -Name $IP_HOST -PtrDomainName "www.$DOMINIO." -ErrorAction Stop } catch {}

    Write-Host "Dominio $DOMINIO (y su zona inversa) creados exitosamente." -ForegroundColor Green
}

function Eliminar-Dominio {
    Write-Host "`n--- ELIMINAR DOMINIO DNS ---"
    $DOMINIO = Read-Host "Ingresa el dominio a eliminar"
    
    $existe = Get-DnsServerZone -Name $DOMINIO -ErrorAction SilentlyContinue
    if (-not $existe) {
        Write-Host "El dominio $DOMINIO no existe en la configuracion." -ForegroundColor Red
        return
    }

    $zonasInversas = Get-DnsServerZone | Where-Object IsReverseLookupZone -eq $true
    foreach ($zona in $zonasInversas) {
        $registrosPtr = Get-DnsServerResourceRecord -ZoneName $zona.ZoneName -RRType Ptr -ErrorAction SilentlyContinue
        foreach ($reg in $registrosPtr) {
            if ($reg.RecordData.PtrDomainName -like "*$DOMINIO.") {
                Remove-DnsServerResourceRecord -ZoneName $zona.ZoneName -Name $reg.HostName -RRType Ptr -RecordData $reg.RecordData -Force
            }
        }
    }

    Remove-DnsServerZone -Name $DOMINIO -Force
    Write-Host "Dominio $DOMINIO y sus registros de IP eliminados exitosamente." -ForegroundColor Green
}

function Listar-Dominios {
    Write-Host "`n--- DOMINIOS CONFIGURADOS ACTUALMENTE ---"
    $zonas = Get-DnsServerZone | Where-Object IsAutoCreated -eq $false | Where-Object IsReverseLookupZone -eq $false
    if ($zonas) {
        $zonas | Select-Object ZoneName | Format-Table -HideTableHeaders
    } else {
        Write-Host "No hay dominios configurados."
    }
    Write-Host "-----------------------------------------"
}

function Validar-Resolucion {
    Write-Host "`n--- PRUEBAS DE RESOLUCION (MONITOREO DNS) ---"
    
    $BUSQUEDA = Read-Host "Ingresa el dominio o IP a buscar en nslookup (ej. reprobados.com o 192.168.10.10)"
    
    Write-Host "`n--- Ejecutando NSLOOKUP hacia $BUSQUEDA ---" -ForegroundColor Yellow
    nslookup $BUSQUEDA localhost
    
    Write-Host "`n"
    $DOM_PING = Read-Host "Ingresa el nombre del dominio para el PING (ej. reprobados.com)"
    Write-Host "--- Ejecutando PING a www.$DOM_PING ---" -ForegroundColor Yellow
    Test-Connection -ComputerName "www.$DOM_PING" -Count 3 -ErrorAction SilentlyContinue
}

# --- MENU PRINCIPAL ---

while ($true) {
    Write-Host "`n-------------------------------------"
    Write-Host "             ( DHCP | DNS )            "
    Write-Host "-------------------------------------"
    Write-Host "*** SERVICIO DHCP ***"
    Write-Host "1. Instalar DHCP"
    Write-Host "2. Configurar DHCP (Asigna IP y Rango)"
    Write-Host "3. Monitorear DHCP"
    Write-Host "*** SERVICIO DNS ***"
    Write-Host "4. Instalar DNS"
    Write-Host "5. Verificar IP Fija en Interfaz"
    Write-Host "6. Agregar Dominio DNS"
    Write-Host "7. Eliminar Dominio DNS"
    Write-Host "8. Ver Dominios DNS Configurados"
    Write-Host "9. Validar y Probar DNS (nslookup/ping)"
    Write-Host "*** SISTEMA ***"
    Write-Host "10. Verificar Instalaciones"
    Write-Host "11. Salir"
    Write-Host "-------------------------------------"
    
    $op = Read-Host "Opcion"
    
    switch ($op) {
        '1'  { Instalar-DHCP }
        '2'  { Configurar-DHCP }
        '3'  { Monitorear-DHCP }
        '4'  { Instalar-DNS }
        '5'  { Verificar-IP-Fija }
        '6'  { Agregar-Dominio }
        '7'  { Eliminar-Dominio }
        '8'  { Listar-Dominios }
        '9'  { Validar-Resolucion }
        '10' { Verificar-Instalaciones }
        '11' { Write-Host "Saliendo..."; break }
        default { Write-Host "Opcion invalida."}
    }
    
    if ($op -eq '11') { break }
}