# ============================================================
#  DEMO — Cambios en Grupos Privilegiados
#  Genera eventos 4728/4732 añadiendo y quitando miembros
#  en grupos privilegiados del dominio
#  Ejecutar en: DC (como administrador de dominio)
#  Resultado visible: Visor de Eventos > Seguridad > 4728/4732
# ============================================================
# INSTRUCCIONES PARA EL FORMADOR:
#   Esta demo tiene tres momentos:
#
#   MOMENTO 1 — Ver el estado actual de grupos privilegiados
#     Muestra quién está en Domain Admins ahora mismo.
#     Buena pregunta para los alumnos: ¿conocéis a todos?
#
#   MOMENTO 2 — Simular escalada de privilegios
#     Añade una cuenta de demo a Domain Admins.
#     Genera Event ID 4728. Lo vemos en tiempo real.
#
#   MOMENTO 3 — Detectar y revertir
#     Muestra cómo el defensor detecta el cambio y lo revierte.
#     Genera Event ID 4729 al quitar el miembro.
# ============================================================

$Dominio         = "contoso.com"               # <-- ajusta
$OUDemo          = "OU=Demo,DC=contoso,DC=com" # <-- ajusta
$NombreCuentaDemo = "demo.escalada"            # cuenta que simula al atacante

# Grupos privilegiados a monitorizar. Se resuelven por SID para que funcione
# en dominios en español, inglés u otros idiomas.
$GruposPrivilegiados = @(
    @{ NombreCanonico = "Domain Admins";     Sid = "Domain-512" },
    @{ NombreCanonico = "Enterprise Admins"; Sid = "Domain-519" },
    @{ NombreCanonico = "Schema Admins";     Sid = "Domain-518" },
    @{ NombreCanonico = "Administrators";    Sid = "S-1-5-32-544" }
)

function Resolve-GrupoPrivilegiado {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Grupo
    )

    $sid = $Grupo.Sid
    if ($sid -like "Domain-*") {
        $rid = $sid -replace "^Domain-",""
        $domainSid = (Get-ADDomain).DomainSID.Value
        $sid = "$domainSid-$rid"
    }

    try {
        Get-ADGroup -Identity $sid -ErrorAction Stop
    } catch {
        Write-Host "  [$($Grupo.NombreCanonico)] — No se pudo resolver por SID $sid : $_" -ForegroundColor Gray
        $null
    }
}

function Resolve-DomainAdminsGroup {
    Resolve-GrupoPrivilegiado -Grupo @{ NombreCanonico = "Domain Admins"; Sid = "Domain-512" }
}

function Show-EstadoActualGrupos {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║  ESTADO ACTUAL — Miembros de grupos privilegiados        ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    foreach ($grupoConfig in $GruposPrivilegiados) {
        $grupo = Resolve-GrupoPrivilegiado -Grupo $grupoConfig
        if (-not $grupo) { continue }

        try {
            $miembros = Get-ADGroupMember -Identity $grupo.DistinguishedName -Recursive -ErrorAction Stop
            Write-Host "`n  [$($grupo.Name)] — $($miembros.Count) miembro(s):" -ForegroundColor Yellow
            Write-Host "    Grupo canónico: $($grupoConfig.NombreCanonico)" -ForegroundColor Gray

            if ($miembros.Count -eq 0) {
                Write-Host "    (vacío — correcto según recomendaciones Microsoft)" -ForegroundColor Green
            } else {
                foreach ($m in $miembros) {
                    $tipo = if ($m.objectClass -eq "user") { "👤" } else { "👥" }
                    Write-Host "    $tipo $($m.SamAccountName) [$($m.objectClass)]" -ForegroundColor White
                }
            }
        } catch {
            Write-Host "  [$($grupo.Name)] — No accesible: $_" -ForegroundColor Gray
        }
    }

    Write-Host @"

  PREGUNTA PARA LOS ALUMNOS:
  ¿Reconocéis a todos estos usuarios? ¿Sabéis por qué están ahí?
  ¿Alguno debería estar en Domain Admins para su función diaria?
"@ -ForegroundColor Yellow
}

