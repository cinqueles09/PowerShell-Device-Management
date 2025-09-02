<#
.SYNOPSIS
    Sincroniza contactos en Microsoft 365 para usuarios con extensionAttribute8 = "1".

.DESCRIPTION
    Este script se conecta a Microsoft Graph API utilizando OAuth 2.0 (client credentials).
    Realiza las siguientes acciones:
      - Obtiene todos los usuarios de la organización.
      - Identifica usuarios "destino" cuyo atributo onPremisesExtensionAttributes.extensionAttribute8 = "1".
      - Construye la lista de "contactos" a partir de usuarios con licencia y teléfono definido.
      - Para cada usuario destino:
            * Crea nuevos contactos si no existen.
            * Actualiza contactos ya existentes.
            * Elimina contactos duplicados.

.AUTHOR
    Ismael Morilla Orellana

.VERSION
    1.0.0

.REQUIREMENTS
    - Permisos delegados o de aplicación en Azure AD:
        * User.Read.All
        * Contacts.ReadWrite
    - PowerShell 5.1+ o PowerShell Core 7+
    - No requiere módulos externos (usa Invoke-RestMethod / Invoke-WebRequest nativos)

.USAGE
    1. Editar las variables $clientId, $clientSecret y $tenantId con las credenciales de tu App Registration.
    2. Ejecutar en PowerShell:
        PS> .\Sync-M365UserContacts.ps1
    3. Revisar en consola la salida con acciones ejecutadas (creación, actualización, eliminación de contactos).

.NOTES
    Creación: 27/08/2025
    Última actualización: 2025-09-02
#>
# Variables de autenticación
$clientId     = "<CLIENT_ID>"
$clientSecret = "<CLIENT_SECRET>"
$tenantId     = "<TENANT_ID>"

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

# --- Obtener todos los usuarios (para construir listas destino y contactos) ---
$allUsers = @()
$usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,givenName,surname,userPrincipalName,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&`$top=999"

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $allUsers += $response.value
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)

# --- Separar listas ---
# 1. Usuarios destino → extensionAttribute8 = "1"
$usuariosDestino = $allUsers | Where-Object {
    $_.onPremisesExtensionAttributes.extensionAttribute8 -eq "1"
}

# 2. Lista de contactos → con licencia
$usuariosContacto = $allUsers | Where-Object {
    ($_.assignedLicenses.Count -gt 0) -and
    ( -not [string]::IsNullOrEmpty($_.businessPhones) -or -not [string]::IsNullOrEmpty($_.mobilePhone) )
}



Write-Host "Usuarios destino encontrados: $($usuariosDestino.displayname.Count)"
Write-Host "Usuarios contacto encontrados: $($usuariosContacto.Count)"

# --- Procesar cada usuario destino ---
foreach ($usuario in $usuariosDestino) {

    Write-Host "`nProcesando usuario destino: $($usuario.displayName) <$($usuario.userPrincipalName)>"

    # Obtener contactos existentes de este usuario
    $allContacts = @()
    $contactsUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts?`$top=999"

    do {
        $response = Invoke-RestMethod -Uri $contactsUrl -Headers $headers -Method GET
        $allContacts += $response.value
        $contactsUrl = $response.'@odata.nextLink'
    } while ($contactsUrl)

    # Crear diccionario de contactos existentes
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

    # Procesar lista de contactos
    foreach ($otroUsuario in $usuariosContacto) {
        # Evitar que un usuario se agregue a sí mismo
        if ($otroUsuario.userPrincipalName -eq $usuario.userPrincipalName) { continue }

        $correo = $otroUsuario.userPrincipalName.ToLower().Trim()

        $contactoData = @{
            givenName      = $otroUsuario.givenName
            surname        = $otroUsuario.surname
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
                $null =Invoke-WebRequest -Uri $updateUrl -Headers $headers -Method PATCH -Body $utf8Json -ContentType "application/json" -UseBasicParsing | Out-Null
                Write-Host "  - Contacto actualizado: $($otroUsuario.displayName)"
            } catch {
                Write-Warning "Error al actualizar contacto <$correo> en $($usuario.userPrincipalName) $_"
            }
        } else {
            # Crear nuevo contacto
            $createUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts"
            try {
                $null= Invoke-WebRequest -Uri $createUrl -Headers $headers -Method POST -Body $utf8Json -ContentType "application/json" -UseBasicParsing | Out-Null
                Write-Host "  + Contacto nuevo: $($otroUsuario.displayName)"
                $contactMap[$correo] = "nuevo"
            } catch {
                Write-Warning "Error al crear contacto <$correo> en $($usuario.userPrincipalName) $_"
            }
        }
    }

    # Eliminar duplicados
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
                $deleteUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($_.id)"
                try {
                    $null=Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE | Out-Null
                    Write-Host "  - Duplicado eliminado: $($_.displayName) <$correo>"
                } catch {
                    Write-Warning "Error al eliminar duplicado <$correo> en $($usuario.userPrincipalName) $_"
                }
            }
        }
    }
}
