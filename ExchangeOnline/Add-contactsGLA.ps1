<#
.SYNOPSIS
    Sincroniza automáticamente los contactos entre usuarios con licencia en Microsoft 365.

.DESCRIPTION
    Este script utiliza Microsoft Graph API para:
    - Autenticarse mediante client credentials.
    - Obtener todos los usuarios de tipo "Member" con licencias asignadas.
    - Leer los contactos existentes de cada usuario.
    - Añadir como contactos a los demás usuarios con licencia, si aún no existen en su libreta.

.NOTAS
    Autor: Ismael Morilla
    Fecha: 21/07/2025
    Version: 1.2
    Requisitos:
        - Aplicación registrada en Azure AD con permisos de aplicación para `Contacts.ReadWrite` y `User.Read.All`.
        - PowerShell 5.1+ o PowerShell Core.
        - Módulo `Microsoft.Graph` no requerido, se usa `Invoke-RestMethod`.

.PARAMETER tenantId
    ID del inquilino de Azure AD.

.PARAMETER clientId
    ID de la aplicación registrada en Azure AD.

.PARAMETER clientSecret
    Secreto de cliente generado para la aplicación.

.LIMITACIONES
    - El script no maneja paginación de usuarios si hay más de 999.
    - No se eliminan contactos obsoletos, solo se añaden nuevos.

#>


# Variables de autenticación
$tenantId = ""
$clientId = ""
$clientSecret = ""

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

# Obtener todos los usuarios con licencia
$usersUrl = 'https://graph.microsoft.com/v1.0/users?$filter=userType eq ''Member''&$select=id,displayName,userPrincipalName,assignedLicenses,mobilePhone,businessPhones&$top=999'
$usuarios = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
$usuarios = $usuarios.value | Where-Object { $_.assignedLicenses.Count -gt 0 }

function Get-AllUserContacts {
    param (
        [string]$userId,
        [hashtable]$headers
    )

    $allContacts = @()
    $url = "https://graph.microsoft.com/v1.0/users/$userId/contacts?\$top=999"

    do {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method GET
        $allContacts += $response.value
        $url = $response.'@odata.nextLink'
    } while ($url)

    return @{ value = $allContacts }
}


foreach ($usuario in $usuarios) {
    $userId = $usuario.id
    $userUPN = $usuario.userPrincipalName
    Write-Host "`nProcesando libreta de: $userUPN"

    # Obtener contactos existentes
    #$existingContactsUrl = "https://graph.microsoft.com/v1.0/users/$userId/contacts?\$select=emailAddresses&\$top=999"
    #$existingContacts = Invoke-RestMethod -Uri $existingContactsUrl -Headers $headers -Method GET

    $existingContacts = Get-AllUserContacts -userId $userId -headers $headers

    # Extraer correos existentes
    $existingEmails = @()
    foreach ($contact in $existingContacts.value) {
        foreach ($email in $contact.emailAddresses) {
            if ($email.address) {
                $existingEmails += $email.address.ToLower().Trim()
            }
        }
    }

    # Añadir contactos si no existen
    foreach ($otroUsuario in $usuarios) {
        if ($otroUsuario.userPrincipalName -ne $userUPN) {
            $correo = $otroUsuario.userPrincipalName.ToLower().Trim()
            if (-not ($existingEmails -contains $correo)) {
                $nuevoContacto = @{
                    givenName      = $otroUsuario.displayName.Split(" ")[0]
                    surname        = $otroUsuario.displayName.Split(" ")[-1]
                    emailAddresses = @(@{ address = $correo; name = $otroUsuario.displayName })
                    businessPhones = $otroUsuario.businessPhones
                    mobilePhone    = $otroUsuario.mobilePhone
                }

                $contactJson = $nuevoContacto | ConvertTo-Json -Depth 3
                $contactUrl = "https://graph.microsoft.com/v1.0/users/$userId/contacts"

                try {
                    $null= Invoke-RestMethod -Uri $contactUrl -Headers $headers -Method POST -Body $contactJson
                    Write-Host "Contacto nuevo: $($otroUsuario.displayName) → $userUPN"
                } catch {
                    Write-Warning "Error al crear contacto en $userUPN $_"
                }
            } else {
                Write-Host "Ya existe contacto: $correo en $userUPN"
            }
        }
    }
}
