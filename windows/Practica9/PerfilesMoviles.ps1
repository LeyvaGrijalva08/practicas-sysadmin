Import-Module ActiveDirectory

# Definicion de variables personalizadas
$ServidorLocal = $env:COMPUTERNAME
$DirectorioBase = "C:\PerfilesEnRed"
$NombreShare = "PerfilesMoviles$"

Clear-Host
Write-Host "PERFILES MOVILES" -ForegroundColor Yellow

# FASE 1: Acondicionamiento del almacenamiento
Write-Host "`n[*] Comprobando almacenamiento central..." -ForegroundColor Cyan

if (-not (Test-Path -Path $DirectorioBase)) {
    Write-Host "    -> Creando el directorio raiz: $DirectorioBase" -ForegroundColor DarkGray
    New-Item -Path $DirectorioBase -ItemType Directory -Force | Out-Null
}

$verificarShare = Get-SmbShare -Name $NombreShare -ErrorAction SilentlyContinue
if (-not $verificarShare) {
    Write-Host "    -> Publicando la carpeta en la red ($NombreShare)..." -ForegroundColor DarkGray
    New-SmbShare -Name $NombreShare -Path $DirectorioBase -FullAccess "Everyone" | Out-Null
} else {
    Write-Host "    -> La carpeta compartida ya esta operativa." -ForegroundColor DarkGray
}

# FASE 2: Inyeccion del atributo a los usuarios de la OU Cuate
$Dominio = (Get-ADDomain).DistinguishedName
$RutaOU = "OU=Cuates,$Dominio"

# obtiene los usuarios que estan dentro de esa carpeta
$GrupoUsuarios = Get-ADUser -Filter * -SearchBase $RutaOU

if ($GrupoUsuarios.Count -eq 0) {
    Write-Host "    [!] Atencion: No se encontro ningun usuario en esa OU." -ForegroundColor Red
} else {
    foreach ($usr in $GrupoUsuarios) {
        # ruta de red unica para cada uno
        $RutaPerfilRed = "\\$ServidorLocal\$NombreShare\$($usr.SamAccountName)"

        try {
            # atributo del usuario en la base de datos de AD
            Set-ADUser -Identity $usr.SamAccountName -ProfilePath $RutaPerfilRed
            Write-Host "    [+] Perfil de red enlazado exitosamente: $($usr.SamAccountName)" -ForegroundColor Green
        } catch {
            Write-Host "    [-] Hubo un fallo al intentar actualizar a: $($usr.SamAccountName)" -ForegroundColor Red
        }
    }
}

Write-Host "PERFILES MOVILES CREADOS" -ForegroundColor Yellow