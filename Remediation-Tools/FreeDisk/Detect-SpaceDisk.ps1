<#
.SYNOPSIS
    Comprueba el espacio libre en la partición EFI y evalúa el cumplimiento según un umbral definido.

.DESCRIPTION
    Este script localiza la partición EFI del sistema, la monta temporalmente si es necesario
    y calcula el espacio total, usado y libre. Además, mide el tamaño de la carpeta
    \EFI\HP\DEVFW si existe.

    Se evalúa el cumplimiento en función de un umbral mínimo de espacio libre definido
    (en MB). El resultado se devuelve en una sola línea, optimizada para su uso en
    herramientas de gestión como Microsoft Intune.

.PARAMETER mountLetter
    Letra de unidad temporal utilizada para montar la partición EFI (por defecto: S:)

.PARAMETER minFreeMB
    Espacio mínimo requerido en MB para que el sistema sea considerado "COMPLIANT"

.OUTPUTS
    Salida en texto plano con el siguiente formato:
    EFI: <Total> MB | Used: <Usado> MB | Free: <Libre> MB | HP DEVFW: <Tamaño> MB | Status: <Estado>

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 29/04/2026
    Versión: 1.0

    Requisitos:
    - Ejecutar con privilegios administrativos
    - PowerShell 5.1 o superior

    Comportamiento:
    - Devuelve exit code 0 si COMPLIANT
    - Devuelve exit code 1 si NO COMPLIANT
    - Devuelve exit code 0 en caso de error (para evitar falsos positivos en despliegues)

    Uso típico:
    - Scripts de detección en Microsoft Intune
    - Auditorías de estado de partición EFI
#>

$mountLetter = "S:"
$mountLetterClean = $mountLetter.Replace(":", "")
$efiFolder = "$mountLetter\EFI\HP\DEVFW"

# Umbral mínimo de espacio libre (MB)
$minFreeMB = 20

try {
    # Buscar partición EFI
    $efiPartition = Get-Partition | Where-Object {
        $_.GptType -eq "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"
    }

    if (-not $efiPartition) {
        Write-Output "ERROR: No EFI partition found"
        exit 0
    }

    # Montar si no tiene letra
    if (-not $efiPartition.DriveLetter) {
        Add-PartitionAccessPath -DiskNumber $efiPartition.DiskNumber `
            -PartitionNumber $efiPartition.PartitionNumber `
            -AccessPath $mountLetter
    }

    Start-Sleep -Seconds 2

    # Obtener info del volumen
    $volume = Get-Volume -DriveLetter $mountLetterClean

    $sizeMB = [math]::Round($volume.Size / 1MB, 2)
    $freeMB = [math]::Round($volume.SizeRemaining / 1MB, 2)
    $usedMB = [math]::Round($sizeMB - $freeMB, 2)

    # Tamaño carpeta HP
    $hpSizeMB = 0
    if (Test-Path $efiFolder) {
        $hpSizeBytes = (Get-ChildItem $efiFolder -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum

        $hpSizeMB = [math]::Round($hpSizeBytes / 1MB, 2)
    }

    # Evaluación
    if ($freeMB -lt $minFreeMB) {
        $status = "NO COMPLIANT"
        $exitCode = 1
    } else {
        $status = "COMPLIANT"
        $exitCode = 0
    }

    # Mensaje en una sola línea (ideal para Intune)
    $message = "EFI: $sizeMB MB | Used: $usedMB MB | Free: $freeMB MB | HP DEVFW: $hpSizeMB MB | Status: $status (threshold: $minFreeMB MB)"

    Write-Output $message

}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    $exitCode = 0
}
finally {
    try {
        Remove-PartitionAccessPath -DiskNumber $efiPartition.DiskNumber `
            -PartitionNumber $efiPartition.PartitionNumber `
            -AccessPath $mountLetter
    } catch {}
}

exit $exitCode
