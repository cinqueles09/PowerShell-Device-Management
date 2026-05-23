# ============================================================
#  DEMO — Reutilización de tickets Kerberos (PtT)
#  Demuestra el riesgo de exposición y reutilización de tickets Kerberos
#  Ejecutar en: DC o equipo unido al dominio (como admin)
#  Resultado visible: Visor de Eventos > Seguridad > 4768/4769
# ============================================================
# INSTRUCCIONES PARA EL FORMADOR:
#   Esta demo tiene TRES actos:
#
#   ACTO 1 — Cómo funcionan los tickets Kerberos (contexto)
#     Muestra los tickets activos en memoria del equipo.
#     Los alumnos ven que hay TGT y TGS reales en sesión.
#
#   ACTO 2 — El problema: ticket expuesto = identidad reutilizable
#     Solicita un TGS de la sesión actual y muestra la evidencia.
#     La demo no exporta material de autenticación ni lo reutiliza.
#
#   ACTO 3 — La mitigación: Protected Users + Auth Policies
#     Muestra cómo Protected Users limita el TGT a 4 horas
#     y deshabilita la delegación. Ventana de ataque mínima.
#
#   NOTA IMPORTANTE:
#     Esta demo NO exporta ni importa tickets. Demuestra el concepto
#     con klist, eventos Kerberos reales y PowerShell nativo.
#     El impacto se entiende sin necesidad de ejecutar el ataque.
# ============================================================

$Dominio      = "contoso.com"               # <-- ajusta
$OUDemo       = "OU=Demo,DC=contoso,DC=com" # <-- ajusta
$DCHost       = "DC01"                      # <-- nombre de tu DC
$ServidorDemo = "FILESERVER01"              # <-- un servidor al que tengas acceso

# Cuenta privilegiada de demo (simula la víctima del PtT)
$CuentaVictima   = "demo.adminptt"
$CuentaAtacante  = "demo.userptt"
$ContrasenhaDemo = "Demo@PtT2024!"

# ────────────────────────────────────────────────────────────
#  ACTO 1 — CONTEXTO: ver tickets activos en memoria
# ────────────────────────────────────────────────────────────

function Show-ContextoKerberos {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║  ACTO 1 — CONTEXTO: tickets Kerberos en memoria          ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    Write-Host "  Kerberos almacena tickets en memoria para evitar autenticarse" -ForegroundColor White
    Write-Host "  en cada acceso a un recurso. Mientras el ticket sea válido," -ForegroundColor White
    Write-Host "  cualquier proceso con acceso a esa memoria puede usarlo.`n" -ForegroundColor White

    Write-Host "  Tickets activos en esta sesión (klist):`n" -ForegroundColor Yellow

    # klist muestra los tickets Kerberos de la sesión actual
    $klistOutput = & klist 2>&1
    Write-Host $klistOutput -ForegroundColor Gray

    Write-Host "`n  Tickets activos via PowerShell:`n" -ForegroundColor Yellow

    # Ver tickets via .NET
    Add-Type -AssemblyName System.IdentityModel
    try {
        $tickets = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        Write-Host "  Usuario actual : $($tickets.Name)" -ForegroundColor White
        Write-Host "  Tipo auth      : $($tickets.AuthenticationType)" -ForegroundColor White
        Write-Host "  Es Kerberos    : $($tickets.AuthenticationType -eq 'Kerberos')" -ForegroundColor White
    } catch {}

    Write-Host @"

  PREGUNTA PARA LOS ALUMNOS:
  Si una amenaza tiene acceso al material de sesión de este equipo,
  ¿qué tiene en sus manos?
  Respuesta: tickets válidos durante su ventana de vida. Sin necesitar la contraseña.
"@ -ForegroundColor Yellow
}

