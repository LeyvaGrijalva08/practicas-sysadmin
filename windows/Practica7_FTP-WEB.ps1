$ErrorActionPreference = "Stop"
$DOMAIN = "www.reprobados.com"

# Asegurar protocolos de seguridad
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

function Instalar-DependenciasBase {
    Write-Host "Verificando dependencias (Chocolatey, OpenSSL)..." -ForegroundColor Cyan
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    choco install openssl.light -y --no-progress
}

function Limpiar-Entorno {
    Write-Host "=== LIMPIEZA DE ENTORNO ===" -ForegroundColor Cyan
    Set-Location "C:\"
    Write-Host "Deteniendo servicios competidores..."
    
    # Detener IIS (Este es el que te esta bloqueando el puerto 80)
    Stop-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    # Detener Apache
    Stop-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    # Matar cualquier rastro de Nginx
    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
    
    Write-Host "Limpiando carpetas de instalacion anteriores..."
    Remove-Item -Path "C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Apache24" -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host "Limpieza completada. Puertos 80 y 443 liberados." -ForegroundColor Green
}

function Generar-Certificados {
    param($servicio)
    $certDir = "C:\certs"
    if (-not (Test-Path $certDir)) { New-Item -ItemType Directory -Path $certDir | Out-Null }
    
    Write-Host "Generando certificados SSL..." -ForegroundColor Cyan
    $cert = New-SelfSignedCertificate -DnsName $DOMAIN -CertStoreLocation "Cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
    
    $openssl = (Get-Command openssl.exe -ErrorAction SilentlyContinue).Source
    if ($openssl) {
        $args = "req -x509 -nodes -days 365 -newkey rsa:2048 -keyout `"$certDir\reprobados.key`" -out `"$certDir\reprobados.crt`" -subj `"/C=MX/ST=Sinaloa/L=LosMochis/O=FIM/CN=$DOMAIN`""
        Start-Process -FilePath $openssl -ArgumentList $args -Wait -WindowStyle Hidden
    }
}

function Instalar-Nginx {
    Write-Host "=== INSTALACION DE NGINX ===" -ForegroundColor Cyan
    
    Write-Host "Liberando puerto 80 (Apagando IIS)..."
    Stop-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    
    $puertoHTTP = Read-Host "Ingrese el puerto principal (ej. 80)"
    $activar_ssl = Read-Host "Desea activar SSL? [S/N]"
    
    if ($activar_ssl -match "s") {
        $puertoSSL = Read-Host "Ingrese el puerto seguro (ej. 443)"
        Generar-Certificados "Nginx"
    }

    if (-not (Test-Path "C:\nginx")) {
        Write-Host "Instalando Nginx via Chocolatey..."
        choco install nginx -y --no-progress
        
        # Chocolatey a veces lo pone en C:\tools o en C:\ProgramData. Vamos a moverlo a C:\nginx
        $posiblesRutas = @("C:\tools\nginx", "C:\ProgramData\chocolatey\lib\nginx\tools\nginx")
        foreach ($r in $posiblesRutas) {
            if (Test-Path $r) {
                Move-Item -Path $r -Destination "C:\nginx" -Force
                break
            }
        }
    }

    if (-not (Test-Path "C:\nginx")) {
        Write-Host "Error: No se pudo localizar la carpeta de Nginx." -ForegroundColor Red
        return
    }

    $confPath = "C:\nginx\conf\nginx.conf"
    $config = @"
worker_processes  1;
events { worker_connections  1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       ${puertoHTTP};
        server_name  ${DOMAIN};
        location / {
            root   html;
            index  index.html index.htm;
        }
    }
"@
    if ($activar_ssl -match "s") {
        $config += @"
    server {
        listen       ${puertoSSL} ssl;
        server_name  ${DOMAIN};
        ssl_certificate      C:/certs/reprobados.crt;
        ssl_certificate_key  C:/certs/reprobados.key;
        location / {
            root   html;
            index  index.html index.htm;
        }
    }
"@
    }
    $config += "`n}"
    Set-Content -Path $confPath -Value $config -Force

    Set-Location "C:\nginx"
    Start-Process -FilePath ".\nginx.exe" -WindowStyle Hidden
    Write-Host "Nginx configurado y corriendo correctamente." -ForegroundColor Green
    Set-Location "C:\"
}

# --- MENU ---
Instalar-DependenciasBase
while ($true) {
    Write-Host "`n1. Instalar Nginx  2. Limpiar Entorno (Liberar Puertos)  3. Salir" -ForegroundColor Yellow
    $op = Read-Host "Opcion"
    if ($op -eq "1") { Instalar-Nginx }
    elseif ($op -eq "2") { Limpiar-Entorno }
    elseif ($op -eq "3") { exit }
}