<#
.SYNOPSIS
    Script para analizar, exportar y eliminar dispositivos inactivos, huérfanos, duplicados 
    o con configuración incorrecta en Intune y Entra ID (Azure AD) mediante Microsoft Graph API.

.DESCRIPTION
    Este script realiza una limpieza integral de dispositivos gestionados o registrados en el entorno 
    de Microsoft 365, a través de múltiples bloques de procesamiento que incluyen:

        1. Autenticación en Microsoft Graph API mediante Client Credentials.
        2. Obtención de todos los dispositivos registrados en Intune y Entra ID.
        3. Comparación entre ambas fuentes (coincidentes, solo Intune, solo Entra ID).
        4. Detección y eliminación de dispositivos inactivos (sin sincronización desde 2024 o antes).
        5. Eliminación de dispositivos huérfanos sin registrationDateTime ni presencia en Intune.
        6. Filtrado de dispositivos con TrustType = Workplace.
        7. Identificación y eliminación de duplicados en Intune por número de serie, 
           conservando el más reciente.
        8. Exportación de todos los resultados a archivos CSV para revisión y trazabilidad.

.PARAMETER tenantId
    ID del tenant de Azure AD (Entra ID).

.PARAMETER appId
    ID de la aplicación registrada en Azure AD utilizada para la autenticación Graph API.

.PARAMETER clientSecret
    Secreto de la aplicación registrada en Azure AD.

.PARAMETER scopes
    Permisos (scopes) utilizados para solicitar el token de acceso a Graph API.

.EXAMPLE
    .\Limpieza-Dispositivos_Intune-EntraID.ps1

.NOTES
    Autor: Ismael Morilla Orellana
    Versión: 1.0
    Fecha: 2025-11-04

    Requiere permisos de aplicación en Microsoft Graph API:
        - Device.ReadWrite.All
        - DeviceManagementManagedDevices.ReadWrite.All

    Este script puede ELIMINAR dispositivos de Intune y/o Entra ID.
    Se recomienda revisar siempre los CSV exportados antes de confirmar cualquier eliminación.

#>


# ==========================
# CONFIGuRACIoN
# ==========================
$tenantId = ""
$appId = ""
$clientSecret=""
$scopes       = "https://graph.microsoft.com/.default"


# ==========================
# CONFIGURACION Y TOKEN
# ==========================
Write-Host "Obteniendo token de acceso..."

