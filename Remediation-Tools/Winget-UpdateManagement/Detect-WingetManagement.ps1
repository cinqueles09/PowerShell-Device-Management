<#
.SYNOPSIS
Detecta actualizaciones pendientes de aplicaciones instaladas mediante Winget.

.DESCRIPTION
Este script analiza las aplicaciones instaladas con Winget y detecta actualizaciones pendientes. Proporciona un informe con el estado de las aplicaciones que necesitan actualización.

.OUTPUTS
Lista de aplicaciones con actualizaciones pendientes.

.NOTES
Autor      : Ismael Morilla Orellana
Fecha      : [08/01/2025]
Versión    : 1.0
Revisión   : 1.0

.EXAMPLES
Ejemplo 1: Ejecutar el script para detectar actualizaciones pendientes
PS C:\> .\Detect-WingetUpdates.ps1

.LINK
Repositorio: [https://github.com/cinqueles09/PowerShell-Device-Management]
Documentación de Winget: [https://learn.microsoft.com/es-es/windows/package-manager/configuration/]
#>


$Flag = winget upgrade | Select-Object -Last 1

if ($Flag -like "* actualizaciones disponibles")
{
    Write-output "Se detectan aplicaciones a actualizar"
    Exit 1
}
else
{
    Write-output "No se detectan aplicaciones a actualizar"
    Exit 0
}
