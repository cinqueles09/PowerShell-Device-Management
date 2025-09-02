<#
.SYNOPSIS
    Script en PowerShell para contar los contactos de usuarios en Microsoft 365
    cuyo atributo personalizado onPremisesExtensionAttributes.extensionAttribute8 = "1".

.DESCRIPTION
    Este script se conecta a Microsoft Graph API utilizando OAuth 2.0 (client credentials),
    obtiene todos los usuarios, filtra aquellos con extensionAttribute8 = "1"
    y cuenta la cantidad de contactos que cada uno posee.

    Los resultados se muestran en consola y opcionalmente se pueden exportar a CSV.

.AUTHOR
    Ismael Morilla Orellana

.VERSION
    1.0.0

.REQUIREMENTS
    - Permisos en Azure AD App Registration:
        * User.Read.All
        * Contacts.Read
    - PowerShell 5.1+ o PowerShell Core 7+
    - Módulo: Ninguno adicional (usa Invoke-RestMethod nativo)

.USAGE
    1. Edita las variables $clientId, $clientSecret y $tenantId con tus credenciales.
    2. Ejecuta el script en PowerShell:
        PS> .\Contar-Contactos.ps1
    3. (Opcional) Descomenta la línea de Export-Csv para guardar los resultados.

.NOTES
    Fecha: 2025-09-02
#>


# =============================
# CONFIGURACIÓN PREVIA
# =============================
$clientId     = "<CLIENT_ID>"
$clientSecret = "<CLIENT_SECRET>"
$tenantId     = "<TENANT_ID>"

# =============================
# OBTENER TOKEN DE ACCESO
# =============================
$body = @{
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $clientId
    client_secret = $clientSecret
}

$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method POST -Body $body
$accessToken   = $tokenResponse.access_token

$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

# =============================
# OBTENER TODOS LOS USUARIOS
# =============================
$allUsers = @()
$usersUrl = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,onPremisesExtensionAttributes&`$top=999"

do {
    $response  = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $allUsers += $response.value
    $usersUrl  = $response.'@odata.nextLink'
} while ($usersUrl)

# =============================
# FILTRAR USUARIOS CON extensionAttribute8 = "1"
# =============================
$usuariosDestino = $allUsers | Where-Object {
    $_.onPremisesExtensionAttributes.extensionAttribute8 -eq "1"
}

# =============================
# RECORRER USUARIOS Y CONTAR CONTACTOS
# =============================
$resultados = @()

foreach ($usuario in $usuariosDestino) {
    Write-Host "`nProcesando usuario destino: $($usuario.displayName) <$($usuario.userPrincipalName)>"

    $allContacts = @()
    $contactsUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts?`$top=999"

    do {
        $response    = Invoke-RestMethod -Uri $contactsUrl -Headers $headers -Method GET
        $allContacts += $response.value
        $contactsUrl = $response.'@odata.nextLink'
    } while ($contactsUrl)

    $conteoContactos = $allContacts.Count

    Write-Host "→ Contactos encontrados: $conteoContactos"

    $resultados += [PSCustomObject]@{
        Usuario  = $usuario.displayName
        UPN      = $usuario.userPrincipalName
        Contactos = $conteoContactos
    }
}

# =============================
# MOSTRAR TABLA FINAL
# =============================
$resultados | Format-Table -AutoSize

# (Opcional) Exportar a CSV
#$resultados | Export-Csv -Path ".\reporte_contactos.csv" -NoTypeInformation -Encoding UTF8
