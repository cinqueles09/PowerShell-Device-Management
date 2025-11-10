<#
.SYNOPSIS
    Comprueba el tiempo de actividad del sistema (uptime) y genera un resultado según el tiempo desde el último reinicio.

.DESCRIPTION
    Este script obtiene la hora del último arranque del sistema utilizando la clase WMI Win32_OperatingSystem 
    y calcula el tiempo total que el sistema ha estado encendido. 
    Si el equipo lleva más de un día sin reiniciarse, devuelve un código de salida 1.
    Si el equipo se ha reiniciado en las últimas 24 horas, devuelve 0.

.PARAMETER None
    No requiere parámetros.

.OUTPUTS
    Muestra en consola el tiempo total de encendido en horas y días.
    Código de salida:
        0 - El sistema se ha reiniciado en las últimas 24 horas.
        1 - El sistema lleva más de un día encendido.

.EXAMPLE
    PS C:\> .\Get-UptimeStatus.ps1
    Hace más de un día que no se reinicia. El sistema lleva encendido: 25.5 horas (~1.06 dias).

.NOTES
    Autor:       Ismael Morilla Orellana
    Versión:     1.0
    Fecha:       10/11/2025
    Compatibilidad: Windows 10 / Windows 11 / Windows Server 2016+
    Requisitos:  PowerShell 5.1 o superior

    Descripción adicional:
    Este script puede integrarse en tareas programadas, scripts de remediación o políticas de cumplimiento
    para detectar sistemas que no se reinician con frecuencia.

#>

# Obtener la hora del último arranque del sistema
$bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

# Obtener la hora actual
$now = Get-Date

# Calcular la diferencia
$uptime = $now - $bootTime
$totalHours = [math]::Round($uptime.TotalHours, 2)
$totalDays = [math]::Round($uptime.TotalDays, 2)

# Comprobar si hace más de un día
if ($uptime.TotalDays -ge 1) {
    Write-Output "Hace más de un día que no se reinicia. El sistema lleva encendido: $totalHours horas (~$totalDays dias)."
    exit 1
} else {
    Write-Output "Hace menos de un día que se reinició. El sistema lleva encendido: $totalHours horas (~$totalDays dias)."
    exit 0
}
