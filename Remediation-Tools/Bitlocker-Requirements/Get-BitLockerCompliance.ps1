<#
.SYNOPSIS
    Script de auditoría de cifrado BitLocker y cumplimiento de hardware.

.DESCRIPTION
    Este script verifica el estado de BitLocker en todas las unidades, validando 
    requisitos críticos como el estado del chip TPM, SecureBoot, modo de BIOS 
    y la partición de recuperación (WinRE). 
    Agrupa los motivos de error en una sola línea por unidad.

.PARAMETER ExitCode
    - Exit 0: Si la unidad está protegida.
    - Exit 1: Si la unidad no está protegida o falta hardware crítico.

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 10 Febrero 2025
    Versión: 1.2
#>

############### VARIABLES DE ENTORNO Y HARDWARE
$BIOS = if ($env:Firmware_Type) { $env:Firmware_Type } else { "Legacy/BIOS" }
$SecureBoot = try { Confirm-SecureBootUEFI } catch { $false }
$WinReInfo = reagentc /info
$WinReStatus = if ($WinReInfo -match "Enabled|Habilitado") { "Enabled" } else { "Disabled" }
$WinReGUID = $WinReInfo | Select-String "BCD" | ForEach-Object { ($_.ToString().Split(':')[1]).Trim() }

$TpmObj = Get-Tpm
$Presente = $TpmObj.TpmPresent
$Ready = $TpmObj.TpmReady
$Habilitado = $TpmObj.TpmEnabled
$Version = (Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftTpm" -ClassName Win32_Tpm).SpecVersion.Split(',')[0]

$Tmp = (Get-BitLockerVolume -MountPoint C).KeyProtector
if ($Tmp -match "TpmPin") { $PreAuth = "TpmPin" } 
elseif ($Tmp -match "Tpm") { $PreAuth = "Tpm" } 
else { $PreAuth = "No configurado" }

############### CONSTRUCCION DEL REPORTE
$Reporte = @"
--- RESUMEN TECNICO ---
TPM: $Presente | Version: $Version | Ready: $Ready | Habilitado: $Habilitado
WinRe: $WinReStatus | GUID: $WinReGUID
SecureBoot: $SecureBoot | BIOS: $BIOS | PreAuth: $PreAuth
-----------------------
"@

if ($Presente -ne $True) {
    $Reporte += "`n[!] CRITICO: El dispositivo no dispone de TPM fisico o esta oculto en BIOS."
    Write-Output $Reporte
    Exit 1
}

$volumes = Get-BitLockerVolume
if (!$volumes) {
    $Reporte += "`n[!] No se encontraron unidades compatibles con BitLocker."
    Write-Output $Reporte
    Exit 1
}

foreach ($volume in $volumes) {
    $lineaUnidad = "`nUnidad [$($volume.MountPoint)]:"
    
    if ($volume.ProtectionStatus -eq "On") {
        $lineaUnidad += " PROTEGIDA correctamente."
    } else {
        # Recolectar motivos en una lista para unirlos luego
        $motivos = @()
        if ($Habilitado -ne $true) { $motivos += "TPM no habilitado" }
        if ($Ready -ne $true) { $motivos += "TPM no preparado" }
        if ($Version -and [decimal]$Version -lt 1.2) { $motivos += "TPM obsoleto ($Version)" }
        if ($SecureBoot -ne $true) { $motivos += "SecureBoot desactivado" }
        if ($BIOS -ne "UEFI") { $motivos += "Modo BIOS no compatible ($BIOS)" }
        if ($WinReStatus -eq "Disabled") { $motivos += "WinRE desactivado" }

        $lineaUnidad += " NO PROTEGIDA. Motivos: " + ($motivos -join ", ")
    }
    $Reporte += $lineaUnidad
}

# --- PRIMERO: Imprimimos todo el reporte con los motivos agrupados ---
Write-Output $Reporte

# --- SEGUNDO: Decidimos el código de salida basado en C: ---
$driveC = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue

if ($driveC -and $driveC.ProtectionStatus -eq "On") {
    # Si C: está bien, salimos con 0 (Éxito)
    Exit 0
} else {
    # Si C: no está protegida, salimos con 1 (Error)
    Exit 1
}
