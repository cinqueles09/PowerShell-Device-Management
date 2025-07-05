<#
.SYNOPSIS
    Elimina toda la configuración de Windows Hello del sistema.

.DESCRIPTION
    Este script desactiva Windows Hello para empresas, elimina datos biométricos,
    detiene servicios relacionados y borra claves de registro asociadas.

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 05/07/2025
    Version: 1.0
#>

# Deshabilitar Windows Hello para empresas
$passportKey = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
if (!(Test-Path $passportKey)) {
    New-Item -Path $passportKey -Force | Out-Null
}
Set-ItemProperty -Path $passportKey -Name "Enabled" -Value 0

# Eliminar datos biométricos
$biometricPath = "$env:ProgramData\Microsoft\Biometrics"
Remove-Item -Path $biometricPath -Recurse -Force -ErrorAction SilentlyContinue

# Detener y deshabilitar servicio biométrico
Stop-Service -Name "WbioSrvc" -Force -ErrorAction SilentlyContinue
Set-Service -Name "WbioSrvc" -StartupType Disabled

# Eliminar claves de PIN del registro
$pinKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{D6886603-9D2F-4EB2-B667-1971041FA96B}"
Remove-Item -Path $pinKey -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Configuración de Windows Hello eliminada. Reinicia el equipo para aplicar los cambios."
