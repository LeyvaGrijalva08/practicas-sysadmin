$DomainName    = "practica8_repo.com"
$DomainDN      = "DC=practica8_repo,DC=com"
$HomePath      = "C:\Carpetas"
$CSVPath       = "C:\Scripts\usuarios.csv"
$UTCOffset     = -7
$GPOLogoffName = "GPO_ForceLogoff"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Mensaje, [ValidateSet("OK","INFO","WARN","ERROR","TITULO")][string]$Tipo = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    switch ($Tipo) {
        "OK"     { Write-Host "[$ts] [+] $Mensaje" -ForegroundColor Green }
        "INFO"   { Write-Host "[$ts] [i] $Mensaje" -ForegroundColor Cyan }
        "WARN"   { Write-Host "[$ts] [!] $Mensaje" -ForegroundColor Yellow }
        "ERROR"  { Write-Host "[$ts] [X] $Mensaje" -ForegroundColor Red }
        "TITULO" { Write-Host "`n[$ts] ===== $Mensaje =====" -ForegroundColor Magenta }
    }
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module GroupPolicy     -ErrorAction Stop
    Write-Log "Modulos cargados." -Tipo OK
} catch {
    Write-Log "Error cargando modulos: $_" -Tipo ERROR; exit 1
}

# --- PARTE 1: OUs ---
Write-Log "CREANDO OUs" -Tipo TITULO
foreach ($OUName in @("Cuates", "NoCuates")) {
    $existe = Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -SearchBase $DomainDN -ErrorAction SilentlyContinue
    if (-not $existe) {
        New-ADOrganizationalUnit -Name $OUName -Path $DomainDN -ProtectedFromAccidentalDeletion $false
        Write-Log "OU '$OUName' creada." -Tipo OK
    } else { Write-Log "OU '$OUName' ya existe." -Tipo WARN }
}

