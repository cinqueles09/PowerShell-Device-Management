#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
    Autor: Ismael Morilla
    Version: 2.0
    Fecha: 26/11/2026

    Descripcion:
    Diagnostico de requisitos de BitLocker y deteccion
    de posibles bloqueos del cifrado silencioso con Intune.

    Ejecucion: PowerShell 5.1 como administrador o SYSTEM.
#>

#region CONFIGURACION

$Unidad = $env:SystemDrive

$RutaMDM = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\BitLocker"
$RutaFVE = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"

$Incidencias = [System.Collections.Generic.List[object]]::new()

function Add-Incidencia {
    param (
        [string]$Nivel,
        [string]$Componente,
        [string]$Mensaje
    )

    $Incidencias.Add([PSCustomObject]@{
        Nivel      = $Nivel
        Componente = $Componente
        Mensaje    = $Mensaje
    })
}

#endregion

#region INFORMACION DEL DISPOSITIVO

$OS = Get-CimInstance -ClassName Win32_OperatingSystem

$Equipo = $env:COMPUTERNAME

$Usuario = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName

# Detectar modo de firmware

try {
    $Firmware = (Get-ComputerInfo `
        -Property BiosFirmwareType `
        -ErrorAction Stop).BiosFirmwareType.ToString()
}
catch {
    $Firmware = "Desconocido"
}

# Detectar Secure Boot

try {
    $SecureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
}
catch {
    $SecureBoot = "No disponible"
}

#endregion

#region WINDOWS RECOVERY ENVIRONMENT

$WinRE = "Desconocido"

try {
    $Reagent = reagentc.exe /info 2>&1

    if ($LASTEXITCODE -eq 0) {

        $Estado = $Reagent | Where-Object {
            $_ -match "Windows RE" -and
            $_ -match "(status|estado)"
        }

        if ($Estado -match "(Disabled|Deshabilitado)") {
            $WinRE = "Deshabilitado"
        }
        elseif ($Estado -match "(Enabled|Habilitado)") {
            $WinRE = "Habilitado"
        }
    }
}
catch {
    $WinRE = "Error de consulta"
}

#endregion

#region TPM

$TPM = $null
$TPMVersion = $null

