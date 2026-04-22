
Function Validar-Entrada {
    param([string]$ValorTexto)
    if ([string]::IsNullOrWhiteSpace($ValorTexto) -or $ValorTexto -match "[^0-9]") {
        Write-Host "Error: Entrada invalida. Solo se admiten numeros." -ForegroundColor Red
        return $false
    }
    return $true
}

Function Validar-Puerto {
    param([int]$Port)
    # Puertos reservados basados en tu logica de Linux [cite: 77]
    $PuertosBloqueados = @(1..1023) 
    if ($PuertosBloqueados -contains $Port -and $Port -ne 80) {
        Write-Host "Error: Puerto $Port reservado para servicios del sistema." -ForegroundColor Red
        return $false
    }
    $Connection = Test-NetConnection -ComputerName localhost -Port $Port -WarningAction SilentlyContinue
    if ($Connection.TcpTestSucceeded) {
        Write-Host "Error: El puerto $Port ya esta en uso." -ForegroundColor Red
        return $false
    }
    return $true
}

Function Limpiar-Entorno {
    Write-Host "Ejecutando limpieza completa (Estilo Linux)..." -ForegroundColor Yellow
    
    Stop-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    Stop-Service -Name "apache2.4" -ErrorAction SilentlyContinue
    
    $Procesos = @("httpd", "nginx", "w3wp")
    foreach ($Proc in $Procesos) {
        Get-Process -Name $Proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Remove-NetFirewallRule -DisplayName "HTTP-Practica6-*" -ErrorAction SilentlyContinue
    
    Write-Host "Entorno limpio. Puertos liberados." -ForegroundColor Green
}

Function Instalar-IIS {
    param([int]$Port)
    Write-Host "Iniciando instalacion de IIS..."
    
    # Asegurar que el modulo de administracion este cargado
    if (!(Get-Module -ListAvailable WebAdministration)) {
        Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    }
    Import-Module WebAdministration

    Set-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" -PropertyName "Port" -Value $Port -ErrorAction SilentlyContinue
  
    try {
        Remove-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/httpProtocol/customHeaders" -name "collection" -AtElement @{name='X-Powered-By'} -ErrorAction SilentlyContinue
    } catch {}

    $WebRoot = "C:\inetpub\wwwroot"
    "Servidor: IIS - Puerto: $Port" | Set-Content "$WebRoot\index.html" -Force

    New-NetFirewallRule -DisplayName "HTTP-Practica6-$Port" -LocalPort $Port -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

    # CORRECCION: Uso de -Path explícito para evitar el error de las capturas
    Start-Service -Name W3SVC -ErrorAction SilentlyContinue
    Start-WebItem -Path "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue

    Write-Host "IIS desplegado en puerto $Port." -ForegroundColor Green
}

Function Instalar-Servicio-Choco {
    param([string]$Servicio, [int]$Port)
    
    if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "Instalando Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }

    $Package = if ($Servicio -eq "apache") { "apache-httpd" } else { "nginx" }
    choco install $Package -y --no-progress | Out-Null

    if ($Servicio -eq "apache") {
        $Conf = "C:\tools\apache24\Apache24\conf\httpd.conf"
        (Get-Content $Conf) -replace "Listen \d+", "Listen $Port" | Set-Content $Conf
        Restart-Service -Name "apache2.4" -Force -ErrorAction SilentlyContinue
    }
    else {
        $Conf = "C:\tools\nginx\conf\nginx.conf"
        (Get-Content $Conf) -replace "listen\s+\d+;", "listen $Port;" | Set-Content $Conf
        Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Process "C:\tools\nginx\nginx.exe" -WorkingDirectory "C:\tools\nginx" -WindowStyle Hidden
    }

    New-NetFirewallRule -DisplayName "HTTP-Practica6-$Port" -LocalPort $Port -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "$Servicio desplegado en puerto $Port." -ForegroundColor Green
}