function Setup-CuentaEscalada {
    Write-Host "`n[SETUP] Creando cuenta de demo para simular escalada..." -ForegroundColor Cyan

    try {
        Get-ADOrganizationalUnit -Identity $OUDemo -ErrorAction Stop | Out-Null
    } catch {
        New-ADOrganizationalUnit -Name "Demo" -Path ($OUDemo -replace "^OU=Demo,","") `
            -ProtectedFromAccidentalDeletion $false
    }

    $SecPass = ConvertTo-SecureString "Demo@Escalada2024!" -AsPlainText -Force

    try {
        Get-ADUser -Identity $NombreCuentaDemo -ErrorAction Stop | Out-Null
        Write-Host "  Ya existe: $NombreCuentaDemo" -ForegroundColor Yellow
    } catch {
        New-ADUser -Name $NombreCuentaDemo `
                   -SamAccountName $NombreCuentaDemo `
                   -UserPrincipalName "$NombreCuentaDemo@$Dominio" `
                   -Path $OUDemo `
                   -AccountPassword $SecPass `
                   -Enabled $true `
                   -Description "Cuenta demo escalada privilegios — formacion"
        Write-Host "  Creada: $NombreCuentaDemo (usuario normal, sin privilegios)" -ForegroundColor Green
    }

    Write-Host "`n  Estado inicial de la cuenta:" -ForegroundColor White
    Get-ADUser -Identity $NombreCuentaDemo -Properties MemberOf |
        Select-Object SamAccountName, Enabled,
            @{N='GruposDirectos'; E={ ($_.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=','' }) -join ', ' }} |
        Format-List
}

function Start-SimulacionEscalada {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║  MOMENTO 2 — ESCALADA: añadir a Domain Admins            ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Red

    $domainAdmins = Resolve-DomainAdminsGroup
    if (-not $domainAdmins) {
        Write-Host "  Error: no se pudo localizar el grupo Domain Admins por SID." -ForegroundColor Red
        return
    }

    Write-Host "  Simulando: atacante añade '$NombreCuentaDemo' a $($domainAdmins.Name)..." -ForegroundColor Red
    Write-Host "  Esto es lo que ocurre en un ataque real tras obtener credenciales de admin.`n" -ForegroundColor Red

    $timestampAntes = Get-Date

    try {
        Add-ADGroupMember -Identity $domainAdmins.DistinguishedName -Members $NombreCuentaDemo
        Write-Host "  [!] '$NombreCuentaDemo' añadido a $($domainAdmins.Name)" -ForegroundColor Red
        Write-Host "  [!] Event ID 4728 generado en este momento" -ForegroundColor Red
        Write-Host "  Vista gráfica: Visor de eventos > Registros de Windows > Seguridad > Filtrar por Event ID 4728`n" -ForegroundColor White
        Write-Host "  [!] ¿Cuánto tardaríais en detectarlo sin alertas automáticas?`n" -ForegroundColor Yellow
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Gray
        return
    }

    # Esperar un momento para que el evento se escriba
    Start-Sleep -Seconds 2

    # Mostrar el evento en tiempo real
    Write-Host "  Evento generado en el DC:" -ForegroundColor Cyan
    $eventos = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4728
        StartTime = $timestampAntes
    } -ErrorAction SilentlyContinue | Select-Object -First 3

    if ($eventos) {
        foreach ($e in $eventos) {
            $xml = [xml]$e.ToXml()
            Write-Host @"

    Event ID  : 4728
    Hora      : $($e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss"))
    Miembro   : $($xml.Event.EventData.Data[0].'#text')
    Grupo     : $($xml.Event.EventData.Data[2].'#text')
    Modificado por: $($xml.Event.EventData.Data[4].'#text')
"@ -ForegroundColor Red
        }
    } else {
        Write-Host "  (El evento puede tardar unos segundos en aparecer. Ejecuta Show-EventosEscalada)" -ForegroundColor Yellow
    }
}

function Start-SimulacionMultipleEscalada {
    # Simula varios cambios en distintos grupos para generar más eventos
    Write-Host "`n[SIMULACIÓN EXTENDIDA] Generando múltiples cambios en grupos privilegiados...`n" -ForegroundColor Red

    $cambios = @(
        @{ Grupo = @{ NombreCanonico = "Domain Admins";  Sid = "Domain-512" }; Accion = "Add" },
        @{ Grupo = @{ NombreCanonico = "Administrators"; Sid = "S-1-5-32-544" }; Accion = "Add" },
        @{ Grupo = @{ NombreCanonico = "Domain Admins";  Sid = "Domain-512" }; Accion = "Remove" },
        @{ Grupo = @{ NombreCanonico = "Administrators"; Sid = "S-1-5-32-544" }; Accion = "Remove" }
    )

    foreach ($cambio in $cambios) {
        $grupo = Resolve-GrupoPrivilegiado -Grupo $cambio.Grupo
        if (-not $grupo) { continue }

        try {
            if ($cambio.Accion -eq "Add") {
                Add-ADGroupMember -Identity $grupo.DistinguishedName -Members $NombreCuentaDemo -ErrorAction SilentlyContinue
                Write-Host "  [+] Añadido a $($grupo.Name) — Event 4728" -ForegroundColor Red
            } else {
                Remove-ADGroupMember -Identity $grupo.DistinguishedName -Members $NombreCuentaDemo -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "  [-] Quitado de $($grupo.Name) — Event 4729" -ForegroundColor Yellow
            }
            Start-Sleep -Milliseconds 800
        } catch { }
    }

    Write-Host "`n  Patrón generado: add/remove rápidos = posible atacante probando y cubriendo huellas`n" -ForegroundColor Yellow
}

function Show-DeteccionYReversion {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║  MOMENTO 3 — DETECCIÓN y RESPUESTA                       ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

    $domainAdmins = Resolve-DomainAdminsGroup
    if (-not $domainAdmins) {
        Write-Host "  Error: no se pudo localizar el grupo Domain Admins por SID." -ForegroundColor Red
        return
    }

    # Mostrar estado actual — el atacante ya está en Domain Admins
    Write-Host "  Estado actual de $($domainAdmins.Name) (el atacante ya está dentro):`n" -ForegroundColor Yellow
    try {
        Get-ADGroupMember -Identity $domainAdmins.DistinguishedName -ErrorAction Stop |
            Select-Object SamAccountName, objectClass |
            Format-Table -AutoSize
    } catch {
        Write-Host "  No se pudo leer el grupo $($domainAdmins.Name): $_" -ForegroundColor Gray
    }

    Write-Host "  El defensor detecta el cambio y revierte:" -ForegroundColor Green

    # Revertir — quitar la cuenta de Domain Admins
    try {
        $esMiembro = Get-ADGroupMember -Identity $domainAdmins.DistinguishedName -ErrorAction Stop |
            Where-Object { $_.SamAccountName -eq $NombreCuentaDemo }

        if ($esMiembro) {
            Remove-ADGroupMember -Identity $domainAdmins.DistinguishedName -Members $NombreCuentaDemo -Confirm:$false
            Write-Host "  [✓] '$NombreCuentaDemo' eliminado de $($domainAdmins.Name)" -ForegroundColor Green
            Write-Host "  [✓] Event ID 4729 generado" -ForegroundColor Green
        } else {
            Write-Host "  '$NombreCuentaDemo' ya no está en $($domainAdmins.Name)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  Error al revertir: $_" -ForegroundColor Gray
    }

    Write-Host @"

  LECCIÓN:
  Sin alertas automáticas sobre 4728/4729, un atacante puede:
    1. Añadirse a Domain Admins
    2. Hacer lo que necesite (DCSync, Golden Ticket...)
    3. Quitarse del grupo para eliminar evidencias
  Todo esto en minutos, sin que nadie lo detecte en tiempo real.
"@ -ForegroundColor Yellow
}

function Show-EventosEscalada {
    Write-Host "`n[EVIDENCIA] Cambios en grupos privilegiados (últimos 20 min):`n" -ForegroundColor Cyan
    Write-Host "  Vista gráfica: Visor de eventos > Registros de Windows > Seguridad > Filtrar por Event ID 4728, 4729, 4732, 4733, 4756 y 4757`n" -ForegroundColor White

    $eventos = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = @(4728, 4729, 4732, 4733, 4756, 4757)
        StartTime = (Get-Date).AddMinutes(-20)
    } -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Write-Host "  No hay eventos recientes. Ejecuta Start-SimulacionEscalada primero." -ForegroundColor Yellow
        return
    }

    $eventos | ForEach-Object {
        $xml = [xml]$_.ToXml()
        $accion = switch ($_.Id) {
            4728 { "AÑADIDO a grupo global    🔴" }
            4729 { "QUITADO de grupo global   🟡" }
            4732 { "AÑADIDO a grupo local     🔴" }
            4733 { "QUITADO de grupo local    🟡" }
            4756 { "AÑADIDO a grupo universal 🔴" }
            4757 { "QUITADO de grupo universal🟡" }
        }
        [PSCustomObject]@{
            Hora       = $_.TimeCreated.ToString("HH:mm:ss")
            EventID    = $_.Id
            Accion     = $accion
            Miembro    = $xml.Event.EventData.Data[0].'#text'
            Grupo      = $xml.Event.EventData.Data[2].'#text'
            HechoBy    = $xml.Event.EventData.Data[4].'#text'
        }
    } | Format-Table -AutoSize

    Write-Host "  REGLA DE ORO: cualquier 4728/4732/4756 en Domain Admins o Enterprise Admins" -ForegroundColor Red
    Write-Host "  debe generar una alerta INMEDIATA, sin excepciones.`n" -ForegroundColor Red
}

function Cleanup-CuentaEscalada {
    Write-Host "`n[CLEANUP] Limpiando demo de escalada..." -ForegroundColor Cyan

    # Asegurarse de que no está en ningún grupo privilegiado
    foreach ($grupoConfig in $GruposPrivilegiados) {
        $grupo = Resolve-GrupoPrivilegiado -Grupo $grupoConfig
        if (-not $grupo) { continue }
        try {
            Remove-ADGroupMember -Identity $grupo.DistinguishedName -Members $NombreCuentaDemo -Confirm:$false -ErrorAction SilentlyContinue
        } catch {}
    }

    # Eliminar la cuenta
    try {
        Remove-ADUser -Identity $NombreCuentaDemo -Confirm:$false
        Write-Host "  Eliminada: $NombreCuentaDemo" -ForegroundColor Green
    } catch {
        Write-Host "  No encontrada: $NombreCuentaDemo" -ForegroundColor Yellow
    }

    try {
        Remove-ADOrganizationalUnit -Identity $OUDemo -Recursive -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  OU eliminada." -ForegroundColor Green
    } catch {}

    Write-Host "[CLEANUP] Listo.`n" -ForegroundColor Cyan
}

# ── MENÚ PRINCIPAL ──────────────────────────────────────────
Write-Host @"
╔══════════════════════════════════════════════════════════╗
║   DEMO: Cambios en Grupos Privilegiados — Módulo 4       ║
╠══════════════════════════════════════════════════════════╣
║  1. Show-EstadoActualGrupos   (estado inicial)           ║
║  2. Setup-CuentaEscalada      (crear cuenta demo)        ║
║  3. Start-SimulacionEscalada  (añadir a Domain Admins)   ║
║  4. Show-DeteccionYReversion  (detectar y revertir)      ║
║  5. Show-EventosEscalada      (eventos 4728/4729)        ║
║  6. Start-SimulacionMultipleEscalada (patrón avanzado)   ║
║  7. Cleanup-CuentaEscalada    (limpiar todo)             ║
║  0. Salir                                                ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "Flujo básico recomendado: 1 -> 2 -> 3 -> 4 -> 5 -> 7`n" -ForegroundColor White
Write-Host "Flujo extendido: añade Start-SimulacionMultiple antes de Show-Eventos para más drama.`n" -ForegroundColor Yellow

do {
    $opcion = Read-Host "Selecciona una opción"
    switch ($opcion) {
        "1" { Show-EstadoActualGrupos }
        "2" { Setup-CuentaEscalada }
        "3" { Start-SimulacionEscalada }
        "4" { Show-DeteccionYReversion }
        "5" { Show-EventosEscalada }
        "6" { Start-SimulacionMultipleEscalada }
        "7" { Cleanup-CuentaEscalada }
        "0" { Write-Host "Saliendo..." -ForegroundColor Gray }
        default { Write-Host "Opción no válida. Elige un número del 0 al 7." -ForegroundColor Yellow }
    }
} until ($opcion -eq "0")
