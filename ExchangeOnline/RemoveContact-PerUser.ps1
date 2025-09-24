<#
.SYNOPSIS
Elimina los contactos que ya no están presentes en Azure AD para mantener la lista actualizada.

.DESCRIPCIÓN
Este script obtiene un token de acceso mediante autenticación con credenciales de cliente (client credentials),
recupera todos los usuarios de Azure AD, filtra aquellos con licencias activas y números de teléfono válidos,
y sincroniza los contactos del usuario objetivo (UPN) en Microsoft Graph. Elimina los contactos que ya no están presentes
en Azure AD para mantener la lista actualizada.

.REQUISITOS
- Permisos adecuados en Azure AD y Microsoft Graph API.
- Registro de aplicación con clientId, clientSecret y tenantId.
- PowerShell 5.1 o superior.

.PARAMETERS
- $tenantId: ID del tenant de Azure AD.
- $clientId: ID de la aplicación registrada en Azure AD.
- $clientSecret: Secreto de la aplicación.
- $usuarioObjetivoUPN: UPN del usuario cuyos contactos se van a sincronizar.

.NOTAS
- La eliminación de contactos está comentada por defecto. Descomentar la línea correspondiente para activar la eliminación real.
- Este script no crea nuevos contactos, solo elimina los que ya no están en Azure AD.

.AUTHOR
Ismael Morilla Orellana
24/09/2025

.Version
1.0

#>

# Variables de autenticación
$tenantId = ""
$clientId = ""
$clientSecret = ""

# === Definir usuario destino concreto (UPN) ===
$usuarioObjetivoUPN = "sgutierreza@mc-mutual.com"

# === Obtener token de acceso ===
$body = @{
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $clientId
    client_secret = $clientSecret
}
$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method POST -Body $body
$accessToken = $tokenResponse.access_token

# === Encabezados para Graph API ===
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

# === Obtener todos los usuarios de Azure AD ===
$allUsers = @()
$usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,givenName,surname,userPrincipalName,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&`$top=999"

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $allUsers += $response.value
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)

# === Filtrar el usuario destino concreto ===
$usuarioDestino = $allUsers | Where-Object {
    $_.userPrincipalName -eq $usuarioObjetivoUPN
}

if (-not $usuarioDestino) {
    Write-Host "Usuario $usuarioObjetivoUPN no encontrado en Azure AD."
    exit
}

# === Lista de contactos válidos (usuarios con licencia y teléfono/móvil) ===
$usuariosContacto = $allUsers | Where-Object {
    ($_.assignedLicenses.Count -gt 0) -and
    ( -not [string]::IsNullOrEmpty($_.businessPhones) -or -not [string]::IsNullOrEmpty($_.mobilePhone) )
}

Write-Host "`nProcesando usuario destino: $($usuarioDestino.displayName) <$($usuarioDestino.userPrincipalName)>"
Write-Host "Usuarios contacto encontrados: $($usuariosContacto.Count)"

# --- Obtener contactos existentes del usuario destino ---
$allContacts = @()
$contactsUrl = "https://graph.microsoft.com/v1.0/users/$($usuarioDestino.id)/contacts?`$top=999"

do {
    $response = Invoke-RestMethod -Uri $contactsUrl -Headers $headers -Method GET
    $allContacts += $response.value
    $contactsUrl = $response.'@odata.nextLink'
} while ($contactsUrl)

# Diccionario de contactos existentes (correo → ID)
$contactMap = @{}
foreach ($contact in $allContacts) {
    foreach ($email in $contact.emailAddresses) {
        if ($email.address) {
            $correoKey = $email.address.ToLower().Trim()
            if (-not $contactMap.ContainsKey($correoKey)) {
                $contactMap[$correoKey] = $contact.id
            }
        }
    }
}

# --- Eliminar contactos que ya no están en Azure AD ---
$contactosValidos = $usuariosContacto.userPrincipalName | ForEach-Object { $_.ToLower().Trim() }
foreach ($correoExistente in $contactMap.Keys) {
    if ($contactosValidos -notcontains $correoExistente) {
        $deleteUrl = "https://graph.microsoft.com/v1.0/users/$($usuarioDestino.id)/contacts/$($contactMap[$correoExistente])"
        try {
            # Descomenta la siguiente línea para que realmente elimine
            Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE | Out-Null
            Write-Host "  - Contacto eliminado (ya no existe en AAD): <$correoExistente>"
        } catch {
            Write-Warning "Error al eliminar contacto <$correoExistente> en $($usuarioDestino.userPrincipalName) $_"
        }
    }
}

Write-Host "`nLimpieza de contactos completada para $($usuarioDestino.userPrincipalName)."
