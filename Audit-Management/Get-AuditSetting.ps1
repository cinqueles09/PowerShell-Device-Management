<#
.SYNOPSIS
    Auditoría del entorno Intune.

.DESCRIPTION
    Este script está diseñado para realizar una revisión detallada de los aspectos más importantes de la configuración actual en Intune. 
    Su objetivo es facilitar la identificación de configuraciones críticas y proporcionar un análisis que sirva como punto de partida para llevar a 
    cabo una auditoría exhaustiva. Al evaluar la configuración existente, el script permite a los administradores y equipos de seguridad establecer 
    un marco claro para las mejoras y optimizaciones necesarias en la gestión de dispositivos y aplicaciones.

.NOTES
    Author: Ismael Morilla Orellana
    Date: 29/03/2025
    Version: 1.0
#>


# Conectar a Microsoft Graph con permisos especificos
#Connect-MgGraph -Scopes @(
#    "DeviceManagementManagedDevices.Read.All",
#    "DeviceManagement.DeviceConfigurations.Read.All",
#    "DeviceManagement.DeviceCompliancePolicies.Read.All",
#    "DeviceAppManagement.Read.All",
#    "DeviceAppManagement.ManagedAppConfigurations.Read.All",
#    "DeviceAppManagement.ManagedAppPolicies.Read.All"
#)

# Tu codigo para obtener datos de Microsoft Graph va aqui

# Definir la ruta de la carpeta para los CSV
$csvFolderPath = "$env:USERPROFILE\Documents\AuditoriaIntuneCSV"

# Verificar si la carpeta existe, si no, crearla
if (-Not (Test-Path -Path $csvFolderPath)) {
    New-Item -Path $csvFolderPath -ItemType Directory
    Write-Host "Carpeta creada en: $csvFolderPath" -ForegroundColor Green
} else {
    Write-Host "La carpeta ya existe: $csvFolderPath" -ForegroundColor Yellow
}


# Definir las URIs para obtener datos
$managedDevicesUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"
$compliancePoliciesUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies"
$configurationPoliciesUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations"
$autopilotProfilesUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"

# Inicializar contadores
$totalDevices = 0
$totalCompliant = 0
$totalNonCompliant = 0
$totalGracePeriod = 0
$totalIntuneManaged = 0
$totalMDEManaged = 0

# Realizar la solicitud a Microsoft Graph para obtener dispositivos gestionados
try {
    $response = Invoke-MgGraphRequest -Method GET -Uri $managedDevicesUri -ErrorAction Stop

    if ($response.value -ne $null) {
        $totalDevices = $response.value.Count

        foreach ($device in $response.value) {
            # Contar dispositivos segun su estado de cumplimiento
            if ($device.complianceState -eq "compliant") {
                $totalCompliant++
            } elseif ($device.complianceState -eq "nonCompliant") {
                $totalNonCompliant++
            } elseif ($device.complianceState -eq "gracePeriod") {
                $totalGracePeriod++
            }

            # Contar si estan administrados por Intune o MDE
            if ($device.managementAgent -eq "mdm") {
                $totalIntuneManaged++
            } elseif ($device.managementAgent -eq "mde") {
                $totalMDEManaged++
            }
        }
    } else {
        Write-Host "No se encontraron dispositivos gestionados."
    }
} catch {
    Write-Host "Error al obtener dispositivos gestionados: $_"
}

# Mostrar resultados de dispositivos
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "         Resultados de Auditoria de Intune    " -ForegroundColor Yellow
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ("Total de dispositivos:                " + $totalDevices) 
Write-Host ("Dispositivos compliant:       " + $totalCompliant) -ForegroundColor Green
Write-Host ("Dispositivos non-compliant:   " + $totalNonCompliant) -ForegroundColor Red
Write-Host ("Dispositivos en periodo de gracia: " + $totalGracePeriod) 
Write-Host ("Dispositivos administrados por Intune: " + $totalIntuneManaged)
Write-Host ("Dispositivos administrados por MDE: " + $totalMDEManaged)

# Inicializar lista para almacenar politicas de cumplimiento
$compliancePoliciesList = @()

