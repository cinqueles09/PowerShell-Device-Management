<#
.SYNOPSIS
    Verifica si el usuario local Admin existe, lo crea o actualiza, y configura las políticas de contraseña.

.DESCRIPTION
    Este script realiza una comprobación del usuario local 'Admin'.
    Si no existe, lo crea y lo agrega al grupo de administradores locales.
    Si ya existe, actualiza su contraseña.
    En ambos casos, configura que la contraseña no expire nunca
    y desactiva la opción de cambiar la contraseña en el próximo inicio de sesión.
    Además, detecta correctamente el grupo de administradores independientemente del idioma del sistema,
    utilizando el SID estándar (S-1-5-32-544).

.PARAMETER UserName
    Nombre del usuario local que se desea verificar o crear. Por defecto es 'Admin'.

.PARAMETER PasswordPlain
    Contraseña que se desea establecer al usuario.

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 05/07/2025
    Versión: 1.0
    Requiere: PowerShell 5.1 o superior, permisos de administrador
#>


# =====================
# CONFIGURACIÓN
# =====================
$UserName = "Admin"
$PasswordPlain = "PasswordNew"  # ← CAMBIA ESTA CONTRASEÑA POR UNA SEGURA
$SecurePassword = ConvertTo-SecureString $PasswordPlain -AsPlainText -Force

# =====================
# LÓGICA DEL SCRIPT
# =====================
# Verificar si el usuario ya existe
$User = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

if ($User -eq $null) {
    Write-Host "El usuario '$UserName' no existe. Creando..."
    New-LocalUser -Name $UserName -Password $SecurePassword -FullName "Store Admin" -Description "Cuenta de administrador local"

    # Obtener el grupo de administradores por SID (funciona en cualquier idioma)
    $adminGroup = Get-LocalGroup | Where-Object { $_.SID -eq "S-1-5-32-544" }
    Add-LocalGroupMember -Group $adminGroup.Name -Member $UserName
} else {
    Write-Host "El usuario '$UserName' ya existe. Cambiando contraseña..."
    Set-LocalUser -Name $UserName -Password $SecurePassword
}

# Configurar políticas de contraseña
Write-Host "Configurando políticas de contraseña..."
wmic useraccount where "name='$UserName'" set PasswordExpires=FALSE

# Eliminar requerimiento de cambiar contraseña al iniciar sesión
Write-Host "Eliminando requerimiento de cambio de contraseña al iniciar sesión..."
try {
    net user $UserName /logonpasswordchg:no | Out-Null
} catch {
    Write-Warning "No se pudo establecer el cambio de contraseña al inicio de sesión."
}

Write-Host "Proceso completado para el usuario '$UserName'."
