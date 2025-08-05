<#
.SYNOPSIS
    Sincroniza automáticamente los contactos entre usuarios con licencia en Microsoft 365.

.DESCRIPTION
    Este script utiliza Microsoft Graph API para:
    - Autenticarse mediante client credentials.
    - Obtener todos los usuarios de tipo "Member" con licencias asignadas.
    - Leer los contactos existentes de cada usuario.
    - Añadir como contactos a los demás usuarios con licencia, si aún no existen en su libreta.

.NOTES
    Autor: Ismael Morilla
    Fecha: 21/07/2025
    Version: 2.0
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

# Nueva paginación para obtener todos los usuarios del tenant sin limitación
$usuarios = @()
$usersUrl = 'https://graph.microsoft.com/v1.0/users?$filter=userType eq ''Member''&$select=id,displayName,givenName,surname,userPrincipalName,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&$top=999'

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $usuarios += $response.value | Where-Object {
        $_.assignedLicenses.Count -gt 0 -and
        $_.userPrincipalName -ne $targetUserUPN
    } | sort
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)


function Get-AllUserContacts {
    param (
        [string]$userId,
        [hashtable]$headers
    )

    $allContacts = @()
    $contactsUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts?\$top=999"

    do {
        $response = Invoke-RestMethod -Uri $contactsUrl -Headers $headers -Method GET
        $allContacts += $response.value
        $contactsUrl = $response.'@odata.nextLink'
    } while ($contactsUrl)

    return @{ value = $allContacts }
}


foreach ($usuario in $usuarios) {
    $userId = $usuario.id
    $userUPN = $usuario.userPrincipalName
    Write-Host "`nProcesando libreta de: $userUPN"

    # Obtener contactos existentes
    $allContacts = (Get-AllUserContacts -userId $userId -headers $headers).value

    # Crear diccionario de contactos existentes por email
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

    # Procesar usuarios
    foreach ($otroUsuario in $usuarios) {
        $correo = $otroUsuario.userPrincipalName.ToLower().Trim()
        if ($correo -ne $userUPN) {
            $contactoData = @{
                givenName      = if ($otroUsuario.givenName) { $otroUsuario.givenName } else { $otroUsuario.displayName.Split(" ")[0] }
                surname        = if ($otroUsuario.surname)   { $otroUsuario.surname }   else { $otroUsuario.displayName.Split(" ")[-1] }
                displayName    = $otroUsuario.displayName
                emailAddresses = @(@{ address = $correo; name = $otroUsuario.displayName })
                businessPhones = $otroUsuario.businessPhones
                mobilePhone    = $otroUsuario.mobilePhone
            }

            $contactJson = $contactoData | ConvertTo-Json -Depth 3
            $utf8Json = [System.Text.Encoding]::UTF8.GetBytes($contactJson)

            if ($contactMap.ContainsKey($correo)) {
                # Actualizar contacto existente
                $contactId = $contactMap[$correo]
                $updateUrl = "https://graph.microsoft.com/v1.0/users/$userId/contacts/$contactId"
                try {
                    $null = Invoke-WebRequest -Uri $updateUrl -Headers $headers -Method PATCH -Body $utf8Json -ContentType "application/json" -UseBasicParsing
                    Write-Host "Contacto actualizado: $($otroUsuario.displayName) > $userUPN"
                } catch {
                    Write-Warning "Error al actualizar contacto en $userUPN $_"
                }
            } else {
                # Crear nuevo contacto
                $createUrl = "https://graph.microsoft.com/v1.0/users/$userId/contacts"
                try {
                    $null = Invoke-WebRequest -Uri $createUrl -Headers $headers -Method POST -Body $utf8Json -ContentType "application/json" -UseBasicParsing
                    Write-Host "Contacto nuevo: $($otroUsuario.displayName) > $userUPN"
                    $contactMap[$correo] = "nuevo"
                } catch {
                    Write-Warning "Error al crear contacto en $userUPN $_"
                }
            }
        }
    }

    # Eliminar contactos duplicados por correo
    $contactosPorCorreo = @{}
    foreach ($contact in $allContacts) {
        foreach ($email in $contact.emailAddresses) {
            $correo = $email.address.ToLower().Trim()
            if ($correo) {
                if (-not $contactosPorCorreo.ContainsKey($correo)) {
                    $contactosPorCorreo[$correo] = @($contact)
                } else {
                    $contactosPorCorreo[$correo] += $contact
                }
            }
        }
    }

    foreach ($correo in $contactosPorCorreo.Keys) {
        $duplicados = $contactosPorCorreo[$correo]
        if ($duplicados.Count -gt 1) {
            $duplicados[1..($duplicados.Count - 1)] | ForEach-Object {
                $deleteUrl = "https://graph.microsoft.com/v1.0/users/$userId/contacts/$($_.id)"
                try {
                    $null = Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
                    Write-Host "Duplicado eliminado: $($_.displayName) <$correo>"
                } catch {
                    Write-Warning "Error al eliminar duplicado <$correo>: $_"
                }
            }
        }
    }
}