# Obtener politicas de cumplimiento
try {
    $policiesResponse = Invoke-MgGraphRequest -Method GET -Uri $compliancePoliciesUri -ErrorAction Stop

    if ($policiesResponse.value -ne $null) {
        Write-Host "===============================================" -ForegroundColor Cyan
        Write-Host "         Directivas de Cumplimiento            " -ForegroundColor Yellow
        Write-Host "===============================================" -ForegroundColor Cyan

        foreach ($policy in $policiesResponse.value) {
            # Determinar la plataforma usando @odata.type
            $platform = switch ($policy.'@odata.type') {
                "#microsoft.graph.windows10CompliancePolicy" { "Windows 10" }
                "#microsoft.graph.windows10XCompliancePolicy" { "Windows 10X" }
                "#microsoft.graph.androidCompliancePolicy" { "Android" }
                "#microsoft.graph.iosCompliancePolicy" { "iOS" }
                "#microsoft.graph.macOSCompliancePolicy" { "macOS" }
                default { "Desconocido" }
            }

            # Obtener asignaciones para la politica actual
            $assignmentsUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$($policy.id)/assignments"
            try {
                $assignmentsResponse = Invoke-MgGraphRequest -Method GET -Uri $assignmentsUri -ErrorAction Stop
                
                if ($assignmentsResponse.value -ne $null) {
                    $groupAssignments = @()
                    foreach ($assignment in $assignmentsResponse.value) {
                        $targetType = $assignment.target.'@odata.type'
                        $assignmentGroup = switch ($targetType) {
                            "#microsoft.graph.allDevicesAssignmentTarget" { "Todos los Dispositivos" }
                            "#microsoft.graph.allLicensedUsersAssignmentTarget" { "Todos los Usuarios Licenciados" }
                            "#microsoft.graph.groupAssignmentTarget" { 
                                "Grupo Especifico (ID: $($assignment.target.groupId))" 
                            }
                            default { "Tipo de Asignacion Desconocido" }
                        }
                        $groupAssignments += $assignmentGroup
                    }
                    $groupAssignmentsString = $groupAssignments -join ", "
                } else {
                    $groupAssignmentsString = "No asignaciones"
                }
            } catch {
                $groupAssignmentsString = "Error al obtener asignaciones"
            }

            # Mostrar la informacion con colores
            Write-Host -NoNewline ("- ID: ") 
            Write-Host -NoNewline ($policy.id) -ForegroundColor Yellow
            Write-Host -NoNewline (" | Nombre: ") 
            Write-Host -NoNewline ($policy.displayName) -ForegroundColor Yellow
            Write-Host -NoNewline (" | Plataforma: ")
            Write-Host -NoNewline ($platform) -ForegroundColor Yellow
            Write-Host -NoNewline (" | Asignaciones: " )
            Write-Host ($groupAssignmentsString) -ForegroundColor Yellow

            # Agregar la politica a la lista para exportar
            $compliancePoliciesList += [PSCustomObject]@{
                ID           = $policy.id
                Nombre       = $policy.displayName
                Plataforma   = $platform
                Asignaciones = $groupAssignmentsString
            }
        }

        # Exportar la lista a CSV
        $csvPath = "$csvFolderPath\politicas_cumplimiento.csv"
        $compliancePoliciesList | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nLas politicas de cumplimiento han sido exportadas a CSV en: $csvPath" -ForegroundColor Green

    } else {
        Write-Host "No se encontraron directivas de cumplimiento." -ForegroundColor Red
    }
} catch {
    Write-Host "Error al obtener directivas de cumplimiento: $_" -ForegroundColor Red
}


# Definir URIs de las API para obtener politicas de configuracion
$uris = @(
    "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies",
    "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
)

# Lista para almacenar todas las politicas
$allPolicies = @()

