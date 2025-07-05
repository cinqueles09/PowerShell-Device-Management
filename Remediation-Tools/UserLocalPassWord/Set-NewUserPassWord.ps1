<#
.SYNOPSIS
    Verifica si el usuario local Admin existe, lo crea o actualiza, y configura las politicas de contraseña.

.DESCRIPTION
    Este script realiza una comprobacion del usuario local 'Admin'.
    Si no existe, lo crea y lo agrega al grupo de administradores locales.
    Si ya existe, actualiza su contraseña.
    En ambos casos, configura que la contraseña no expire nunca
    y desactiva la opcion de cambiar la contraseña en el proximo inicio de sesion.
    Ademas, detecta correctamente el grupo de administradores independientemente del idioma del sistema,
    utilizando el SID estandar (S-1-5-32-544).

.PARAMETER UserName
    Nombre del usuario local que se desea verificar o crear. Por defecto es 'Admin'.

.PARAMETER PasswordPlain
    Contraseña que se desea establecer al usuario.

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 05/07/2025
    Version: 1.0
    Requiere: PowerShell 5.1 o superior, permisos de administrador
#>

# =====================
# CONFIGURACION
# =====================
$UserName = "Admin"
$PasswordPlain = "PasswordNew"  # ← CAMBIA ESTA PASSWORD POR UNA SEGURA
$SecurePassword = ConvertTo-SecureString $PasswordPlain -AsPlainText -Force

# =====================
# LOGICA DEL SCRIPT
# =====================
# Verificar si el usuario ya existe
$User = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

if ($User -eq $null) {
    Write-Host "El usuario '$UserName' no existe. Creando..."
    New-LocalUser -Name $UserName -Password $SecurePassword -FullName "Admin" -Description "Cuenta de administrador local"

    # Obtener el grupo de administradores por SID (funciona en cualquier idioma)
    $adminGroup = Get-LocalGroup | Where-Object { $_.SID -eq "S-1-5-32-544" }
    Add-LocalGroupMember -Group $adminGroup.Name -Member $UserName
} else {
    Write-Host "El usuario '$UserName' ya existe. Cambiando password..."
    Set-LocalUser -Name $UserName -Password $SecurePassword
}

# Configurar politicas de password
Write-Host "Configurando politicas de password..."
wmic useraccount where "name='$UserName'" set PasswordExpires=FALSE

# Eliminar requerimiento de cambiar password al iniciar sesion
Write-Host "Eliminando requerimiento de cambio de password al iniciar sesion..."
try {
    net user $UserName /logonpasswordchg:no | Out-Null
} catch {
    Write-Warning "No se pudo establecer el cambio de password al inicio de sesion."
}

Write-Host "Proceso completado para el usuario '$UserName'."
