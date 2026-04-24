Clear-Host
$MotorMfa = "C:\Program Files\multiOTP\multiotp.exe"
$RutaGuardian = "C:\P09\Guardian-SSH.ps1"
$ConfigSsh = "C:\ProgramData\ssh\sshd_config"

# FASE 1 Creando el script Guardian que intercepta la conexion
Write-Host "[] Creando el interceptor de seguridad..." -ForegroundColor Yellow

$CodigoGuardian = @"
Write-Host `n"[ ESCUDO DE SEGURIDAD ACTIVO ]" -ForegroundColor Cyan
`$intentoMfa = Read-Host "Ingrese su codigo de Google Authenticator (6 digitos)"

if (`$intentoMfa -notmatch '^\d{6}$') {
    Write-Host "[X] Formato invalido. La conexion sera destruida." -ForegroundColor Red
    Start-Sleep -Seconds 2
    Exit
}

Write-Host "[] Evaluando token..." -ForegroundColor DarkGray
`$respuesta = & "$MotorMfa" `$env:USERNAME `$intentoMfa

if (`$LASTEXITCODE -eq 0 -or `$respuesta -match "OK") {
    Write-Host "[+] Identidad confirmada. Bienvenido/a, `$env:USERNAME." -ForegroundColor Green
    & powershell.exe -NoExit -Command "Set-Location C:\Users\$env:USERNAME"
} else {
    Write-Host "[X] Acceso Denegado. Token invalido o expirado." -ForegroundColor Red
    Start-Sleep -Seconds 3
    Exit
}
"@

Set-Content -Path $RutaGuardian -Value $CodigoGuardian -Force

# FASE 2 Inyectar el Guardian en la configuracion de OpenSSH
Write-Host "[] Modificando el motor de OpenSSH..." -ForegroundColor Yellow

$ContenidoSsh = Get-Content $ConfigSsh | Where-Object { $_ -notmatch "^\s*ForceCommand" }

# regla al final
$ComandoFuerza = "ForceCommand powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$RutaGuardian`""
$ContenidoSsh += $ComandoFuerza

Set-Content -Path $ConfigSsh -Value $ContenidoSsh -Force

# FASE 3 Ajuste de Permisos (Seguro) y Reinicio
Write-Host "[] Ajustando permisos de la base de datos OTP..." -ForegroundColor Yellow
# A diferencia de Everyone Full Control, solo damos Modificacion a Users
icacls "C:\Program Files\multiOTP" /grant "Users:(OI)(CI)M" /T /Q | Out-Null

Write-Host "[] Reiniciando servicio SSH..." -ForegroundColor Yellow
Restart-Service sshd -Force

Write-Host "`n DEPLIEGUE EXITOSO SSH" -ForegroundColor Green