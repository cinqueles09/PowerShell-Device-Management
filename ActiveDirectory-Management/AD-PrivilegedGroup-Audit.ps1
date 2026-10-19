
#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Auditoria de pertenencia a grupos privilegiados de Active Directory.

.DESCRIPTION
    Comprueba si un usuario pertenece directa o indirectamente
    a determinados grupos privilegiados de Active Directory. ORIENTADO A CLOUD KERBEROS TRUST WHfB.

    El script debe ejecutarse en un controlador de dominio.
    Detecta automaticamente el DC local y realiza las consultas
    contra dicho servidor.

    Si no se especifica el usuario, se solicita por pantalla.

    Utiliza SID y LDAP_MATCHING_RULE_IN_CHAIN
    (OID: 1.2.840.113556.1.4.1941) para comprobar
    pertenencias directas y anidadas.

    Resultados:
        SI          = Rojo (pertenencia detectada)
        NO          = Verde (sin pertenencia detectada)
        DESCONOCIDO = Amarillo (error de comprobacion)

.PARAMETER Usuario
    SamAccountName del usuario que se desea auditar.
    Si se omite, se solicita de forma interactiva.

.PARAMETER ExportCsv
    Ruta opcional para exportar los resultados a CSV.

.PARAMETER NoInteractivo
    Impide solicitar datos por pantalla.
    Requiere especificar el parametro Usuario.

.EXAMPLE
    .\Get-ADPrivilegedGroupMembership.ps1

.EXAMPLE
    .\Get-ADPrivilegedGroupMembership.ps1 -Usuario "caunos"

.EXAMPLE
    .\Get-ADPrivilegedGroupMembership.ps1 `
        -Usuario "caunos" `
        -ExportCsv "C:\Auditorias\resultado.csv"

.NOTES
    Nombre     : Get-ADPrivilegedGroupMembership.ps1
    Version    : 1.4.1
    Fecha      : 19/10/2026
    Plataforma : Windows PowerShell 5.1+
    Modulo     : ActiveDirectory
    Ejecucion  : Exclusivamente en controladores de dominio
    Operacion  : Solo lectura sobre Active Directory

    Codigos de salida:
        0 = Sin pertenencias detectadas
        1 = Detectada pertenencia a grupos DENY
        2 = Error o auditoria incompleta

    IMPORTANTE:
    DENY es una clasificacion definida en el script.
    No se comprueban directivas GPO ni ACL reales.

    La regla LDAP utilizada no contempla primaryGroupID.

.CHANGELOG
    [1.4.1] - 19/10/2026
    - Eliminada la columna ESTADO de la consola.
    - Incorporada leyenda explicativa.
    - Conservado el control interno de errores.

    [1.4.0]
    - Presentacion de resultados con colores.

    [1.3.0]
    - Solicitud interactiva del usuario.
    - Parametro NoInteractivo.

    [1.2.0]
    - Ejecucion obligatoria desde un DC.
    - Deteccion automatica del DC local.

    [1.1.0]
    - Exportacion CSV y gestion de errores.

    [1.0.0]
    - Version inicial.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Usuario,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ExportCsv,

    [Parameter()]
    [switch]$NoInteractivo
)

$ErrorActionPreference = "Stop"

