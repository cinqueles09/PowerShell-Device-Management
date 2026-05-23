# ============================================================
#  DEMO — Pass-the-Hash
#  Demuestra el problema de contraseñas locales compartidas
#  y cómo LAPS lo resuelve. NO usa herramientas ofensivas.
#  Ejecutar en: DC (como administrador de dominio)
#  Resultado visible: comportamiento + eventos 4624/4625/4648
# ============================================================
# INSTRUCCIONES PARA EL FORMADOR:
#   Esta demo tiene DOS actos:
#
#   ACTO 1 — El problema (sin LAPS):
#     Demuestra que el mismo hash funciona en múltiples equipos
#     simulando autenticaciones con la misma contraseña local.
#     No se usa Mimikatz ni herramientas de ataque reales.
#     El concepto se demuestra con PowerShell puro.
#
#   ACTO 2 — La solución (con LAPS):
#     Muestra cómo cada equipo tiene una contraseña diferente
#     y cómo el hash de un equipo no sirve en los demás.
#
#   Los eventos generados (4624 éxito, 4625 fallo) son reales
#   y visibles en el Visor de Eventos del DC.
# ============================================================

$Dominio         = "contoso.com"               # <-- ajusta
$OUEquipos       = "OU=Demo,DC=contoso,DC=com" # <-- ajusta
$ContrasenhaLocal = "!Admin2019"               # contraseña local compartida (el problema)

# Equipos de demo — nombres de VMs unidas al dominio
$EquiposDemo = @("VM-DEMO-01", "VM-DEMO-02", "VM-DEMO-03")

# ────────────────────────────────────────────────────────────
#  ACTO 1 — DEMOSTRAR EL PROBLEMA
# ────────────────────────────────────────────────────────────

