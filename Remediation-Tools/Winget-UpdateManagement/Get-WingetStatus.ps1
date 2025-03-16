# ======================================================
# Winget Info Extractor
# ======================================================
# Este script extrae y muestra informacion clave de winget
# Autor: Ismael Morilla Orellana
# Fecha: 15/03/2025
# ======================================================

function Check-AdminPrivileges {
    # Verificar si el script se esta ejecutando como administrador
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # Mostrar un banner de advertencia en rojo
        $bannerColor = [System.ConsoleColor]::Red
        $resetColor = [System.ConsoleColor]::White

        $bannerMessage = "Este script NO esta siendo ejecutado con privilegios de administrador. Algunos comandos pueden no funcionar correctamente."
        $bannerLength = $bannerMessage.Length + 4  # Longitud del banner con los bordes

        # Crear el banner
        Write-Host ("*" * $bannerLength) -ForegroundColor $bannerColor
        Write-Host "* $bannerMessage *" -ForegroundColor $bannerColor
        Write-Host ("*" * $bannerLength) -ForegroundColor $bannerColor
        Write-Host ""  # Espacio en blanco
    }
}

function info {
    # Ejecutar winget --info y extraer la informacion relevante
    $wingetInfo = winget --info | Out-String

    # Expresiones regulares para extraer la informacion especifica
    $windowsVersion = $wingetInfo | Select-String "Windows: (.+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $architecture = $wingetInfo | Select-String "Arquitectura del sistema: (.+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $packageVersion = $wingetInfo | Select-String "Paquete: (.+)" | ForEach-Object { $_.Matches.Groups[1].Value }

    # Mostrar la informacion con cabeceras
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "                INFORMACION DE WINGET                " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "Windows Version: " -NoNewline; Write-host $windowsVersion -ForegroundColor Yellow
    Write-Host "Arquitectura del sistema: " -NoNewline; Write-host $architecture -ForegroundColor Yellow
    Write-Host "Paquete: " -NoNewline; Write-host $packageVersion -ForegroundColor Yellow
}

function task {
    # ======================================================
    # Verificar tareas programadas de WAU-aaS
    # ======================================================
    Write-Host "" 
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "       VERIFICACION DE TAREAS PROGRAMADAS DE WAU      " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    $wauTasks = Get-ScheduledTask | Where-Object { $_.TaskName -match "Winget|WAU|AutoUpdate" } | Select-Object TaskName, State

    if ($wauTasks) {
        $wauTasks | ForEach-Object {
            Write-Host "Tarea: " -NoNewline; Write-Host "$($_.TaskName)" -ForegroundColor Yellow -NoNewline; Write-Host " - Estado: " -NoNewline; write-Host "$($_.State)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No se encontraron tareas programadas de WAU-aaS." -ForegroundColor Red
    }
}

function logs {
    # ======================================================
    # Verificar existencia de carpetas de logs
    # ======================================================
    Write-Host "" 
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "         VERIFICACION DE CARPETAS DE LOGS             " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    $logPaths = @(
        "C:\\ProgramData\\Winget-AutoUpdate\\Logs\\"
    )

    # Obtener todos los usuarios del sistema
    $users = Get-ChildItem -Path "C:\\Users" | Select-Object -ExpandProperty Name
    foreach ($user in $users) {
        $logPaths += "C:\\Users\\$user\\AppData\\Local\\Packages\\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\\LocalState\\DiagOutputDir"
    }

    foreach ($path in $logPaths) {
        if (Test-Path $path) {
            Write-Host "Existe: $path" -ForegroundColor Green
        } else {
            Write-Host "No existe: $path" -ForegroundColor Red
        }
    }
    # ======================================================
    # Analizar logs en busca de errores
    # ======================================================
    Write-Host "" 
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "         ANALISIS DE ERRORES EN LOS LOGS              " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    $logFiles = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir\" -Filter "*.log" -ErrorAction SilentlyContinue

    $errors = @{}
    $unknownErrors = @()

    if ($logFiles) {
        foreach ($logFile in $logFiles) {
            $logContent = Get-Content $logFile.FullName -Raw | Select-String "Error|w[0-9]+:" | Select-Object -Unique
            if ($logContent -match "Error encountered parsing command line") {
                $errors["Error de linea de comandos en Winget"] = " * Error de linea de comandos en Winget. Posibles causas: - El comando ejecutado podria estar mal escrito. - Un script esta pasando un argumento incorrecto. - Puede ser un problema con el archivo de configuracion de Winget."
            }
            if ($logContent -match "Could not create system restore point, error: 0x80070422") {
                $errors["No se pudo crear un punto de restauracion"] = " * No se pudo crear un punto de restauracion. Winget continuara con la instalacion o actualizacion sin el punto de restauracion."
            }
            $logContent | ForEach-Object {
                if ($_ -match "\[.*\]w\d+: (.+)") {
                    $unknownErrors += $matches[1]
                }
            }
        }
        if ($errors.Count -gt 0) {
            $errors.Values | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        $filteredErrors = $unknownErrors | Select-Object -Unique | Where-Object { $_ -notmatch "Could not create system restore point, error: 0x80070422" }
        if ($filteredErrors.Count -gt 0) {
        Write-Host " "
            Write-Host "Errores desconocidos detectados en los logs:" -ForegroundColor Cyan
            $filteredErrors | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
        }
        if ($errors.Count -eq 0 -and $filteredErrors.Count -eq 0) {
            Write-Host "No se encontraron errores en los logs." -ForegroundColor Green
        }
    } else {
        Write-Host "No se encontraron archivos de log para analizar." -ForegroundColor Yellow
    }
}

function app {
    # ======================================================
    # Verificar aplicaciones pendientes por actualizar
    # ======================================================
    Write-Host "" 
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "        APLICACIONES PENDIENTES POR ACTUALIZAR        " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    $updates = winget update | Select-Object -Skip 7 | Out-String

    if ($updates -match "\S") {
        Write-Host "Las siguientes aplicaciones tienen actualizaciones pendientes:" -ForegroundColor Yellow
        Write-host " "
        Write-Host $updates
    } else {
        Write-Host "No hay actualizaciones pendientes." -ForegroundColor Green
    }

    Write-Host " "
    Write-Host "Estado de las aplicaciones de las que depende el servicio:" -ForegroundColor Yellow
    winget list --name "Winget-AutoUpdate"
    Write-Host " "
}

cls 
# Definir ruta del archivo de salida
$logFilePath = "C:\Winget-Log.txt"

Check-AdminPrivileges

# Agregar una línea separadora para identificar cada ejecución
"======================================================" | Out-File -FilePath $logFilePath -Append
"            EJECUCION: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $logFilePath -Append
"======================================================" | Out-File -FilePath $logFilePath -Append

# Ejecutar funciones y guardar en archivo sin sobrescribir
info
task
logs
app

