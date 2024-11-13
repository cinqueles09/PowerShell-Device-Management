#SYNOPSIS: Eliminar Hash ID de forma masiva
#DESCRIPTION: 
#Con este Script se pueden eliminar los HWID de Intune de forma masiva mediante dos metodos:
#1. Eliminacion completa de todos los HWID existentes en Intune.
#2. Carga de un archivo CSV sin cabecera con los numeros de serie de los dispositivos para eliminar sus HWID de forma masiva.
#AUTOR: Ismael Morilla Orellana
#VERSION: 1.0
#DATE: 24/04/2024

#Connect-MgGraph

Write-output "Cuantos Hash ID desea eliminar del portal de Intune?"
Write-output "1. Todos los existentes"
Write-output "2. Seleccion de varios Hash ID"
$op=Read-Host "Indique una opcion"

switch ($op)
{
    1 {
        #Esta opcion busca todos los ID de los hashes para eliminarlos todos
        $IDs=(get-MgDeviceManagementWindowsAutopilotDeviceIdentity).Id
        $Total= ($IDs | Measure-Object).Count
        for ($var=1; $var -le $total; $var++){
            $ID=$IDs |  select-object -First $var | Select-Object -last 1
            Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $ID
        }
        Write-output "Los Hashes tardaran en desaparecer en la consola de Autopilot entre 10 y 20 minutos. Tambien puedes forzar una sincronizacion en el portal"
    }
    2 {
        #Esta opcion buscara los S/N correspondientes para buscar la ID y borrar solo los indicados.
        cls
        Write-output " "
        Write-output "Para garantizar el correcto funcionamiento de esta seccion, 
es imperativo especificar los hashes que deben eliminarse. Por consiguiente, 
se requerira la provision de un archivo CSV que contenga los numeros de serie seleccionados."
        Write-output " "
        Write-output "Ejemplo:"
        Write-output "XXXXXXXXX"
        Write-output "YYYYYYYYY"
        Write-output " "
        $Ruta = Read-Host "Indica la ruta donde se encuentra el CSV (ejemplo: C:\User\Public\Desktop\Snumber.csv)"

        $count=(Get-Content "$Ruta" | Measure-Object).Count
        $Pre=get-MgDeviceManagementWindowsAutopilotDeviceIdentity | Select-Object SerialNumber,ID
            for ($var=1; $var -le $count; $var++){
                $SNOrigen=Get-Content $Ruta | Select-Object -First $var | Select-Object -Last 1
                $Total_Intune=($Pre | Measure-Object).Count
                for ($var1=1; $var1 -le $Total_Intune; $var1++){
                    $SNIntune=($Pre | Select-Object -First $var1 | Select-Object -Last 1).SerialNumber
                    $IDIntune=($Pre | Select-Object -First $var1 | Select-Object -Last 1).Id
                    if ($SNOrigen -eq $SNIntune)
                    {
                        Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $IDIntune
                    }
                }
            }
            Write-output "Los Hashes tardaran en desaparecer en la consola de Autopilot entre 10 y 20 minutos. Tambien puedes forzar una sincronizacion en el portal"
    }
}