function Show-ElProblema {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║  ACTO 1 — EL PROBLEMA: contraseña local compartida       ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Red

    Write-Host "  Escenario: tres equipos, misma imagen, misma contraseña local '$ContrasenhaLocal'" -ForegroundColor White
    Write-Host "  Un atacante que extrae el hash de VM-DEMO-01 lo prueba en los demás.`n" -ForegroundColor White

    # Simular reconocimiento: mostrar que la contraseña es idéntica
    # Calculamos el hash NTLM de la contraseña para visualizarlo
    $hashNTLM = Get-NTLMHash -Texto $ContrasenhaLocal

    Write-Host "  Hash NTLM de '$ContrasenhaLocal':" -ForegroundColor Yellow
    Write-Host "  $hashNTLM" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Este MISMO hash está en la memoria de los $($EquiposDemo.Count) equipos." -ForegroundColor Red
    Write-Host "  Si lo robas de uno, lo tienes en todos. Sin explotar nada más.`n" -ForegroundColor Red

    # Intentar autenticación en cada equipo con la misma contraseña
    # Esto simula lo que haría el atacante con el hash
    Write-Host "  Simulando autenticación en cada equipo con la misma contraseña:`n" -ForegroundColor Yellow

    foreach ($equipo in $EquiposDemo) {
        $credencial = New-Object System.Management.Automation.PSCredential(
            "$equipo\Administrador",
            (ConvertTo-SecureString $ContrasenhaLocal -AsPlainText -Force)
        )

        try {
            $resultado = Test-WSMan -ComputerName $equipo `
                                    -Credential $credencial `
                                    -Authentication Negotiate `
                                    -ErrorAction Stop
        } catch {
            $resultado = $null
        }

        if ($resultado) {
            Write-Host "  [✓] $equipo — ACCESO CONSEGUIDO con la misma contraseña" -ForegroundColor Red
        } else {
            Write-Host "  [?] $equipo — No alcanzable (verifica que la VM está encendida)" -ForegroundColor Gray
        }
    }

    Write-Host @"

  CONCLUSIÓN: una contraseña compartida = compromiso masivo.
  El atacante no necesita Mimikatz después del primer equipo.
  Le basta con reutilizar el hash en los siguientes.
"@ -ForegroundColor Red
}

function Get-NTLMHash {
    param([string]$Texto)
    # NTLM = MD4 de la contraseña en UTF-16LE. .NET no trae MD4 nativo,
    # así que se compila una implementación mínima para la demo.
    if (-not ("DemoCrypto.NtlmHash" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Text;

namespace DemoCrypto {
public static class NtlmHash {
    public static string Hash(string password) {
        byte[] input = Encoding.Unicode.GetBytes(password);
        byte[] hash = Md4(input);
        StringBuilder sb = new StringBuilder(hash.Length * 2);
        foreach (byte b in hash) {
            sb.Append(b.ToString("x2"));
        }
        return sb.ToString();
    }

    private static byte[] Md4(byte[] input) {
        uint a = 0x67452301;
        uint b = 0xefcdab89;
        uint c = 0x98badcfe;
        uint d = 0x10325476;

        ulong bitLength = (ulong)input.Length * 8;
        int paddingLength = (56 - ((input.Length + 1) % 64) + 64) % 64;
        byte[] padded = new byte[input.Length + 1 + paddingLength + 8];
        Buffer.BlockCopy(input, 0, padded, 0, input.Length);
        padded[input.Length] = 0x80;
        for (int i = 0; i < 8; i++) {
            padded[padded.Length - 8 + i] = (byte)(bitLength >> (8 * i));
        }

        for (int offset = 0; offset < padded.Length; offset += 64) {
            uint[] x = new uint[16];
            for (int i = 0; i < 16; i++) {
                x[i] = BitConverter.ToUInt32(padded, offset + i * 4);
            }

            uint aa = a, bb = b, cc = c, dd = d;

            FF(ref a, b, c, d, x[0], 3);   FF(ref d, a, b, c, x[1], 7);
            FF(ref c, d, a, b, x[2], 11);  FF(ref b, c, d, a, x[3], 19);
            FF(ref a, b, c, d, x[4], 3);   FF(ref d, a, b, c, x[5], 7);
            FF(ref c, d, a, b, x[6], 11);  FF(ref b, c, d, a, x[7], 19);
            FF(ref a, b, c, d, x[8], 3);   FF(ref d, a, b, c, x[9], 7);
            FF(ref c, d, a, b, x[10], 11); FF(ref b, c, d, a, x[11], 19);
            FF(ref a, b, c, d, x[12], 3);  FF(ref d, a, b, c, x[13], 7);
            FF(ref c, d, a, b, x[14], 11); FF(ref b, c, d, a, x[15], 19);

            GG(ref a, b, c, d, x[0], 3);   GG(ref d, a, b, c, x[4], 5);
            GG(ref c, d, a, b, x[8], 9);   GG(ref b, c, d, a, x[12], 13);
            GG(ref a, b, c, d, x[1], 3);   GG(ref d, a, b, c, x[5], 5);
            GG(ref c, d, a, b, x[9], 9);   GG(ref b, c, d, a, x[13], 13);
            GG(ref a, b, c, d, x[2], 3);   GG(ref d, a, b, c, x[6], 5);
            GG(ref c, d, a, b, x[10], 9);  GG(ref b, c, d, a, x[14], 13);
            GG(ref a, b, c, d, x[3], 3);   GG(ref d, a, b, c, x[7], 5);
            GG(ref c, d, a, b, x[11], 9);  GG(ref b, c, d, a, x[15], 13);

            HH(ref a, b, c, d, x[0], 3);   HH(ref d, a, b, c, x[8], 9);
            HH(ref c, d, a, b, x[4], 11);  HH(ref b, c, d, a, x[12], 15);
            HH(ref a, b, c, d, x[2], 3);   HH(ref d, a, b, c, x[10], 9);
            HH(ref c, d, a, b, x[6], 11);  HH(ref b, c, d, a, x[14], 15);
            HH(ref a, b, c, d, x[1], 3);   HH(ref d, a, b, c, x[9], 9);
            HH(ref c, d, a, b, x[5], 11);  HH(ref b, c, d, a, x[13], 15);
            HH(ref a, b, c, d, x[3], 3);   HH(ref d, a, b, c, x[11], 9);
            HH(ref c, d, a, b, x[7], 11);  HH(ref b, c, d, a, x[15], 15);

            a += aa; b += bb; c += cc; d += dd;
        }

        byte[] result = new byte[16];
        Buffer.BlockCopy(BitConverter.GetBytes(a), 0, result, 0, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(b), 0, result, 4, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(c), 0, result, 8, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(d), 0, result, 12, 4);
        return result;
    }

    private static uint F(uint x, uint y, uint z) { return (x & y) | (~x & z); }
    private static uint G(uint x, uint y, uint z) { return (x & y) | (x & z) | (y & z); }
    private static uint H(uint x, uint y, uint z) { return x ^ y ^ z; }
    private static uint Rot(uint x, int s) { return (x << s) | (x >> (32 - s)); }
    private static void FF(ref uint a, uint b, uint c, uint d, uint x, int s) { a = Rot(a + F(b, c, d) + x, s); }
    private static void GG(ref uint a, uint b, uint c, uint d, uint x, int s) { a = Rot(a + G(b, c, d) + x + 0x5a827999, s); }
    private static void HH(ref uint a, uint b, uint c, uint d, uint x, int s) { a = Rot(a + H(b, c, d) + x + 0x6ed9eba1, s); }
}
}
"@
    }

    return [DemoCrypto.NtlmHash]::Hash($Texto)
}

# ────────────────────────────────────────────────────────────
#  ACTO 2 — LA SOLUCIÓN: LAPS
# ────────────────────────────────────────────────────────────

function Show-LaSolucion {
    Write-Host @"

╔══════════════════════════════════════════════════════════╗
║  ACTO 2 — LA SOLUCIÓN: LAPS en acción                    ║
╚══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

    Write-Host "  Con LAPS cada equipo tiene su propia contraseña única.`n" -ForegroundColor White

    # Mostrar contraseñas LAPS actuales de cada equipo
    $tieneLAPS = $false
    foreach ($equipo in $EquiposDemo) {
        try {
            $lapsPass = Get-LapsADPassword -Identity $equipo -AsPlainText -ErrorAction Stop
            Write-Host "  $equipo" -ForegroundColor White
            Write-Host "    Contraseña : $($lapsPass.Password)" -ForegroundColor Yellow
            Write-Host "    Expira     : $($lapsPass.ExpirationTimestamp)" -ForegroundColor Gray
            Write-Host ""
            $tieneLAPS = $true
        } catch {
            Write-Host "  $equipo — LAPS no configurado o sin permisos de lectura" -ForegroundColor Gray
        }
    }

    if (-not $tieneLAPS) {
        Write-Host "  (Ejecuta primero la demo de LAPS del Bloque 7 para ver contraseñas reales)`n" -ForegroundColor Yellow
        Write-Host "  Simulación visual de lo que mostraría LAPS:`n" -ForegroundColor Cyan

        # Generar contraseñas ficticias para visualizar el concepto
        foreach ($equipo in $EquiposDemo) {
            $pass = -join ((65..90) + (97..122) + (48..57) + (33,35,36,64) |
                           Get-Random -Count 16 | ForEach-Object { [char]$_ })
            Write-Host "  $equipo" -ForegroundColor White
            Write-Host "    Contraseña LAPS : $pass  (única, generada automáticamente)" -ForegroundColor Yellow
            Write-Host "    Hash NTLM       : $((-join ((1..16) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })))" -ForegroundColor DarkYellow
            Write-Host ""
        }
    }

    Write-Host @"
  CONCLUSIÓN: con LAPS el hash robado de VM-DEMO-01 NO sirve en VM-DEMO-02.
  El movimiento lateral se rompe. El atacante necesita comprometer cada equipo
  de forma independiente — coste mucho mayor, detección mucho más probable.
"@ -ForegroundColor Green
}

function Show-EventosPtH {
    Write-Host "`n[EVIDENCIA] Eventos de autenticación generados durante la demo:`n" -ForegroundColor Cyan
    Write-Host "  Vista gráfica: Visor de eventos > Registros de Windows > Seguridad > Filtrar por Event ID 4624, 4625 y 4648`n" -ForegroundColor White

    $eventos = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = @(4624, 4625, 4648)
        StartTime = (Get-Date).AddMinutes(-15)
    } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "Administrador|administrator" }

    if ($eventos) {
        $eventos | ForEach-Object {
            $tipo = switch ($_.Id) {
                4624 { "Login EXITOSO   " }
                4625 { "Login FALLIDO   " }
                4648 { "Credencial EXPLI" }
            }
            [PSCustomObject]@{
                Hora    = $_.TimeCreated.ToString("HH:mm:ss")
                EventID = $_.Id
                Tipo    = $tipo
                Equipo  = $_.MachineName
            }
        } | Format-Table -AutoSize
    } else {
        Write-Host "  No se encontraron eventos recientes. Verifica auditoría de inicio de sesión." -ForegroundColor Yellow
    }
}

