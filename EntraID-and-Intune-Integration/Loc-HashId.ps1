<#
.SYNOPSIS
    Script para gestionar dispositivos en Azure AD y Autopilot.

.DESCRIPTION
    Este script permite buscar dispositivos en Azure Active Directory por nombre. 
    Al buscar por nombre, se obtiene el ZTDID del dispositivo en Autopilot y se 
    muestra la información de los propietarios asociados a ese ZTDID. 

.EXAMPLE
    Introduce el nombre del dispositivo: AutoPilot-PC

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 02/04/2025
    Versión: 1.0
    Requiere conexión a Microsoft Graph con los permisos "Device.Read.All" y "User.Read.All".

#>

# Verificar si ya hay una conexion a Microsoft Graph
if (-not (Get-MgContext)) {
    Write-Host "Conectando a Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "Group.ReadWrite.All", "User.Read.All", "Device.Read.All"
} else {
    Write-Host "Ya hay una sesion activa en Microsoft Graph." -ForegroundColor Green
}

# Pedir el nombre del dispositivo
$deviceName = Read-Host "Introduce el nombre del dispositivo"

# Buscar dispositivos en Azure AD con ese nombre
$azureDevices = Get-MgDevice -Filter "displayName eq '$deviceName'"

if ($azureDevices) {
    Write-Host "`nSe encontraron $($azureDevices.Count) dispositivos con el nombre '$deviceName'." -ForegroundColor Cyan

    # Obtener todos los dispositivos de Autopilot
    $autopilotDevices = Get-AutopilotDevice

    # Lista para almacenar ZTDID únicos ya revisados
    $checkedZTDIDs = @()

    foreach ($device in $azureDevices) {
        # Extraer ZTDID de PhysicalIds
        $ztdid = ($device.PhysicalIds -match "ZTDID") -replace "\[ZTDID\]:", ""

        if ($ztdid -and $checkedZTDIDs -notcontains $ztdid) {
            Write-Host "`nDispositivo con ZTDID: $ztdid" -ForegroundColor Green

            # Buscar en Autopilot por ZTDID
            $matchingDevice = $autopilotDevices | Where-Object { $_.Id -eq $ztdid }

            if ($matchingDevice) {
                Write-Host "`nDispositivo encontrado en Autopilot:" -ForegroundColor Cyan
                Write-Host "------------------------------------" -ForegroundColor DarkGray
                Write-Host "ZTDID: $ztdid" -ForegroundColor Yellow
                Write-Host "Autopilot Device ID: $($matchingDevice.Id)" -ForegroundColor Yellow
                Write-Host "Modelo: $($matchingDevice.Model)" -ForegroundColor Yellow
                Write-Host "Fabricante: $($matchingDevice.Manufacturer)" -ForegroundColor Yellow
                Write-Host "Numero de Serie: $($matchingDevice.SerialNumber)" -ForegroundColor Yellow
                Write-Host "------------------------------------" -ForegroundColor DarkGray
            } else {
                Write-Host "`nNo se encontro un dispositivo en Autopilot con ese ZTDID." -ForegroundColor Red
            }

            # Agregar el ZTDID a la lista de revisados
            $checkedZTDIDs += $ztdid
        }
    }

    # Si no se encontró ningún ZTDID en Autopilot
    if ($checkedZTDIDs.Count -eq 0) {
        Write-Host "`nNinguno de los dispositivos con el nombre '$deviceName' tiene un ZTDID registrado en Autopilot." -ForegroundColor Red
    }
} else {
    Write-Host "`nNo se encontraron dispositivos en Azure AD con ese nombre." -ForegroundColor Red
}
