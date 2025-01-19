<#
.SYNOPSIS
Cambia una licencia de usuario en Entra ID de una licencia especificada a otra.

.DESCRIPTION
Este script permite a los administradores de TI reasignar licencias de usuario en Entra ID. 
La licencia actual indicada se elimina y se reemplaza por otra especificada en el script.

.OUTPUTS
Mensaje de confirmación al realizar el cambio de licencia.

.NOTES
Autor      : Ismael Morilla Orellana
Fecha      : [11/07/2024]
Versión    : 1.0
Revisión   : 1.0

.EXAMPLES
Ejemplo 1: Cambiar una licencia
PS C:\> .\Switch-License.ps1 -OldLicense "E3" -NewLicense "E5"

.LINK
Repositorio: [https://github.com/TuUsuario/TuRepositorio]
#>


# Leer todas las UPN desde el archivo una vez y almacenar en una lista
$UPNList = Get-Content .\UPN.txt

# Obtener el total de UPN
$total = $UPNList.Count

# Iterar sobre la lista de UPN
foreach ($UPN in $UPNList) {
    # Elimina la licencia X
    Set-MgUserLicense -UserId $UPN -RemoveLicenses @("") -AddLicenses @{}
    
    # Asigna la licencia X
    Set-MgUserLicense -UserId $UPN -AddLicenses @{""} -RemoveLicenses @()
}

