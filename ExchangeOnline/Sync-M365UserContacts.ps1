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
    Versión            : 5.1 (con token dinámico)
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

# Función para normalizar texto (soluciona caracteres como ñ, í, etc.)
function Get-NormalizedString {
    param([string]$inputString)
    if ([string]::IsNullOrWhiteSpace($inputString)) { return $inputString }
    return [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes($inputString))
}

# =============================
# TOKEN DINÁMICO PARA GRAPH
# =============================
function Get-DynamicToken {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret)
    if ($script:AccessToken -and ($script:TokenExpiry -gt (Get-Date))) { return $script:AccessToken }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Renovando token..." -ForegroundColor Gray
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

# =============================
# OBTENER TODOS LOS USUARIOS MIEMBROS CON LICENCIA
# =============================
$headers = Get-GraphHeaders -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret
$usuariosMiembros = @()
$usersUrl = 'https://graph.microsoft.com/v1.0/users?$filter=userType eq ''Member''&$select=id,displayName,givenName,surname,userPrincipalName,mail,assignedLicenses,mobilePhone,businessPhones,onPremisesExtensionAttributes&$top=999'

do {
    $response = Invoke-RestMethod -Uri $usersUrl -Headers $headers -Method GET
    $usuariosMiembros += $response.value
    $usersUrl = $response.'@odata.nextLink'
} while ($usersUrl)

$usuariosObjetivo = $usuariosMiembros | Where-Object { $_.onPremisesExtensionAttributes.extensionAttribute15 -eq 1 }
Write-Host "Usuarios objetivo encontrados: $($usuariosObjetivo.Count)" -ForegroundColor Cyan

# =============================
# PROCESAR CADA USUARIO OBJETIVO
# =============================
foreach ($usuario in $usuariosObjetivo) {
    Write-Host "Procesando usuario objetivo: $($usuario.displayName) <$($usuario.userPrincipalName)>" -ForegroundColor Magenta
    $headers = Get-GraphHeaders -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret
    
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

    # --- CREAR/ACTUALIZAR CONTACTOS ---
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
                $null = Invoke-WebRequest -Uri "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($c.id)" -Headers $headers -Method PATCH -Body ([System.Text.Encoding]::UTF8.GetBytes($patchJson)) -ContentType "application/json; charset=utf-8"
                Write-Host "[!] Contacto actualizado: $($otroUsuario.displayName) <$correo>" -ForegroundColor Green
            }
        } else {
            $payload = @{ givenName=$data.givenName; surname=$data.surname; displayName=$data.displayName; emailAddresses=@(@{address=$correo; name=$data.displayName}); businessPhones=$data.businessPhones; mobilePhone=$data.mobilePhone }
            $null = Invoke-WebRequest -Uri "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts" -Headers $headers -Method POST -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 2))) -ContentType "application/json; charset=utf-8"
            Write-Host "[v] Contacto nuevo creado: $($otroUsuario.displayName) <$correo>" -ForegroundColor Cyan
        }
    }

    # --- LIMPIAR DUPLICADOS ---
    $contactosPorCorreo = @{}
    foreach ($contact in $allContacts) {
        foreach ($email in $contact.emailAddresses) {
            $correo = $email.address.ToLower().Trim()
            if ($correo) {
                if (-not $contactosPorCorreo.ContainsKey($correo)) { $contactosPorCorreo[$correo] = @($contact) }
                else { $contactosPorCorreo[$correo] += $contact }
            }
        }
    }

    foreach ($correo in $contactosPorCorreo.Keys) {
        if ($correo -like "*@dominio.com") {
            $duplicados = $contactosPorCorreo[$correo]
            if ($duplicados.Count -gt 1) {
                $duplicados[1..($duplicados.Count - 1)] | ForEach-Object {
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($_.id)" -Headers $headers -Method DELETE
                    Write-Host "[X] Duplicado eliminado: $($_.displayName) <$correo>" -ForegroundColor Red
                }
            }
        }
    }

    # --- ELIMINAR CONTACTOS QUE YA NO EXISTEN EN AAD ---
    $correosValidosAAD = $otrosUsuarios.mail | ForEach-Object { $_.ToLower().Trim() }
    foreach ($correoExistente in $contactMap.Keys) {
        if ($correoExistente -like "*@dominio.com" -and $correosValidosAAD -notcontains $correoExistente) {
            $c = $contactMap[$correoExistente]
            if ($c.id) {
                Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($usuario.id)/contacts/$($c.id)" -Headers $headers -Method DELETE
                Write-Host "[X] Contacto eliminado (obsoleto): <$correoExistente>" -ForegroundColor Red
            }
        }
    }
    Write-Host "Finalizado usuario $($usuario.userPrincipalName)" -ForegroundColor DarkYellow
}
