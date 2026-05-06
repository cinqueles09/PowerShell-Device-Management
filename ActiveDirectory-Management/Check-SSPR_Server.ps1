<#
.SYNOPSIS
    SSPR_0030 - Microsoft Entra Connect Diagnostic Tool (Multi-namespace)
    
.DESCRIPTION
    Realiza un diagnóstico exhaustivo de red, protocolos TLS, configuración de Proxy y dependencias .NET
    específicamente para el servicio de Password Writeback (SSPR).
    Detecta dinámicamente los namespaces de Azure Service Bus analizando los logs de eventos.

.NOTES
    Autor: Ismael Morilla Orellana
    Versión: 2.0.1
    Fecha: 06/05/2026
    Requiere: PowerShell 5.1 o superior y privilegios de Administrador.
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Días de histórico para analizar eventos de aplicación.")]
    [int]$DaysBack = 7,

    [Parameter(HelpMessage = "Límite de eventos a procesar para optimizar rendimiento.")]
    [int]$MaxEvents = 500,

    [Parameter(HelpMessage = "Namespace adicional para pruebas manuales.")]
    [string]$AddNamespace,

    [Parameter(HelpMessage = "GUID del conector AAD de Entra Connect para verificar Password Writeback.")]
    [string]$AADConnectorId = "b891884f-051e-4a83-95af-2544101c9083"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# -------------------- Funciones de Soporte --------------------

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-WinHttpProxy {
    try {
        $proxyInfo = & netsh winhttp show proxy 2>&1 | Out-String
        return $proxyInfo.Trim()
    } catch {
        return "CRITICAL: Fallo al consultar WinHTTP Proxy: $($_.Exception.Message)"
    }
}

function Get-DotNetStatus {
    $regPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
    $release = $null

    if (Test-Path $regPath) {
        try { $release = (Get-ItemProperty -Path $regPath -ErrorAction Stop).Release } catch {}
    }

    $isMinimumVersion = ($null -ne $release -and [int]$release -ge 528040)

    return [pscustomobject]@{
        RegistryPath = $regPath
        ReleaseValue = $release
        IsCompliant  = $isMinimumVersion
        Description  = if ($null -eq $release) { "No detectado" } elseif ($isMinimumVersion) { ".NET 4.8 o superior (OK)" } else { "Versión obsoleta (Revisar)" }
    }
}

function Get-Tls12Config {
    param([ValidateSet("Client","Server")]$Role)

    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\$Role"
    
    if (-not (Test-Path $registryPath)) {
        return [pscustomobject]@{
            Role = $Role; Path = $registryPath; KeyExists = $false; IsEnabled = $false; Note = "Clave SCHANNEL no configurada"
        }
    }

    $enabled = $null
    $disabledByDefault = $null
    try {
        $props = Get-ItemProperty -Path $registryPath -ErrorAction Stop
        $enabled = $props.Enabled
        $disabledByDefault = $props.DisabledByDefault
    } catch {}

    $status = ($null -ne $enabled -and [int]$enabled -eq 1)

    return [pscustomobject]@{
        Role              = $Role
        Path              = $registryPath
        KeyExists         = $true
        EnabledValue      = $enabled
        DisabledByDefault = $disabledByDefault
        IsEnabled         = $status
        Note              = if ($status) { "Configuración Correcta" } else { "TLS 1.2 no habilitado explícitamente" }
    }
}

function Test-NetworkEndpoint {
    param(
        [Parameter(Mandatory)] [string]$Target,
        [Parameter(Mandatory)] [int]$Port
    )

    try {
        $connection = Test-NetConnection -ComputerName $Target -Port $Port -WarningAction SilentlyContinue -InformationAction SilentlyContinue
        return [pscustomobject]@{
            Target           = $Target
            Port             = $Port
            RemoteIp         = $connection.RemoteAddress
            Success          = [bool]$connection.TcpTestSucceeded
            Diagnostics      = "OK"
        }
    } catch {
        return [pscustomobject]@{
            Target           = $Target
            Port             = $Port
            RemoteIp         = $null
            Success          = $false
            Diagnostics      = $_.Exception.Message
        }
    }
}

function Test-ServiceBusHealth {
    param([Parameter(Mandatory)][string]$Uri)

    try {
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -Method GET -TimeoutSec 20 -ErrorAction Stop
        return [pscustomobject]@{
            Uri        = $Uri
            StatusCode = $response.StatusCode
            Status     = "Success"
            Type       = $response.Headers.'Content-Type'
            Accessible = $true
            Error      = $null
        }
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        return [pscustomobject]@{
            Uri        = $Uri
            StatusCode = $code
            Status     = "Failed"
            Type       = $null
            Accessible = $false
            Error      = $_.Exception.Message
        }
    }
}

