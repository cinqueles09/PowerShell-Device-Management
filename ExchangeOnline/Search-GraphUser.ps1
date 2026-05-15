# =============================================================
#
#   Script  : Search-GraphUser.ps1
#   Version : 1.0
#   Autor   : Ismael Morilla Orellana
#   Fecha   : 14/05/2026
#
#   Descripcion:
#       Busca un usuario en Microsoft 365 a traves de la API
#       de Microsoft Graph filtrando por UPN o alias de correo
#       (proxyAddresses). Devuelve informacion detallada del
#       usuario si existe en el directorio.
#
#   Uso:
#       .\Search-GraphUser.ps1 -UPN "usuario@dominio.com"
#
#       .\Search-GraphUser.ps1 -UPN "usuario@dominio.com" `
#           -TenantId     "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
#           -ClientId     "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
#           -ClientSecret "tu-client-secret"
#
#   Requisitos:
#       - App Registration en Azure AD con permiso:
#         User.Read.All (Application) + Admin Consent
#       - PowerShell 5.1 o superior
#       - Conectividad a login.microsoftonline.com y graph.microsoft.com
#
#   Historial de cambios:
#       1.0 - 2026 - Version inicial
#
# =============================================================

param(
    [Parameter(Mandatory = $true,  HelpMessage = "UPN o alias de correo a buscar")]
    [string]$UPN,

    [Parameter(Mandatory = $false, HelpMessage = "Tenant ID de Azure AD")]
    [string]$TenantId = "TENANT_ID",

    [Parameter(Mandatory = $false, HelpMessage = "Client ID de la App Registration")]
    [string]$ClientId = "CLIENT_ID",

    [Parameter(Mandatory = $false, HelpMessage = "Client Secret de la App Registration")]
    [string]$ClientSecret = "SECRET"
)


