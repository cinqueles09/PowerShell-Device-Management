<#
.SYNOPSIS
    Exporta todas las GPO habilitadas del dominio a archivos XML legibles..

.DESCRIPTION
    Este script recorre todas las GPO existentes en el dominio y genera un informe en formato XML
    para cada una, utilizando Get-GPOReport. Se incluye manejo de caracteres inválidos en los nombres
    de archivo y una barra de progreso para seguimiento del proceso.

.NOTES
    Autor      : Ismael Morilla Orellana
    Fecha      : 10/11/2025
    Versión    : 1.0
    Requisitos : PowerShell 5.1 o superior, módulo GroupPolicy
#>

# Importar módulo de GroupPolicy
Import-Module GroupPolicy

# Carpeta de destino para los XML
$exportPath = "C:\GPO_Export"

# Crear carpeta si no existe
If (!(Test-Path $exportPath)) {
    New-Item -ItemType Directory -Path $exportPath | Out-Null
}

# Obtener todas las GPO del dominio
$gpos = Get-GPO -All

$total = $gpos.Count
$counter = 0

foreach ($gpo in $gpos) {
    $counter++
    
    # Barra de progreso
    Write-Progress -Activity "Exportando GPOs a XML" `
                   -Status "Procesando $($gpo.DisplayName) ($counter de $total)" `
                   -PercentComplete (($counter / $total) * 100)

    # Limpiar nombre del archivo de caracteres inválidos
    $safeName = [RegEx]::Replace($gpo.DisplayName, '[\\\/:*?"<>|]', '_')
    $reportPath = Join-Path $exportPath ($safeName + ".xml")

    # Generar reporte XML
    try {
        Get-GPOReport -Guid $gpo.Id -ReportType Xml -Path $reportPath -ErrorAction Stop
    }
    catch {
        Write-Warning "No se pudo exportar la GPO: $($gpo.DisplayName) - $_"
    }
}

Write-Host "Exportación completada. Los archivos XML se encuentran en: $exportPath"
