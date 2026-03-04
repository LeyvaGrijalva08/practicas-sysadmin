Import-Module WebAdministration -ErrorAction SilentlyContinue

function msg_info($text) { Write-Host "[INFO] $text" -ForegroundColor Green }
function msg_error($text) { Write-Host "[ERROR] $text" -ForegroundColor Red }

function instalar_ftp {
    Install-WindowsFeature Web-Server, Web-FTP-Server -IncludeManagementTools | Out-Null
    
    if (Test-Path "IIS:\Sites\ServidorFTP") {
        Remove-WebSite -Name "ServidorFTP" | Out-Null
    }

    $ftpRoot = "C:\FTP"
    if (Test-Path $ftpRoot) { Remove-Item -Path $ftpRoot -Recurse -Force | Out-Null }
    
    $rutas = @("C:\FTP", "C:\FTP\grupos", "C:\FTP\grupos\recursadores", "C:\FTP\grupos\reprobados", "C:\FTP\LocalUser", "C:\FTP\LocalUser\Public", "C:\FTP\LocalUser\Public\general")
    foreach ($ruta in $rutas) {
        if (-not (Test-Path $ruta)) { New-Item -Path $ruta -ItemType Directory -Force | Out-Null }
    }

    $grupos = @("reprobados", "recursadores")
    $ADSI = [ADSI]"WinNT://$env:ComputerName"
    foreach ($g in $grupos) {
        if (-not ($ADSI.Children | Where-Object { $_.SchemaClassName -eq 'Group' -and $_.Name -eq $g })) {
            $nuevoGrupo = $ADSI.Create("Group", $g)
            $nuevoGrupo.SetInfo()
        }
        $rutaGrupo = "C:\FTP\grupos\$g"
        $acl = Get-Acl $rutaGrupo
        $acl.SetAccessRuleProtection($true, $false)
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($adminRule)
        $groupRule = New-Object System.Security.AccessControl.FileSystemAccessRule($g, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($groupRule)
        Set-Acl $rutaGrupo $acl
    }

    $AclGeneral = Get-Acl "C:\FTP\LocalUser\Public\general"
    $AccessRuleGen = New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $AclGeneral.SetAccessRule($AccessRuleGen)
    Set-Acl "C:\FTP\LocalUser\Public\general" $AclGeneral

    if (-not (Get-NetFirewallRule -DisplayName "FTP_Practica" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP_Practica" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
    }

    New-WebFtpSite -Name "ServidorFTP" -Port 21 -PhysicalPath "C:\FTP" -Force | Out-Null
    Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/siteDefaults/ftpServer/userIsolation" -Name "mode" -Value "IsolateAllDirectories"
    
    Remove-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -Name "." -Location "ServidorFTP" -ErrorAction SilentlyContinue
    Add-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Value @{ accessType = "Allow"; users = "IUSR"; permissions = 1 } -Location "ServidorFTP" | Out-Null
    Add-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Value @{ accessType = "Allow"; roles = "reprobados,recursadores"; permissions = 3 } -Location "ServidorFTP" | Out-Null

    Set-ItemProperty -Path "IIS:\Sites\ServidorFTP" -Name ftpServer.Security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty -Path "IIS:\Sites\ServidorFTP" -Name ftpServer.Security.authentication.anonymousAuthentication.userName -Value "IUSR"
    Set-ItemProperty -Path "IIS:\Sites\ServidorFTP" -Name ftpServer.Security.authentication.anonymousAuthentication.password -Value ""

    Set-ItemProperty -Path "IIS:\Sites\ServidorFTP" -Name ftpServer.Security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty -Path "IIS:\Sites\ServidorFTP" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0
    Set-ItemProperty -Path "IIS:\Sites\ServidorFTP" -Name "ftpServer.security.ssl.dataChannelPolicy" -Value 0

    Restart-WebItem "IIS:\Sites\ServidorFTP" -ErrorAction SilentlyContinue | Out-Null
    msg_info "Servicio FTP instalado con exito."
}

function crear_usuarios {
    $n = Read-Host "Numero de usuarios a crear"
    for ($i = 1; $i -le $n; $i++) {
        Write-Host "--- Usuario $i ---"
        $username = Read-Host "Nombre de usuario"
        $passwordSecure = Read-Host -AsSecureString "Contrasena (ej. Password123!)"
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure))
        
        while ($true) {
            $g_opt = Read-Host "Grupo (1: reprobados, 2: recursadores)"
            if ($g_opt -eq "1") { $grupo = "reprobados"; break }
            if ($g_opt -eq "2") { $grupo = "recursadores"; break }
            msg_error "Opcion no valida."
        }

        $ADSI = [ADSI]"WinNT://$env:ComputerName"
        $usuarioExiste = $ADSI.Children | Where-Object { $_.SchemaClassName -eq 'User' -and $_.Name -eq $username }
        if ($usuarioExiste) {
            msg_error "El usuario $username ya existe."
            continue
        }

        try {
            $CreateUserFTPUser = $ADSI.Create("User", "$username")
            $CreateUserFTPUser.SetPassword("$password")  
            $CreateUserFTPUser.SetInfo()
        } catch {
            msg_error "Error al crear usuario. Revisa las politicas de Windows."
            continue
        }

        $groupADSI = [ADSI]"WinNT://$env:ComputerName/$grupo,group"
        $groupADSI.Invoke("Add", "WinNT://$env:ComputerName/$username,user")

        $UserPath = "C:\FTP\LocalUser\$username"
        New-Item -Path $UserPath -ItemType Directory -Force | Out-Null
        New-Item -Path "$UserPath\$username" -ItemType Directory -Force | Out-Null

        $Acl = Get-Acl "$UserPath\$username"
        $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($username, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($AccessRule)
        Set-Acl "$UserPath\$username" $Acl

        cmd /c mklink /D "$UserPath\general" "C:\FTP\LocalUser\Public\general" | Out-Null
        cmd /c mklink /D "$UserPath\$grupo" "C:\FTP\grupos\$grupo" | Out-Null

        msg_info "Usuario $username creado en el grupo $grupo."
    }
}

function cambiar_grupo {
    $username = Read-Host "Nombre del usuario a modificar"
    $ADSI = [ADSI]"WinNT://$env:ComputerName"
    $usuarioExiste = $ADSI.Children | Where-Object { $_.SchemaClassName -eq 'User' -and $_.Name -eq $username }
    if (-not $usuarioExiste) {
        msg_error "El usuario no existe."
        return
    }

    $userADSI = [ADSI]"WinNT://$env:ComputerName/$username,user"
    $gruposActuales = $userADSI.Groups() | ForEach-Object { $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null) }
    $viejoGrupo = ""
    if ($gruposActuales -contains "reprobados") { $viejoGrupo = "reprobados" }
    elseif ($gruposActuales -contains "recursadores") { $viejoGrupo = "recursadores" }

    while ($true) {
        $g_opt = Read-Host "Nuevo Grupo (1: reprobados, 2: recursadores)"
        if ($g_opt -eq "1") { $nuevoGrupo = "reprobados"; break }
        if ($g_opt -eq "2") { $nuevoGrupo = "recursadores"; break }
        msg_error "Opcion no valida."
    }

    if ($viejoGrupo -eq $nuevoGrupo) {
        msg_error "El usuario ya pertenece a ese grupo."
        return
    }

    if ($viejoGrupo -ne "") {
        $oldGroupADSI = [ADSI]"WinNT://$env:ComputerName/$viejoGrupo,group"
        $oldGroupADSI.Invoke("Remove", "WinNT://$env:ComputerName/$username,user")
    }
    $newGroupADSI = [ADSI]"WinNT://$env:ComputerName/$nuevoGrupo,group"
    $newGroupADSI.Invoke("Add", "WinNT://$env:ComputerName/$username,user")

    $UserPath = "C:\FTP\LocalUser\$username"
    if ($viejoGrupo -ne "") {
        cmd /c "rmdir /S /Q `"$UserPath\$viejoGrupo`"" 2>$null
    }

    cmd /c mklink /D "$UserPath\$nuevoGrupo" "C:\FTP\grupos\$nuevoGrupo" | Out-Null

    Restart-Service ftpsvc -Force -ErrorAction SilentlyContinue | Out-Null
    msg_info "Usuario $username movido a $nuevoGrupo exitosamente."
}

while ($true) {
    Write-Host "`nMENU DE GESTION FTP"
    Write-Host "1. Instalar/Reinstalar Servidor FTP"
    Write-Host "2. Creacion Masiva de Usuarios"
    Write-Host "3. Cambiar Usuario de Grupo"
    Write-Host "4. Salir"
    $opcion = Read-Host "Seleccione una opcion"

    switch ($opcion) {
        "1" { instalar_ftp }
        "2" { crear_usuarios }
        "3" { cambiar_grupo }
        "4" { exit }
        default { msg_error "Opcion no valida." }
    }
}