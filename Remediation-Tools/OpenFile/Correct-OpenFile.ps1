<#
.SYNOPSIS
    Aperturas de fichero que se detecte del script de detección

.DESCRIPTION
    Este script se encargará de abrir de manera automatizada los archivos que fueron detectados por el script anterior.
    Los archivos se abrirán en una ventana minimizada y permanecerán abiertos durante un periodo de 5 segundos antes de cerrarse automáticamente.

.NOTES
    Author: Ismael Morilla Orellana
    Date: 29/03/2025
    Version: 1.0
#>


$folderPath = "C:\Users\AdeleVance\Desktop\Test"  # Cambia esto por la ruta de la carpeta
$timeLimit = (Get-Date).AddMinutes(-1)  # Tiempo límite de 1 minuto atrás

# Obtener lista de archivos en la carpeta
$files = Get-ChildItem -Path $folderPath -File

# Revisar cada archivo
foreach ($file in $files) {
    $filePath = $file.FullName
    $lastAccessTime = [System.IO.File]::GetLastAccessTime($filePath)

    # Comprobar si el último acceso fue hace más de un minuto
    if ($lastAccessTime -lt $timeLimit) {
        Write-Host "Abriendo archivo: $filePath" -ForegroundColor Cyan

        # Abrir el archivo minimizado
        $process = Start-Process -FilePath $filePath -WindowStyle Minimized -PassThru
        
        # Esperar 10 segundos
        Start-Sleep -Seconds 10
        
        # Cerrar el proceso
        $process | Stop-Process -Force
        Write-Host "Archivo cerrado: $filePath" -ForegroundColor Yellow
    }
}