# Obtener politicas de ambas rutas
foreach ($uri in $uris) {
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri

        if ($response.value -ne $null) {
            $allPolicies += $response.value | ForEach-Object {
                # Determinar plataforma y tipo de configuracion
                $platform = switch ($_. '@odata.type') {
                    "#microsoft.graph.androidGeneralDeviceConfiguration" { "Android (General)" }
                    "#microsoft.graph.androidWorkProfileGeneralDeviceConfiguration" { "Android Work Profile" }
                    "#microsoft.graph.androidDeviceOwnerGeneralDeviceConfiguration" { "Android Device Owner" }
                    "#microsoft.graph.iosGeneralDeviceConfiguration" { "iOS" }
                    "#microsoft.graph.macOSCustomConfiguration" { "macOS" }
                    "#microsoft.graph.windows10CustomConfiguration" { "Windows 10 Custom" }
                    default { "Windows" }
                }

                [PSCustomObject]@{
                    ID           = $_.id
                    Nombre       = if ($uri -like "*deviceConfigurations") { $_.displayName } else { $_.name }
                    Plataforma   = $platform
                    UltimaModificacion = $_.lastModifiedDateTime
                    IsConfigurationPolicy = $uri -like "*configurationPolicies"
                }
            }
        }

        # Verificar si hay mas paginas de resultados
        $uri = $response.'@odata.nextLink'
    } while ($uri -ne $null)  # Continuar hasta que no haya mas paginas
}

# Lista para almacenar las politicas con sus asignaciones
$policyAssignments = @()

# Recorrer cada politica y obtener sus asignaciones
foreach ($policy in $allPolicies) {
    $policyId = $policy.ID  # Obtener el ID de la politica

    if ($policy.IsConfigurationPolicy) {
        # Para politicas de configuracion
        $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policyId)/assignments"
    } else {
        # Para configuraciones de dispositivos
        $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policyId)/groupAssignments"
    }

    try {
        $assignmentsResponse = Invoke-MgGraphRequest -Method GET -Uri $assignmentsUri -ErrorAction Stop
        
        if ($assignmentsResponse.value -ne $null -and $assignmentsResponse.value.Count -gt 0) {
            foreach ($assignment in $assignmentsResponse.value) {
                if ($policy.IsConfigurationPolicy) {
                    # Acceder al target para determinar el tipo de asignacion
                    $assignmentType = $assignment.target.'@odata.type'
                    $groupId = switch ($assignmentType) {
                        "#microsoft.graph.allDevicesAssignmentTarget" { "Asignada a todos los dispositivos" }
                        "#microsoft.graph.allLicensedUsersAssignmentTarget" { "Asignada a todos los usuarios" }
                        default { $assignment.target.groupId }
                    }
                } else {
                    # Para configuraciones de dispositivos
                    $groupId = if ($assignment.targetGroupId) { $assignment.targetGroupId } else { "Grupo desconocido" }
                }

                $policyAssignments += [PSCustomObject]@{
                    PolicyID     = $policyId
                    Nombre       = $policy.Nombre
                    Plataforma   = $policy.Plataforma
                    TargetGroup  = $groupId
                    UltimaModificacion = $policy.UltimaModificacion
                }
            }
        } else {
            # Politica sin asignaciones
            $policyAssignments += [PSCustomObject]@{
                PolicyID     = $policyId
                Nombre       = $policy.Nombre
                Plataforma   = $policy.Plataforma
                TargetGroup  = "Sin asignaciones"
                UltimaModificacion = $policy.UltimaModificacion
            }
        }
    } catch {
        Write-Host "Error obteniendo asignaciones para la politica con ID: $policyId"
        $policyAssignments += [PSCustomObject]@{
            PolicyID     = $policyId
            Nombre       = $policy.Nombre
            Plataforma   = $policy.Plataforma
            TargetGroup  = "Error en la solicitud"
            UltimaModificacion = $policy.UltimaModificacion
        }
    }
}

# Mostrar resultados en pantalla
if ($policyAssignments.Count -gt 0) {
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "           Politicas de Configuracion         " -ForegroundColor Yellow
    Write-Host "===============================================" -ForegroundColor Cyan
    $policyAssignments | Format-Table -AutoSize
} else {
    Write-Host "No se encontraron politicas." -ForegroundColor Red
}

# Exportar a CSV para politicas de configuracion
$DeviceConfigCsvPath = "$csvFolderPath\Device_config_policies.csv"
$policyAssignments | Export-Csv -Path $DeviceConfigCsvPath -NoTypeInformation -Encoding UTF8
Write-Host "Las politicas de configuracion han sido exportadas a CSV en: $DeviceConfigCsvPath" -ForegroundColor Green



# Definir la URI para obtener aplicaciones
$appsUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"

