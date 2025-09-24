<#
.SYNOPSIS
Script para limpieza automatizada de contactos en Azure AD mediante Microsoft Graph API.

.DESCRIPCIÓN
Este script realiza una sincronización de contactos en Azure AD para todos los usuarios que tengan el atributo `extensionAttribute8` igual a "1".
Obtiene un token de acceso mediante autenticación con credenciales de cliente, recupera todos los usuarios de Azure AD, filtra aquellos con licencias activas y números de teléfono válidos, y elimina los contactos obsoletos del usuario destino.

.REQUISITOS
- Registro de aplicación en Azure AD con permisos adecuados para acceder a Microsoft Graph.
- Valores válidos para `$tenantId`, `$clientId` y `$clientSecret`.
- PowerShell 5.1 o superior.

.PARAMETERS
- $tenantId: ID del tenant de Azure AD.
- $clientId: ID de la aplicación registrada.
- $clientSecret: Secreto de la aplicación.

.NOTAS
- El script elimina contactos que ya no están presentes en Azure AD, manteniendo actualizada la libreta de direcciones del usuario.
- Se procesan todos los usuarios que tengan `extensionAttribute8 = "1"` como destino de sincronización.
- Asegúrate de tener permisos de escritura sobre los contactos del usuario en Graph API.

.AUTHOR
Ismael Morilla Orellana
24/09/2025

.VERSION
1.0
#>


# Variables de autenticación
$tenantId = ""
$clientId = ""
$clientSecret = ""

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

# === Obtener todos los usuarios ===
$allUsers = @()
$usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,givenName,surname,userPrincipalName,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&`$top=999"

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $allUsers += $response.value
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)

# === Separar listas ===
$usuariosDestino = $allUsers | Where-Object {
    $_.onPremisesExtensionAttributes.extensionAttribute8 -eq "1"
}

$usuariosContacto = $allUsers | Where-Object {
    ($_.assignedLicenses.Count -gt 0) -and
    ( -not [string]::IsNullOrEmpty($_.businessPhones) -or -not [string]::IsNullOrEmpty($_.mobilePhone) )
}

Write-Host "Usuarios destino encontrados: $($usuariosDestino.displayname.Count)"
Write-Host "Usuarios contacto encontrados: $($usuariosContacto.Count)"

# === Procesar cada usuario destino ===
foreach ($usuario in $usuariosDestino) {
    Write-Host "`nProcesando usuario destino: $($usuario.displayName) <$($usuario.userPrincipalName)>"

    # --- Obtener contactos existentes ---
    $allContacts = @()
    $contactsUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts?`$top=999"

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
            $deleteUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($contactMap[$correoExistente])"
            try {
                $null = Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE | Out-Null
                Write-Host "  - Contacto eliminado (ya no existe en AAD): <$correoExistente>"
            } catch {
                Write-Warning "Error al eliminar contacto <$correoExistente> en $($usuario.userPrincipalName) $_"
            }
        }
    }

}
