<#
.SYNOPSIS
    Sincroniza los contactos de usuarios de Microsoft 365 con otros usuarios que tengan extensionAttribute15 = 1.

.DESCRIPTION
    Este script obtiene todos los usuarios miembros con licencia en Azure AD y, para cada usuario cuyo
    extensionAttribute15 esté configurado en 1, realiza las siguientes acciones:
        - Crea o actualiza contactos basados en los demás usuarios con extensionAttribute15 = 1. [Editable]
        - Elimina contactos duplicados del dominio @dominio.com. [Editable]
        - Elimina contactos que ya no existen en Azure AD y que sean del dominio @dominio.com.

    El script utiliza Microsoft Graph API y requiere un registro de aplicación con permisos adecuados
    (User.Read.All, Contacts.ReadWrite, etc.) en Azure AD para funcionar correctamente.

.NOTES
    Autor              : Seidor: Ismael Morilla Orellana
    Fecha creación     : 2025-08-01
    Fecha actualización: 2026-03-02
    Versión            : 5.2 (con token dinámico)
    Requisitos         : PowerShell 5.x o superior, conexión a Internet, credenciales de aplicación en Azure AD.
    Observaciones      :
        - Todas las llamadas a Graph API para crear/actualizar/eliminar contactos están comentadas (#)
          para evitar modificaciones accidentales. Descomentar solo en entorno controlado.
        - Se recomienda probar primero con un subconjunto de usuarios antes de ejecutar en producción.
        - Mantener un registro de acciones o logs para trazabilidad es altamente recomendable.

.EXAMPLE
    # Ejecutar el script para sincronizar contactos
    .\Sync-M365UserContacts.ps1

#>

# =============================
# CONFIGURACIÓN PREVIA
# =============================
$tenantId = ""
$clientId = ""
$clientSecret = ""


[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# ==============================================================================
# FUNCIONES DE APOYO
# ==============================================================================
function Get-NormalizedString {
    param([string]$inputString)
    if ([string]::IsNullOrWhiteSpace($inputString)) { return $inputString }
    return [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes($inputString))
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) { "SUCCESS" { "Green" }; "WARN" { "Yellow" }; "ERROR" { "Red" }; "HEADER" { "Cyan" }; Default { "Gray" } }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# ==============================================================================
# AUTENTICACION
# ==============================================================================
function Get-DynamicToken {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret)
    if ($script:AccessToken -and ($script:TokenExpiry -gt (Get-Date))) { return $script:AccessToken }
    Write-Log "Autenticando en Microsoft Graph..." "HEADER"
    $body = @{ grant_type = "client_credentials"; scope = "https://graph.microsoft.com/.default"; client_id = $ClientId; client_secret = $ClientSecret }
    try {
        $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $body
        $script:AccessToken = $tokenResponse.access_token
        $script:TokenExpiry = (Get-Date).AddSeconds($tokenResponse.expires_in - 300)
    } catch { throw "Error al obtener token: $_" }
    return $script:AccessToken
}

function Get-GraphHeaders {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret)
    return @{ "Authorization" = "Bearer $(Get-DynamicToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret)"; "Content-Type" = "application/json; charset=utf-8" }
}

# ==============================================================================
# PROCESO PRINCIPAL
# ==============================================================================
$headers = Get-GraphHeaders -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret
Write-Log "Iniciando sincronizacion masiva de contactos..." "HEADER"

$usuariosMiembros = @()
$usersUrl = 'https://graph.microsoft.com/v1.0/users?$filter=userType eq ''Member''&$select=id,displayName,givenName,surname,userPrincipalName,mail,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&$top=999'

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $usuariosMiembros += $response.value
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)

$usuariosObjetivo = $usuariosMiembros | Where-Object { $_.onPremisesExtensionAttributes.extensionAttribute15 -eq 1 }
Write-Log "Usuarios objetivo detectados: $($usuariosObjetivo.Count)" "HEADER"

