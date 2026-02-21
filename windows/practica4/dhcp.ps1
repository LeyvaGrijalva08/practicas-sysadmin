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