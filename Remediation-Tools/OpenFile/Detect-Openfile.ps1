$folderPath = "C:\Users\AdeleVance\Desktop\Test"  # Cambia esto por la ruta de la carpeta
$handlePath = "C:\Sysinternals\handle.exe"  # Cambia esto por la ruta donde guardaste handle.exe

if (-not (Test-Path $handlePath)) {
    Write-Host "Error: No se encontró handle.exe en $handlePath" -ForegroundColor Red
    exit 1
}

$foundOpenFile = $false
$foundRecentlyOpened = $false
$foundOldFile = $false  # Nuevo: Detectar archivos NO abiertos recientemente
$timeLimit = (Get-Date).AddMinutes(-1)

# Habilitar actualización de LastAccessTime si está deshabilitada
try {
    $ntfsSetting = fsutil behavior query disablelastaccess | Select-String "= 1"
    if ($ntfsSetting) {
        Write-Host "Habilitando la actualización de LastAccessTime..." -ForegroundColor Cyan
        fsutil behavior set disablelastaccess 0 | Out-Null
    }
} catch {
    Write-Host "No se pudo verificar la configuración de NTFS." -ForegroundColor Red
}

# Función para verificar si un archivo está en uso usando handle.exe
function Test-FileInUse {
    param ([string]$filePath)
    
    $output = & "$handlePath" -accepteula $filePath 2>$null  
    return $output -match [regex]::Escape($filePath)
}

# Obtener lista de archivos en la carpeta
$files = Get-ChildItem -Path $folderPath -File

# Revisar cada archivo
foreach ($file in $files) {
    $filePath = $file.FullName

    # 🔹 Forzar actualización de metadatos
    $null = [System.IO.File]::GetLastAccessTimeUtc($filePath)

    # Obtener LastAccessTime actualizado
    $fileInfo = Get-Item $filePath
    $lastAccessTime = $fileInfo.LastAccessTime
    $formattedTime = $lastAccessTime.ToString("dd/MM/yyyy HH:mm:ss")

    if (Test-FileInUse -filePath $filePath) {
        Write-Host "[ABIERTO]  $filePath" -ForegroundColor Green
        $foundOpenFile = $true  
    } elseif ($lastAccessTime -gt $timeLimit) {
        Write-Host "[RECIENTEMENTE ABIERTO]  $filePath (Ultimo acceso: $formattedTime)" -ForegroundColor Cyan
        $foundRecentlyOpened = $true  
    } else {
        Write-Host "[NO ABIERTO]  $filePath (Ultimo acceso: $formattedTime)" -ForegroundColor Yellow
        $foundOldFile = $true  # Si al menos un archivo no es reciente, activamos la corrección
    }
}

# 🚀 Nueva lógica para la corrección en Intune:
if ($foundOldFile) {
    exit 1  # Ejecutar la remediación si hay al menos un archivo no abierto recientemente
} else {
    exit 0  # No ejecutar la remediación si todos han sido abiertos recientemente o están en uso
}
