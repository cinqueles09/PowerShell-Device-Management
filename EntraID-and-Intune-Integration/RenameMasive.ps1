<#
.SYNOPSIS
    Renombrado masivo de dispositivos en Microsoft Intune via Graph API.
 
.DESCRIPTION
    Lee un fichero CSV con numeros de serie, busca cada dispositivo en Intune
    y le aplica un nuevo nombre con el formato [PREFIJO][SERIAL] respetando
    el limite de 15 caracteres. Compatible con Windows, iOS, macOS y Android.
 
.PARAMETER TenantId
    ID del tenant de Azure AD.
 
.PARAMETER ClientId
    ID de la aplicacion registrada en Azure AD.
 
.PARAMETER ClientSecret
    Secreto de la aplicacion registrada en Azure AD.
 
.PARAMETER Prefix
    Prefijo que se antepone al numero de serie. Ejemplo: "CONTOSO-"
 
.PARAMETER CsvPath
    Ruta al fichero CSV con la columna SerialNumber.
 
.NOTES
    Autor      : Ismael Morilla Orellana
    Version    : 1.0
    Fecha      : 2026-05-15
 
    Permisos requeridos en App Registration (Application):
      - DeviceManagementManagedDevices.ReadWrite.All
      - DeviceManagementManagedDevices.PrivilegedOperations.All
 
    Endpoint utilizado:
      POST https://graph.microsoft.com/beta/deviceManagement/managedDevices/{id}/microsoft.graph.setDeviceName
 
.EXAMPLE
    .\RenameMasive.ps1
 
    Ejecuta el script con la configuracion definida en la seccion CONFIGURACION.
#>

# --- CONFIGURACIÓN DE CREDENCIALES ---
$TenantId     = ""
$ClientId     = ""
$ClientSecret = ""
$Prefix       = "CONTOSO-" #Cambiar por el prefijo deseado
$CsvPath      = ".\dispositivos.csv"

# --- 1. TOKEN ---
$tokenUrl  = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$tokenBody = @{
    client_id     = $ClientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $ClientSecret
    grant_type    = "client_credentials"
}

try {
    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody -ErrorAction Stop
} catch {
    Write-Host "[FATAL] No se pudo obtener el token: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$authHeader = @{
    'Authorization' = "Bearer $($tokenResponse.access_token)"
    'Content-Type'  = 'application/json'
}

# --- 2. FUNCION: Buscar dispositivo por serial ---
function Get-ManagedDeviceBySerial {
    param($Serial, $Headers)

    $url = "https://graph.microsoft.com/beta/deviceManagement/managedDevices" +
           "?`$filter=serialNumber eq '$Serial'" +
           "&`$select=id,deviceName,serialNumber,operatingSystem,managedDeviceOwnerType"
    do {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $Headers -ErrorAction Stop
        if ($response.value.Count -gt 0) { return $response.value[0] }
        $url = $response.'@odata.nextLink'
    } while ($url)

    return $null
}

# --- 3. FUNCION: Calcular nombre nuevo (max 15 caracteres) ---
function Get-NewDeviceName {
    param($Prefix, $Serial)

    $maxSerial = 15 - $Prefix.Length
    $short = if ($Serial.Length -gt $maxSerial) {
        $Serial.Substring($Serial.Length - $maxSerial)
    } else {
        $Serial
    }
    return "$Prefix$short"
}

# --- 4. FUNCION: Extraer mensaje de error de Graph ---
function Get-GraphError {
    param($CaughtError)
    $body = $CaughtError.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($body) { return $body.error.message }
    return $CaughtError.Exception.Message
}

# =============================================================================
# PROCESAMIENTO PRINCIPAL
# =============================================================================
$devices = Import-Csv $CsvPath

$ok      = 0
$skipped = 0
$failed  = 0

foreach ($row in $devices) {
    $serial = $row.SerialNumber.Trim()

    Write-Host ""
    Write-Host "-------------------------------------" -ForegroundColor DarkGray
    Write-Host "Serial: $serial" -ForegroundColor Cyan

    # Buscar dispositivo en Intune
    try {
        $device = Get-ManagedDeviceBySerial -Serial $serial -Headers $authHeader
    } catch {
        Write-Host "  [ERROR] Fallo al consultar Graph: $(Get-GraphError $_)" -ForegroundColor Red
        $failed++
        continue
    }

    if ($null -eq $device) {
        Write-Host "  [!] No encontrado en Intune." -ForegroundColor Yellow
        $skipped++
        continue
    }

    $newName = Get-NewDeviceName -Prefix $Prefix -Serial $serial

    Write-Host "  OS        : $($device.operatingSystem)"          -ForegroundColor Gray
    Write-Host "  Nombre    : $($device.deviceName)"               -ForegroundColor Gray
    Write-Host "  Ownership : $($device.managedDeviceOwnerType)"   -ForegroundColor Gray
    Write-Host "  Nuevo     : $newName"                            -ForegroundColor White

    # Renombrar via setDeviceName
    $url  = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($device.id)/microsoft.graph.setDeviceName"
    $body = @{ deviceName = $newName } | ConvertTo-Json -Compress

    try {
        $null = Invoke-RestMethod -Uri $url -Method Post -Headers $authHeader -Body $body -ErrorAction Stop
        Write-Host "  [OK] Renombrado correctamente. Se aplica en el proximo check-in." -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

# --- RESUMEN FINAL ---
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Completado -> OK: $ok | Skipped: $skipped | Errores: $failed" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
