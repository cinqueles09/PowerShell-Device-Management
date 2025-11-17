<#
.SYNOPSIS
    Script para agregar equipos a un grupo de Active Directory de forma automatizada.

.DESCRIPTION
    Este script lee una lista de equipos desde un archivo de texto y los agrega
    a un grupo específico de Active Directory.  
    Valida la existencia del equipo en AD antes de intentar incluirlo, 
    e informa en pantalla cada resultado (éxito, error o inexistencia).

.AUTHOR
    Ismael Morilla Orellana

.VERSION
    1.0

.DATE
    17/11/2025

.PARAMETER rutaTXT
    Ruta del archivo de texto que contiene la lista de equipos, uno por línea.

.PARAMETER grupoAD
    Nombre del grupo de Active Directory al que se agregarán los equipos.
    Puede ser el nombre del grupo o la ruta completa “OU=...,DC=...”.

.REQUIREMENTS
    - Permisos adecuados para consultar AD y modificar miembros de grupos.
    - Módulo ActiveDirectory instalado.
    - Ejecución desde un entorno con conectividad al dominio.

.NOTES
    Este script está orientado a tareas de migración y administración de equipos
    vinculados a Active Directory (por ejemplo, integración con Intune u Office 365).

#>

# Ruta del archivo de texto con los equipos
$rutaTXT = "equipos.txt"

# Nombre del grupo de AD (solo nombre o ruta completa tipo "OU=...,DC=...")
$grupoAD = "Intune-Migracion-Office365"

# Importar modulo de Active Directory (si no estÃ¡ cargado)
Import-Module ActiveDirectory

# Leer cada equipo del archivo
$equipos = Get-Content -Path $rutaTXT

foreach ($equipo in $equipos) {
    if ($equipo -ne "") {

        # Comprobar que el equipo existe en AD
        $objEquipo = Get-ADComputer -Identity $equipo -ErrorAction SilentlyContinue

        if ($objEquipo) {
            try {
                # AÃ±adir al grupo
                Add-ADGroupMember -Identity $grupoAD -Members $objEquipo -ErrorAction Stop
                Write-Host "Equipo incluido: $equipo"
            }
            catch {
                Write-Host "Error al incluir ${equipo}: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "El equipo no existe en AD: $equipo" -ForegroundColor Yellow
        }

    }
}