# Inicializar diccionario para contar aplicaciones por plataforma
$appCounts = @{
    "Windows"  = 0
    "Android"  = 0
    "Android - Tienda Privada" = 0
    "iOS"      = 0
    "macOS"    = 0
    "Desconocido" = 0
}

# Inicializar lista para almacenar detalles de aplicaciones
$appList = @()
$unknownTypes = @()  # Lista para guardar los tipos no reconocidos

try {
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $appsUri -ErrorAction Stop

        if ($response.value -ne $null) {
            foreach ($app in $response.value) {
                # Obtener el tipo de aplicacion
                $appType = $app.'@odata.type'

                # Determinar la plataforma segun el tipo de aplicacion
                $platform = switch ($appType) {
                    # Windows
                    "#microsoft.graph.windowsMobileMSI" { "Windows" }
                    "#microsoft.graph.win32LobApp" { "Windows" }
                    "#microsoft.graph.windowsUniversalAppX" { "Windows" }
                    "#microsoft.graph.winGetApp" { "Windows" }
                    "#microsoft.graph.officeSuiteApp" { "Windows" }

                    # iOS
                    "#microsoft.graph.iosLobApp" { "iOS" }
                    "#microsoft.graph.iosStoreApp" { "iOS" }

                    # macOS
                    "#microsoft.graph.macOSOfficeSuiteApp" { "macOS" }
                    "#microsoft.graph.mobileLobApp" { "macOS" }
                    "#microsoft.graph.macOSDmgApp" { "macOS" }
                    "#microsoft.graph.macOSLobApp" { "macOS" }
                    "#microsoft.graph.macOSPkgApp" { "macOS" }

                    # Android
                    "#microsoft.graph.androidManagedStoreApp" { "Android" }
                    "#microsoft.graph.androidLobApp" { "Android" }
                    "#microsoft.graph.androidForWorkApp" { "Android" }
                    "#microsoft.graph.androidStoreApp" { "Android" }
                    "#microsoft.graph.androidManagedStoreWebApp" { "Android" }

                    default { 
                        $unknownTypes += $appType  # Guardar tipo no reconocido
                        "Desconocido" 
                    }
                }

                # Si es una app de Android, revisar si es de la tienda privada
                if ($platform -eq "Android" -and $app.publisher -match "\(ID: .+, Web\)") {
                    $platform = "Android - Tienda Privada"
                }

                # Obtener asignaciones de la aplicacion
                $assignmentsUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/assignments"
                $groupName = "Sin asignacion"

                try {
                    $assignmentsResponse = Invoke-MgGraphRequest -Method GET -Uri $assignmentsUri -ErrorAction Stop
                    
                    if ($assignmentsResponse.value -ne $null -and $assignmentsResponse.value.Count -gt 0) {
                        $groupNames = @()

                        foreach ($assignment in $assignmentsResponse.value) {
                            if ($assignment.target.groupId) {
                                # Obtener el nombre del grupo
                                $groupUri = "https://graph.microsoft.com/beta/groups/$($assignment.target.groupId)"
                                $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $groupUri -ErrorAction SilentlyContinue

                                if ($groupResponse.displayName) {
                                    $groupNames += $groupResponse.displayName
                                } else {
                                    $groupNames += "Grupo no encontrado"
                                }
                            }
                        }

                        if ($groupNames.Count -gt 0) {
                            $groupName = $groupNames -join ", "  # Unir multiples asignaciones con coma
                        }
                    }
                } catch {
                    $groupName = "Error al obtener grupo"
                }

                # Incrementar el contador de la plataforma correspondiente
                $appCounts[$platform]++

                # Agregar la aplicacion a la lista con su nombre, plataforma y grupo asignado
                $appList += [PSCustomObject]@{
                    Nombre     = $app.displayName
                    Plataforma = $platform
                    Grupo      = $groupName
                }
            }
        }

        # Verificar si hay mas paginas de resultados
        $appsUri = $response.'@odata.nextLink'
    } while ($appsUri -ne $null)  # Continuar hasta que no haya mas paginas

    # Mostrar resumen del total de aplicaciones por plataforma
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "            Aplicaciones por Plataforma        " -ForegroundColor Yellow
    Write-Host "===============================================" -ForegroundColor Cyan
    $appCounts.GetEnumerator() | Sort-Object Name | Format-Table -AutoSize

    # Mostrar la lista detallada de aplicaciones con su nombre, plataforma y grupo asignado
    if ($appList.Count -gt 0) {
        Write-Host "`n===============================================" -ForegroundColor Cyan
        Write-Host "              Aplicaciones Detallada           " -ForegroundColor Yellow
        Write-Host "===============================================" -ForegroundColor Cyan
        $appList | Sort-Object Plataforma | Format-Table -AutoSize

        # Exportar a CSV para aplicaciones
        $applicationsCsvPath = "$csvFolderPath\applications.csv"
        $appList | Export-Csv -Path $applicationsCsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Las politicas de proteccion han sido exportadas a CSV en: $applicationsCsvPath" -ForegroundColor Green
    } else {
        Write-Host "No se encontraron aplicaciones." -ForegroundColor Red
    }

    # Mostrar tipos desconocidos encontrados
    if ($unknownTypes.Count -gt 0) {
        Write-Host "`n Tipos de aplicacion desconocidos encontrados:" -ForegroundColor Yellow
        $unknownTypes | Sort-Object | Get-Unique | Format-Table -AutoSize
    }

} catch {
    Write-Host "Error al obtener aplicaciones: $_" -ForegroundColor Red
}