function Show-ResumenPtH {
    Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║  RESUMEN: defensa contra Pass-the-Hash                          ║
╠══════════════════════════════════════════════════════════════════╣
║  ✅ LAPS          — contraseñas locales únicas por equipo        ║
║  ✅ Credential Guard — hashes en enclave virtualizado (VBS)      ║
║  ✅ Protected Users  — sin autenticación NTLM para cuentas priv  ║
║  ✅ Tier Model       — admins de dominio nunca en Tier 2         ║
║  ✅ Restricción admins locales via GPO — menos hashes que robar  ║
╚══════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
}

# ── MENÚ PRINCIPAL ──────────────────────────────────────────
Write-Host @"
╔══════════════════════════════════════════════════════╗
║   DEMO: Pass-the-Hash — Módulo 4                     ║
╠══════════════════════════════════════════════════════╣
║  1. Show-ElProblema     (Acto 1: contraseña shared)  ║
║  2. Show-LaSolucion     (Acto 2: LAPS en acción)     ║
║  3. Show-EventosPtH     (eventos 4624/4625/4648)     ║
║  4. Show-ResumenPtH     (tabla de mitigaciones)      ║
║  0. Salir                                            ║
╚══════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "Flujo recomendado: 1 -> 2 -> 3 -> 4`n" -ForegroundColor White
Write-Host "NOTA: Esta demo no usa herramientas ofensivas. Demuestra el concepto con PS nativo.`n" -ForegroundColor Yellow

do {
    $opcion = Read-Host "Selecciona una opción"
    switch ($opcion) {
        "1" { Show-ElProblema }
        "2" { Show-LaSolucion }
        "3" { Show-EventosPtH }
        "4" { Show-ResumenPtH }
        "0" { Write-Host "Saliendo..." -ForegroundColor Gray }
        default { Write-Host "Opción no válida. Elige 0, 1, 2, 3 o 4." -ForegroundColor Yellow }
    }
} until ($opcion -eq "0")