# --- PARTE 2: GRUPOS ---
Write-Log "CREANDO GRUPOS DE SEGURIDAD" -Tipo TITULO
@(
    @{ Nombre = "GRP_Cuates";   OU = "OU=Cuates,$DomainDN"   },
    @{ Nombre = "GRP_NoCuates"; OU = "OU=NoCuates,$DomainDN" }
) | ForEach-Object {
    if (-not (Get-ADGroup -Filter "SamAccountName -eq '$($_.Nombre)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $_.Nombre -SamAccountName $_.Nombre -GroupScope Global -GroupCategory Security -Path $_.OU
        Write-Log "Grupo '$($_.Nombre)' creado." -Tipo OK
    } else { Write-Log "Grupo '$($_.Nombre)' ya existe." -Tipo WARN }
}

# --- PARTE 3: USUARIOS Y HOMES ---
Write-Log "IMPORTANDO USUARIOS DESDE CSV" -Tipo TITULO

if (-not (Test-Path $HomePath)) { New-Item -Path $HomePath -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $CSVPath))  { Write-Log "CSV no en '$CSVPath'. Copia usuarios.csv a C:\Scripts\" -Tipo ERROR; exit 1 }

Import-Csv -Path $CSVPath -Encoding UTF8 | ForEach-Object {
    $U           = $_
    $TargetOU    = if ($U.Departamento -eq "Cuates") { "OU=Cuates,$DomainDN"   } else { "OU=NoCuates,$DomainDN" }
    $TargetGrupo = if ($U.Departamento -eq "Cuates") { "GRP_Cuates"             } else { "GRP_NoCuates"           }
    $UserHome    = "$HomePath\$($U.SamAccountName)"
    $SecurePass  = ConvertTo-SecureString $U.Password -AsPlainText -Force

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($U.SamAccountName)'" -ErrorAction SilentlyContinue)) {
        New-ADUser `
            -GivenName $U.Nombre -Surname $U.Apellido `
            -Name "$($U.Nombre) $($U.Apellido)" -DisplayName "$($U.Nombre) $($U.Apellido)" `
            -SamAccountName $U.SamAccountName -UserPrincipalName "$($U.SamAccountName)@$DomainName" `
            -AccountPassword $SecurePass -Enabled $true -Path $TargetOU -Department $U.Departamento `
            -HomeDirectory $UserHome -HomeDrive "H:" -PasswordNeverExpires $true
        Write-Log "Usuario '$($U.SamAccountName)' creado." -Tipo OK
    } else { Write-Log "Usuario '$($U.SamAccountName)' ya existe." -Tipo WARN }

    Add-ADGroupMember -Identity $TargetGrupo -Members $U.SamAccountName -ErrorAction SilentlyContinue
    Write-Log "  '$($U.SamAccountName)' -> '$TargetGrupo'" -Tipo OK

    if (-not (Test-Path $UserHome)) {
        New-Item -Path $UserHome -ItemType Directory -Force | Out-Null
        $ACL = Get-Acl $UserHome
        $ACL.SetAccessRuleProtection($true, $false)
        @(
            [System.Security.AccessControl.FileSystemAccessRule]::new("$DomainName\$($U.SamAccountName)", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"),
            [System.Security.AccessControl.FileSystemAccessRule]::new("BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"),
            [System.Security.AccessControl.FileSystemAccessRule]::new("NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        ) | ForEach-Object { $ACL.AddAccessRule($_) }
        Set-Acl -Path $UserHome -AclObject $ACL
        Write-Log "  Carpeta '$UserHome' creada con ACLs." -Tipo OK
    }
}

# --- PARTE 4: LOGON HOURS (CONVERSION UTC-7) ---
Write-Log "CONFIGURANDO LOGON HOURS" -Tipo TITULO

function New-LogonHoursArray {
    param([int[]]$HorasLocalesPermitidas, [int]$OffsetUTC)
    $bytes = New-Object byte[] 21
    for ($dia = 0; $dia -lt 7; $dia++) {
        foreach ($h in $HorasLocalesPermitidas) {
            $hUTC  = (($h - $OffsetUTC) % 24 + 24) % 24
            $iB    = ($dia * 3) + [int][math]::Floor($hUTC / 8)
            $bit   = $hUTC % 8
            $bytes[$iB] = [byte]($bytes[$iB] -bor (1 -shl $bit))
        }
    }
    return $bytes
}

$BytesCuates   = New-LogonHoursArray -HorasLocalesPermitidas (8..14)                            -OffsetUTC $UTCOffset
$BytesNoCuates = New-LogonHoursArray -HorasLocalesPermitidas @(15,16,17,18,19,20,21,22,23,0,1) -OffsetUTC $UTCOffset

Write-Log "Cuates: 8:00 AM - 3:00 PM local | NoCuates: 3:00 PM - 2:00 AM local" -Tipo INFO

@(
    @{ Nombre = "GRP_Cuates";   Bytes = $BytesCuates   },
    @{ Nombre = "GRP_NoCuates"; Bytes = $BytesNoCuates }
) | ForEach-Object {
    $G = $_
    Get-ADGroupMember -Identity $G.Nombre | Where-Object { $_.objectClass -eq "user" } | ForEach-Object {
        Set-ADUser -Identity $_.SamAccountName -Replace @{ logonHours = $G.Bytes }
        Write-Log "LogonHours aplicado a '$($_.SamAccountName)'" -Tipo OK
    }
}

# --- PARTE 5: GPO FORCE LOGOFF ---
Write-Log "GPO FORCE LOGOFF" -Tipo TITULO

$GPO = Get-GPO -Name $GPOLogoffName -ErrorAction SilentlyContinue
if (-not $GPO) { $GPO = New-GPO -Name $GPOLogoffName; Write-Log "GPO creada." -Tipo OK }

$GPOID   = $GPO.Id.ToString().ToUpper()
$SecEdit = "\\$DomainName\SYSVOL\$DomainName\Policies\{$GPOID}\Machine\Microsoft\Windows NT\SecEdit"
if (-not (Test-Path $SecEdit)) { New-Item -Path $SecEdit -ItemType Directory -Force | Out-Null }

"[Unicode]`r`nUnicode=yes`r`n[System Access]`r`nForceLogoffWhenHourExpire = 1`r`n[Version]`r`nsignature=""`$CHICAGO`$""`r`nRevision=1" |
    Out-File "$SecEdit\GptTmpl.inf" -Encoding Unicode -Force

$ADGPObj = [ADSI]"LDAP://CN={$GPOID},CN=Policies,CN=System,$DomainDN"
$Ver = [int]($ADGPObj.Properties["versionNumber"].Value)
$NV  = ((($Ver -shr 16) + 1) -shl 16) -bor ($Ver -band 0xFFFF)
$ADGPObj.Properties["versionNumber"].Value = [int]$NV
$ADGPObj.CommitChanges()
"[General]`r`nVersion=$NV`r`n" | Set-Content "\\$DomainName\SYSVOL\$DomainName\Policies\{$GPOID}\GPT.INI" -Encoding ASCII

try { New-GPLink -Name $GPOLogoffName -Target $DomainDN -LinkEnabled Yes -ErrorAction Stop; Write-Log "GPO vinculada." -Tipo OK }
catch { Write-Log "GPLink: $_" -Tipo WARN }

gpupdate /force /quiet
Write-Log "SCRIPT 01 COMPLETADO. Ejecuta ahora el script 02." -Tipo TITULO
