<#
.SYNOPSIS
    Script para obtener todos los dispositivos de Azure AD gestionados por Intune y exportarlos a un CSV.

.DESCRIPTION
    Este script se autentica en Microsoft Graph utilizando credenciales de aplicación (Client ID y Client Secret),
    recupera todos los dispositivos incluyendo sus extensionAttributes y otra información relevante,
    y exporta los resultados a un archivo CSV. Maneja paginación automática si hay más de 999 dispositivos.

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 2025-11-20
    Version: 1.1
    Requiere: PowerShell 7+ o Windows PowerShell con módulo REST
#>

# -------------------------------
# --- CONFIGURACIÓN DE AUTENTICACIÓN ---
# -------------------------------
$tenantId     = "<TuTenantId>"
$clientId     = "<TuClientId>"      # Cambiado de $appId a $clientId
$clientSecret = "<TuClientSecret>"

$body = @{
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $clientId
    client_secret = $clientSecret
}

Write-Host "Solicitando token de acceso..." -ForegroundColor Cyan
$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
                                   -Method POST `
                                   -Body $body `
                                   -ContentType "application/x-www-form-urlencoded"

$accessToken = $tokenResponse.access_token
Write-Host "Token obtenido correctamente." -ForegroundColor Green

# -------------------------------
# --- ENCABEZADOS PARA GRAPH API ---
# -------------------------------
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

# -------------------------------
# --- CONFIGURACIÓN DE LA CONSULTA ---
# -------------------------------
$deviceUrl     = 'https://graph.microsoft.com/v1.0/devices?$select=id,deviceId,displayName,trustType,operatingSystem,managementType,registrationDateTime,approximateLastSignInDateTime,mdmAppId,extensionAttributes&$top=999'
$allDevicesAAD = @()

# -------------------------------
# --- RECUPERACIÓN DE DISPOSITIVOS CON PAGINACIÓN ---
# -------------------------------
Write-Host "Recuperando dispositivos de Azure AD..." -ForegroundColor Cyan
while ($deviceUrl) {
    try {
        $response = Invoke-RestMethod -Uri $deviceUrl -Headers $headers -Method GET
        $allDevicesAAD += $response.value
        $deviceUrl = $response.'@odata.nextLink'
    }
    catch {
        Write-Host "Error consultando la URL: $deviceUrl" -ForegroundColor Red
        throw
    }
}

Write-Host "Dispositivos obtenidos:" $allDevicesAAD.Count -ForegroundColor Green

# -------------------------------
# --- EXPORTACIÓN A CSV ---
# -------------------------------
$csvPath = "C:\temp\DispositivosAAD.csv"
Write-Host "Exportando dispositivos a CSV en $csvPath ..." -ForegroundColor Cyan

$allDevicesAAD | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "CSV exportado correctamente." -ForegroundColor Green