# Definir la URI para obtener las politicas de configuracion de aplicaciones
$appConfigPoliciesUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations"

# Lista para almacenar las politicas de configuracion de aplicaciones
$appConfigPolicies = @()

try {
    do {
        # Realizar la solicitud a Microsoft Graph
        $response = Invoke-MgGraphRequest -Method GET -Uri $appConfigPoliciesUri -ErrorAction Stop

        if ($response.value -ne $null) {
            foreach ($policy in $response.value) {
                # Determinar la plataforma segun el tipo de politica
                $platform = switch ($policy.'@odata.type') {
                    "#microsoft.graph.iosMobileAppConfiguration" { "iOS" }
                    "#microsoft.graph.androidManagedStoreAppConfiguration" { "Android" }
                    default { "Desconocido" }
                }

                # Obtener el Package Name si es una app de Android
                $packageName = if ($platform -eq "Android" -and $policy.packageId) {
                    $policy.packageId
                } else {
                    "No disponible"
                }

                # Obtener los grupos de asignacion
                $assignmentsUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations/$($policy.id)/assignments"
                $assignedGroups = @()

                try {
                    $assignmentsResponse = Invoke-MgGraphRequest -Method GET -Uri $assignmentsUri -ErrorAction Stop
                    if ($assignmentsResponse.value -ne $null -and $assignmentsResponse.value.Count -gt 0) {
                        foreach ($assignment in $assignmentsResponse.value) {
                            if ($assignment.target -and $assignment.target.'@odata.type') {
                                $targetType = $assignment.target.'@odata.type'

                                # Verificar si esta asignado a todos los dispositivos o usuarios con licencia
                                if ($targetType -eq "#microsoft.graph.allDevicesAssignmentTarget") {
                                    $assignedGroups += "Todos los dispositivos"
                                } elseif ($targetType -eq "#microsoft.graph.allLicensedUsersAssignmentTarget") {
                                    $assignedGroups += "Todos los usuarios con licencia"
                                } elseif ($targetType -match "groupAssignmentTarget") {
                                    $assignedGroups += $assignment.target.groupId
                                }
                            }
                        }
                    }
                } catch {
                    $assignedGroups = @("Error al obtener asignaciones")
                }

                # Convertir los IDs de grupo a nombres
                $groupNames = @()
                foreach ($groupId in $assignedGroups) {
                    if ($groupId -match "Todos los dispositivos|Todos los usuarios con licencia") {
                        $groupNames += $groupId  # Si ya es un nombre especial, lo dejamos tal cual
                    } else {
                        $groupUri = "https://graph.microsoft.com/beta/groups/$groupId"
                        try {
                            $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $groupUri -ErrorAction Stop
                            if ($groupResponse.displayName) {
                                $groupNames += $groupResponse.displayName
                            }
                        } catch {
                            $groupNames += "Grupo Desconocido ($groupId)"
                        }
                    }
                }

                # Agregar la politica a la lista con su nombre, plataforma, package name y grupos de asignacion
                $appConfigPolicies += [PSCustomObject]@{
                    Nombre      = $policy.displayName
                    Plataforma  = $platform
                    PackageName = $packageName
                    Asignacion  = if ($groupNames.Count -gt 0) { $groupNames -join ", " } else { "Sin asignacion" }
                }
            }
        }

        # Verificar si hay mas paginas de resultados
        $appConfigPoliciesUri = $response.'@odata.nextLink'
    } while ($appConfigPoliciesUri -ne $null)  # Continuar hasta que no haya mas paginas

    # Mostrar la lista de politicas con su nombre, plataforma, package name y asignacion
    if ($appConfigPolicies.Count -gt 0) {
        Write-Host "`n===============================================" -ForegroundColor Cyan
        Write-Host "   Politicas de Configuracion de Aplicaciones    " -ForegroundColor Yellow
        Write-Host "===============================================" -ForegroundColor Cyan
        $appConfigPolicies | Sort-Object Plataforma | Format-Table Nombre, Plataforma, PackageName, Asignacion -AutoSize
        Write-Host "===============================================" -ForegroundColor Cyan

        # Exportar a CSV para politicas de proteccion
        $appConfigCsvPath = "$csvFolderPath\configuration_policies.csv"
        $appConfigPolicies | Export-Csv -Path $appConfigCsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Las politicas de proteccion han sido exportadas a CSV en: $appConfigCsvPath" -ForegroundColor Green
    } else {
        Write-Host "No se encontraron politicas de configuracion de aplicaciones." -ForegroundColor Red
    }

} catch {
    Write-Host "Error al obtener politicas de configuracion de aplicaciones: $_" -ForegroundColor Red
}

