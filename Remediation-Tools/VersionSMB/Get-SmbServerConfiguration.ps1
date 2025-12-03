<#
.SYNOPSIS
    Script de detección de versiones SMB para Intune.

.DESCRIPTION
    Este script verifica si SMB1 está habilitado y si SMB2/3 está activo.
    Muestra el estado en una sola línea y devuelve un código de salida:
        exit 0 → Cumple (SMB1 deshabilitado)
        exit 1 → No cumple (SMB1 habilitado)
    Ideal para usar como Detection Script en Microsoft Intune.

.AUTHOR
    Ismael Morilla Orellana

.CREATED
    03/12/2025

.LASTMODIFIED
    03/12/2025

.NOTES
    - Compatible con Windows 10 y 11.
    - Requiere privilegios de administrador para ejecutar Get-SmbServerConfiguration.
    - Todo el estado se muestra en una sola línea.
#>

# Script de detección SMB para Intune (todo en una línea de mensaje)
$smbConfig = Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol

$message = "SMB1: $($smbConfig.EnableSMB1Protocol); SMB2/3: $($smbConfig.EnableSMB2Protocol); "

if ($smbConfig.EnableSMB1Protocol -eq $true) {
    $message += "Resultado: NO cumple"
    Write-Host $message
    exit 1
} else {
    $message += "Resultado: Cumple"
    Write-Host $message
    exit 0
}