function Discover-ServiceBusNamespaces {
    param([int]$Days, [int]$Limit)

    $startTime = (Get-Date).AddDays(-$Days)
    $eventIds = @(31019, 31034)
    $results = New-Object System.Collections.Generic.List[object]

    $patterns = @(
        '(?i)\bHeartBeat\s+for\s+Namespace:\s*([a-z0-9-]+)\b',
        '(?i)\bNamespace:\s*([a-z0-9-]+)\b',
        '(?i)\b([a-z0-9-]+)\.servicebus\.windows\.net\b'
    )

    try {
        $events = Get-WinEvent -FilterHashtable @{LogName="Application"; Id=$eventIds; StartTime=$startTime} -ErrorAction SilentlyContinue | 
                  Sort-Object TimeCreated -Descending | Select-Object -First $Limit

        foreach ($ev in $events) {
            foreach ($p in $patterns) {
                if ($ev.Message -match $p) {
                    $nsName = $Matches[1].ToLower()
                    $results.Add([pscustomobject]@{
                        Timestamp     = $ev.TimeCreated
                        EventId       = $ev.Id
                        Namespace     = $nsName
                        NamespaceFqdn = "$nsName.servicebus.windows.net"
                        Source        = "EventLog-ID$($ev.Id)"
                    })
                    break
                }
            }
        }
    } catch {}

    return $results | Group-Object NamespaceFqdn | ForEach-Object { $_.Group | Select-Object -First 1 }
}

# -------------------- NUEVA FUNCIÓN: ADSync Password Writeback --------------------

function Get-PasswordWritebackStatus {
    param([string]$ConnectorId)

    $result = [pscustomobject]@{
        Available         = $false
        ConnectorFound    = $false
        ConnectorName     = $null
        ConnectorId       = $ConnectorId
        Enabled           = $null
        EnabledStatus     = "Desconocido"
        EnabledColor      = "Gray"
        ModifiedTimestamp = $null
        ModifiedAge       = $null
        ServiceStatus     = $null
        ServiceStatusOk   = $false
        OnboardingStatus  = $null
        Error             = $null
    }

    # Verificar si el módulo ADSync está disponible
    if (-not (Get-Module -Name ADSync -ListAvailable -ErrorAction SilentlyContinue)) {
        $result.Error = "Módulo ADSync no disponible en este equipo. Ejecutar en el servidor de Entra Connect."
        return $result
    }

    try {
        Import-Module ADSync -ErrorAction Stop
        $result.Available = $true
    } catch {
        $result.Error = "Error al importar módulo ADSync: $($_.Exception.Message)"
        return $result
    }

    # Obtener el conector AAD por GUID
    try {
        $connector = Get-ADSyncConnector -ErrorAction Stop | Where-Object { $_.Identifier -eq $ConnectorId }

        if (-not $connector) {
            $result.Error = "No se encontró ningún conector con ID: $ConnectorId"
            return $result
        }

        $result.ConnectorFound = $true
        $result.ConnectorName  = $connector.Name

    } catch {
        $result.Error = "Error al obtener conectores ADSync: $($_.Exception.Message)"
        return $result
    }

    # Obtener configuración de Password Reset para el conector
    try {
        $pwConfig = Get-ADSyncAADPasswordResetConfiguration -Connector $connector.Name -ErrorAction Stop

        # --- Enabled ---
        $result.Enabled = $pwConfig.Enabled
        if ($pwConfig.Enabled -eq $true) {
            $result.EnabledStatus = "HABILITADO"
            $result.EnabledColor  = "Green"
        } elseif ($pwConfig.Enabled -eq $false) {
            $result.EnabledStatus = "DESHABILITADO"
            $result.EnabledColor  = "Red"
        } else {
            $result.EnabledStatus = "No determinado"
            $result.EnabledColor  = "Yellow"
        }

        # --- Timestamp modificación ---
        $result.ModifiedTimestamp = $pwConfig.ModifiedTimestamp
        if ($pwConfig.ModifiedTimestamp) {
            $age = (Get-Date) - $pwConfig.ModifiedTimestamp
            $result.ModifiedAge = "{0}d {1}h {2}m" -f [int]$age.TotalDays, $age.Hours, $age.Minutes
        }

        # --- Estado del servicio ---
        $result.ServiceStatus   = $pwConfig.ServiceStatus
        $result.ServiceStatusOk = ($pwConfig.ServiceStatus -eq "Started")

        # --- Onboarding ---
        $result.OnboardingStatus = $pwConfig.OnboardingRequiredStatus

    } catch {
        $result.Error = "Error al obtener configuración de Password Reset: $($_.Exception.Message)"
    }

    return $result
}

# -------------------- Ejecución Principal --------------------

$isAdmin = Test-IsAdmin
$reportPath = "C:\ProgramData\SSPR-Diag"
Ensure-Directory $reportPath