# Definir la URI para obtener las politicas de proteccion
$protectionPoliciesUri = "https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies"

# Lista para almacenar las politicas de proteccion
$protectionPolicies = @()

try {
    do {
        # Realizar la solicitud a Microsoft Graph
        $response = Invoke-MgGraphRequest -Method GET -Uri $protectionPoliciesUri -ErrorAction Stop

        if ($response.value -ne $null) {
            foreach ($policy in $response.value) {
                # Determinar la plataforma segun el tipo de politica
                $platform = switch ($policy.'@odata.type') {
                    "#microsoft.graph.iosManagedAppProtection" { "iOS" }
                    "#microsoft.graph.androidManagedAppProtection" { "Android" }
                    default { "Desconocido" }
                }

                # Verificar si la politica esta asignada
                $isAssigned = if ($policy.isAssigned -eq $true) { "Asignada" } else { "Sin asignar" }

                # Agregar la politica a la lista con su nombre, plataforma y estado de asignacion
                $protectionPolicies += [PSCustomObject]@{
                    Nombre      = $policy.displayName
                    Plataforma  = $platform
                    Asignacion  = $isAssigned
                }
            }
        }

        # Verificar si hay mas paginas de resultados
        $protectionPoliciesUri = $response.'@odata.nextLink'
    } while ($protectionPoliciesUri -ne $null)  # Continuar hasta que no haya mas paginas

    # Mostrar la lista de politicas de proteccion con su nombre, plataforma y estado de asignacion
    if ($protectionPolicies.Count -gt 0) {
        Write-Host "`n===============================================" -ForegroundColor Cyan
        Write-Host "    Politicas de Proteccion de Aplicaciones    " -ForegroundColor Yellow
        Write-Host "===============================================" -ForegroundColor Cyan
        $protectionPolicies | Format-Table Nombre, Plataforma, Asignacion -AutoSize

        # Exportar a CSV para politicas de proteccion
        $protectionCsvPath = "$csvFolderPath\protection_policies.csv"
        $protectionPolicies | Export-Csv -Path $protectionCsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Las politicas de proteccion han sido exportadas a CSV en: $protectionCsvPath" -ForegroundColor Green
    } else {
        Write-Host "No se encontraron politicas de proteccion." -ForegroundColor Red
    }

} catch {
    Write-Host "Error al obtener politicas de proteccion: $_" -ForegroundColor Red
}



# Obtener perfiles de implementacion
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "          INFORMACION DE PERFIL AUTOPILOT             " -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Cyan

# Lista para almacenar todos los perfiles de implementacion
$deploymentProfiles = @()