foreach ($usuario in $usuariosObjetivo) {
    Write-Host "`n" + ("=" * 80) -ForegroundColor DarkGray
    Write-Log "Procesando: $($usuario.displayName) ($($usuario.userPrincipalName))" "HEADER"
    
    $headers = Get-GraphHeaders -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret
    
    # Obtener contactos
    $allContacts = @()
    $contactsUrl = "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts?`$top=999"
    do {
        $response = Invoke-RestMethod -Uri $contactsUrl -Headers $headers -Method GET
        $allContacts += $response.value
        $contactsUrl = $response.'@odata.nextLink'
    } while ($contactsUrl)

    $contactMap = @{}
    foreach ($contact in $allContacts) {
        foreach ($email in $contact.emailAddresses) {
            if ($email.address) { $contactMap[$email.address.ToLower().Trim()] = $contact }
        }
    }

    $otrosUsuarios = $usuariosMiembros | Where-Object { $_.assignedLicenses.Count -gt 0 -and $_.userPrincipalName -ne $usuario.userPrincipalName -and $_.onPremisesExtensionAttributes.extensionAttribute15 -eq 1 }

    # --- SINCRONIZACION ---
    foreach ($otroUsuario in $otrosUsuarios) {
        $correo = $otroUsuario.mail.ToLower().Trim()
        $data = @{
            givenName      = $otroUsuario.givenName
            surname        = $otroUsuario.surname
            businessPhones = $otroUsuario.businessPhones
            mobilePhone    = $otroUsuario.mobilePhone
            displayName    = $otroUsuario.displayName
        }

        if ($contactMap.ContainsKey($correo)) {
            $c = $contactMap[$correo]
            $cambiado = (Get-NormalizedString $c.givenName) -ne (Get-NormalizedString $data.givenName) -or 
                        (Get-NormalizedString $c.surname) -ne (Get-NormalizedString $data.surname) -or 
                        (Get-NormalizedString $c.displayName) -ne (Get-NormalizedString $data.displayName) -or
                        ($c.mobilePhone -ne $data.mobilePhone) -or 
                        (($c.businessPhones -join ',') -ne ($data.businessPhones -join ','))

            if ($cambiado) {
                $patchJson = $data | ConvertTo-Json -Depth 2
                $null=Invoke-WebRequest -Uri "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($c.id)" -Headers $headers -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchJson)) -ContentType "application/json; charset=utf-8"
                Write-Log "Actualizado: $($otroUsuario.displayName)" "SUCCESS"
            }
        } else {
            $payload = @{ givenName=$data.givenName; surname=$data.surname; displayName=$data.displayName; emailAddresses=@(@{address=$correo; name=$data.displayName}); businessPhones=$data.businessPhones; mobilePhone=$data.mobilePhone }
            $null=Invoke-WebRequest -Uri "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts" -Headers $headers -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 2))) -ContentType "application/json; charset=utf-8"
            Write-Log "Creado: $($otroUsuario.displayName)" "SUCCESS"
        }
    }

    # --- LIMPIEZA ---
    # --- A. LIMPIAR DUPLICADOS ---
    # Primero filtramos solo contactos que tengan correo Y que pertenezcan a tu dominio
    $contactosDominio = $allContacts | Where-Object { 
        $_.emailAddresses.Count -gt 0 -and 
        $_.emailAddresses[0].address -like "*@dominio.com" 
    }

    if ($contactosDominio) {
        $group = $contactosDominio | Group-Object { $_.emailAddresses[0].address.ToLower().Trim() }
        foreach ($item in $group) {
            if ($item.Count -gt 1) {
                # Mantenemos el primero, eliminamos el resto (del segundo en adelante)
                foreach ($duplicate in $item.Group[1..($item.Count - 1)]) {
                    $dupeEmail = $duplicate.emailAddresses[0].address
                    $dupeName  = $duplicate.displayName
                    
                    try {
                        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($duplicate.id)" -Headers $headers -Method DELETE
                        Write-Log "Duplicado eliminado: $dupeName <$dupeEmail>" "WARN"
                    } catch {
                        $errorMessage = $_.Exception.Message
                        if ($_.Exception.Response.StatusCode.value__ -ne 404) {
                            Write-Log "Error al eliminar duplicado $($dupeName): $errorMessage" "ERROR"
                        } else {
                            Write-Log "El duplicado $dupeName ya no existía (404 ignorado)" "INFO"
                        }
                    }
                }
            }
        }
    }
    # --- B. LIMPIAR OBSOLETOS ---
    foreach ($correoExistente in $contactMap.Keys) {
        if ($correoExistente -like "*@dominio.com" -and ($otrosUsuarios.mail -notcontains $correoExistente)) {
            $c = $contactMap[$correoExistente]
            if ($c.id) {
                $null=Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($c.id)" -Headers $headers -Method DELETE
                Write-Log "Depurado (obsoleto): $correoExistente" "WARN"
            }
        }
    }
}
Write-Log "Proceso de sincronizacion finalizado con exito." "HEADER"
}
Write-Log "Proceso de sincronizacion finalizado con exito." "HEADER"