try {

    # ---------------------------------------------------------
    # 1. VALIDACION DEL USUARIO
    # ---------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($Usuario)) {

        if ($NoInteractivo) {
            throw "Debes especificar -Usuario cuando utilizas -NoInteractivo."
        }

        do {
            $Usuario = Read-Host "Introduce el usuario de Active Directory"

            if ($null -ne $Usuario) {
                $Usuario = $Usuario.Trim()
            }

            if ([string]::IsNullOrWhiteSpace($Usuario)) {
                Write-Warning "Debes introducir un nombre de usuario valido."
            }

        } while ([string]::IsNullOrWhiteSpace($Usuario))
    }
    else {
        $Usuario = $Usuario.Trim()
    }

    # ---------------------------------------------------------
    # 2. VALIDACION DEL ENTORNO
    # ---------------------------------------------------------

    Import-Module ActiveDirectory -ErrorAction Stop

    Write-Verbose "Validando entorno de ejecucion..."

    $Sistema = Get-CimInstance `
        -ClassName Win32_ComputerSystem `
        -ErrorAction Stop

    if ($Sistema.DomainRole -notin @(4, 5)) {
        throw "Este script solo puede ejecutarse en un controlador de dominio."
    }

    # ---------------------------------------------------------
    # 3. DETECCION DEL CONTROLADOR DE DOMINIO LOCAL
    # ---------------------------------------------------------

    $NombreLocal = $env:COMPUTERNAME
    $Servidor = "$NombreLocal.$($Sistema.Domain)"

    Write-Verbose "Controlador local detectado: $Servidor"

    $Conexion = Test-NetConnection `
        -ComputerName $Servidor `
        -Port 9389 `
        -WarningAction SilentlyContinue

    if (-not $Conexion.TcpTestSucceeded) {
        throw "ADWS no esta disponible en ${Servidor}:9389."
    }

    Write-Verbose "Conexion con ADWS correcta."

    # ---------------------------------------------------------
    # 4. OBTENCION DEL USUARIO Y DOMINIO
    # ---------------------------------------------------------

    $User = Get-ADUser `
        -Identity $Usuario `
        -Server $Servidor `
        -ErrorAction Stop

    $Domain = Get-ADDomain `
        -Server $Servidor `
        -ErrorAction Stop

    $DomainSID = $Domain.DomainSID.Value

    Write-Verbose "Dominio: $($Domain.DNSRoot)"
    Write-Verbose "Usuario: $($User.SamAccountName)"

    # ---------------------------------------------------------
    # 5. DEFINICION DE GRUPOS PRIVILEGIADOS
    # ---------------------------------------------------------

    $Grupos = @(
        @{ Nombre = "Administracion de empresas"; SID = "$DomainSID-519" }
        @{ Nombre = "Administradores"; SID = "S-1-5-32-544" }
        @{ Nombre = "Administradores de esquema"; SID = "$DomainSID-518" }
        @{ Nombre = "Admins. del dominio"; SID = "$DomainSID-512" }
        @{ Nombre = "Controladores de dominio"; SID = "$DomainSID-516" }
        @{ Nombre = "Operadores de copia"; SID = "S-1-5-32-551" }
        @{ Nombre = "Opers. de cuentas"; SID = "S-1-5-32-548" }
        @{ Nombre = "Opers. de servidores"; SID = "S-1-5-32-549" }
        @{ Nombre = "Publicadores de certificados"; SID = "$DomainSID-517" }
    )

    # ---------------------------------------------------------
    # 6. AUDITORIA DE PERTENENCIA
    # ---------------------------------------------------------

    $Resultado = @(
        foreach ($Grupo in $Grupos) {

            Write-Verbose "Comprobando grupo: $($Grupo.Nombre)"

            try {

                $ADGrupo = Get-ADGroup `
                    -Identity $Grupo.SID `
                    -Server $Servidor `
                    -ErrorAction Stop

                $Filtro = "(&(objectCategory=person)(objectClass=user)(distinguishedName=$($User.DistinguishedName))(memberOf:1.2.840.113556.1.4.1941:=$($ADGrupo.DistinguishedName)))"

                $Encontrado = Get-ADUser `
                    -LDAPFilter $Filtro `
                    -Server $Servidor `
                    -ErrorAction Stop

                $Pertenencia = if ($Encontrado) {
                    "SI"
                }
                else {
                    "NO"
                }

                [PSCustomObject]@{
                    Usuario   = $Usuario
                    Grupo     = $Grupo.Nombre
                    SID       = $Grupo.SID
                    Politica  = "Deny"
                    Pertenece = $Pertenencia
                    Estado    = "OK"
                }

            }
            catch {

                Write-Warning (
                    "Error al comprobar '{0}': {1}" -f `
                    $Grupo.Nombre, $_.Exception.Message
                )

                [PSCustomObject]@{
                    Usuario   = $Usuario
                    Grupo     = $Grupo.Nombre
                    SID       = $Grupo.SID
                    Politica  = "Deny"
                    Pertenece = "DESCONOCIDO"
                    Estado    = "ERROR"
                }
            }
        }
    )

    # ---------------------------------------------------------
    # 7. PRESENTACION DE RESULTADOS CON COLORES
    # ---------------------------------------------------------

    Write-Host ""
    Write-Host "AUDITORIA DE GRUPOS PRIVILEGIADOS" -ForegroundColor Cyan
    Write-Host "Usuario : $Usuario"
    Write-Host "Servidor: $Servidor"
    Write-Host ""

    Write-Host ("{0,-38} {1,-12} {2,-14}" -f `
        "GRUPO", "POLITICA", "PERTENECE") `
        -ForegroundColor Cyan

    Write-Host ("-" * 66) -ForegroundColor DarkGray

    foreach ($Item in $Resultado) {

        $Color = switch ($Item.Pertenece) {
            "SI"    { "Red" }
            "NO"    { "Green" }
            default { "Yellow" }
        }

        Write-Host ("{0,-38} " -f $Item.Grupo) -NoNewline
        Write-Host ("{0,-12} " -f $Item.Politica) -NoNewline

        Write-Host ("{0,-14}" -f $Item.Pertenece) `
            -ForegroundColor $Color
    }

    Write-Host ("-" * 66) -ForegroundColor DarkGray

    # ---------------------------------------------------------
    # 8. LEYENDA DE RESULTADOS
    # ---------------------------------------------------------

    Write-Host ""
    Write-Host "LEYENDA" -ForegroundColor Cyan

    Write-Host "  SI           " -ForegroundColor Red -NoNewline
    Write-Host "- Pertenece al grupo (ALERTA)."

    Write-Host "  NO           " -ForegroundColor Green -NoNewline
    Write-Host "- No pertenece al grupo."

    Write-Host "  DESCONOCIDO  " -ForegroundColor Yellow -NoNewline
    Write-Host "- No se ha podido comprobar."

    Write-Host ""
    Write-Host "  Deny         - Grupo incluido en la lista de auditoria."
    Write-Host "                 No implica una denegacion real mediante GPO o ACL."

    # ---------------------------------------------------------
    # 9. EXPORTACION CSV
    # ---------------------------------------------------------

    if ($ExportCsv) {

        $RutaCompleta = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
            $ExportCsv
        )

        $Directorio = Split-Path -Path $RutaCompleta -Parent

        if (-not (Test-Path -LiteralPath $Directorio -PathType Container)) {

            New-Item `
                -Path $Directorio `
                -ItemType Directory `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        $Resultado | Select-Object Usuario, Grupo, SID, Politica, Pertenece |
            Export-Csv `
                -LiteralPath $RutaCompleta `
                -NoTypeInformation `
                -Delimiter ";" `
                -Encoding UTF8 `
                -ErrorAction Stop

        Write-Host ""
        Write-Host "CSV exportado: $RutaCompleta" -ForegroundColor Cyan
    }

    # ---------------------------------------------------------
    # 10. EVALUACION FINAL
    # ---------------------------------------------------------

    $Errores = @(
        $Resultado | Where-Object { $_.Estado -eq "ERROR" }
    )

    $Pertenencias = @(
        $Resultado | Where-Object { $_.Pertenece -eq "SI" }
    )

    Write-Host ""

    if ($Errores.Count -gt 0) {

        Write-Warning "Auditoria incompleta: $($Errores.Count) grupo(s) con errores."
        exit 2
    }

    if ($Pertenencias.Count -gt 0) {

        Write-Warning (
            "ALERTA: El usuario '{0}' pertenece a {1} grupo(s) DENY." -f `
            $Usuario, $Pertenencias.Count
        )

        exit 1
    }

    Write-Host "OK: No se han detectado pertenencias a grupos DENY." `
        -ForegroundColor Green

    exit 0

}
catch {

    Write-Error "Error durante la auditoria: $($_.Exception.Message)"
    exit 2
}
