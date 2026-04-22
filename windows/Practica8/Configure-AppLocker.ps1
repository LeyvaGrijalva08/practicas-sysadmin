$DomainName       = "practica8_repo.com"
$DomainDN         = "DC=practica8_repo,DC=com"
$GPOAppLockerName = "GPO_AppLocker_Control"
$NotepadPath      = "C:\Windows\System32\notepad.exe"

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

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy     -ErrorAction Stop

# --- OBTENER HASH DE NOTEPAD ---
Write-Log "OBTENIENDO HASH SHA256 DE NOTEPAD.EXE" -Tipo TITULO
if (-not (Test-Path $NotepadPath)) { Write-Log "notepad.exe no encontrado." -Tipo ERROR; exit 1 }

$NotepadInfo = Get-AppLockerFileInformation -Path $NotepadPath
$NotepadHash = $NotepadInfo.Hash.HashDataString
$NotepadSize = (Get-Item $NotepadPath).Length
Write-Log "Hash: $NotepadHash" -Tipo OK
Write-Log "Tamano: $NotepadSize bytes" -Tipo INFO

# --- OBTENER SID DE GRP_NoCuates ---
Write-Log "OBTENIENDO SID DE GRP_NoCuates" -Tipo TITULO
$NoCuatesSID = (Get-ADGroup -Identity "GRP_NoCuates").SID.Value
Write-Log "SID: $NoCuatesSID" -Tipo OK

# --- GENERAR GUIDS PARA LAS REGLAS ---
$GuidAdmin    = [System.Guid]::NewGuid().ToString()
$GuidWin      = [System.Guid]::NewGuid().ToString()
$GuidPF       = [System.Guid]::NewGuid().ToString()
$GuidPFx86    = [System.Guid]::NewGuid().ToString()
$GuidDenyHash = [System.Guid]::NewGuid().ToString()

$SID_Admins   = "S-1-5-32-544"
$SID_Everyone = "S-1-1-0"

# --- GENERAR XML DE POLITICA APPLOCKER ---
Write-Log "GENERANDO POLITICA APPLOCKER (XML)" -Tipo TITULO

$AppLockerXML = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <FilePathRule Id="$GuidAdmin" Name="Admins - Todos los archivos"
                  Description="Administradores pueden ejecutar cualquier cosa."
                  UserOrGroupSid="$SID_Admins" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
    </FilePathRule>

    <FilePathRule Id="$GuidWin" Name="Todos - Carpeta Windows"
                  Description="Permite ejecutar apps desde carpeta Windows."
                  UserOrGroupSid="$SID_Everyone" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>

    <FilePathRule Id="$GuidPF" Name="Todos - Program Files"
                  Description="Permite ejecutar apps instaladas en Program Files."
                  UserOrGroupSid="$SID_Everyone" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>

    <FilePathRule Id="$GuidPFx86" Name="Todos - Program Files x86"
                  Description="Permite ejecutar apps en Program Files x86."
                  UserOrGroupSid="$SID_Everyone" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES(X86)%\*" /></Conditions>
    </FilePathRule>

    <!-- REGLA CLAVE: Hash SHA256 de notepad.exe para GRP_NoCuates.
         Funciona aunque el usuario renombre o mueva el archivo. -->
    <FileHashRule Id="$GuidDenyHash" Name="BLOQUEO Notepad por Hash - NoCuates"
                  Description="Bloquea notepad.exe por hash SHA256. El bloqueo es efectivo aunque renombren o muevan el ejecutable."
                  UserOrGroupSid="$NoCuatesSID" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="$NotepadHash"
                    SourceFileLength="$NotepadSize" SourceFileName="notepad.exe" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

  </RuleCollection>
  <RuleCollection Type="Msi"    EnforcementMode="NotConfigured" />
  <RuleCollection Type="Script" EnforcementMode="NotConfigured" />
  <RuleCollection Type="Dll"    EnforcementMode="NotConfigured" />
  <RuleCollection Type="Appx"   EnforcementMode="NotConfigured" />