try {
    $TPM = Get-Tpm -ErrorAction Stop

    if ($TPM.TpmPresent) {

        $TPMInfo = Get-CimInstance `
            -Namespace "Root\CIMv2\Security\MicrosoftTpm" `
            -ClassName Win32_Tpm `
            -ErrorAction Stop

        $TPMVersion = ($TPMInfo.SpecVersion -split ",")[0].Trim()
    }
}
catch {
    Add-Incidencia "AVISO" "TPM" `
        "No se ha podido obtener toda la informacion del TPM."
}

#endregion

#region ESTADO BITLOCKER

$BitLocker = $null
$Protectores = $null

try {
    $BitLocker = Get-BitLockerVolume `
        -MountPoint $Unidad `
        -ErrorAction Stop

    $Protectores = @(
        $BitLocker.KeyProtector |
        ForEach-Object { $_.KeyProtectorType.ToString() }
    )
}
catch {
    Add-Incidencia "ERROR" "BitLocker" `
        "No se ha podido consultar el volumen del sistema."
}

#endregion

#region POLITICAS MDM Y FVE

$MDM = Get-ItemProperty `
    -Path $RutaMDM `
    -ErrorAction SilentlyContinue

$FVE = Get-ItemProperty `
    -Path $RutaFVE `
    -ErrorAction SilentlyContinue

$RequireEncryption = $MDM.RequireDeviceEncryption
$AllowStandardUser = $MDM.AllowStandardUserEncryption
$AllowWarning = $MDM.AllowWarningForOtherDiskEncryption

# Metodo de cifrado configurado para el sistema operativo

$Metodos = @{
    3 = "Aes128"
    4 = "Aes256"
    6 = "XtsAes128"
    7 = "XtsAes256"
}

$MetodoID = $FVE.EncryptionMethodWithXtsOs

$MetodoPolitica = "No configurado o no detectado"

if ($null -ne $MetodoID) {

    if ($Metodos.ContainsKey([int]$MetodoID)) {
        $MetodoPolitica = $Metodos[[int]$MetodoID]
    }
    else {
        $MetodoPolitica = "Valor desconocido: $MetodoID"
    }
}

#endregion

#region MICROSOFT ENTRA ID

$EntraJoined = "Desconocido"
$DomainJoined = "Desconocido"

try {
    $DSReg = dsregcmd.exe /status

    if ($DSReg -match "AzureAdJoined\s*:\s*YES") {
        $EntraJoined = $true
    }
    elseif ($DSReg -match "AzureAdJoined\s*:\s*NO") {
        $EntraJoined = $false
    }

    if ($DSReg -match "DomainJoined\s*:\s*YES") {
        $DomainJoined = $true
    }
    elseif ($DSReg -match "DomainJoined\s*:\s*NO") {
        $DomainJoined = $false
    }
}
catch {
    Add-Incidencia "AVISO" "Entra ID" `
        "No se ha podido consultar el estado de union."
}

#endregion

#region EVALUACION DE REQUISITOS

# TPM

if ($null -eq $TPM) {
    Add-Incidencia "AVISO" "TPM" `
        "No se ha podido determinar el estado del TPM."
}
elseif (-not $TPM.TpmPresent) {
    Add-Incidencia "ERROR" "TPM" `
        "TPM no presente. Impide el cifrado silencioso."
}
else {
    if (-not $TPM.TpmEnabled) {
        Add-Incidencia "ERROR" "TPM" `
            "El TPM no esta habilitado."
    }

    if (-not $TPM.TpmReady) {
        Add-Incidencia "ERROR" "TPM" `
            "El TPM no esta preparado."
    }

    if (-not $TPM.TpmActivated) {
        Add-Incidencia "ERROR" "TPM" `
            "El TPM no esta activado."
    }

    if ($TPM.LockedOut) {
        Add-Incidencia "ERROR" "TPM" `
            "El TPM se encuentra bloqueado."
    }

    if ($TPMVersion) {
        try {
            if ([version]$TPMVersion -lt [version]"1.2") {
                Add-Incidencia "ERROR" "TPM" `
                    "Version del TPM inferior a 1.2."
            }
        }
        catch {
            Add-Incidencia "AVISO" "TPM" `
                "No se ha podido interpretar la version."
        }
    }
}

# WinRE

if ($WinRE -eq "Deshabilitado") {
    Add-Incidencia "ERROR" "WinRE" `
        "WinRE deshabilitado. Revisar con reagentc /info."
}
elseif ($WinRE -ne "Habilitado") {
    Add-Incidencia "AVISO" "WinRE" `
        "No se ha podido verificar el estado de WinRE."
}

# Firmware

if ($Firmware -eq "Bios" -or $Firmware -eq "Legacy") {

    if ($TPMVersion -eq "2.0") {
        Add-Incidencia "ERROR" "Firmware" `
            "TPM 2.0 con BIOS Legacy. Se requiere UEFI."
    }
    else {
        Add-Incidencia "AVISO" "Firmware" `
            "Modo Legacy detectado. Se recomienda UEFI."
    }
}
elseif ($Firmware -ne "Uefi") {
    Add-Incidencia "AVISO" "Firmware" `
        "No se ha podido confirmar el modo UEFI."
}

# Secure Boot

if ($SecureBoot -ne $true) {
    Add-Incidencia "AVISO" "Secure Boot" `
        "Arranque seguro deshabilitado o no verificable."
}

# Entra ID

if ($EntraJoined -eq $false) {
    Add-Incidencia "ERROR" "Entra ID" `
        "Dispositivo no unido a Microsoft Entra ID."
}
elseif ($EntraJoined -ne $true) {
    Add-Incidencia "AVISO" "Entra ID" `
        "No se ha podido verificar la union a Entra ID."
}

# Politicas de cifrado silencioso

if ($RequireEncryption -ne 1) {
    Add-Incidencia "ERROR" "MDM" `
        "RequireDeviceEncryption debe estar establecido en 1."
}

if ($AllowStandardUser -ne 1) {
    Add-Incidencia "ERROR" "MDM" `
        "AllowStandardUserEncryption debe estar en 1 para usuarios estandar."
}

if ($AllowWarning -ne 0) {
    Add-Incidencia "ERROR" "MDM" `
        "AllowWarningForOtherDiskEncryption debe estar en 0 para cifrado silencioso."
}

# Autenticacion de prearranque requerida por politica

if (
    $FVE.UseTPMPIN -eq 1 -or
    $FVE.UseTPMKey -eq 1 -or
    $FVE.UseTPMKeyPIN -eq 1
) {
    Add-Incidencia "ERROR" "Politica FVE" `
        "La politica exige PIN o clave de inicio. Revisar compatibilidad con cifrado silencioso."
}

if ($FVE.UseTPM -eq 0) {
    Add-Incidencia "AVISO" "Politica FVE" `
        "La politica no permite el protector TPM sin autenticacion adicional."
}

# Estado del cifrado

if ($BitLocker) {

    switch ($BitLocker.VolumeStatus.ToString()) {

        "FullyDecrypted" {
            Add-Incidencia "ERROR" "BitLocker" `
                "El volumen del sistema esta completamente descifrado."
        }

        "EncryptionInProgress" {
            Add-Incidencia "INFO" "BitLocker" `
                "Cifrado en curso."
        }

        "EncryptionPaused" {
            Add-Incidencia "ERROR" "BitLocker" `
                "El proceso de cifrado esta pausado."
        }

        "DecryptionInProgress" {
            Add-Incidencia "AVISO" "BitLocker" `
                "Descifrado en curso."
        }

        "DecryptionPaused" {
            Add-Incidencia "AVISO" "BitLocker" `
                "Proceso de descifrado pausado."
        }
    }

    if (
        $BitLocker.VolumeStatus -eq "FullyEncrypted" -and
        $BitLocker.ProtectionStatus -ne "On"
    ) {
        Add-Incidencia "ERROR" "BitLocker" `
            "Unidad cifrada, pero proteccion desactivada o no verificable."
    }

    # Comparar algoritmo real con el configurado

    if (
        $null -ne $MetodoID -and
        $Metodos.ContainsKey([int]$MetodoID) -and
        $BitLocker.VolumeStatus -ne "FullyDecrypted"
    ) {

        if ($BitLocker.EncryptionMethod.ToString() -ne $MetodoPolitica) {

            Add-Incidencia "ERROR" "Metodo de cifrado" `
                "El algoritmo actual no coincide con la politica."
        }
    }

    # Comprobar protector de recuperacion

    if (
        $BitLocker.VolumeStatus -eq "FullyEncrypted" -and
        $Protectores -notcontains "RecoveryPassword"
    ) {
        Add-Incidencia "AVISO" "Recuperacion" `
            "No se detecta protector de contrasena de recuperacion."
    }
}

#endregion

#region INFORME

$Informe = [PSCustomObject][ordered]@{

    Equipo                 = $Equipo
    Usuario                = $Usuario
    SistemaOperativo       = $OS.Caption
    Build                  = $OS.BuildNumber

    EntraIDJoined          = $EntraJoined
    DomainJoined           = $DomainJoined

    Firmware               = $Firmware
    SecureBoot             = $SecureBoot
    WinRE                  = $WinRE

    TPMPresente            = $TPM.TpmPresent
    TPMVersion             = $TPMVersion
    TPMPreparado           = $TPM.TpmReady
    TPMHabilitado          = $TPM.TpmEnabled
    TPMActivado            = $TPM.TpmActivated
    TPMBloqueado           = $TPM.LockedOut

    Unidad                 = $Unidad
    EstadoCifrado          = $BitLocker.VolumeStatus
    PorcentajeCifrado      = $BitLocker.EncryptionPercentage
    EstadoProteccion       = $BitLocker.ProtectionStatus
    MetodoActual           = $BitLocker.EncryptionMethod
    MetodoPolitica         = $MetodoPolitica
    Protectores            = $Protectores -join ", "

    RequireDeviceEncryption          = $RequireEncryption
    AllowStandardUserEncryption      = $AllowStandardUser
    AllowWarningForOtherDiskEncryption = $AllowWarning
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "           DIAGNOSTICO BITLOCKER - INTUNE" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$Informe | Format-List | Out-String | Write-Host

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "            INCIDENCIAS Y RECOMENDACIONES" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

foreach ($Incidencia in $Incidencias) {

    $Color = switch ($Incidencia.Nivel) {
        "ERROR" { "Red" }
        "AVISO" { "Yellow" }
        "INFO"  { "Cyan" }
        default { "White" }
    }

    Write-Host `
        "[$($Incidencia.Nivel)] [$($Incidencia.Componente)] $($Incidencia.Mensaje)" `
        -ForegroundColor $Color
}

$Errores = @(
    $Incidencias | Where-Object { $_.Nivel -eq "ERROR" }
).Count

$Avisos = @(
    $Incidencias | Where-Object { $_.Nivel -eq "AVISO" }
).Count

Write-Host ""
Write-Host "================ RESUMEN ===========================" -ForegroundColor Cyan
Write-Host "Errores : $Errores" -ForegroundColor Red
Write-Host "Avisos  : $Avisos" -ForegroundColor Yellow

if ($Errores -gt 0) {
    Write-Host "RESULTADO: INCIDENCIAS DETECTADAS" -ForegroundColor Red
}
elseif ($Avisos -gt 0) {
    Write-Host "RESULTADO: REQUIERE REVISION" -ForegroundColor Yellow
}
else {
    Write-Host "RESULTADO: SIN INCIDENCIAS DETECTADAS" -ForegroundColor Green
}

#endregion
