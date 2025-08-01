<#
.SYNOPSIS
    Sincroniza usuarios con licencia de Microsoft Entra ID (Azure AD) y con extensionAttribute15 con valor 1 como contactos en la cuenta de Outlook de un usuario específico.

.DESCRIPTION
    Este script utiliza Microsoft Graph API para:
    - Autenticarse mediante credenciales de aplicación (client credentials flow).
    - Obtener todos los usuarios con licencia y un atributo personalizado específico.
    - Crear o actualizar contactos en la cuenta de Outlook de un usuario objetivo.
    - Eliminar contactos duplicados y aquellos que ya no están en la lista de usuarios válidos.

    Se asegura de mantener la codificación UTF-8 para preservar caracteres especiales como la "ñ".

.AUTHOR
    Ismael Morilla

.VERSION
    2.0

.REQUIREMENTS
    - Permisos de aplicación en Microsoft Graph API: Contacts.ReadWrite, User.Read.All
    - Registro de aplicación en Azure AD con client_id, client_secret y tenant_id
    - PowerShell 5.1 o superior

.NOTES
    - Asegúrate de que el atributo personalizado `extensionAttribute15` esté configurado correctamente en los usuarios.
    - El script evita duplicados comparando direcciones de correo electrónico.
    - Se recomienda ejecutar este script de forma periódica para mantener los contactos sincronizados.

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
$targetUserUPN = "jmotero@mtorres.com"

# Obtener información del usuario específico
$userUrl = "https://graph.microsoft.com/v1.0/users/$targetUserUPN"
$usuario = Invoke-RestMethod -Uri $userUrl -Headers $headers -Method GET

# Obtener todos los usuarios con licencia (para comparar y añadir como contactos)
$usuarios = @()
$usersUrl = 'https://graph.microsoft.com/v1.0/users?$filter=userType eq ''Member''&$select=id,displayName,userPrincipalName,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&$top=999'

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $usuarios += $response.value | Where-Object {
        $_.assignedLicenses.Count -gt 0 -and
        $_.onPremisesExtensionAttributes.extensionAttribute15 -eq 1 -and
        $_.userPrincipalName -ne $targetUserUPN
    }
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)

# Obtener todos los contactos existentes del usuario objetivo
$allContacts = @()
$contactsUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts?\$top=999"

do {
    $response = Invoke-RestMethod -Uri $contactsUrl -Headers $headers -Method GET
    $allContacts += $response.value
    $contactsUrl = $response.'@odata.nextLink'
} while ($contactsUrl)

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

    # Dividir nombre y apellidos
    $nombrePartes = $otroUsuario.displayName.Split(" ")
    $givenName = $nombrePartes[0]
    $surname = ($nombrePartes[1..($nombrePartes.Length - 1)] -join " ")

    $contactoData = @{
        givenName      = $givenName
        surname        = $surname
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
        $updateUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$contactId"
        try {
            $null = Invoke-WebRequest -Uri $updateUrl -Headers $headers -Method PATCH -Body $utf8Json -ContentType "application/json" -UseBasicParsing
            Write-Host "Contacto actualizado: $($otroUsuario.displayName) > $targetUserUPN"
        } catch {
            Write-Warning "Error al actualizar contacto en $targetUserUPN $_"
        }
    } else {
        # Crear nuevo contacto
        $createUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts"
        try {
            $null = Invoke-WebRequest -Uri $createUrl -Headers $headers -Method POST -Body $utf8Json -ContentType "application/json" -UseBasicParsing
            Write-Host "Contacto nuevo: $($otroUsuario.displayName) > $targetUserUPN"
            # Añadir al mapa para evitar duplicados en la misma ejecución
            $contactMap[$correo] = "nuevo"
        } catch {
            Write-Warning "Error al crear contacto en $targetUserUPN $_"
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
        # Conservar el primero, eliminar el resto
        $duplicados[1..($duplicados.Count - 1)] | ForEach-Object {
            $deleteUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($_.id)"
            try {
                $null= Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
                Write-Host "Duplicado eliminado: $($_.displayName) <$correo>"
            } catch {
                Write-Warning "Error al eliminar duplicado <$correo>: $_"
            }
        }
    }
}
