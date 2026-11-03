<#
.SYNOPSIS
    Detectar la configuración de Windows Hello del sistema.

.DESCRIPTION
    Este script detecta Windows Hello para empresas, para posteriormente lanzar la remediación de eliminación

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 05/07/2025
    Version: 1.0
#>

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()

if ($identity.User.Value -eq "S-1-5-18") {
    Write-Output "ERROR: Ejecutado como SYSTEM."
    exit 1
}

$output = & "$env:SystemRoot\System32\dsregcmd.exe" /status

$match = $output |
    Select-String '^\s*NgcSet\s*:\s*(YES|NO)\s*$' |
    Select-Object -First 1

if (-not $match) {
    Write-Output "ERROR: No se pudo consultar NgcSet."
    exit 1
}

if ($match.Matches[0].Groups[1].Value -eq "YES") {
    Write-Output "DETECTED: PIN Windows Hello configurado."
    exit 1
}

Write-Output "COMPLIANT: Sin contenedor Windows Hello."
exit 0

Write-Output "COMPLIANT: Configuracion deshabilitada."
exit 0
