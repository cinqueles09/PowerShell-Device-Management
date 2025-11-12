# Variables de autenticacion
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

# === Obtener todos los usuarios de Azure AD ===
$allUsers = @()
$usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,givenName,surname,userPrincipalName,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&`$top=999"

Write-Host "Obteniendo lista de usuarios de Azure AD..."

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $allUsers += $response.value
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)

Write-Host "Total de usuarios obtenidos: $($allUsers.Count)"

# === Filtrar listas ===
$usuariosDestino = $allUsers | Where-Object {
    $_.onPremisesExtensionAttributes.extensionAttribute8 -eq "1"
}

$usuariosContacto = $allUsers | Where-Object {
    ($_.assignedLicenses.Count -gt 0) -and
    ( -not [string]::IsNullOrEmpty($_.businessPhones) -or -not [string]::IsNullOrEmpty($_.mobilePhone) ) -and
    $_.userPrincipalName.ToLower().EndsWith("@mc-mutual.com")
}

Write-Host "Usuarios destino encontrados: $($usuariosDestino.Count)"
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

    # --- Construir lista de contactos validos ---
    $contactosValidos = $usuariosContacto.userPrincipalName | ForEach-Object { $_.ToLower().Trim() }

    # --- Eliminar contactos que ya no estan en Azure AD ---
    foreach ($correoExistente in $contactMap.Keys) {
        $correoExistenteNorm = $correoExistente.ToLower().Trim()

        # Solo contactos del dominio @mc-mutual.com
        if ($correoExistenteNorm -like "*@mc-mutual.com") {

            # Si el correo ya no esta en la lista de contactos validos → eliminar
            if ($contactosValidos -notcontains $correoExistenteNorm) {

                $deleteUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($contactMap[$correoExistente])"

                Write-Host "  - Eliminando contacto: <$correoExistenteNorm> ..."

                try {
                    #Eliminar contacto (descomenta si quieres eliminar realmente)
                    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE | Out-Null
                    Write-Host "Contacto eliminado correctamente."
                }
                catch {
                    Write-Warning "Error al eliminar contacto <$correoExistenteNorm> en $($usuario.userPrincipalName): $_"
                }
            }
        }
    }
}

Write-Host "`nProceso completado"