function Show-CicloKerberos {
    Write-Host @"

  FLUJO NORMAL DE KERBEROS:
  ┌──────────┐    AS-REQ (1)    ┌─────────────┐
  │ Cliente  │ ──────────────►  │     DC      │
  │          │ ◄──────────────  │  (KDC)      │
  │          │    TGT (2)       │             │
  │          │                  │             │
  │          │  TGS-REQ (3)     │             │
  │          │ ──────────────►  │             │
  │          │ ◄──────────────  │             │
  │          │    TGS (4)       └─────────────┘
  │          │
  │          │  TGS (5)         ┌─────────────┐
  │          │ ──────────────►  │  Servidor   │
  │          │ ◄──────────────  │  de recurso │
  └──────────┘  Acceso (6)      └─────────────┘

  RIESGO: si una amenaza consigue material Kerberos válido,
  el DC ve un ticket correcto y concede acceso dentro de su
  ventana de vida. Sin contraseña y sin intentos fallidos.
"@ -ForegroundColor Cyan
}

# ────────────────────────────────────────────────────────────
#  ACTO 2 — RIESGO Y EVIDENCIA
# ────────────────────────────────────────────────────────────

function Setup-CuentasDemo {
    Write-Host "`n[SETUP] Creando cuentas de demo para PtT..." -ForegroundColor Cyan

    try {
        Get-ADOrganizationalUnit -Identity $OUDemo -ErrorAction Stop | Out-Null
    } catch {
        New-ADOrganizationalUnit -Name "Demo" -Path ($OUDemo -replace "^OU=Demo,","") `
            -ProtectedFromAccidentalDeletion $false
        Write-Host "  OU creada: $OUDemo" -ForegroundColor Green
    }

    $SecPass = ConvertTo-SecureString $ContrasenhaDemo -AsPlainText -Force

    # Cuenta víctima — usuario privilegiado con sesión activa
    try {
        Get-ADUser -Identity $CuentaVictima -ErrorAction Stop | Out-Null
        Write-Host "  Ya existe: $CuentaVictima" -ForegroundColor Yellow
    } catch {
        New-ADUser -Name $CuentaVictima `
                   -SamAccountName $CuentaVictima `
                   -UserPrincipalName "$CuentaVictima@$Dominio" `
                   -Path $OUDemo `
                   -AccountPassword $SecPass `
                   -Enabled $true `
                   -PasswordNeverExpires $true `
                   -Description "Demo PtT - cuenta victima privilegiada"
        # Añadir a un grupo con algo de acceso para que tenga TGS interesantes
        Add-ADGroupMember -Identity "Remote Desktop Users" -Members $CuentaVictima -ErrorAction SilentlyContinue
        Write-Host "  Creada (víctima): $CuentaVictima" -ForegroundColor Green
    }

    # Cuenta atacante — usuario normal que "robará" el ticket
    try {
        Get-ADUser -Identity $CuentaAtacante -ErrorAction Stop | Out-Null
        Write-Host "  Ya existe: $CuentaAtacante" -ForegroundColor Yellow
    } catch {
        New-ADUser -Name $CuentaAtacante `
                   -SamAccountName $CuentaAtacante `
                   -UserPrincipalName "$CuentaAtacante@$Dominio" `
                   -Path $OUDemo `
                   -AccountPassword $SecPass `
                   -Enabled $true `
                   -PasswordNeverExpires $true `
                   -Description "Demo PtT - cuenta atacante (usuario normal)"
        Write-Host "  Creada (atacante): $CuentaAtacante" -ForegroundColor Green
    }

    Write-Host "`n  Escenario montado:" -ForegroundColor White
    Write-Host "    Víctima  : $CuentaVictima (usuario privilegiado con sesión activa)" -ForegroundColor White
    Write-Host "    Atacante : $CuentaAtacante (usuario normal que compromete el equipo)`n" -ForegroundColor White
}

function Show-RiesgoTickets {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║  ACTO 2 — EL RIESGO: tickets reutilizables               ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Red

    Write-Host "  Escenario: $CuentaVictima tiene una sesión activa en un equipo." -ForegroundColor White
    Write-Host "  Si el material Kerberos queda expuesto, la identidad puede reutilizarse" -ForegroundColor White
    Write-Host "  hasta que el ticket expire o se fuerce el cierre de sesión.`n" -ForegroundColor White

    # Solicitamos un TGS real para generar eventos y demostrar que existe
    # actividad Kerberos observable sin exportar material de autenticación.
    Write-Host "  Solicitando TGS para el servicio CIFS del DC (genera evidencia 4769)..." -ForegroundColor Yellow

    try {
        Add-Type -AssemblyName System.IdentityModel
        $spn = "cifs/$DCHost.$Dominio"
        New-Object System.IdentityModel.Tokens.KerberosRequestorSecurityToken -ArgumentList $spn | Out-Null

        Write-Host "  [!] TGS solicitado para: $spn" -ForegroundColor Red
        Write-Host "  [!] Busca Event ID 4769 para ver la solicitud del servicio.`n" -ForegroundColor Red
        Write-Host "  Vista gráfica: Visor de eventos > Registros de Windows > Seguridad > Filtrar por Event ID 4769`n" -ForegroundColor White

        Write-Host "  Nota: por seguridad, esta demo no guarda tickets en disco" -ForegroundColor Yellow
        Write-Host "  ni muestra comandos de reutilización. El objetivo es detectar" -ForegroundColor Yellow
        Write-Host "  el riesgo y enseñar las mitigaciones.`n" -ForegroundColor Yellow

    } catch {
        Write-Host "  No se pudo solicitar el TGS (normal si no hay conectividad al DC): $_" -ForegroundColor Gray
        Write-Host "  Explicación conceptual igualmente válida para la demo.`n" -ForegroundColor Yellow
    }

    # Mostrar los tickets actuales con klist para visualizar el concepto
    Write-Host "  Tickets en memoria tras la solicitud (klist):`n" -ForegroundColor Cyan
    & klist 2>&1 | Select-String -Pattern "Server:|Client:|KerbTicket|Ticket Flags" |
        ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
}

function Show-ImpactoAtaque {
    Write-Host @"

  IMPACTO DE LA REUTILIZACIÓN DE TICKETS:
  ┌─────────────────────────────────────────────────────────┐
  │  Si un ticket válido queda expuesto, puede actuar como   │
  │  prueba temporal de identidad de la víctima.             │
  │                                                         │
  │  Resultado:                                             │
  │  ✗ El DC ve un ticket válido firmado con la clave krbtgt │
  │  ✗ Concede acceso a los recursos de la víctima          │
  │  ✗ Sin contraseña. Sin login. Sin rastro de 4625.       │
  │  ✓ Solo un 4769 (solicitud TGS) que parece normal       │
  └─────────────────────────────────────────────────────────┘

  DIFERENCIA CLAVE CON PASS-THE-HASH:
    PtH   — usa el hash NTLM (funciona hasta que cambia la pass)
    PtT   — usa el ticket Kerberos (funciona hasta que expira)
    Golden— abuso de la clave krbtgt (funciona hasta rotar krbtgt)
"@ -ForegroundColor Red
}

function Show-EventosPtT {
    Write-Host "`n[EVIDENCIA] Actividad Kerberos generada (últimos 10 min):`n" -ForegroundColor Cyan
    Write-Host "  Vista gráfica: Visor de eventos > Registros de Windows > Seguridad > Filtrar por Event ID 4768, 4769, 4770 y 4771`n" -ForegroundColor White

    $eventos = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = @(4768, 4769, 4770, 4771)
        StartTime = (Get-Date).AddMinutes(-10)
    } -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Write-Host "  No hay eventos Kerberos recientes." -ForegroundColor Yellow
        Write-Host "  Verifica: auditpol /set /subcategory:'Kerberos Service Ticket Operations' /success:enable`n"
        return
    }

    $eventos | ForEach-Object {
        $xml = [xml]$_.ToXml()
        $tipo = switch ($_.Id) {
            4768 { "TGT solicitado  (AS-REQ) " }
            4769 { "TGS solicitado  (TGS-REQ)" }
            4770 { "TGS renovado             " }
            4771 { "Preauth FALLIDA (AS-REQ) " }
        }
        $encType = $xml.Event.EventData.Data[6].'#text'
        $alerta  = if ($encType -eq "0x17") { " ⚠️ RC4" } else { "" }

        [PSCustomObject]@{
            Hora    = $_.TimeCreated.ToString("HH:mm:ss")
            Evento  = "$($_.Id) — $tipo"
            Cuenta  = $xml.Event.EventData.Data[0].'#text'
            Servicio= $xml.Event.EventData.Data[2].'#text'
            Cifrado = "$encType$alerta"
        }
    } | Format-Table -AutoSize

    Write-Host "  En un PtT real verías 4769 para el servicio accedido," -ForegroundColor Yellow
    Write-Host "  pero NO verías 4625 (no hay intento de login fallido)." -ForegroundColor Yellow
    Write-Host "  El ticket es válido desde el punto de vista del DC.`n" -ForegroundColor Yellow
}

