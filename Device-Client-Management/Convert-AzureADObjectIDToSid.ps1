<#
.SYNOPSIS
    Conversor de SID de Azure AD a Object ID de Microsoft Entra ID.

.DESCRIPTION
    Este script toma un SID de usuario/grupo de Azure (formato S-1-12-1-...) generado en 
    dispositivos locales y lo traduce a su Object ID original de la nube, consultando 
    posteriormente el nombre del objeto en Microsoft Graph.

.NOTES
    Autor: Ismael Morilla Orellana
    Versión: 2.0
    Requisitos: Módulo Microsoft.Graph.Identities
#>

# Configuración de estilo
$ErrorActionPreference = "Stop"
Clear-Host

Write-Host "=========================================================" -ForegroundColor Magenta
Write-Host "   ENTRA ID SID RESOLVER - HERRAMIENTA DE DIAGNÓSTICO    " -ForegroundColor White -BackgroundColor Magenta
Write-Host "=========================================================" -ForegroundColor Magenta

function Convert-AzureAdSIDtoObjectId {
    param([String] $Sid)
    try {
        $text = $Sid.Replace('S-1-12-1-', "")
        $array = [UInt32[]]$text.Split('-')
        $bytes = New-Object 'Byte[]' 16
        [Buffer]::BlockCopy($array, 0, $bytes, 0, 16)
        return [Guid]$bytes
    }
    catch {
        return $null
    }
}

# 1. Entrada de datos
$sidInput = Read-Host "`n[?] Introduce el SID para identificar"

if (-not $sidInput.StartsWith("S-1-12-1")) {
    Write-Host "`n[!] ADVERTENCIA: El SID no parece tener el formato de Azure AD (S-1-12-1)." -ForegroundColor Yellow
}

$guidResult = Convert-AzureAdSIDtoObjectId -Sid $sidInput

if ($null -eq $guidResult) {
    Write-Host "[X] ERROR: El formato del SID es inválido." -ForegroundColor Red
    return
}

$objectId = $guidResult.Guid

# 2. Consulta y Visualización
Write-Host "`n[i] Conectando con Microsoft Graph..." -ForegroundColor Gray

try {
    # Intenta obtener el objeto del directorio
    $directoryObject = Get-MgDirectoryObject -DirectoryObjectId $objectId
    
    # Procesar metadatos
    $displayName = $directoryObject.AdditionalProperties['displayName']
    if (-not $displayName) { $displayName = "N/A" }
    
    $type = $directoryObject.AdditionalProperties['@odata.type'] -replace "#microsoft.graph.", ""
    $type = $type.ToUpper()

    # Panel de resultados profesional
    Write-Host "`n+-------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "| RESULTADOS DE LA BÚSQUEDA" -ForegroundColor Cyan
    Write-Host "+-------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "| " -NoNewline; Write-Host "TIPO:        " -ForegroundColor DarkGray -NoNewline; Write-Host $type -ForegroundColor White
    Write-Host "| " -NoNewline; Write-Host "NOMBRE:      " -ForegroundColor DarkGray -NoNewline; Write-Host $displayName -ForegroundColor Green -FontWeight Bold
    Write-Host "| " -NoNewline; Write-Host "OBJECT ID:   " -ForegroundColor DarkGray -NoNewline; Write-Host $objectId -ForegroundColor White
    Write-Host "+-------------------------------------------------------" -ForegroundColor Cyan
}
catch {
    Write-Host "`n[!] No se encontró el objeto en el Directorio Activo." -ForegroundColor Red
    Write-Host "[?] Posibles causas: El objeto fue eliminado o no tienes sesión iniciada." -ForegroundColor Gray
    Write-Host "[?] Tip: Ejecuta 'Connect-MgGraph -Scopes Directory.Read.All'" -ForegroundColor Gray
}

Write-Host "`n Proceso finalizado.`n"
