# ============================================================
#  DEMO — Password Spraying
#  Genera eventos 4625 contra múltiples cuentas desde el DC
#  Ejecutar en: DC (como administrador)
#  Resultado visible: Visor de Eventos > Seguridad > 4625
# ============================================================
# INSTRUCCIONES PARA EL FORMADOR:
#   1. Ajusta $Dominio y $CuentasObjetivo antes de ejecutar
#   2. Ejecuta Setup-CuentasDemo primero (crea las cuentas)
#   3. Ejecuta Start-SimulacionSpraying para generar los eventos
#   4. Luego abre el Visor de Eventos y muestra el patrón
#   5. Al terminar ejecuta Cleanup-CuentasDemo
# ============================================================

$Dominio        = "contoso.com"          # <-- ajusta a tu dominio
$OUDemo         = "OU=Demo,DC=contoso,DC=com"  # <-- ajusta a tu OU
$ContrasenaDemo = "Demo@Formacion2024!"  # contraseña real de las cuentas

# ── Cuentas ficticias que recibirán los intentos fallidos ──
$CuentasObjetivo = @(
    "demo.usuario01", "demo.usuario02", "demo.usuario03",
    "demo.usuario04", "demo.usuario05", "demo.usuario06",
    "demo.usuario07", "demo.usuario08", "demo.usuario09",
    "demo.usuario10"
)

# ── Contraseña incorrecta que usará el atacante simulado ──
$ContrasenaAtacante = "Password123"

function Setup-CuentasDemo {
    # Crea la OU y las cuentas de demo si no existen
    Write-Host "`n[SETUP] Creando cuentas de demo..." -ForegroundColor Cyan

    # Crear OU si no existe
    try {
        Get-ADOrganizationalUnit -Identity $OUDemo -ErrorAction Stop | Out-Null
        Write-Host "  OU ya existe: $OUDemo" -ForegroundColor Yellow
    } catch {
        New-ADOrganizationalUnit -Name "Demo" -Path ($OUDemo -replace "^OU=Demo,","") -ProtectedFromAccidentalDeletion $false
        Write-Host "  OU creada: $OUDemo" -ForegroundColor Green
    }

    $SecPass = ConvertTo-SecureString $ContrasenaDemo -AsPlainText -Force

    foreach ($cuenta in $CuentasObjetivo) {
        try {
            Get-ADUser -Identity $cuenta -ErrorAction Stop | Out-Null
            Write-Host "  Ya existe: $cuenta" -ForegroundColor Yellow
        } catch {
            New-ADUser -Name $cuenta `
                       -SamAccountName $cuenta `
                       -UserPrincipalName "$cuenta@$Dominio" `
                       -Path $OUDemo `
                       -AccountPassword $SecPass `
                       -Enabled $true `
                       -PasswordNeverExpires $true
            Write-Host "  Creada: $cuenta" -ForegroundColor Green
        }
    }
    Write-Host "[SETUP] Listo. $($CuentasObjetivo.Count) cuentas disponibles.`n" -ForegroundColor Cyan
}

function Start-SimulacionSpraying {
    param(
        [int]$Rondas    = 3,   # cuántas rondas de spraying simular
        [int]$Intervalo = 2    # segundos entre intentos (mantener bajo para demo)
    )

    Write-Host "`n[ATAQUE] Iniciando simulación de Password Spraying..." -ForegroundColor Red
    Write-Host "  Rondas : $Rondas" -ForegroundColor Red
    Write-Host "  Cuentas: $($CuentasObjetivo.Count)" -ForegroundColor Red
    Write-Host "  Pass   : $ContrasenaAtacante (incorrecta)" -ForegroundColor Red
    Write-Host ""

    for ($ronda = 1; $ronda -le $Rondas; $ronda++) {
        Write-Host "  [Ronda $ronda/$Rondas]" -ForegroundColor Yellow

        foreach ($cuenta in $CuentasObjetivo) {
            $upn = "$cuenta@$Dominio"

            # Intentar autenticación con contraseña incorrecta
            # Esto genera evento 4625 en el DC
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
            $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
                [System.DirectoryServices.AccountManagement.ContextType]::Domain, $Dominio
            )
            try {
                $ctx.ValidateCredentials($upn, $ContrasenaAtacante) | Out-Null
            } catch {}

            Write-Host "    Intento fallido -> $cuenta" -ForegroundColor DarkRed
            Start-Sleep -Seconds $Intervalo
        }

        if ($ronda -lt $Rondas) {
            Write-Host "  Esperando 5s antes de la siguiente ronda...`n" -ForegroundColor Gray
            Start-Sleep -Seconds 5
        }
    }

    Write-Host "`n[ATAQUE] Simulación completada." -ForegroundColor Red
    Write-Host "  Eventos generados: ~$($Rondas * $CuentasObjetivo.Count) x Event ID 4625`n" -ForegroundColor Red
    Write-Host "[SIGUIENTE PASO] Abre el Visor de Eventos y ejecuta el filtro del speech." -ForegroundColor Cyan
}

