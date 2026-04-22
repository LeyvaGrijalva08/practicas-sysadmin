. .\http_functions.ps1

do {
    Clear-Host
    Write-Host "=== GESTOR DE SERVICIOS WEB (WINDOWS SERVER) ===" -ForegroundColor Cyan
    Write-Host "1. Instalar IIS (Nativo)"
    Write-Host "2. Instalar Apache (Choco)"
    Write-Host "3. Instalar Nginx (Choco)"
    Write-Host "4. Limpiar Entorno (Borrar todo)"
    Write-Host "5. Salir"
    
    $Opcion = Read-Host "Seleccione una opcion"

    switch ($Opcion) {
        "1" { 
            $P = Read-Host "Puerto"
            if (Validar-Puerto $P) { Instalar-IIS -Port $P }
        }
        "2" { 
            $P = Read-Host "Puerto"
            if (Validar-Puerto $P) { Instalar-Servicio-Choco -Servicio "apache" -Port $P }
        }
        "3" { 
            $P = Read-Host "Puerto"
            if (Validar-Puerto $P) { Instalar-Servicio-Choco -Servicio "nginx" -Port $P }
        }
        "4" { Limpiar-Entorno }
        "5" { break }
    }
    if ($Opcion -ne "5") { Read-Host "`nPresione Enter para continuar..." }
} while ($Opcion -ne "5")