# Obtener perfiles de implementacion
try {
    $response = Invoke-MgGraphRequest -Method GET -Uri $autopilotProfilesUri -ErrorAction Stop
    
    if ($response.value -ne $null) {
        # Agregar los perfiles obtenidos a la lista
        $deploymentProfiles += $response.value | ForEach-Object {
            [PSCustomObject]@{
                ID           = $_.id
                DisplayName  = $_.displayName
                Description  = $_.description
                LastModified = $_.lastModifiedDateTime
            }
        }
    } else {
        Write-Host "No se encontraron perfiles de implementacion."
    }
} catch {
    Write-Host "Error al obtener los perfiles de implementacion: $_"
}

# Lista para almacenar las asignaciones
$deploymentProfileAssignments = @()

# Recorrer cada perfil de implementacion y obtener sus asignaciones
foreach ($profile in $deploymentProfiles) {
    $profileId = $profile.ID  # Obtener el ID del perfil

    # Definir la URI para obtener las asignaciones del perfil de implementacion
    $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$profileId/assignments"

    try {
        $assignmentsResponse = Invoke-MgGraphRequest -Method GET -Uri $assignmentsUri -ErrorAction Stop
        
        # Verificar si hay asignaciones
        if ($assignmentsResponse.value -ne $null -and $assignmentsResponse.value.Count -gt 0) {
            foreach ($assignment in $assignmentsResponse.value) {
                # Agregar los datos a la lista de asignaciones
                $deploymentProfileAssignments += [PSCustomObject]@{
                    ProfileID     = $profileId
                    ProfileName   = $profile.DisplayName
                    Source        = $assignment.source
                    SourceId      = $assignment.sourceId
                    ExcludeGroup  = $assignment.excludeGroup
                }
            }
        } else {
            # Agregar el perfil con "Sin asignaciones" si no tiene grupos asignados
            $deploymentProfileAssignments += [PSCustomObject]@{
                ProfileID     = $profileId
                ProfileName   = $profile.DisplayName
                Source        = "Sin asignacion"
                SourceId      = ""
                ExcludeGroup  = $false
            }
        }
    } catch {
        Write-Host "Error obteniendo asignaciones para el perfil de implementacion con ID: $profileId"
        # Agregar el perfil con "Error en la solicitud" en caso de fallo
        $deploymentProfileAssignments += [PSCustomObject]@{
            ProfileID     = $profileId
            ProfileName   = $profile.DisplayName
            Source        = "Error en la solicitud"
            SourceId      = ""
            ExcludeGroup  = $false
        }
    }
}

# Mostrar todas las asignaciones de los perfiles de implementacion en la consola
$deploymentProfileAssignments | Format-Table -AutoSize

# Exportar los datos de asignaciones a CSV
$exportPath = "$csvFolderPath\perfil_implementacion.csv"
$deploymentProfileAssignments | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
Write-Host "Los datos de las asignaciones de perfiles de implementacion han sido exportados a CSV en: $exportPath" -ForegroundColor Green

# Definir la URI para obtener todos los scripts de salud
$healthScriptsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"

# Inicializar lista para almacenar todos los scripts de salud
$healthScripts = @()
$exportData = @()  # Lista para almacenar datos a exportar

