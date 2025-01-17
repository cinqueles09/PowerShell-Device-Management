#Conexión a Graph
Connect-MgGraph -Scopes "DeviceManagementApps.Read.All DeviceManagementManagedDevices.ReadWrite.All Directory.ReadWrite.All"

# Lista de IDs de aplicaciones detectadas
$AppDetectIds = @(
    "0000280454765080393b6d697d9be5287cb00000ffff", # ID de la aplicación 1
    "722603f8ca318e4de02e55a8a268f06687524108ad40eefcf890edce7e74d116",   # ID de la aplicación 2
    "00008ce343a8466b5f55b26e93ba70c0aaa50000ffff"    # ID de la aplicación 3
)

# Obtener los dispositivos deseados
$AllDevice = Get-MgDevice -All | Where-Object { $_.TrustType -ne "Workplace" } | Select-Object id, DisplayName

# Crear un diccionario para almacenar las aplicaciones por dispositivo
$DeviceApplications = @{}

# Iterar sobre cada ID de aplicación
foreach ($AppDetectId in $AppDetectIds) {
    # Obtener el nombre de la aplicación detectada
    $AppName = (Get-MgDeviceManagementDetectedApp -DetectedAppId $AppDetectId).DisplayName
    Write-Host "Procesando aplicación detectada: $AppName (ID: $AppDetectId)"

    # Obtener los dispositivos asignados a la aplicación
    $ManagedDevices = Get-MgDeviceManagementDetectedAppManagedDevice -DetectedAppId $AppDetectId

    if ($ManagedDevices) {
        Write-Host "Dispositivos asignados a la aplicación '$AppName': $($ManagedDevices.Count)"

        # Iterar sobre cada dispositivo
        foreach ($Device in $ManagedDevices) {
            # Buscar el dispositivo en la lista global
            $DeviceMatch = $AllDevice | Where-Object { $_.DisplayName -like $Device.DeviceName }
            
            if ($DeviceMatch) {
                # Inicializar la lista de aplicaciones si no existe para este dispositivo
                if (-not $DeviceApplications.ContainsKey($DeviceMatch.id)) {
                    $DeviceApplications[$DeviceMatch.id] = @()
                }

                # Agregar la aplicación detectada a la lista de aplicaciones del dispositivo
                $DeviceApplications[$DeviceMatch.id] += $AppName
            } else {
                Write-Host "No se encontró el dispositivo '$($Device.DeviceName)' en la lista de dispositivos."
            }
        }
    } else {
        Write-Host "No se encontraron dispositivos asignados a la aplicación con ID $AppDetectId."
    }
}

# Actualizar los dispositivos con cada aplicación en un atributo único
foreach ($DeviceId in $DeviceApplications.Keys) {
    $AppList = $DeviceApplications[$DeviceId] # Lista de aplicaciones detectadas para el dispositivo
    Write-Host "Actualizando dispositivo $DeviceId con aplicaciones: $($AppList -join ', ')"

    # Preparar los atributos dinámicamente
    $Attributes = @{
        "extensionAttributes" = @{}
    }

    # Mapear aplicaciones a los atributos extensionAttribute1, extensionAttribute2, etc.
    for ($i = 0; $i -lt $AppList.Count; $i++) {
        $AttributeName = "extensionAttribute$($i + 1)"
        $Attributes["extensionAttributes"][$AttributeName] = $AppList[$i]
    }

    # Convertir a JSON
    $AttributesJson = $Attributes | ConvertTo-Json -Depth 2

    # Actualizar el dispositivo
    try {
        Update-MgDevice -DeviceId $DeviceId -BodyParameter $AttributesJson
        Write-Host "Dispositivo actualizado: $DeviceId con aplicaciones: $($AppList -join ', ')"
    } catch {
        Write-Host "Error al actualizar el dispositivo $DeviceId. Error: $_"
    }
}
