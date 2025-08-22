<#
.SYNOPSIS
    Exporta todas las licencias asignadas a los usuarios de Microsoft 365.

.DESCRIPTION
    Este script utiliza el módulo Microsoft Graph PowerShell para consultar los usuarios
    del tenant y listar sus licencias (SKU) junto con los planes de servicio habilitados.
    El resultado se muestra en pantalla en formato tabla y se exporta opcionalmente a CSV.

.AUTHOR
    Ismael Morilla Orella
    22/08/2025

.REQUIREMENTS
    - Módulo Microsoft.Graph instalado
      Install-Module Microsoft.Graph -Scope CurrentUser
    - Permisos: User.Read.All

.VERSION
    1.0

.EXAMPLE
    # Ejecutar el script y exportar resultados
    .\Get-M365UserLicenses.ps1

    # El archivo CSV se generará en la carpeta actual con el nombre "UserLicenses.csv"
#>

# Conectar a Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All"

# Obtener todos los usuarios
$users = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName

# Crear un listado con las licencias de cada usuario
$results = foreach ($user in $users) {
    $licenses = Get-MgUserLicenseDetail -UserId $user.Id
    foreach ($license in $licenses) {
        [PSCustomObject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            SkuPartNumber     = $license.SkuPartNumber
            ServicePlans      = ($license.ServicePlans | Where-Object {$_.ProvisioningStatus -eq "Success"} | Select-Object -ExpandProperty ServicePlanName) -join ", "
        }
    }
}

# Mostrar resultados en pantalla
$results | Format-Table -AutoSize

# Exportar a CSV
$results | Export-Csv -Path "UserLicenses.csv" -NoTypeInformation -Encoding UTF8
