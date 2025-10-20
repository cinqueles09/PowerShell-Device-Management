<#
.SYNOPSIS
    Detecta instalaciones MSI de Microsoft Office Professional Plus en el equipo.

.DESCRIPTION
    Este script recorre las ramas del registro de Windows (32 y 64 bits)
    buscando claves MSI de Microsoft Office Professional Plus.
    Para cada instalación detectada, muestra una línea única con el formato:
        Nombre del producto - ProductID interno - ProductCode (GUID)
    También elimina duplicados basados en el ProductCode para evitar mostrar múltiples entradas por la misma instalación.
    Diseñado para usarse como script de detección en Intune o en automatizaciones de remediación.

.EXAMPLE
    .\Detectar-OfficeProPlus.ps1
    Salida:
    Microsoft Office Professional Plus 2010 - Office14.PROPLUS - {90140000-0011-0000-0000-0000000FF1CE}

.EXAMPLE
    Uso en Intune:
    - Se ejecuta en System context
    - Devuelve exit 0 si se detecta al menos una instalación
    - Devuelve exit 1 si no se detecta ninguna instalación

.NOTES
    Autor     : Ismael Morilla Orellana
    Fecha     : 2025-10-18
    Versión   : 1.0
    Requisitos: PowerShell 5.1 o superior
    Comentarios: Compatible con Office 2010, 2013, 2016 MSI Professional Plus.
#>

# Rutas del registro donde se almacenan productos MSI
$RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$Results = @()

foreach ($path in $RegPaths) {
    Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue

        if ($props.DisplayName -match "Microsoft Office Professional Plus") {
            $name = $props.DisplayName
            $productCode = $_.PSChildName
            $productID = $props.ProductID

            # Asegurar que el ProductCode sea un GUID válido
            if ($productCode -notmatch '^\{[0-9A-Fa-f\-]{36}\}$') {
                # Saltar si no es un ProductCode válido
                return
            }

            # Si ProductID no existe o parece un número de serie, asignar valor genérico
            if (-not $productID -or $productID -match '^\d{5}-\d{3}') {
                $productID = "Office14.PROPLUS"
            }

            $Results += [PSCustomObject]@{
                Name        = $name
                ProductID   = $productID
                ProductCode = $productCode
            }
        }
    }
}

# Eliminar duplicados basados en ProductCode
$Unique = $Results | Sort-Object ProductCode -Unique

# Mostrar resultado limpio
foreach ($r in $Unique) {
    Write-Output "$($r.Name) - $($r.ProductID) - $($r.ProductCode)"
}

# Exit code para detección en Intune
if ($Unique.Count -gt 0) {
    exit 0  # Detectado
} else {
    exit 1  # No detectado
}

