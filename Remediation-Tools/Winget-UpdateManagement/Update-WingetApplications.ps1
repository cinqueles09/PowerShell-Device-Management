<#
.SYNOPSIS
Actualizar las aplicaciones pendientes mediante Winget.

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
PS C:\> .\Update-WingetApplications.ps1

.LINK
Repositorio: [https://github.com/cinqueles09/PowerShell-Device-Management]
Documentación de Winget: [https://learn.microsoft.com/es-es/windows/package-manager/configuration/]
#>

winget upgrade --all
