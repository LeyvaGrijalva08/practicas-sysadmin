Import-Module ActiveDirectory

# 1. Recoleccion de datos del entorno
$InfoDominio = Get-ADDomain
$RutaDN = $InfoDominio.DistinguishedName
$NetBIOS = $InfoDominio.NetBIOSName

$CarpetaA = "OU=Cuates,$RutaDN"
$CarpetaB = "OU=NoCuates,$RutaDN"

Clear-Host
Write-Host ">>> INICIANDO HARDENING EN $($InfoDominio.Name) <<<" -ForegroundColor DarkCyan

# 2. Gestion de Dependencias
$ExisteCarbon = Get-Module -ListAvailable -Name "Carbon"

if (!$ExisteCarbon) {
    Write-Host "    -> Descargando e instalando dependencias..." -ForegroundColor Gray
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    Install-Module -Name Carbon -AllowClobber -Force -Scope CurrentUser
}
Import-Module Carbon

# 3. Estructura de Cuentas RBAC

$ClaveMaestra = ConvertTo-SecureString "Practica9.admin123" -AsPlainText -Force
$NombreGrupo = "Admins_P09"

# Arreglo de objetos
$Operadores = @(
    [pscustomobject]@{ ID = "admin_identidad"; Descripcion = "IAM Operator - Gestion de Usuarios" }
    [pscustomobject]@{ ID = "admin_storage";   Descripcion = "Storage Operator - Gestion FSRM" }
    [pscustomobject]@{ ID = "admin_politicas"; Descripcion = "GPO Compliance - Directivas" }
    [pscustomobject]@{ ID = "admin_auditoria"; Descripcion = "Security Auditor - Solo Lectura" }
)

# Creamos el grupo si no existe
if (!(Get-ADGroup -Filter "Name -eq '$NombreGrupo'" -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name $NombreGrupo -GroupScope Global -GroupCategory Security -Path "CN=Users,$RutaDN"
}

foreach ($op in $Operadores) {
    $busqueda = Get-ADUser -Filter "SamAccountName -eq '$($op.ID)'" -ErrorAction SilentlyContinue
    
    if (!$busqueda) {
        New-ADUser -SamAccountName $op.ID -Name $op.ID -UserPrincipalName "$($op.ID)@$($InfoDominio.Name)" `
                   -AccountPassword $ClaveMaestra -Enabled $true -Description $op.Descripcion -Path "CN=Users,$RutaDN"
        
        Grant-CPrivilege -Identity $op.ID -Privilege "SeInteractiveLogonRight"
        Write-Host "    [OK] Cuenta configurada: $($op.ID)" -ForegroundColor Green
    }
    
    # Asegurar membresia
    Add-ADGroupMember -Identity $NombreGrupo -Members $op.ID -ErrorAction SilentlyContinue
}

# 4. Inyeccion de Reglas de Acceso (ACLs)

# Identidad
$ReglaUser1 = "$NetBIOS\admin_identidad:CCDC;user"
$ReglaUser2 = "$NetBIOS\admin_identidad:CA;Reset Password;user"
$ReglaUser3 = "$NetBIOS\admin_identidad:RPWP;;user"

& dsacls $CarpetaA /I:S /G $ReglaUser1 $ReglaUser2 $ReglaUser3 | Out-Null
& dsacls $CarpetaB /I:S /G $ReglaUser1 $ReglaUser2 $ReglaUser3 | Out-Null

# Storage (Denegación Explícita)
& dsacls $CarpetaA /I:S /D "$NetBIOS\admin_storage:CA;Reset Password;user" | Out-Null
& dsacls $CarpetaB /I:S /D "$NetBIOS\admin_storage:CA;Reset Password;user" | Out-Null
Add-ADGroupMember -Identity "Administrators" -Members "admin_storage" -ErrorAction SilentlyContinue

# Politicas
& dsacls $RutaDN /G "$NetBIOS\admin_politicas:GR" | Out-Null
Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "admin_politicas" -ErrorAction SilentlyContinue
& dsacls "CN=Password Settings Container,CN=System,$RutaDN" /I:S /G "$NetBIOS\admin_politicas:RPWP;;msDS-PasswordSettings" | Out-Null

# Auditoria (Con parche SDDL integrado directamente)
& dsacls $RutaDN /G "$NetBIOS\admin_auditoria:GR" | Out-Null

$SID_Auditor = (Get-ADUser "admin_auditoria").SID.Value
$DataSDDL = auditpol /get /sd
$LineaFiltrada = ($DataSDDL | Where-Object { $_ -match "D:\(" }) -join ""
$SDDL_Procesado = $LineaFiltrada.Substring($LineaFiltrada.IndexOf("D:")).Trim()

auditpol /set /sd:"$($SDDL_Procesado)(A;;GR;;;$SID_Auditor)" | Out-Null
Write-Host "    [OK] SDDL de auditoría inyectado correctamente." -ForegroundColor Green

# 5. Politicas de Contraseña (FGPP)

if (!(Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'Pol_Admins_12'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy -Name "Pol_Admins_12" -Precedence 10 -MinPasswordLength 12 -ComplexityEnabled $true
    Add-ADFineGrainedPasswordPolicySubject -Identity "Pol_Admins_12" -Subjects $NombreGrupo
}

if (!(Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'Pol_Estandar_8'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy -Name "Pol_Estandar_8" -Precedence 20 -MinPasswordLength 8 -ComplexityEnabled $true
    Add-ADFineGrainedPasswordPolicySubject -Identity "Pol_Estandar_8" -Subjects "Domain Users"
}

# 6. Motor de Auditoria y Parametros MFA

"Logon", "Logoff", "User Account Management", "File System" | ForEach-Object {
    & auditpol /set /subcategory:$_ /success:enable /failure:enable | Out-Null
}

& "C:\Program Files\multiOTP\multiotp.exe" -config "max-block-failures=3" | Out-Null

$DirectorioRegistro = "HKLM:\SOFTWARE\multiOTP"
if (!(Test-Path $DirectorioRegistro)) {
    New-Item -Path $DirectorioRegistro -Force | Out-Null
}

Set-ItemProperty -Path $DirectorioRegistro -Name "totp_offline_ui_login_failures" -Value 3 -Type DWord -Force | Out-Null
Set-ItemProperty -Path $DirectorioRegistro -Name "totp_offline_ui_lockout_minutes" -Value 30 -Type DWord -Force | Out-Null

Write-Host "`n>>> OPERACIÓN FINALIZADA CON EXITO <<<" -ForegroundColor DarkGreen