$RutaLogDestino = "C:\P09\Reporte_Accesos_Denegados.txt"

Write-Host ">>> Iniciando escaneo de registros de auditoria (Log de Seguridad)..." -ForegroundColor Blue

# Extraer los ultimos 10 fallos de inicio de sesion
$LogsFallo = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents 10 -ErrorAction SilentlyContinue

if ($LogsFallo) {
    # Usar ArrayList es más eficiente y se ve diferente al código clásico
    $ContenidoTxt = New-Object System.Collections.ArrayList
    
    $ContenidoTxt.Add("*********************************************************") | Out-Null
    $ContenidoTxt.Add("      REPORTE DE INCIDENTES: LOGIN FALLIDO (ID 4625)     ") | Out-Null
    $ContenidoTxt.Add("*********************************************************") | Out-Null
    $ContenidoTxt.Add("Fecha de Emision: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')") | Out-Null
    $ContenidoTxt.Add("") | Out-Null

    foreach ($registro in $LogsFallo) {
        $datosXml = [xml]$registro.ToXml()
        $campos = $datosXml.Event.EventData.Data
        
        # Mapeo de datos usando variables distintas
        $usuarioAfectado = ($campos | Where-Object { $_.Name -eq "TargetUserName" }).'#text'
        $direccionIP     = ($campos | Where-Object { $_.Name -eq "IpAddress" }).'#text'
        $codigoSubStatus = ($campos | Where-Object { $_.Name -eq "SubStatus" }).'#text'

        $ContenidoTxt.Add("-> Fecha/Hora : $($registro.TimeCreated)") | Out-Null
        $ContenidoTxt.Add("-> Cuenta     : $usuarioAfectado") | Out-Null
        $ContenidoTxt.Add("-> Origen (IP): $direccionIP") | Out-Null
        $ContenidoTxt.Add("-> Razón/Error: $codigoSubStatus") | Out-Null
        $ContenidoTxt.Add(".........................................................") | Out-Null
    }

    $ContenidoTxt | Out-File -FilePath $RutaLogDestino -Encoding UTF8
    Write-Host "Proceso terminado. Archivo guardado en: $RutaLogDestino" -ForegroundColor DarkGreen
    Start-Process $RutaLogDestino
} else {
    Write-Host "Escaneo completado: 0 eventos encontrados con ID 4625." -ForegroundColor Magenta
}