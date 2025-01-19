# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 11/07/2024
# Descripción: Este script automatiza el proceso de gestión de licencias de usuario en Microsoft 365. Permite eliminar una licencia existente de un usuario especificado y asignar una nueva licencia desde un listado definido en un archivo UPN.txt.

#Obtener el total de las UPN seleccionadas
$total=(Get-Content .\UPN.txt | Measure-Object -line).lines

for ($var=1; $var -le $total; $var++) {
    $UPN=Get-Content .\UPN.txt | select-object -First $var | Select-Object -last 1

    #Elimina la licencia E1
    Set-MgUserLicense -UserId "$UPN" -RemoveLicenses @("") -AddLicenses @{}
    #Asigna la licencia E3
    Set-MgUserLicense -UserId "$UPN" -AddLicenses @{""} -RemoveLicenses @()

}
