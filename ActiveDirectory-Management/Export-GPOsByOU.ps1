<#
.SYNOPSIS
    Exporta todas las GPOs vinculadas a las OUs del dominio a un archivo CSV.

.DESCRIPTION
    Este script recorre todas las Organizational Units (OUs) del dominio y obtiene
    las GPOs vinculadas a cada OU, incluyendo si están habilitadas y si están forzadas (Enforced).
    El resultado se exporta a un archivo CSV con ';' como separador, listo para abrir en Excel.

.NOTES
    Autor      : Ismael Morilla Orellana
    Fecha      : 19/01/2026
    Versión    : 1.0
    Requisitos : Módulos ActiveDirectory y GroupPolicy
                 - Import-Module ActiveDirectory
                 - Import-Module GroupPolicy
    Uso        : Ejecutar con privilegios adecuados de dominio (lector de GPOs y OUs).

.EXAMPLE
    .\Export-GPOsByOU.ps1
#>


# Obtiene todas las OUs
$OUs = Get-ADOrganizationalUnit -Filter *

# Lista donde guardaremos los resultados
$GPOInfo = @()

foreach ($ou in $OUs) {
    # Obtiene los GPOs vinculados a esta OU
    $links = Get-GPInheritance -Target $ou.DistinguishedName
    foreach ($link in $links.GpoLinks) {
        $GPOInfo += [PSCustomObject]@{
            OU      = $ou.DistinguishedName
            GPOName = $link.DisplayName
            Enabled = $link.Enabled
            Enforced = $link.Enforced
        }
    }
}

# Exporta a CSV usando ; como delimitador
$GPOInfo | Export-Csv -Path "GPOs_OUs.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ";"