function Show-ResultadoSpraying {
    # Muestra los eventos 4625 generados en los últimos 10 minutos
    Write-Host "`n[EVIDENCIA] Eventos 4625 generados (últimos 10 min):`n" -ForegroundColor Cyan
    Write-Host "  Vista gráfica: Visor de eventos > Registros de Windows > Seguridad > Filtrar por Event ID 4625`n" -ForegroundColor White

    $eventos = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4625
        StartTime = (Get-Date).AddMinutes(-10)
    } -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Write-Host "  No se encontraron eventos. Verifica que la auditoría esté activa." -ForegroundColor Yellow
        return
    }

    $eventos | ForEach-Object {
        $xml = [xml]$_.ToXml()
        [PSCustomObject]@{
            Hora       = $_.TimeCreated.ToString("HH:mm:ss")
            Cuenta     = $xml.Event.EventData.Data[5].'#text'
            IP_Origen  = $xml.Event.EventData.Data[19].'#text'
            Motivo     = $xml.Event.EventData.Data[8].'#text'
        }
    } | Format-Table -AutoSize

    Write-Host "  Total eventos: $($eventos.Count)" -ForegroundColor Yellow
    Write-Host "  PATRÓN: misma IP, múltiples cuentas, timestamps muy próximos = PASSWORD SPRAYING`n" -ForegroundColor Red
}

function Cleanup-CuentasDemo {
    Write-Host "`n[CLEANUP] Eliminando cuentas de demo..." -ForegroundColor Cyan
    foreach ($cuenta in $CuentasObjetivo) {
        try {
            Remove-ADUser -Identity $cuenta -Confirm:$false
            Write-Host "  Eliminada: $cuenta" -ForegroundColor Green
        } catch {
            Write-Host "  No encontrada: $cuenta" -ForegroundColor Yellow
        }
    }
    try {
        Remove-ADOrganizationalUnit -Identity $OUDemo -Recursive -Confirm:$false
        Write-Host "  OU eliminada: $OUDemo" -ForegroundColor Green
    } catch {}
    Write-Host "[CLEANUP] Listo.`n" -ForegroundColor Cyan
}

# ── MENÚ PRINCIPAL ──────────────────────────────────────────
Write-Host @"
╔══════════════════════════════════════════════╗
║   DEMO: Password Spraying — Módulo 4         ║
╠══════════════════════════════════════════════╣
║  1. Setup-CuentasDemo      (crear cuentas)   ║
║  2. Start-SimulacionSpraying                 ║
║  3. Show-ResultadoSpraying (ver evidencias)  ║
║  4. Cleanup-CuentasDemo    (limpiar todo)    ║
║  0. Salir                                    ║
╚══════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "Flujo recomendado: 1 -> 2 -> 3 -> 4`n" -ForegroundColor White

do {
    $opcion = Read-Host "Selecciona una opción"
    switch ($opcion) {
        "1" { Setup-CuentasDemo }
        "2" { Start-SimulacionSpraying }
        "3" { Show-ResultadoSpraying }
        "4" { Cleanup-CuentasDemo }
        "0" { Write-Host "Saliendo..." -ForegroundColor Gray }
        default { Write-Host "Opción no válida. Elige 0, 1, 2, 3 o 4." -ForegroundColor Yellow }
    }
} until ($opcion -eq "0")
