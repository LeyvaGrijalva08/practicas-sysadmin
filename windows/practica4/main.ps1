. .\funciones.ps1
. .\dhcp.ps1
. .\dns.ps1
. .\diagnostico.ps1

Verificar-Administrador

while ($true) {
    Write-Host "`n-------------------------------------"
    Write-Host "         ( MENU PRINCIPAL )          "
    Write-Host "-------------------------------------"
    Write-Host "*** DIAGNOSTICO ***"
    Write-Host "0. Ejecutar Diagnostico de SO"
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
    Write-Host "*** ESTADO GLOBAL ***"
    Write-Host "10. Verificar Instalaciones"
    Write-Host "11. Salir"
    Write-Host "-------------------------------------"
    
    $op = Read-Host "Opcion"
    
    switch ($op) {
        '0'  { Ejecutar-DiagnosticoSO }
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