# ----------------------------------------------------------
# 1. Obtener token via client_credentials
# ----------------------------------------------------------
function Get-AppToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }

    Write-Host "[AUTH] Obteniendo token para tenant"

    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $body `
                    -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        Write-Host "[AUTH] Token obtenido correctamente." -ForegroundColor Green
        return $response.access_token
    }
    catch {
        $errorDetail = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($errorDetail) {
            $msg = "$($errorDetail.error): $($errorDetail.error_description)"
        } else {
            $msg = $_.ToString()
        }
        Write-Error "[AUTH] Error obteniendo token: $msg"
        exit 1
    }
}

# ----------------------------------------------------------
# 2. Construir la URL de Graph con los tres filtros
# ----------------------------------------------------------
function Build-GraphUrl {
    param([string]$Alias)

    $enc       = [Uri]::EscapeDataString($Alias)
    $smtpUpper = [Uri]::EscapeDataString("SMTP:$Alias")
    $smtpLower = [Uri]::EscapeDataString("smtp:$Alias")

    $filter = "userPrincipalName eq '$enc' or " +
              "proxyAddresses/any(c:c eq '$smtpUpper') or " +
              "proxyAddresses/any(c:c eq '$smtpLower')"

    $select = "id,displayName,userPrincipalName,mail,jobTitle,department," +
              "accountEnabled,proxyAddresses,officeLocation,mobilePhone,createdDateTime"

    return "https://graph.microsoft.com/v1.0/users?`$filter=$filter&`$select=$select"
}

# ----------------------------------------------------------
# 3. Llamada a la API de Graph
# ----------------------------------------------------------
function Invoke-GraphQuery {
    param(
        [string]$Url,
        [string]$Token
    )

    $headers = @{
        "Authorization"    = "Bearer $Token"
        "Content-Type"     = "application/json"
        "ConsistencyLevel" = "eventual"
    }

    try {
        $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method GET -ErrorAction Stop
        return $response
    }
    catch {
        $statusCode  = $_.Exception.Response.StatusCode.value__
        $errorDetail = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($errorDetail) {
            $msg = $errorDetail.error.message
        } else {
            $msg = $_.ToString()
        }

        switch ($statusCode) {
            401 { Write-Error "[ERROR] No autorizado. Verifica Client ID y Secret." }
            403 { Write-Error "[ERROR] Sin permisos. La app necesita User.Read.All (Application) con Admin Consent." }
            400 { Write-Error "[ERROR] Consulta mal formada: $msg" }
            default { Write-Error "[ERROR] HTTP $statusCode : $msg" }
        }
        exit 1
    }
}

# ----------------------------------------------------------
# 4. Mostrar resultado
# ----------------------------------------------------------
function Show-Result {
    param(
        $Users,
        [string]$Query
    )

    $sep = "================================================================="
    Write-Host $sep -ForegroundColor DarkGray

    if ($Users.Count -eq 0) {
        Write-Host "  RESULTADO: NO ENCONTRADO" -ForegroundColor Red
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host "  El alias/UPN '$Query' NO existe en el directorio." -ForegroundColor Yellow
        Write-Host $sep -ForegroundColor DarkGray
        Write-Host ""
        return $null
    }

    $u = $Users[0]

    Write-Host "  RESULTADO: USUARIO ENCONTRADO" -ForegroundColor Green
    Write-Host $sep -ForegroundColor DarkGray
    Write-Host ""

    if ($u.accountEnabled) {
        $estadoColor = "Green"
        $estadoTexto = "ACTIVO"
    } else {
        $estadoColor = "Red"
        $estadoTexto = "DESHABILITADO"
    }

    if ($u.createdDateTime) {
        $creado = ([datetime]$u.createdDateTime).ToString("dd/MM/yyyy HH:mm")
    } else {
        $creado = "N/A"
    }

    if ($u.displayName)    { $nombre = $u.displayName }    else { $nombre = "N/A" }
    if ($u.userPrincipalName) { $upnVal = $u.userPrincipalName } else { $upnVal = "N/A" }
    if ($u.mail)           { $mail = $u.mail }             else { $mail = "N/A" }
    if ($u.jobTitle)       { $puesto = $u.jobTitle }       else { $puesto = "N/A" }
    if ($u.department)     { $depto = $u.department }      else { $depto = "N/A" }
    if ($u.officeLocation) { $oficina = $u.officeLocation } else { $oficina = "N/A" }
    if ($u.mobilePhone)    { $telefono = $u.mobilePhone }  else { $telefono = "N/A" }

    Write-Host "  Nombre        : $nombre"   -ForegroundColor White
    Write-Host "  UPN           : $upnVal"   -ForegroundColor White
    Write-Host "  Mail          : $mail"     -ForegroundColor White
    Write-Host "  Object ID     : $($u.id)" -ForegroundColor Gray
    Write-Host "  Puesto        : $puesto"   -ForegroundColor White
    Write-Host "  Departamento  : $depto"    -ForegroundColor White
    Write-Host "  Oficina       : $oficina"  -ForegroundColor White
    Write-Host "  Telefono      : $telefono" -ForegroundColor White
    Write-Host "  Creado        : $creado"   -ForegroundColor White
    Write-Host "  Estado        : $estadoTexto" -ForegroundColor $estadoColor

    $proxies = $u.proxyAddresses
    if ($proxies -and $proxies.Count -gt 0) {
        Write-Host ""
        Write-Host "  ProxyAddresses:" -ForegroundColor Cyan
        foreach ($proxy in ($proxies | Sort-Object)) {
            if ($proxy.StartsWith("SMTP:")) {
                Write-Host "    $proxy" -ForegroundColor White
            } else {
                Write-Host "    $proxy" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    Write-Host $sep -ForegroundColor DarkGray
    Write-Host ""

    return $u
}

# ----------------------------------------------------------
# MAIN
# ----------------------------------------------------------

if ($TenantId -eq "TU_TENANT_ID" -or $ClientId -eq "TU_CLIENT_ID" -or $ClientSecret -eq "TU_CLIENT_SECRET") {
    Write-Warning "Recuerda rellenar TenantId, ClientId y ClientSecret en los parametros del script."
    Write-Host ""
}

Write-Host ""
Write-Host "  Microsoft Graph - Buscador de usuarios" -ForegroundColor Cyan
Write-Host "  Buscando: $UPN" -ForegroundColor White
Write-Host ""

$token    = Get-AppToken      -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
$url      = Build-GraphUrl    -Alias $UPN
$response = Invoke-GraphQuery -Url $url -Token $token
$users    = $response.value

$user = Show-Result -Users $users -Query $UPN

#return $user
