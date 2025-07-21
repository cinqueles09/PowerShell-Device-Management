<#
.SYNOPSIS
    Sincroniza contactos recientes de la GAL (Global Address List) con los contactos personales de cada usuario en Microsoft 365.

.DESCRIPTION
    Este script realiza las siguientes acciones:
    - Autentica mediante OAuth2 usando credenciales de aplicación (Client Credentials Flow).
    - Obtiene un token de acceso para Microsoft Graph API.
    - Recupera todos los usuarios del tenant.
    - Conecta con Exchange Online para obtener los contactos de la GAL creados en los últimos 7 días.
    - Compara los contactos de la GAL con los contactos existentes de cada usuario.
    - Añade los contactos nuevos a la libreta personal de cada usuario si no existen previamente.

.REQUIREMENTS
    - PowerShell 5.1 o superior.
    - Módulo de Exchange Online Management instalado.
    - Permisos adecuados en Azure AD para acceder a Microsoft Graph y Exchange Online.
    - Valores válidos para $tenantId, $clientId y $clientSecret.

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 21/07/2025
    Versión: 1.0

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

# Obtener todos los usuarios del tenant
$usersUrl = "https://graph.microsoft.com/v1.0/users?$select=id,userPrincipalName&$top=999"
$usuarios = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
$usuarios = $usuarios.value

# Conectar a Exchange Online para obtener contactos de la GAL
#Connect-ExchangeOnline -AppId $clientId -CertificateThumbprint "" -Organization "TU_DOMINIO" -AccessToken $accessToken

# Obtener contactos de la GAL creados en los últimos 7 días
$fechaLimite = (Get-Date).AddDays(-7)
$contactosGAL = Get-Recipient -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Where-Object { $_.WhenCreated -gt $fechaLimite } |
    Select-Object DisplayName, PrimarySmtpAddress, Phone, MobilePhone

# Recorrer cada usuario y añadirle los contactos nuevos
foreach ($usuario in $usuarios) {
    $userId = $usuario.id
    Write-Host "Procesando usuario: $($usuario.userPrincipalName)"

    # Obtener contactos existentes del usuario
    $existingContactsUrl = "https://graph.microsoft.com/v1.0/users/$userId/contacts?$select=emailAddresses&$top=999"
    $existingContacts = Invoke-RestMethod -Uri $existingContactsUrl -Headers $headers -Method GET
    $existingEmails = $existingContacts.value.emailAddresses.address

    foreach ($contacto in $contactosGAL) {
        $correo = $contacto.PrimarySmtpAddress.ToLower()
        if ($existingEmails -notcontains $correo) {
            $nuevoContacto = @{
                givenName      = $contacto.DisplayName.Split(" ")[0]
                surname        = $contacto.DisplayName.Split(" ")[-1]
                emailAddresses = @(@{ address = $correo; name = $contacto.DisplayName })
                businessPhones = @($contacto.Phone)
                mobilePhone    = $contacto.MobilePhone
            }

            $contactJson = $nuevoContacto | ConvertTo-Json -Depth 3
            $contactUrl = "https://graph.microsoft.com/v1.0/users/$userId/contacts"

            try {
                Invoke-RestMethod -Uri $contactUrl -Headers $headers -Method POST -Body $contactJson
                Write-Host "Contacto nuevo: $($contacto.DisplayName) para $($usuario.userPrincipalName)"
            } catch {
                Write-Warning "Error para $($usuario.userPrincipalName): $_"
            }
        } else {
            Write-Host "Contacto ya existe: $correo para $($usuario.userPrincipalName)"
        }
    }
}