# ────────────────────────────────────────────────────────────
#  ACTO 3 — MITIGACIÓN: Protected Users + Auth Policies
# ────────────────────────────────────────────────────────────

function Show-MitigacionPtT {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║  ACTO 3 — MITIGACIÓN: reducir la ventana de ataque       ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

    Write-Host "  MITIGACIÓN 1 — Protected Users (visto en Bloque 3)`n" -ForegroundColor White

    # Mostrar estado actual de la cuenta víctima
    $victima = Get-ADUser -Identity $CuentaVictima -Properties memberOf
    $enProtectedUsers = $victima.MemberOf -match "Protected Users"

    Write-Host "  $CuentaVictima en Protected Users: $($enProtectedUsers -as [bool])" -ForegroundColor $(if ($enProtectedUsers) { "Green" } else { "Red" })
    Write-Host ""

    if (-not $enProtectedUsers) {
        Write-Host "  Sin Protected Users el TGT de $CuentaVictima dura 10 horas." -ForegroundColor Red
        Write-Host "  Un ticket robado a las 9:00 sigue siendo válido a las 18:45.`n" -ForegroundColor Red

        Write-Host "  Añadiendo a Protected Users ahora...`n" -ForegroundColor Yellow
        Add-ADGroupMember -Identity "Protected Users" -Members $CuentaVictima
        Write-Host "  [✓] $CuentaVictima añadido a Protected Users" -ForegroundColor Green
    }

    Write-Host @"
  Efecto inmediato tras añadir a Protected Users:
    ✓ TGT limitado a 4 horas (no renovable)
    ✓ Sin autenticación NTLM
    ✓ Sin delegación Kerberos
    ✓ Sin caché de credenciales offline

  Un ticket robado ahora tiene una ventana máxima de 4 horas.
  Y si se detecta antes, basta con forzar cierre de sesión.
"@ -ForegroundColor Green

    Write-Host "  MITIGACIÓN 2 — Políticas de Autenticación`n" -ForegroundColor White
    Write-Host @"
  Las Authentication Policies permiten restringir DESDE QUÉ
  dispositivos puede autenticarse una cuenta. Un ticket válido
  de la cuenta víctima no sirve si proviene de un equipo
  que no está en la lista de dispositivos autorizados.

  New-ADAuthenticationPolicy -Name 'ProteccionAdmins' ``
      -UserAllowedToAuthenticateFrom 'O:SYG:SYD:(XA;;CR;;;WD;(@USER.ad://ext/AuthenticationSilo == "AdminSilo"))' ``
      -Enforce $true

  Referencia: https://learn.microsoft.com/en-us/windows-server/security/credentials-protection-and-management/authentication-policies-and-authentication-policy-silos
"@ -ForegroundColor Gray

    Write-Host "  MITIGACIÓN 3 — Credential Guard (visto en Bloque 4)`n" -ForegroundColor White
    Write-Host @"
  Credential Guard mueve los TGT al entorno virtualizado.
  El proceso de seguridad normal ya no tiene acceso directo a los tickets.
  Las herramientas de extracción de credenciales pierden acceso directo.

  Resultado: se reduce drásticamente la exposición del material Kerberos.
  Sin material reutilizable, no hay reutilización de tickets.
"@ -ForegroundColor Gray
}

