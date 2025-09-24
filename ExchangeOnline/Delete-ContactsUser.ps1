<#
.SYNOPSIS
    Elimina todos los contactos de la libreta de direcciones de un usuario en Microsoft 365 mediante Microsoft Graph API.

.DESCRIPTION
    Este script se conecta a Microsoft Graph utilizando autenticación basada en credenciales de aplicación (client credentials flow)
    y elimina todos los contactos del buzón de un usuario específico, incluyendo aquellos almacenados en carpetas personalizadas.

.REQUIREMENTS
    - Permisos de aplicación en Microsoft Graph API: Contacts.ReadWrite, User.Read.All
    - Registro de aplicación en Azure AD con client_id, client_secret y tenant_id
    - PowerShell 5.1 o superior

.NOTES

    Autor: Ismael Morilla
    Fecha: 01/08/2025
    Version: 1.0
    - Este script elimina permanentemente los contactos del usuario especificado.
    - Se recomienda realizar una copia de seguridad antes de ejecutar este proceso.
#>


# Variables de autenticación
$tenantId = ""
$clientId = ""
$clientSecret = ""


[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Obtener token de acceso
$body = @{
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $clientId
    client_secret = $clientSecret
}
$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method POST -Body $body
$accessToken = $tokenResponse.access_token

# Encabezados para Graph API
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

# Definir el UPN del usuario objetivo
$targetUserUPN = ""

# Obtener información del usuario específico
$userUrl = "https://graph.microsoft.com/v1.0/users/$targetUserUPN"
$usuario = Invoke-RestMethod -Uri $userUrl -Headers $headers -Method GET

# Obtener todos los contactos del usuario
$allContacts = @()
$contactsUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts?\$top=999"

do {
    $response = Invoke-RestMethod -Uri $contactsUrl -Headers $headers -Method GET
    $allContacts += $response.value
    $contactsUrl = $response.'@odata.nextLink'
} while ($contactsUrl)

# Eliminar todos los contactos
foreach ($contact in $allContacts) {
    $deleteUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($contact.id)"
    try {
        Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
        Write-Host "Eliminado: $($contact.displayName)"
    } catch {
        Write-Warning "Error al eliminar $($contact.displayName): $_"
    }
}
