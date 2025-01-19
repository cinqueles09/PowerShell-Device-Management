# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 25/05/2024
# Descripción:Este script automatiza la recopilación de información de dispositivos en Active Directory (AD) e Intune. Recorre todos los equipos en AD, exportando detalles como nombre del dispositivo, 
#             versión del sistema operativo, último inicio de sesión, y usuario primario, y los cruza con los datos disponibles en Intune. 
#             Posteriormente, realiza la misma operación para los dispositivos que están únicamente registrados en Intune, asegurando así una visión completa de los dispositivos gestionados.

# Requiere módulo de Microsoft.Graph y Active Directory para ejecutarse

# Obtener los dispositivos de AD
$adComputers = Get-ADComputer -Filter * -Properties LastLogon

# Crear lista para almacenar los dispositivos con los datos combinados
$deviceInfoList = @()

# Primero, procesamos los dispositivos que están en AD
foreach ($adComputer in $adComputers) {
    # Nombre del dispositivo en AD
    $deviceName = $adComputer.Name

    # Obtener el último inicio de sesión de AD
    $lastLogon = if ($adComputer.LastLogon -ne $null) { 
        [DateTime]::FromFileTime($adComputer.LastLogon)
    } else {
        "No encontrado en AD"
    }

    # Consultar la API de Intune (Graph) para obtener los detalles del dispositivo
    $response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=deviceName eq '$deviceName'"

    # Verificar si la respuesta de Intune contiene datos
    if ($response.value) {
        $device = $response.value[0]  # Tomamos el primer dispositivo que coincida con el nombre

        # Crear el objeto con los datos combinados
        $deviceInfoList += [PSCustomObject]@{
            DeviceId       = $device["AzureADDeviceId"]
            DeviceName     = $deviceName
            PrimaryUser    = $device["userPrincipalName"]
            OSVersion      = $device["osVersion"]
            LastCheckIn    = $device["lastSyncDateTime"]
            LastLogon      = $lastLogon
        }
    } else {
        # Si no se encuentra el dispositivo en Intune, incluir los datos de AD solamente
        $deviceInfoList += [PSCustomObject]@{
            DeviceId       = "No encontrado en Intune"
            DeviceName     = $deviceName
            PrimaryUser    = "No encontrado en Intune"
            OSVersion      = "No encontrado en Intune"
            LastCheckIn    = "No encontrado en Intune"
            LastLogon      = $lastLogon
        }
    }
}

# Ahora procesamos los dispositivos que están SOLO en Intune, no en AD
$allIntuneDevices = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
$intuneDeviceNames = $allIntuneDevices.value.deviceName

# Filtrar los dispositivos que NO están en AD
$intuneOnlyDevices = foreach ($device in $allIntuneDevices.value) {
    $deviceName = $device.deviceName

    # Comprobar si el dispositivo está en AD (ya lo procesamos)
    $adDevice = $adComputers | Where-Object { $_.Name -eq $deviceName }

    # Si no está en AD, lo agregamos a la lista de dispositivos solo en Intune
    if (-not $adDevice) {
        [PSCustomObject]@{
            DeviceId       = $device["AzureADDeviceId"]
            DeviceName     = $deviceName
            PrimaryUser    = $device["userPrincipalName"]
            OSVersion      = $device["osVersion"]
            LastCheckIn    = $device["lastSyncDateTime"]
            LastLogon      = "No disponible (solo en Intune)"
        }
    }
}

# Combinar los dispositivos de AD con los de Intune que no estaban en AD
$deviceInfoList += $intuneOnlyDevices

# Mostrar la información en consola
$deviceInfoList

# Exportar los datos a un archivo CSV
$deviceInfoList | Export-Csv -Path "AllADAndIntuneDevices.csv" -NoTypeInformation -Encoding UTF8
Write-Output "Datos combinados de AD e Intune exportados a AllADAndIntuneDevices.csv"