function Show-ComparativaMitigaciones {
    Write-Host @"

  COMPARATIVA: PtH vs PtT vs Golden Ticket

  ┌──────────────────┬───────────────┬──────────────────────────┐
  │ Técnica          │ Qué roba      │ Cómo se mitiga           │
  ├──────────────────┼───────────────┼──────────────────────────┤
  │ Pass-the-Hash    │ Hash NTLM     │ Credential Guard + LAPS  │
  │ Reuso de ticket  │ Ticket TGT/TGS│ Protected Users + CG     │
  │ Golden Ticket    │ Hash krbtgt   │ Rotar krbtgt (2 veces)   │
  └──────────────────┴───────────────┴──────────────────────────┘

  Las tres técnicas atacan el mismo problema: credenciales en memoria.
  La defensa en profundidad (CG + PU + LAPS + Tier Model) las mitiga todas.
"@ -ForegroundColor Cyan
}

function Cleanup-Demo {
    Write-Host "`n[CLEANUP] Limpiando demo de reutilización de tickets..." -ForegroundColor Cyan

    # Quitar de Protected Users si se añadió
    try {
        Remove-ADGroupMember -Identity "Protected Users" -Members $CuentaVictima -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
    try {
        Remove-ADGroupMember -Identity "Remote Desktop Users" -Members $CuentaVictima -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}

    # Eliminar cuentas
    foreach ($cuenta in @($CuentaVictima, $CuentaAtacante)) {
        try {
            Remove-ADUser -Identity $cuenta -Confirm:$false
            Write-Host "  Eliminada: $cuenta" -ForegroundColor Green
        } catch {
            Write-Host "  No encontrada: $cuenta" -ForegroundColor Yellow
        }
    }

    # Eliminar OU
    try {
        Remove-ADOrganizationalUnit -Identity $OUDemo -Recursive -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  OU eliminada." -ForegroundColor Green
    } catch {}

    Write-Host "[CLEANUP] Listo.`n" -ForegroundColor Cyan
}

# ── MENÚ PRINCIPAL ──────────────────────────────────────────
Write-Host @"
╔══════════════════════════════════════════════════════════╗
║   DEMO: Reutilización de tickets — Módulo 4 (Bloque 10)  ║
╠══════════════════════════════════════════════════════════╣
║  --- ACTO 1: Contexto ---                                ║
║  1. Show-ContextoKerberos     (tickets en memoria)       ║
║  2. Show-CicloKerberos        (diagrama del flujo)       ║
║                                                          ║
║  --- ACTO 2: Riesgo y evidencia ---                      ║
║  3. Setup-CuentasDemo         (crear cuentas)            ║
║  4. Show-RiesgoTickets        (solicitar TGS seguro)     ║
║  5. Show-ImpactoAtaque        (impacto defensivo)        ║
║  6. Show-EventosPtT           (evidencias 4769)          ║
║                                                          ║
║  --- ACTO 3: Mitigación ---                              ║
║  7. Show-MitigacionPtT        (Protected Users + CG)     ║
║  8. Show-ComparativaMitigaciones (PtH vs PtT vs Golden)  ║
║                                                          ║
║  9. Cleanup-Demo              (limpiar todo)             ║
║  0. Salir                                                ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "Flujo completo recomendado: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9`n" -ForegroundColor White
Write-Host "NOTA: Esta demo no exporta ni reutiliza tickets. El concepto se demuestra con PS, klist y eventos nativos.`n" -ForegroundColor Yellow

do {
    $opcion = Read-Host "Selecciona una opción"
    switch ($opcion) {
        "1" { Show-ContextoKerberos }
        "2" { Show-CicloKerberos }
        "3" { Setup-CuentasDemo }
        "4" { Show-RiesgoTickets }
        "5" { Show-ImpactoAtaque }
        "6" { Show-EventosPtT }
        "7" { Show-MitigacionPtT }
        "8" { Show-ComparativaMitigaciones }
        "9" { Cleanup-Demo }
        "0" { Write-Host "Saliendo..." -ForegroundColor Gray }
        default { Write-Host "Opción no válida. Elige un número del 0 al 9." -ForegroundColor Yellow }
    }
} until ($opcion -eq "0")
