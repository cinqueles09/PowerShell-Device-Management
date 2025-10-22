<#
.SYNOPSIS
    Script para obtener todos los dispositivos de Azure AD mediante Microsoft Graph API 
    y generar un resumen por sistema operativo, tipo de confianza y dispositivos Workplace + Windows sin MDM.

.DESCRIPTION
    Este script realiza los siguientes pasos:
        1. Autenticacion con Microsoft Graph API usando Client Credentials.
        2. Obtencion de todos los dispositivos en Azure AD.
        3. Filtrado por sistema operativo (Windows, Android, iOS) y tipo de confianza (Workplace, AzureAD, ServerAD).
        4. Identificacion de dispositivos Workplace con Windows que no tienen MDM configurado (managementType null).
        5. Generacion de tablas de resumen para facilitar el analisis.

.PARAMETER tenantId
    ID del tenant de Azure AD.

.PARAMETER clientId
    ID de la aplicacion registrada en Azure AD.

.PARAMETER clientSecret
    Secreto de la aplicacion registrada en Azure AD.

.EXAMPLE
    .\Obtener-DispositivosAzureAD.ps1

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 2025-09-24
    Requiere permisos de aplicacion en Azure AD: Device.Read.All
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

# === Obtener todos los dispositivos ===
$allDevices = @()
$devicesUrl = "https://graph.microsoft.com/v1.0/devices?`$select=id,displayName,trustType,operatingSystem,managementType,registrationDateTime&`$top=999"

do {
    $response = Invoke-RestMethod -Uri $devicesUrl -Headers $headers -Method GET
    $allDevices += $response.value
    $devicesUrl = $response.'@odata.nextLink'
} while ($devicesUrl -ne $null)

Write-Host "Total de dispositivos encontrados: $($allDevices.Count)"

# === Filtrado por sistema operativo ===
$osSummary = $allDevices | Group-Object -Property operatingSystem | ForEach-Object {
    [PSCustomObject]@{
        OperatingSystem = $_.Name
        Count           = $_.Count
    }
}

# Mostrar resumen de OS
Write-Host "`n=== Resumen por Sistema Operativo ==="
$osSummary | Format-Table -AutoSize

# === Filtrado por tipo de confianza (trustType) ===
$trustSummary = $allDevices | Group-Object -Property trustType | ForEach-Object {
    [PSCustomObject]@{
        TrustType = $_.Name
        Count     = $_.Count
    }
}

# Mostrar resumen de TrustType
Write-Host "`n=== Resumen por TrustType ==="
$trustSummary | Format-Table -AutoSize

# === Ejemplo específico de conteos que mencionaste ===
$windowsCount   = ($allDevices | Where-Object { $_.operatingSystem -like "Windows*" }).Count
$androidCount   = ($allDevices | Where-Object { $_.operatingSystem -like "Android*" }).Count
$iosCount       = ($allDevices | Where-Object { $_.operatingSystem -like "iOS*" }).Count

$workplaceCount = ($allDevices | Where-Object { $_.trustType -eq "Workplace" }).Count
$azureadCount   = ($allDevices | Where-Object { $_.trustType -eq "AzureAD" }).Count
$serveradCount  = ($allDevices | Where-Object { $_.trustType -eq "ServerAD" }).Count

# === Filtrar Windows + Workplace sin MDM (managementType null) ===
$workplaceWindowsNoMDM = $allDevices | Where-Object {
    ($_.trustType -eq "Workplace") -and
    ($_.operatingSystem -like "Windows*") #-and
    #(-not $_.managementType) 
}

Write-Host "`nTotal de dispositivos Workplace + Windows sin MDM: $($workplaceWindowsNoMDM.Count)"

#Write-Host "`n=== Resumen Final ==="

$summaryTable | Format-Table -AutoSize

# ==========================
# CODIGO NUEVO (Validado)
# ==========================

# === Filtrar conjuntos ===
$workplaceWindows = $allDevices | Where-Object {
    $_.trustType -eq "Workplace" -and
    $_.operatingSystem -like "Windows*"
}

$azureServerWindows = $allDevices | Where-Object {
    ($_.trustType -in @("AzureAD", "ServerAD")) -and
    ($_.operatingSystem -like "Windows*")
}

# === Buscar coincidencias por displayName ===
$coincidentes = $workplaceWindows | Where-Object {
    $name = $_.displayName
    $azureServerWindows.displayName -contains $name
}

# === Workplace Windows que NO están en AzureAD/ServerAD ===
$workplaceWindowsUnicos = $workplaceWindows | Where-Object {
    $azureServerWindows.displayName -notcontains $_.displayName
}
$SinGestion = $workplaceWindowsUnicos.Count

# === Mostrar resumen en pantalla ===
Write-Host "`n=== Dispositivos que existen como Workplace y tambien como AzureAD/ServerAD ==="
if ($coincidentes) {
    #$coincidentes | Select-Object displayName, trustType, operatingSystem | Format-Table -AutoSize
    Write-Host "`nTotal de coincidencias encontradas: $($coincidentes.Count)"
    Write-Host "`nTotal no coincidente: $SinGestion"
} else {
    Write-Host "No se encontraron coincidencias."
}

# === Exportar a CSV ===
$fecha = Get-Date -Format "yyyyMMdd_HHmmss"
$rutaCoincidentes = "C:\Temp\Dispositivos_Coincidentes_$fecha.csv"
$rutaNoCoincidentes = "C:\Temp\Dispositivos_NoCoincidentes_$fecha.csv"

# Crear carpeta si no existe
$carpeta = Split-Path $rutaCoincidentes
if (!(Test-Path $carpeta)) { New-Item -Path $carpeta -ItemType Directory | Out-Null }

# Exportar los datos
$coincidentes | Select-Object displayName, trustType, operatingSystem, managementType |
    Export-Csv -Path $rutaCoincidentes -NoTypeInformation -Encoding UTF8

$workplaceWindowsUnicos | Select-Object displayName, trustType, operatingSystem, managementType |
    Export-Csv -Path $rutaNoCoincidentes -NoTypeInformation -Encoding UTF8

Write-Host "`nArchivos exportados:"
Write-Host " - Coincidentes: $rutaCoincidentes"
Write-Host " - No coincidentes: $rutaNoCoincidentes"

# ==========================
# CODIGO NUEVO 
# ==========================

# === Análisis de dispositivos sin fecha de registro ===
$sinRegistro = $allDevices | Where-Object {
    -not $_.registrationDateTime -and
    ($_.trustType -eq "ServerAD")
}

Write-Host "`n=== Dispositivos con registrationDateTime NULO ==="
if ($sinRegistro.Count -gt 0) {
    Write-Host "Total de dispositivos sin fecha de registro: $($sinRegistro.Count)"
    #$sinRegistro | Select-Object displayName, trustType, operatingSystem, managementType, registrationDateTime | Format-Table -AutoSize
} else {
    Write-Host "No se encontraron dispositivos con registrationDateTime nulo."
}

# === Exportar resultados sin registro ===
$rutaSinRegistro = "C:\Temp\Dispositivos_SinRegistro_$fecha.csv"

$sinRegistro | Select-Object displayName, trustType, operatingSystem, managementType, registrationDateTime |
    Export-Csv -Path $rutaSinRegistro -NoTypeInformation -Encoding UTF8

Write-Host "`nArchivo adicional exportado:"
Write-Host " - Sin fecha de registro: $rutaSinRegistro"

Write-Host "`n=== Resumen Final ==="