# Obtener todos los scripts de salud
try {
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $healthScriptsUri -ErrorAction Stop

        if ($response.value -ne $null) {
            $healthScripts += $response.value
        }

        # Verificar si hay mas paginas de resultados
        $healthScriptsUri = $response.'@odata.nextLink'
    } while ($healthScriptsUri -ne $null)  # Continuar hasta que no haya mas paginas

    # Comprobar si se encontraron scripts
    if ($healthScripts.Count -gt 0) {
        Write-Host "`n===============================================" -ForegroundColor Cyan
        Write-Host "      Scripts de Remediacion Detectados        " -ForegroundColor Yellow
        Write-Host "===============================================" -ForegroundColor Cyan

        # Recorrer cada script y obtener sus asignaciones
        foreach ($script in $healthScripts) {
            $scriptId = $script.id
            # Obtener asignaciones para el script actual
            $assignedGroups = @()
            $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$scriptId/assignments"

            try {
                $assignmentsResponse = Invoke-MgGraphRequest -Method GET -Uri $assignmentsUri -ErrorAction Stop

                if ($assignmentsResponse.value -ne $null -and $assignmentsResponse.value.Count -gt 0) {
                    foreach ($assignment in $assignmentsResponse.value) {
                        if ($assignment.target -and $assignment.target.groupId) {
                            # Obtener el nombre del grupo
                            $groupId = $assignment.target.groupId
                            $groupUri = "https://graph.microsoft.com/beta/groups/$groupId"
                            $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $groupUri -ErrorAction SilentlyContinue

                            if ($groupResponse.displayName) {
                                $assignedGroups += $groupResponse.displayName
                            } else {
                                $assignedGroups += "Grupo no encontrado"
                            }
                        }
                    }
                }
            } catch {
                Write-Host "Error al obtener asignaciones para el script $($script.displayName): $_"
            }

            # Agregar datos a la lista de exportacion
            $exportData += [PSCustomObject]@{
                ID         = $scriptId
                Nombre     = $script.displayName
                Asignacion = if ($assignedGroups.Count -gt 0) { $assignedGroups -join ', ' } else { "Sin asignacion" }
            }
        }

        # Mostrar resultados en el formato solicitado
        foreach ($data in $exportData) {
            Write-Host "ID: " -NoNewline; Write-Host $($data.ID) -ForegroundColor Yellow -NoNewline; Write-Host " | Nombre: " -NoNewline ; Write-Host $($data.Nombre) -ForegroundColor Yellow -NoNewline; Write-Host " | Asignacion: " -NoNewline; Write-Host $($data.Asignacion) -ForegroundColor Yellow
        }

        # Exportar los datos de asignaciones a CSV
        $exportPath = "$csvFolderPath\Script_Remediacion.csv"
        $exportData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nLos datos de los script de remediacion han sido exportados a CSV en: $exportPath" -ForegroundColor Green
    } else {
        Write-Host "No se encontraron scripts de salud."
    }
} catch {
    Write-Host "Error al obtener scripts de salud: $_"
}

# Definir la URI para obtener todos los filtros de asignacion
$assignmentFiltersUri = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"

# Inicializar lista para almacenar todos los filtros de asignacion
$assignmentFilters = @()
$exportData = @()  # Lista para almacenar datos a exportar

# Obtener todos los filtros de asignacion
try {
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $assignmentFiltersUri -ErrorAction Stop

        if ($response.value -ne $null) {
            $assignmentFilters += $response.value
        }

        # Verificar si hay mas paginas de resultados
        $assignmentFiltersUri = $response.'@odata.nextLink'
    } while ($assignmentFiltersUri -ne $null)  # Continuar hasta que no haya mas paginas

    # Comprobar si se encontraron filtros de asignacion
    if ($assignmentFilters.Count -gt 0) {
        Write-Host "`n===============================================" -ForegroundColor Cyan
        Write-Host "        Filtros de Asignacion Detectados       " -ForegroundColor Yellow
        Write-Host "===============================================" -ForegroundColor Cyan

        # Recorrer cada filtro y obtener sus reglas
        foreach ($filter in $assignmentFilters) {
            $filterId = $filter.id
            $filterName = $filter.displayName
            $filterRules = $filter.rule

            # Mostrar el ID y el Nombre del filtro
            Write-Host "ID: " -NoNewline; Write-Host $filterId -ForegroundColor Yellow -NoNewline; Write-Host " | Nombre: " -NoNewline; Write-Host $filterName -ForegroundColor Yellow -NoNewline; Write-Host " | Reglas: " -NoNewline; Write-Host $filterRules -ForegroundColor Yellow 

            # Agregar datos a la lista de exportacion
            $exportFilter += [PSCustomObject]@{
                ID      = $filterId
                Nombre  = $filterName
                Reglas  = if ($filterRules) { $filterRules -join '; ' } else { "Sin reglas" }
            }
        }

        # Exportar los datos a CSV
        $exportPath = "$csvFolderPath\Filters.csv"
        $exportFilter | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nLos filtros de asignacion han sido exportados a CSV en: $exportPath" -ForegroundColor Green
    } else {
        Write-Host "No se encontraron filtros de asignacion."
    }
} catch {
    Write-Host "Error al obtener filtros de asignacion: $_"
}