$token = (Invoke-RestMethod -Method Post -uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body @{
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
# OBTENER DISPOSITIVOS DE INTUNE
# ==========================
Write-Host "`nObteniendo dispositivos administrados por Intune..."

$devicesurl = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=id,deviceName,operatingSystem,osVersion,managementAgent,managementState,lastSyncDateTime,userPrincipalName,azureADDeviceId,serialNumber&`$top=999"
$allManagedDevices = @()

do {
    $response = Invoke-RestMethod -uri $devicesurl -Headers $headers -Method GET
    $allManagedDevices += $response.value
    $devicesurl = $response.'@odata.nextLink'
} while ($devicesurl -ne $null)

Write-Host "Total dispositivos Intune: $($allManagedDevices.Count)"

# ==========================
# OBTENER DISPOSITIVOS DE ENTRA ID / AZURE AD
# ==========================
Write-Host "`nObteniendo dispositivos registrados en Entra ID..."

$devicesurl = "https://graph.microsoft.com/v1.0/devices?`$select=id,deviceId,displayName,trustType,operatingSystem,managementType,registrationDateTime,approximateLastSignInDateTime,mdmAppId&`$top=999"
$allDevicesAAD = @()

do {
    $response = Invoke-RestMethod -uri $devicesurl -Headers $headers -Method GET
    $allDevicesAAD += $response.value
    $devicesurl = $response.'@odata.nextLink'
} while ($devicesurl -ne $null)

Write-Host "Total dispositivos Entra ID: $($allDevicesAAD.Count)"

# ==========================
# COMPARACION
# ==========================
Write-Host "`nComparando dispositivos entre Intune y Entra ID..."

$coincidentes = $allManagedDevices | Where-Object {
    $id = $_.azureADDeviceId
    $allDevicesAAD.deviceId -contains $id
}

$soloIntune = $allManagedDevices | Where-Object {
    $id = $_.azureADDeviceId
    $allDevicesAAD.deviceId -notcontains $id
}

$soloAAD = $allDevicesAAD | Where-Object {
    $id = $_.deviceId
    $allManagedDevices.azureADDeviceId -notcontains $id
}

Write-Host "`nResumen de comparacion:"
Write-Host " - En ambos: $($coincidentes.Count)"
Write-Host " - Solo Intune: $($soloIntune.Count)"
Write-Host " - Solo Entra ID: $($soloAAD.Count)"

# ==========================
# EXPORTAR RESULTADOS
# ==========================
$fecha = Get-Date -Format "yyyyMMdd_HHmmss"
$basePath = "C:\Temp\Comparativa_Dispositivos_$fecha"
New-Item -ItemType Directory -Path $basePath -Force | Out-Null

$coincidentes | Select-Object deviceName, operatingSystem, osVersion, userPrincipalName, managementAgent, lastSyncDateTime, azureADDeviceId |
    Export-Csv -Path "$basePath\Coincidentes.csv" -NoTypeInformation -Encoding UTF8

$soloIntune | Select-Object deviceName, operatingSystem, osVersion, userPrincipalName, managementAgent, lastSyncDateTime, azureADDeviceId |
    Export-Csv -Path "$basePath\Solo_Intune.csv" -NoTypeInformation -Encoding UTF8

$soloAAD | Select-Object displayName, operatingSystem, trustType, managementType, registrationDateTime, approximateLastSignInDateTime, mdmAppId, deviceId |
    Export-Csv -Path "$basePath\Solo_AzureAD.csv" -NoTypeInformation -Encoding UTF8

# ==========================
# DETECTAR DISPOSITIVOS INACTIVOS
# ==========================
Write-Host "`nAnalizando dispositivos inactivos (ultima actividad antes de 2025)..."

$fechaLimite = Get-Date "2024-12-31"

$inactivosIntune = $allManagedDevices | Where-Object {
    $_.lastSyncDateTime -and ([datetime]$_.lastSyncDateTime -lt $fechaLimite)
}

$inactivosAAD = $allDevicesAAD | Where-Object {
    $_.approximateLastSignInDateTime -and ([datetime]$_.approximateLastSignInDateTime -lt $fechaLimite)
}

Write-Host " - Intune inactivos: $($inactivosIntune.Count)"
Write-Host " - Entra ID inactivos: $($inactivosAAD.Count)"

$inactivosIntune | Export-Csv -Path "$basePath\Inactivos_Intune.csv" -NoTypeInformation -Encoding UTF8
$inactivosAAD | Export-Csv -Path "$basePath\Inactivos_AzureAD.csv" -NoTypeInformation -Encoding UTF8

# ==========================
# MDM OFFICE 365 MOBILE
# ==========================
Write-Host "`nIdentificando dispositivos con MDM Office 365 Mobile..."
$office365MobileMDMAppId = "7add3ecd-5b01-452e-b4bf-cdaf9df1d097"

$mdmOfficeDevices = $allDevicesAAD | Where-Object {
    $_.mdmAppId -eq $office365MobileMDMAppId
}

Write-Host "Total dispositivos con MDM Office 365 Mobile: $($mdmOfficeDevices.Count)"

$mdmOfficeDevices | Export-Csv -Path "$basePath\Dispositivos_MDM_Office365Mobile_$fecha.csv" -NoTypeInformation -Encoding UTF8

# ==========================
# BLOQUE 1: ELIMINAR INACTIVOS INTUNE + ENTRA ID
# ==========================
Write-Host "`n--------------------------------------------------------"
Write-Host "Detectando dispositivos inactivos (sin sincronizacion con Intune desde 2024 o antes)..."

$fechaLimite = Get-Date "2024-12-31"

# Buscar inactivos en Intune
$inactivosIntune = $allManagedDevices | Where-Object {
    $_.lastSyncDateTime -and ([datetime]$_.lastSyncDateTime -lt $fechaLimite)
}

Write-Host "Total dispositivos inactivos detectados en Intune: $($inactivosIntune.Count)"

# Exportar lista para revision
$exportPathMDM = "$basePath\Dispositivos_Inactivos_Intune_$fecha.csv"
$inactivosIntune |
    Select-Object deviceName, operatingSystem, lastSyncDateTime, azureADDeviceId, id |
    Export-Csv -Path $exportPathMDM -NoTypeInformation -Encoding UTF8

Write-Host "`nLista exportada para revision: $exportPathMDM"

# Mostrar ordenados por nombre
$inactivosIntune_Ordenados = $inactivosIntune | Sort-Object deviceName

foreach ($device in $inactivosIntune_Ordenados) {
    $lastSync = if ($device.lastSyncDateTime) { [datetime]$device.lastSyncDateTime } else { "Sin datos" }
    Write-Host " - $($device.deviceName) | $($device.operatingSystem) | Ultima sincronizacion: $lastSync"
}

# Confirmar eliminacion
$confirm = Read-Host "`n¿Deseas eliminar TODOS estos dispositivos inactivos de Intune y Entra ID? (S/N)"

if ($confirm -match "^[sS]$") {
    Write-Host "`nIniciando eliminacion de dispositivos inactivos..."

    foreach ($device in $inactivosIntune_Ordenados) {
        Write-Host "`nProcesando: $($device.deviceName)"
        $eliminadoIntune = $false
        $eliminadoAAD = $false

        # --- Eliminar de Intune ---
        if ($device.id) {
            try {
                Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($device.id)" -Headers $headers -Method DELETE
                Write-Host "Eliminado de Intune"
                $eliminadoIntune = $true
            } catch {
                Write-Warning "Error al eliminar de Intune: $_"
            }
        }

        # --- Buscar y eliminar de Entra ID ---
        if ($device.azureADDeviceId) {
            $aadDevice = $allDevicesAAD | Where-Object { $_.deviceId -eq $device.azureADDeviceId }
            if ($aadDevice) {
                try {
                    Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/devices/$($aadDevice.id)" -Headers $headers -Method DELETE
                    Write-Host "Eliminado de Entra ID"
                    $eliminadoAAD = $true
                } catch {
                    Write-Warning "Error al eliminar de Entra ID: $_"
                }
            } else {
                Write-Host "No se encontro en Entra ID (solo en Intune)"
            }
        }

        # --- Resultado final ---
        if (-not $eliminadoIntune -and -not $eliminadoAAD) {
            Write-Warning "No se pudo eliminar el dispositivo: $($device.deviceName)"
        }
    }

    Write-Host "`nProceso completado. Se eliminaron todos los dispositivos inactivos disponibles."
} else {
    Write-Host "`nOperacion cancelada."
}
# ==========================
# BLOQUE 1.1: ELIMINAR INACTIVOS SOLO EN ENTRA ID
# ==========================
Write-Host "`n--------------------------------------------------------"
Write-Host "Detectando dispositivos inactivos que solo existen en Entra ID..."

# Tomamos la misma fecha limite
$fechaLimite = Get-Date "2024-12-31"

# Buscar inactivos en Entra ID
$inactivosAAD = $allDevicesAAD | Where-Object {
    $_.approximateLastSignInDateTime -and ([datetime]$_.approximateLastSignInDateTime -lt $fechaLimite)
}

# Excluir los que ya se eliminaron (los que estaban en Intune y fueron tratados en bloque 1)
$inactivosSoloAAD = $inactivosAAD | Where-Object {
    $id = $_.deviceId
    -not ($inactivosIntune | Where-Object { $_.azureADDeviceId -eq $id })
}

Write-Host "Total dispositivos inactivos solo en Entra ID: $($inactivosSoloAAD.Count)"

# Exportar lista para revision
$exportPathSoloAAD = "$basePath\Dispositivos_Inactivos_Solo_EntraID_$fecha.csv"
$inactivosSoloAAD |
    Select-Object displayName, operatingSystem, trustType, managementType,
                  registrationDateTime, approximateLastSignInDateTime, deviceId, id |
    Export-Csv -Path $exportPathSoloAAD -NoTypeInformation -Encoding UTF8

Write-Host "`nLista exportada para revision: $exportPathSoloAAD"

# Mostrar ordenados por nombre
$inactivosSoloAAD_Ordenados = $inactivosSoloAAD | Sort-Object displayName

foreach ($device in $inactivosSoloAAD_Ordenados) {
    $lastSeen = if ($device.approximateLastSignInDateTime) { [datetime]$device.approximateLastSignInDateTime } else { "Sin datos" }
    Write-Host " - $($device.displayName) | $($device.operatingSystem) | ultimo inicio: $lastSeen"
}

# Confirmar eliminacion
$confirm = Read-Host "`n¿Deseas eliminar estos dispositivos inactivos solo en Entra ID? (S/N)"

if ($confirm -match "^[sS]$") {
    Write-Host "`nIniciando eliminacion de dispositivos inactivos solo en Entra ID..."

    foreach ($device in $inactivosSoloAAD_Ordenados) {
        Write-Host "`nEliminando: $($device.displayName)"

        try {
            Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/devices/$($device.id)" -Headers $headers -Method DELETE
            Write-Host "Eliminado de Entra ID"
        } catch {
            Write-Warning "Error al eliminar de Entra ID: $_"
        }
    }

    Write-Host "`nProceso completado. Se eliminaron todos los dispositivos inactivos que solo estaban en Entra ID."
} else {
    Write-Host "`nOperacion cancelada."
}


# ==========================
# BLOQUE 2: ELIMINAR HUERFANOS (sin registrationDateTime ni Intune)
# ==========================
Write-Host "`n--------------------------------------------------------"
Write-Host "Filtrando dispositivos sin registrationDateTime y sin Intune..."

# Crear listas seguras de IDs y nombres de Intune
$intuneIds = $allManagedDevices.azureADDeviceId | Where-Object { $_ } | ForEach-Object { $_.ToLower() }
$intuneNames = $allManagedDevices.deviceName | Where-Object { $_ } | ForEach-Object { $_.ToLower() }

# Filtrar huerfanos reales
$sinRegistro = $allDevicesAAD | Where-Object {
    $_.registrationDateTime -eq $null -and
    $_.managementType -ne "MicrosoftSense" -and
    $_.operatingSystem -notlike "*Server*" -and
    (
        (
            -not $_.deviceId -or
            ($_.deviceId.ToLower() -notin $intuneIds)
        ) -and
        (
            -not $_.displayName -or
            ($_.displayName.ToLower() -notin $intuneNames)
        )
    )
}

Write-Host "Total dispositivos sin registro ni Intune: $($sinRegistro.Count)"

# Exportar para revision
$exportPathSinRegistro = "$basePath\Dispositivos_Sin_Registro_$fecha.csv"
$sinRegistro |
    Select-Object displayName, operatingSystem, trustType, managementType,
                  registrationDateTime, approximateLastSignInDateTime, mdmAppId, deviceId, azureADDeviceId |
    Export-Csv -Path $exportPathSinRegistro -NoTypeInformation -Encoding UTF8

Write-Host "`nLista exportada para revision: $exportPathSinRegistro"
Write-Host "--------------------------------------------------------"
Write-Host "Dispositivos sin registro (huerfanos):"
Write-Host "--------------------------------------------------------"
Write-Host " "
Write-Host "Acuerdate de eliminar los objetos en el Active Directory" -ForegroundColor Yellow
Write-Host " "

# Ordenar alfabeticamente por nombre de dispositivo
$sinRegistro_Ordenados = $sinRegistro | Sort-Object displayName

foreach ($device in $sinRegistro_Ordenados) {
    Write-Host " - $($device.displayName) | $($device.operatingSystem) | ManagementType: $($device.managementType)"
}


# Confirmacion del bloque
Write-Host "`n--------------------------------------------------------"
$confirmSinRegistro = Read-Host "Deseas eliminar los dispositivos SIN registro ni Intune? (S/N)"

if ($confirmSinRegistro -match "^[sS]$") {
    Write-Host "`nIniciando eliminacion de dispositivos sin registro..."

    foreach ($device in $sinRegistro) {
        Write-Host "`nEliminando: $($device.displayName)"

        # Comprobar una ultima vez si existe en Intune
        $intuneDevice = $allManagedDevices | Where-Object {
            ($_.azureADDeviceId -eq $device.deviceId) -or
            ($_.deviceName -eq $device.displayName)
        }

        if ($intuneDevice) {
            Write-Warning "Se encontro en Intune, saltando eliminacion: $($device.displayName)"
            continue
        }

        # Eliminar de Entra ID
        try {
            Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/devices/$($device.id)" -Headers $headers -Method DELETE
            Write-Host "Eliminado de Entra ID (Azure AD)"
        } catch {
            Write-Warning "Error al eliminar de Entra ID: $_"
        }
    }

    Write-Host "`nEliminacion completada para dispositivos huerfanos."
} else {
    Write-Host "`nOperacion cancelada: no se eliminaron los dispositivos sin registro."
}

# ==========================
# BLOQUE 3: DISPOSITIVOS CON TRUSTTYPE = WORKPLACE
# ==========================
Write-Host "`n--------------------------------------------------------"
Write-Host "Filtrando dispositivos con trustType = Workplace..."

$workplaceDevices = $allDevicesAAD | Where-Object {
    $_.trustType -eq "Workplace" -and
    $_.operatingSystem -notlike "*Server*" -and
    $_.operatingSystem -like "Windows*" -and
    $_.managementType -ne "MDM"
}

Write-Host "Total dispositivos con trustType Workplace: $($workplaceDevices.Count)"

# Exportar a CSV
$exportPathWorkplace = "$basePath\Dispositivos_TrustType_Workplace_$fecha.csv"
$workplaceDevices |
    Select-Object displayName, operatingSystem, trustType, managementType,
                  registrationDateTime, approximateLastSignInDateTime, mdmAppId, deviceId, azureADDeviceId |
    Export-Csv -Path $exportPathWorkplace -NoTypeInformation -Encoding UTF8

Write-Host "`nLista exportada para revision: $exportPathWorkplace"
Write-Host "--------------------------------------------------------"
Write-Host "Dispositivos Workplace:"
Write-Host "--------------------------------------------------------"

# Ordenar alfabeticamente por nombre
$workplaceDevices_Ordenados = $workplaceDevices | Sort-Object displayName

foreach ($device in $workplaceDevices_Ordenados) {
    Write-Host " - $($device.displayName) | $($device.operatingSystem) | LastLogon: $($device.approximateLastSignInDateTime)"
}


# Confirmacion del bloque
Write-Host "`n--------------------------------------------------------"
$confirmWorkplace = Read-Host "Deseas eliminar los dispositivos Registered? (S/N)"

if ($confirmWorkplace -match "^[sS]$") {
    Write-Host "`nIniciando eliminacion de dispositivos Workplace..."

    foreach ($device in $workplaceDevices) {
        Write-Host "`nEliminando: $($device.displayName)"

        # Comprobar si esta en Intune para evitar borrar activos
        $intuneDevice = $allManagedDevices | Where-Object {
            ($_.azureADDeviceId -eq $device.deviceId) -or
            ($_.deviceName -eq $device.displayName)
        }

        if ($intuneDevice) {
            Write-Warning "Se encontro en Intune, saltando eliminacion: $($device.displayName)"
            continue
        }

        # Eliminar de Entra ID
        try {
            Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/devices/$($device.id)" -Headers $headers -Method DELETE
            Write-Host "Eliminado de Entra ID (Azure AD)"
        } catch {
            Write-Warning "Error al eliminar de Entra ID: $_"
        }
    }

    Write-Host "`nEliminacion completada para dispositivos Workplace."
} else {
    Write-Host "`nOperacion cancelada: no se eliminaron los dispositivos Workplace."
}

# ==========================
# BLOQUE 4: DISPOSITIVOS REGISTERED Y ADMINISTRADOS POR INTUNE (MDM)
# ==========================
Write-Host "`n--------------------------------------------------------"
Write-Host "Filtrando dispositivos Registered y administrados por Intune (MDM)..."

$registeredMDMDevices = $allDevicesAAD | Where-Object {
    $_.trustType -eq "Workplace" -and
    $_.managementType -eq "MDM" -and
    $_.operatingSystem -notlike "*Server*" -and
    $_.operatingSystem -like "Windows*"
}

Write-Host "Total dispositivos con trustType Registered y administrados por Intune (MDM): $($registeredMDMDevices.Count)"

# Exportar a CSV
$exportPathRegistered = "$basePath\Dispositivos_TrustType_Registered_MDM_$fecha.csv"
$registeredMDMDevices |
    Select-Object displayName, operatingSystem, trustType, managementType,
                  registrationDateTime, approximateLastSignInDateTime, mdmAppId, deviceId, azureADDeviceId |
    Export-Csv -Path $exportPathRegistered -NoTypeInformation -Encoding UTF8

Write-Host "`nLista exportada para revision: $exportPathRegistered"
Write-Host "--------------------------------------------------------"
Write-Host "Dispositivos Registered y administrados por Intune (requieren revision):"
Write-Host "--------------------------------------------------------"

# Ordenar alfabeticamente por nombre
$registeredMDMDevices_Ordenados = $registeredMDMDevices | Sort-Object displayName

foreach ($device in $registeredMDMDevices_Ordenados) {
    Write-Host " - $($device.displayName) | $($device.operatingSystem) | ManagementType: $($device.managementType)"
}

# ==========================
# BLOQUE 5: ELIMINAR DUPLICADOS EN INTUNE (POR NUMERO DE SERIE)
# ==========================
Write-Host "`n--------------------------------------------------------"
Write-Host "Buscando dispositivos duplicados en Intune (por numero de serie)..."

# Filtrar los dispositivos que tienen numero de serie valido
$devicesConSerie = $allManagedDevices | Where-Object { 
    $_.serialNumber -and $_.serialNumber -ne "" 
}

# Agrupar por numero de serie y quedarnos con los que aparecen mas de una vez
$duplicados = $devicesConSerie | Group-Object serialNumber | Where-Object { $_.Count -gt 1 }

if ($duplicados.Count -eq 0) {
    Write-Host "No se encontraron dispositivos duplicados por numero de serie."
} else {
    Write-Host "Total numeros de serie duplicados detectados: $($duplicados.Count)"

    $duplicadosParaEliminar = @()

    foreach ($grupo in $duplicados) {
        $serial = $grupo.Name
        $dispositivos = $grupo.Group

        # Ordenar por fecha de sincronizacion descendente (mas reciente primero)
        $ordenados = $dispositivos | Sort-Object -Property {[datetime]$_.lastSyncDateTime} -Descending

        # El primero es el mas reciente, se conserva
        $aConservar = $ordenados[0]
        $aEliminar = $ordenados | Select-Object -Skip 1

        Write-Host "`nNumero de serie: $serial"
        Write-Host " - Conservando: $($aConservar.deviceName) (sincronizado: $($aConservar.lastSyncDateTime))"

        foreach ($d in $aEliminar) {
            Write-Host " - Eliminando: $($d.deviceName) (sincronizado: $($d.lastSyncDateTime))"
            $duplicadosParaEliminar += $d
        }
    }

    Write-Host "`nTotal de dispositivos a eliminar por duplicado: $($duplicadosParaEliminar.Count)"

    # Exportar a CSV para registro
    $exportPathDuplicados = "$basePath\Dispositivos_Duplicados_Intune_$fecha.csv"
    $duplicadosParaEliminar |
        Select-Object deviceName, serialNumber, lastSyncDateTime, azureADDeviceId, id |
        Export-Csv -Path $exportPathDuplicados -NoTypeInformation -Encoding UTF8

    Write-Host "`nLista exportada para revision: $exportPathDuplicados"

    # Confirmacion de eliminacion
    $confirm = Read-Host "`nDeseas eliminar los dispositivos duplicados en Intune (manteniendo el mas reciente)? (S/N)"

    if ($confirm -match "^[sS]$") {
        Write-Host "`nIniciando eliminacion de duplicados en Intune..."

        foreach ($device in $duplicadosParaEliminar) {
            try {
                Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($device.id)" -Headers $headers -Method DELETE
                Write-Host "Eliminado de Intune: $($device.deviceName)"
            } catch {
                Write-Warning "Error al eliminar de Intune: $_"
            }
        }

        Write-Host "`nProceso completado. Se eliminaron los duplicados de Intune."
    } else {
        Write-Host "`nOperacion cancelada."
    }
}
