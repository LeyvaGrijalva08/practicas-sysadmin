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
    Write-Host "`nAGREGAR DOMINIO DNS"
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
    Write-Host "`nPRUEBAS DE RESOLUCION (MONITOREO DNS) "
    
    $BUSQUEDA = Read-Host "Ingresa el dominio o IP a buscar en nslookup (ej. reprobados.com o 192.168.10.10)"
    
    Write-Host "`nEjecutando NSLOOKUP hacia $BUSQUEDA" 
    nslookup $BUSQUEDA localhost
    
    Write-Host "`n"
    $DOM_PING = Read-Host "Ingresa el nombre del dominio para el PING (ej. reprobados.com)"
    Write-Host "--- Ejecutando PING a www.$DOM_PING ---"
    Test-Connection -ComputerName "www.$DOM_PING" -Count 3 -ErrorAction SilentlyContinue
}