$fileDate = Get-Date -Format "yyyyMMdd_HHmmss"
$logTxt   = Join-Path $reportPath "SSPR_Diagnostic_$fileDate.txt"
$logJson  = Join-Path $reportPath "SSPR_Diagnostic_$fileDate.json"

Write-Host "`n[#] SSPR / Entra Connect - Herramienta de Diagnóstico de Red" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"
Write-Host "Servidor: $env:COMPUTERNAME"
$adminColor = if($isAdmin){'Green'}else{'Yellow'}
Write-Host "Privilegios: $(if($isAdmin){'Admin OK'}else{'LIMITADO'})" -ForegroundColor $adminColor

# 1. Descubrimiento
$detectedNs = Discover-ServiceBusNamespaces -Days $DaysBack -Limit $MaxEvents
$uniqueFqdns = New-Object System.Collections.Generic.List[string]

if ($detectedNs) { 
    $detectedNs.NamespaceFqdn | ForEach-Object { $uniqueFqdns.Add($_) }
}

if (-not [string]::IsNullOrWhiteSpace($AddNamespace)) {
    $manual = "$($AddNamespace.ToLower()).servicebus.windows.net"
    if ($uniqueFqdns -notcontains $manual) { $uniqueFqdns.Add($manual) }
}

# 2. Pruebas de conectividad
$globalTests = @()
$globalTests += Test-NetworkEndpoint -Target "passwordreset.microsoftonline.com" -Port 443
#$globalTests += Test-NetworkEndpoint -Target "servicebus.windows.net" -Port 443

$nsTcpTests  = @()
$nsHttpTests = @()
$nsSbPorts   = @()

foreach ($fqdn in $uniqueFqdns) {
    Write-Host "[>] Analizando namespace: $fqdn..." -ForegroundColor Gray
    $nsTcpTests  += Test-NetworkEndpoint -Target $fqdn -Port 443
    $nsHttpTests += Test-ServiceBusHealth -Uri "https://$fqdn/"
    9350..9354 | ForEach-Object { $nsSbPorts += Test-NetworkEndpoint -Target $fqdn -Port $_ }
}

# 3. Protocolos y Sistema
$tlsClient = Get-Tls12Config -Role "Client"
$tlsServer = Get-Tls12Config -Role "Server"
$proxyData = Get-WinHttpProxy
$dotnet    = Get-DotNetStatus

# 4. Estado Password Writeback (ADSync)
Write-Host "`n[>] Consultando estado de Password Writeback (ADSync)..." -ForegroundColor Gray
$pwbStatus = Get-PasswordWritebackStatus -ConnectorId $AADConnectorId

# -------------------- Presentación de Resultados --------------------

Write-Host "`n[+] RESULTADOS DE CONECTIVIDAD" -ForegroundColor Cyan
foreach ($test in $globalTests) {
    $statusText = if($test.Success){"PASSED"}else{"FAILED"}
    $color = if($test.Success){"Green"}else{"Red"}
    Write-Host (" - {0}:443 -> {1}" -f $test.Target, $statusText) -ForegroundColor $color
}

if ($uniqueFqdns.Count -gt 0) {
    Write-Host "`n[+] NAMESPACES DETECTADOS" -ForegroundColor Cyan
    foreach ($test in $nsTcpTests) {
        $statusText = if($test.Success){"OK"}else{"FAIL"}
        Write-Host (" - {0} (TCP 443): {1}" -f $test.Target, $statusText)
    }
}

Write-Host "`n[+] CONFIGURACIÓN LOCAL" -ForegroundColor Cyan
Write-Host (" - TLS 1.2 Client: {0}" -f $tlsClient.Note)
Write-Host (" - TLS 1.2 Server: {0}" -f $tlsServer.Note)
Write-Host (" - .NET Framework: {0}" -f $dotnet.Description)

# -------------------- NUEVO BLOQUE: Password Writeback --------------------

Write-Host "`n[+] PASSWORD WRITEBACK - ESTADO DEL CONECTOR AAD" -ForegroundColor Cyan
Write-Host ("    Connector ID : {0}" -f $AADConnectorId)

