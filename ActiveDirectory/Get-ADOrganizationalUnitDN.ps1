# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 12/11/2024
# Descripción: Exporta el distinguishedName de las OUs y subOus indicadas a un CSV en C:

# Importa el módulo de Active Directory 
Import-Module ActiveDirectory

# Archivo de salida
$outputFile = "C:\OutputOUs.csv"

# Verificamos si el archivo de salida ya existe, y lo eliminamos si es así
if (Test-Path $outputFile) {
    Remove-Item $outputFile
    Write-Host "Archivo de salida existente eliminado: $outputFile"
}

# Lista de OUs a procesar: reemplaza los nombres de las OUs según sea necesario
$ouList = @(
    "OU=WServer 2012,DC=morilla,DC=es",
    "OU=Mutual,DC=morilla,DC=es"
)

# Iteramos por cada OU en la lista y llamamos a la función
foreach ($ouName in $ouList) {
    Write-Host "`nProcesando OU y sub-OUs para: $ouName"
    Get-ADOrganizationalUnit -SearchBase $ouName -SearchScope Subtree -Filter * | Select-Object Name, DistinguishedName >> $outputFile
}
