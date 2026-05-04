<#
.SYNOPSIS
    Remedia falta de espacio en la partición EFI eliminando contenido de HP DEVFW tras realizar backup.

.DESCRIPTION
    Este script localiza la partición EFI del sistema, la monta temporalmente si es necesario
    y evalúa el espacio libre disponible. Si el espacio libre es inferior al umbral definido
    y la carpeta \EFI\HP\DEVFW supera un tamaño mínimo, se ejecuta una remediación controlada:

    1. Se realiza una copia de seguridad del contenido de \EFI\HP\DEVFW en disco local.
    2. Se valida que el backup contiene archivos.
    3. Se elimina el contenido original de la partición EFI para liberar espacio.

    El proceso está diseñado para ser seguro, validando previamente el backup antes de eliminar datos.

.PARAMETER mountLetter
    Letra de unidad temporal utilizada para montar la partición EFI (por defecto: S:)

.PARAMETER minFreeMB
    Espacio mínimo requerido en MB antes de considerar la limpieza

.PARAMETER minHPSizeMB
    Tamaño mínimo en MB de la carpeta HP DEVFW para permitir la remediación

.PARAMETER backupPath
    Ruta local donde se almacenarán los backups (por defecto: C:\ProgramData\EFI_HP_Backup)

.OUTPUTS
    Mensajes detallados en consola indicando cada paso del proceso:
    - Estado de la partición EFI
    - Tamaño de HP DEVFW
    - Resultado del backup
    - Resultado de la limpieza

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 29/04/2026
    Versión: 1.0

    Requisitos:
    - Ejecutar con privilegios administrativos o contexto SYSTEM
    - PowerShell 5.1 o superior

    Seguridad:
    - No elimina datos sin backup previo validado
    - Usa robocopy para mayor fiabilidad en entornos gestionados
    - Manejo de errores incluido

    Comportamiento:
    - Siempre devuelve exit code 0 (diseñado para remediación en Intune)
    - Registro detallado mediante Write-Output

    Uso típico:
    - Script de remediación en Microsoft Intune
    - Automatización de mantenimiento de partición EFI en equipos HP
#>

$mountLetter = "S:"
$mountLetterClean = $mountLetter.Replace(":", "")
$efiFolder = "$mountLetter\EFI\HP\DEVFW"
$backupPath = "C:\ProgramData\EFI_HP_Backup"

# Umbrales
$minFreeMB = 20
$minHPSizeMB = 5

Write-Output "=== Remediación EFI HP DEVFW ==="

try {
    # Buscar partición EFI
    $efiPartition = Get-Partition | Where-Object {
        $_.GptType -eq "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"
    }

    if (-not $efiPartition) {
        Write-Output "ERROR: No se encontró la partición EFI"
        exit 0
    }

    # Crear carpeta base de backup
    if (!(Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force -ErrorAction Stop | Out-Null
        Write-Output "Carpeta backup creada: $backupPath"
    }

    # Montar EFI si no tiene letra
    if (-not $efiPartition.DriveLetter) {
        Write-Output "Montando EFI en $mountLetter"

        Add-PartitionAccessPath -DiskNumber $efiPartition.DiskNumber `
            -PartitionNumber $efiPartition.PartitionNumber `
            -AccessPath $mountLetter
    }

    Start-Sleep -Seconds 2

    # Obtener info del volumen
    $volume = Get-Volume -DriveLetter $mountLetterClean

    $sizeMB = [math]::Round($volume.Size / 1MB, 2)
    $freeMB = [math]::Round($volume.SizeRemaining / 1MB, 2)

    Write-Output "EFI total: $sizeMB MB"
    Write-Output "EFI libre: $freeMB MB"

    if (Test-Path $efiFolder) {

        # Calcular tamaño HP
        $hpSizeBytes = (Get-ChildItem $efiFolder -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum

        $hpSizeMB = [math]::Round($hpSizeBytes / 1MB, 2)

        Write-Output "HP DEVFW ocupa: $hpSizeMB MB"

        # Condición de limpieza
        if ($freeMB -lt $minFreeMB -and $hpSizeMB -gt $minHPSizeMB) {

            Write-Output "Condiciones cumplidas → iniciando remediación"

            # Crear carpeta backup con timestamp
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $dest = Join-Path $backupPath "DEVFW_$timestamp"

            New-Item -ItemType Directory -Path $dest -Force | Out-Null

            # Backup con robocopy (más fiable en SYSTEM)
            Write-Output "Iniciando backup con robocopy..."

            robocopy $efiFolder $dest /E /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null

            if ($LASTEXITCODE -le 3) {
                Write-Output "Backup correcto (robocopy code: $LASTEXITCODE)"

                # Validación básica: comprobar que algo se copió
                $copiedFiles = Get-ChildItem $dest -Recurse -ErrorAction SilentlyContinue

                if ($copiedFiles.Count -gt 0) {

                    Write-Output "Validación OK → eliminando contenido original"

                    Remove-Item -Path $efiFolder -Recurse -Force -ErrorAction Stop

                    Write-Output "Limpieza completada correctamente"
                }
                else {
                    Write-Output "ERROR: Backup vacío, no se elimina contenido"
                }
            }
            else {
                Write-Output "ERROR en backup robocopy (code: $LASTEXITCODE)"
            }

        } else {
            Write-Output "No se cumplen condiciones de limpieza"
        }

    } else {
        Write-Output "No existe carpeta HP DEVFW"
    }

}
catch {
    Write-Output "ERROR CRÍTICO: $($_.Exception.Message)"
}
finally {
    try {
        Remove-PartitionAccessPath -DiskNumber $efiPartition.DiskNumber `
            -PartitionNumber $efiPartition.PartitionNumber `
            -AccessPath $mountLetter

        Write-Output "EFI desmontada correctamente"
    }
    catch {
        Write-Output "WARNING: No se pudo desmontar EFI"
    }
}

Write-Output "Remediación finalizada"
exit 0
