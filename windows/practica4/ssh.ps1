if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "ejecuta este script como Administrador."
    exit
}

function Configurar-AccesoSSH {
    $sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($sshCapability.State -eq 'Installed') {
        Write-Host "OpenSSH Server ya se encuentra instalado"
    } else {
        Write-Host "Instalando OpenSSH Server"
        Add-WindowsCapability -Online -Name $sshCapability.Name | Out-Null
        Write-Host "Instalacion de OpenSSH Server completada."
    }

    Set-Service -Name sshd -StartupType 'Automatic'
    Start-Service sshd -ErrorAction SilentlyContinue
    
    $estadoServicio = Get-Service -Name sshd
    if ($estadoServicio.Status -eq 'Running') {
        Write-Host "Servicio SSH iniciado y configurado en el boot correctamente"
    } else {
        Write-Host "Hubo un problema al iniciar el servicio SSH"
    }

    Write-Host "Verificando reglas de Firewall para el puerto 22..."
    $reglaFirewall = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    
    if (-not $reglaFirewall) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        Write-Host "Regla de Firewall creada exitosamente."
    } else {
        Write-Host "La regla de Firewall para SSH ya existe y esta activa."
    }

    # Obtener IP principal de la maquina
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.InterfaceAlias -notmatch "vEthernet"}).IPAddress | Select-Object -First 1
    $usuario = $env:USERNAME
    Write-Host "ssh $usuario@$ip"
}

Configurar-AccesoSSH