if (-not $pwbStatus.Available) {
    Write-Host ("    [!] {0}" -f $pwbStatus.Error) -ForegroundColor Yellow

} elseif (-not $pwbStatus.ConnectorFound) {
    Write-Host ("    [!] {0}" -f $pwbStatus.Error) -ForegroundColor Red

} elseif ($pwbStatus.Error) {
    Write-Host ("    Conector     : {0}" -f $pwbStatus.ConnectorName)
    Write-Host ("    [!] Error    : {0}" -f $pwbStatus.Error) -ForegroundColor Red

} else {
    Write-Host ("    Conector     : {0}" -f $pwbStatus.ConnectorName)

    # Enabled
    $enabledColor = $pwbStatus.EnabledColor
    Write-Host ("    Enabled      : {0}" -f $pwbStatus.EnabledStatus) -ForegroundColor $enabledColor

    # Fecha de modificación
    if ($pwbStatus.ModifiedTimestamp) {
        Write-Host ("    Modificado   : {0}  (hace {1})" -f $pwbStatus.ModifiedTimestamp.ToString("dd/MM/yyyy HH:mm:ss"), $pwbStatus.ModifiedAge)
    } else {
        Write-Host "    Modificado   : No disponible" -ForegroundColor Yellow
    }

    # ServiceStatus
    $svcColor = if ($pwbStatus.ServiceStatusOk) { "Green" } else { "Red" }
    $svcLabel = if ($pwbStatus.ServiceStatusOk) { "OK" } else { "REVISAR" }
    Write-Host ("    ServiceStatus: {0}  [{1}]" -f $pwbStatus.ServiceStatus, $svcLabel) -ForegroundColor $svcColor

    # Onboarding
    Write-Host ("    Onboarding   : {0}" -f $pwbStatus.OnboardingStatus)
}

# -------------------- Generación de Reportes --------------------

$reportData = [ordered]@{
    Metadata = @{
        Timestamp = Get-Date -Format "o"
        Host      = $env:COMPUTERNAME
        IsAdmin   = $isAdmin
    }
    Discovery = @{
        Count = $uniqueFqdns.Count
        List  = $uniqueFqdns
    }
    Connectivity = @{
        GlobalTests          = $globalTests
        NamespaceTcp         = $nsTcpTests
        NamespaceHttp        = $nsHttpTests
        ServiceBusRelayPorts = $nsSbPorts
    }
    System = @{
        TLS    = @{ Client = $tlsClient; Server = $tlsServer }
        Proxy  = $proxyData
        DotNet = $dotnet
    }
    PasswordWriteback = @{
        ConnectorId       = $pwbStatus.ConnectorId
        ConnectorName     = $pwbStatus.ConnectorName
        Enabled           = $pwbStatus.Enabled
        EnabledStatus     = $pwbStatus.EnabledStatus
        ModifiedTimestamp = if ($pwbStatus.ModifiedTimestamp) { $pwbStatus.ModifiedTimestamp.ToString("o") } else { $null }
        ModifiedAge       = $pwbStatus.ModifiedAge
        ServiceStatus     = $pwbStatus.ServiceStatus
        ServiceStatusOk   = $pwbStatus.ServiceStatusOk
        OnboardingStatus  = $pwbStatus.OnboardingStatus
        Error             = $pwbStatus.Error
    }
}

$reportData | ConvertTo-Json -Depth 10 | Out-File $logJson -Encoding UTF8

# Reporte TXT resumido
$txtBuilder = New-Object System.Collections.Generic.List[string]
$txtBuilder.Add("DIAGNÓSTICO SSPR - $env:COMPUTERNAME")
$txtBuilder.Add("="*40)
$txtBuilder.Add("Namespaces: $($uniqueFqdns -join ', ')")
$txtBuilder.Add("TLS 1.2 Client: $($tlsClient.IsEnabled)")
$txtBuilder.Add("TLS 1.2 Server: $($tlsServer.IsEnabled)")
$txtBuilder.Add(".NET 4.8+: $($dotnet.IsCompliant)")
$txtBuilder.Add("WinHTTP Proxy: $proxyData")
$txtBuilder.Add("")
$txtBuilder.Add("--- PASSWORD WRITEBACK ---")
$txtBuilder.Add("Connector ID  : $($pwbStatus.ConnectorId)")
$txtBuilder.Add("Connector     : $($pwbStatus.ConnectorName)")
$txtBuilder.Add("Enabled       : $($pwbStatus.EnabledStatus)")
$txtBuilder.Add("Modificado    : $($pwbStatus.ModifiedTimestamp) (hace $($pwbStatus.ModifiedAge))")
$txtBuilder.Add("ServiceStatus : $($pwbStatus.ServiceStatus)")
$txtBuilder.Add("Onboarding    : $($pwbStatus.OnboardingStatus)")
if ($pwbStatus.Error) { $txtBuilder.Add("Error         : $($pwbStatus.Error)") }
$txtBuilder.Add("")
$txtBuilder.Add("Detalle de conectividad:")
($globalTests + $nsTcpTests) | ForEach-Object { 
    $txtBuilder.Add(" - $($_.Target):$($_.Port) -> Success:$($_.Success)") 
}

$txtBuilder | Out-File $logTxt -Encoding UTF8

Write-Host "`n[!] Reportes generados con éxito en:" -ForegroundColor Green
Write-Host " > $logTxt"
Write-Host " > $logJson`n"
