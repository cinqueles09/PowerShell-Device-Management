<#
.SYNOPSIS
    Actualiza atributos de extensión en dispositivos de Azure AD asociados a usuarios tipo 'Member'.

.DESCRIPTION
    Este script obtiene todos los usuarios 'Member' de Azure AD, recupera sus dispositivos (excluyendo los de tipo 'Workplace') 
    y actualiza los atributos de extensión en cada dispositivo según los valores del usuario. 
    Si el usuario es 'labvantage', se asigna el valor 'labvantage' a extensionAttribute1.

.AUTHOR
    Ismael Morilla Orellana (ismael.moore@outlook.es)

.VERSION
    1.0 (12/10/2025)

.REQUIREMENTS
    - Permisos de aplicación en Azure AD para Microsoft Graph (User.Read.All, Device.ReadWrite.All)
    - PowerShell 5.1 o superior

.NOTES
    Modifica los valores de tenantId, appId y clientSecret según tu entorno.
    Este script utiliza el flujo de credenciales de cliente para autenticación.
    No es necesario iniciarl sesión con el modulo de powershell MgGraph.

#>

# ==========================
# CONFIGURACIÓN INICIAL
# ==========================
$tenantId = ""
$appId = ""
$clientSecret=""
$scopes       = "https://graph.microsoft.com/.default"

# ==========================
# OBTENER TOKEN DE ACCESO
# ==========================
$token = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body @{
    client_id     = $appId
    scope         = $scopes
    grant_type    = "client_credentials"
    client_secret = $clientSecret
}).access_token

# ==========================
# CABECERAS PARA GRAPH
# ==========================
$headers = @{ 
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}

# ==========================
# OBTENER TODOS LOS USUARIOS MEMBER
# ==========================
$usuarios = @()
#$usersUrl = "https://graph.microsoft.com/v1.0/users?$filter=userType eq 'Member'&$select=id,displayName,userPrincipalName,onPremisesExtensionAttributes&$top=999"
$usersUrl = 'https://graph.microsoft.com/v1.0/users?$filter=userType eq ''Member''&$select=id,displayName,givenName,surname,userPrincipalName,mail,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&$top=999'

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $usuarios += $response.value
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)

Write-Host "Se han recuperado $($usuarios.Count) usuarios."

# ==========================
# OBTENER DISPOSITIVOS POR USUARIO (EXCLUYENDO TRUSTTYPE = WORKPLACE)
# ==========================

foreach ($user in $usuarios) {
    $ownedDevicesUrl = "https://graph.microsoft.com/v1.0/users/$($user.id)/ownedDevices/microsoft.graph.device?$select=id,displayName,trustType,operatingSystem"

    try {
        $response = Invoke-RestMethod -Uri $ownedDevicesUrl -Headers $headers -Method GET
        $devices = $response.value | Where-Object { $_.trustType -ne "Workplace" }

        if ($devices.Count -gt 0) {
            $extAtt = $user.onPremisesExtensionAttributes
            $ext2   = $extAtt.extensionAttribute2
            $ext4   = $extAtt.extensionAttribute4

            # Si el usuario es labvantage, extensionAttribute1 = "labvantage"
            if ($user.userPrincipalName -like "LabVantage*") {
                $ext2 = "LabVantage"
            }

            Write-Host "`nUsuario: $($user.displayName) [$($user.userPrincipalName)]"
            Write-Host "   ExtensionAttribute2: $ext2"
            Write-Host "   ExtensionAttribute4: $ext4"

            foreach ($device in $devices) {
                Write-Host "   - $($device.displayName) | $($device.operatingSystem) | TrustType: $($device.trustType)"
                
                $updateBody = @{
                    extensionAttributes = @{
                        extensionAttribute1 = $ext2
                        extensionAttribute2 = $ext4
                    }
                } | ConvertTo-Json

                $deviceUpdateUrl = "https://graph.microsoft.com/v1.0/devices/$($device.id)"
                try {
                    Invoke-RestMethod -Uri $deviceUpdateUrl -Headers $headers -Method PATCH -Body $updateBody
                    Write-Host "      > extensionAttributes actualizado en el dispositivo."
                }
                catch {
                    Write-Warning "      Error actualizando el dispositivo $($device.displayName): $($_.Exception.Message)"
                }
            }
            Write-Host "--------------------------------"
        }
    }
    catch {
        Write-Warning "Error obteniendo dispositivos para $($user.displayName): $($_.Exception.Message)"
    }
}

# ==========================
# ANTIGUO CÓDIGO - NO BORRAR
# ==========================

#foreach ($user in $usuarios) {
#    $ownedDevicesUrl = "https://graph.microsoft.com/v1.0/users/$($user.id)/ownedDevices/microsoft.graph.device?$select=id,displayName,trustType,operatingSystem"
#
#    try {
#        $response = Invoke-RestMethod -Uri $ownedDevicesUrl -Headers $headers -Method GET
#        # Filtrar solo dispositivos que no sean Workplace
#        $devices = $response.value | Where-Object { $_.trustType -ne "Workplace" }
#
#        if ($devices.Count -gt 0) {
#            $extAtt = $user.onPremisesExtensionAttributes
#            $ext2   = $extAtt.extensionAttribute2
#            $ext4   = $extAtt.extensionAttribute4
#
#            Write-Host "`nUsuario: $($user.displayName) [$($user.userPrincipalName)]"
#            Write-Host "   ExtensionAttribute2: $ext2"
#            Write-Host "   ExtensionAttribute4: $ext4"
#
#            foreach ($device in $devices) {
#                Write-Host "   - $($device.displayName) | $($device.operatingSystem) | TrustType: $($device.trustType)"
#                
#                # Actualizar extensionAttribute2 del dispositivo
#                $updateBody = @{
#                    extensionAttributes = @{
#                        extensionAttribute1 = $ext2
#                        extensionAttribute2 = $ext4
#                    }
#                } | ConvertTo-Json
#
#                $deviceUpdateUrl = "https://graph.microsoft.com/v1.0/devices/$($device.id)"
#                try {
#                    Invoke-RestMethod -Uri $deviceUpdateUrl -Headers $headers -Method PATCH -Body $updateBody
#                    Write-Host "      > extensionAttributes actualizado en el dispositivo."
#                    Write-Host "      --------------------------------"
#                }
#                catch {
#                    Write-Warning "      Error actualizando el dispositivo $($device.displayName): $($_.Exception.Message)"
#                }
#            }
#        }
#    }
#    catch {
#        Write-Warning "Error obteniendo dispositivos para $($user.displayName): $($_.Exception.Message)"
#    }
#}