</AppLockerPolicy>
"@

Write-Log "XML generado correctamente." -Tipo OK

# --- CREAR GPO Y ESCRIBIR EN SYSVOL ---
Write-Log "CREANDO GPO DE APPLOCKER" -Tipo TITULO

$GPO = Get-GPO -Name $GPOAppLockerName -ErrorAction SilentlyContinue
if (-not $GPO) {
    $GPO = New-GPO -Name $GPOAppLockerName -Comment "AppLocker: Cuates=Notepad OK, NoCuates=Notepad BLOQUEADO por hash"
    Write-Log "GPO '$GPOAppLockerName' creada." -Tipo OK
} else { Write-Log "GPO '$GPOAppLockerName' ya existe." -Tipo WARN }

$GPOID     = $GPO.Id.ToString().ToUpper()
$AppLkPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{$GPOID}\Machine\Microsoft\Windows NT\AppLocker"
if (-not (Test-Path $AppLkPath)) { New-Item -Path $AppLkPath -ItemType Directory -Force | Out-Null }

$AppLockerXML | Out-File -FilePath "$AppLkPath\Exe.xml" -Encoding UTF8 -Force
Write-Log "Politica AppLocker escrita en SYSVOL." -Tipo OK

# --- CONFIGURAR AppIDSvc COMO AUTOMATICO ---
# CRITICO: Sin AppIDSvc activo, AppLocker no funciona aunque la GPO este configurada.
Write-Log "CONFIGURANDO SERVICIO AppIDSvc" -Tipo TITULO
Set-GPRegistryValue -Name $GPOAppLockerName `
                    -Key "HKLM\SYSTEM\CurrentControlSet\Services\AppIDSvc" `
                    -ValueName "Start" -Type DWord -Value 2
Write-Log "AppIDSvc configurado como Automatico via GPO." -Tipo OK

# --- ACTUALIZAR VERSION GPO ---
$ADGPObj = [ADSI]"LDAP://CN={$GPOID},CN=Policies,CN=System,$DomainDN"
$Ver = [int]($ADGPObj.Properties["versionNumber"].Value)
$NV  = ((($Ver -shr 16) + 1) -shl 16) -bor ($Ver -band 0xFFFF)
$ADGPObj.Properties["versionNumber"].Value = [int]$NV
$ADGPObj.CommitChanges()
"[General]`r`nVersion=$NV`r`n" | Set-Content "\\$DomainName\SYSVOL\$DomainName\Policies\{$GPOID}\GPT.INI" -Encoding ASCII

try {
    New-GPLink -Name $GPOAppLockerName -Target $DomainDN -LinkEnabled Yes -ErrorAction Stop
    Write-Log "GPO vinculada al dominio." -Tipo OK
} catch { Write-Log "GPLink: $_" -Tipo WARN }

# --- INICIAR AppIDSvc EN EL SERVIDOR ---
$svc = Get-Service "AppIDSvc" -ErrorAction SilentlyContinue
if ($svc) {
    Set-Service "AppIDSvc" -StartupType Automatic
    if ($svc.Status -ne "Running") { Start-Service "AppIDSvc" }
    Write-Log "AppIDSvc activo en el servidor." -Tipo OK
}

gpupdate /force /quiet

Write-Log "SCRIPT 03 COMPLETADO." -Tipo TITULO
Write-Host ""
Write-Host "VERIFICACION EN CLIENTE WINDOWS:" -ForegroundColor Yellow
Write-Host "  1. Loguea con usuario NoCuates -> gpupdate /force" -ForegroundColor White
Write-Host "  2. Intenta abrir notepad.exe -> BLOQUEADO" -ForegroundColor White
Write-Host "  3. Renombra notepad.exe a hola.exe -> SIGUE BLOQUEADO (por hash)" -ForegroundColor White
Write-Host "  4. Loguea con usuario Cuates -> notepad abre normal" -ForegroundColor White
Write-Host "  Logs: Visor de Eventos > Microsoft > Windows > AppLocker > EXE and DLL" -ForegroundColor White
