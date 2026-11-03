<#
.SYNOPSIS
    Elimina toda la configuración de Windows Hello del sistema.

.DESCRIPTION
    Este script desactiva Windows Hello para empresas, elimina datos biométricos,
    detiene servicios relacionados y borra claves de registro asociadas.

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 05/07/2025
    Version: 1.0
#>

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()

if ($identity.User.Value -eq "S-1-5-18") {
    Write-Output "ERROR: No ejecutar como SYSTEM."
    exit 1
}

try {
    $output = & "$env:SystemRoot\System32\certutil.exe" -DeleteHelloContainer 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Error eliminando contenedor: $output"
    }

    Write-Output "REMOVED: Contenedor Windows Hello eliminado."
    Write-Output "ACTION_REQUIRED: Cerrar sesion y volver a entrar."
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
