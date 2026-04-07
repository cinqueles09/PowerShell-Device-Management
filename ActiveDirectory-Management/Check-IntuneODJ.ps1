<#
.SYNOPSIS
    Realiza una auditoría técnica de los requisitos para el Intune ODJ Connector (Autopilot).

.DESCRIPTION
    Este script verifica los requisitos críticos para el funcionamiento de Hybrid Azure AD Join:
    - Versión de Windows Server (2016 o superior).
    - Unión al dominio Active Directory local.
    - Versión de .NET Framework (mínimo 4.7.2).
    - Conectividad con endpoints de Microsoft (login.microsoftonline.com y graph.microsoft.com).
    - Configuración de DNS y estado del servicio IntuneODJConnectorSvc.

.NOTES
    Autor      : Ismael Morilla Orellana
    Fecha      : 07/04/2026
    Versión    : 1.2
    Requisitos : Módulo ActiveDirectory y privilegios de Administrador Local.
    Uso        : Ejecutar en el servidor donde se aloja o se planea instalar el conector.

.EXAMPLE
    .\Check-IntuneODJ.ps1
    Ejecuta la comprobación y muestra los resultados formateados por consola con códigos de colores.
#>

# --- INICIO DEL SCRIPT ---
Clear-Host
$Results = New-Object System.Collections.Generic.List[PSObject]

# Obtener contexto del sistema
$computerName = $env:COMPUTERNAME
$domainName = (Get-CimInstance Win32_ComputerSystem).Domain
$fqdn = if ($domainName) { "$computerName.$domainName" } else { $computerName }

# --- CABECERA VISUAL ---
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   REPORTE DE ESTADO: INTUNE HYBRID AD JOIN CONNECTOR" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SERVIDOR : " -NoNewline; Write-Host $fqdn -ForegroundColor Yellow
Write-Host " FECHA    : " -NoNewline; Write-Host (Get-Date -Format "dd/MM/yyyy HH:mm:ss") -ForegroundColor Yellow
Write-Host " EJECUTOR : " -NoNewline; Write-Host $env:USERNAME -ForegroundColor Yellow
Write-Host "------------------------------------------------------------`n"

function Add-Check {
    param($Requirement, $Status, $Details)
    $Results.Add([PSCustomObject]@{
        Requisito = $Requirement
        Estado    = $Status
        Detalles  = $Details
    })
}

# 1. Sistema Operativo
$os = Get-CimInstance Win32_OperatingSystem
if ($os.Caption -match "Windows Server" -and [int]$os.BuildNumber -ge 14393) {
    Add-Check "Sistema Operativo" "PASS" $os.Caption
} else {
    Add-Check "Sistema Operativo" "FAIL" "No soportado: $($os.Caption)"
}

# 2. Unión al Dominio
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.PartOfDomain) {
    Add-Check "Unión a Dominio" "PASS" "Dominio: $domainName"
} else {
    Add-Check "Unión a Dominio" "FAIL" "El servidor no está unido al dominio"
}

# 3. .NET Framework
try {
    $reg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue
    if ($reg) {
        $release = $reg.Release
        $vFriendly = switch ($release) {
            { $_ -ge 533320 } { "4.8.1"; break }
            { $_ -ge 528040 } { "4.8";   break }
            { $_ -ge 461808 } { "4.7.2"; break }
            { $_ -ge 461308 } { "4.7.1"; break }
            { $_ -ge 460798 } { "4.7";   break }
            default           { "Antigua"; break }
        }
        $status = if ($release -ge 461808) { "PASS" } else { "FAIL" }
        Add-Check ".NET Framework" $status "v$vFriendly (Release: $release)"
    } else {
        Add-Check ".NET Framework" "FAIL" "No detectado"
    }
} catch { Add-Check ".NET Framework" "FAIL" "Error de consulta" }

# 4. Conectividad
$urls = @("login.microsoftonline.com", "graph.microsoft.com")
foreach ($u in $urls) {
    $test = Test-NetConnection $u -Port 443 -WarningAction SilentlyContinue
    if ($test.TcpTestSucceeded) {
        Add-Check "Red: $u" "PASS" "Puerto 443 OK"
    } else {
        Add-Check "Red: $u" "FAIL" "Puerto 443 bloqueado"
    }
}

# 5. DNS
$dnsAddresses = (Get-DnsClientServerAddress | Where-Object {$_.ServerAddresses}).ServerAddresses -join ", "
if ($dnsAddresses) {
    Add-Check "DNS" "PASS" $dnsAddresses
} else {
    Add-Check "DNS" "FAIL" "Sin servidores DNS"
}

# 6. Servicio ODJ Connector
$svc = Get-Service -Name "IntuneODJConnectorSvc" -ErrorAction SilentlyContinue
if ($svc) {
    $svcStatus = if ($svc.Status -eq "Running") { "PASS" } else { "WARN" }
    Add-Check "Servicio ODJ" $svcStatus "Estado: $($svc.Status)"
} else {
    Add-Check "Servicio ODJ" "WARN" "No instalado"
}

# --- RENDERIZADO FINAL ---
foreach ($r in $Results) {
    $color = switch($r.Estado) { "PASS" {"Green"} "WARN" {"Yellow"} "FAIL" {"Red"} default {"White"} }
    Write-Host ("[{0}] " -f $r.Estado.PadRight(4)) -NoNewline -ForegroundColor $color
    Write-Host ("{0}" -f $r.Requisito.PadRight(22)) -NoNewline
    Write-Host ": $($r.Detalles)"
}
