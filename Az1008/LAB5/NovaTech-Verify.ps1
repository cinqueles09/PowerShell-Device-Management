#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script de verificacion completa del laboratorio NovaTech Solutions - Modulo 5 AZ-1008
.DESCRIPTION
    Comprueba que todo lo configurado por NovaTech-Setup.ps1 esta correctamente en su lugar:
      Bloque 0  - Requisitos previos (DC, dominio, modulos)
      Bloque 1  - Estructura de OUs
      Bloque 2  - Usuarios y ubicacion en OUs
      Bloque 3  - Grupos Globales, DL y membresias (AGDLP)
      Bloque 4  - Protected Users
      Bloque 5  - Delegacion de reset de contrasenas
      Bloque 6  - Politica de contrasenas del dominio
      Bloque 7  - Fine-Grained Password Policy (PSO)
      Bloque 8  - GPOs y vinculos
      Bloque 9  - Auditoria avanzada
      Bloque 10 - Shares SMB y permisos NTFS
      Bloque 11 - Resumen final
.NOTES
    Ejecutar como Administrador en NOVATECH-DC01 tras completar NovaTech-Setup.ps1
#>

# ==============================================================================
# CONTADORES Y FUNCIONES DE OUTPUT
# ==============================================================================
$script:OK   = 0
$script:KO   = 0
$script:WARN = 0

function Write-Titulo ($t) {
    Write-Host ""
    Write-Host "+--------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host "+--------------------------------------------------+" -ForegroundColor Cyan
}

function Pass ($msg) {
    Write-Host "  [OK]   $msg" -ForegroundColor Green
    $script:OK++
}

function Fail ($msg) {
    Write-Host "  [KO]   $msg" -ForegroundColor Red
    $script:KO++
}

function Warn ($msg) {
    Write-Host "  [WARN] $msg" -ForegroundColor Yellow
    $script:WARN++
}

function Info ($msg) {
    Write-Host "  [>>]   $msg" -ForegroundColor Gray
}

# ==============================================================================
# BLOQUE 0 - REQUISITOS PREVIOS
# ==============================================================================
Write-Titulo "BLOQUE 0 - Requisitos previos"

# Es Domain Controller?
$domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($domainRole -ge 4) {
    Pass "El servidor es Domain Controller (rol $domainRole)."
} else {
    Fail "El servidor NO es DC (rol $domainRole). Deteniendo verificacion."
    Write-Host "`n[!] El servidor debe ser DC para continuar.`n" -ForegroundColor Red
    exit 1
}

# Nombre de equipo
if ($env:COMPUTERNAME -eq 'NOVATECH-DC01') {
    Pass "Nombre de equipo: NOVATECH-DC01"
} else {
    Fail "Nombre de equipo incorrecto: $env:COMPUTERNAME (esperado: NOVATECH-DC01)"
}

# Dominio
try {
    $domain = Get-ADDomain -ErrorAction Stop
    if ($domain.DNSRoot -eq 'novatech.local') {
        Pass "Dominio: novatech.local"
    } else {
        Fail "Dominio incorrecto: $($domain.DNSRoot)"
    }
} catch {
    Fail "No se pudo obtener informacion del dominio: $_"
}

# Modulo ActiveDirectory
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Pass "Modulo ActiveDirectory cargado."
} catch {
    Fail "No se pudo importar el modulo ActiveDirectory."
    exit 1
}

# Modulo GroupPolicy
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Pass "Modulo GroupPolicy cargado."
} catch {
    Warn "No se pudo importar GroupPolicy. Verificaciones de GPO omitidas."
}

# IP estatica
$expectedIP = '192.168.10.1'
$currentIP  = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $expectedIP }
if ($currentIP) {
    Pass "IP estatica configurada: $expectedIP"
} else {
    Warn "No se encontro la IP $expectedIP en ninguna interfaz."
}

# ==============================================================================
# BLOQUE 1 - ESTRUCTURA DE OUs
# ==============================================================================
Write-Titulo "BLOQUE 1 - Estructura de Unidades Organizativas (OUs)"

$root   = 'OU=NovaTech,DC=novatech,DC=local'
$sedes  = @('Madrid','Barcelona','Valencia')
$subOUs = @('Usuarios','Grupos','Equipos')

# OU raiz
try {
    Get-ADOrganizationalUnit -Identity $root -ErrorAction Stop | Out-Null
    Pass "OU raiz: NovaTech"
} catch {
    Fail "OU raiz NovaTech no encontrada."
}

# OUs por sede y sub-nivel
foreach ($sede in $sedes) {
    $sedeDN = "OU=$sede,$root"
    try {
        Get-ADOrganizationalUnit -Identity $sedeDN -ErrorAction Stop | Out-Null
        Pass "OU sede: $sede"
    } catch {
        Fail "OU sede no encontrada: $sedeDN"
    }
    foreach ($sub in $subOUs) {
        $subDN = "OU=$sub,$sedeDN"
        try {
            Get-ADOrganizationalUnit -Identity $subDN -ErrorAction Stop | Out-Null
            Pass "  OU sub: $sede\$sub"
        } catch {
            Fail "  OU sub no encontrada: $subDN"
        }
    }
}

# OU Cuentas de Servicio
$svcOU = "OU=Cuentas de Servicio,$root"
try {
    Get-ADOrganizationalUnit -Identity $svcOU -ErrorAction Stop | Out-Null
    Pass "OU: Cuentas de Servicio"
} catch {
    Fail "OU 'Cuentas de Servicio' no encontrada."
}

# ==============================================================================
# BLOQUE 2 - USUARIOS
# ==============================================================================
Write-Titulo "BLOQUE 2 - Usuarios y ubicacion en OUs"

$usuarios = @(
    @{Sam='cruiz';      Name='Carlos Ruiz';     Dept='Direccion TI';  Sede='Madrid';    Title='Director TI'},
    @{Sam='lgomez';     Name='Laura Gomez';      Dept='Direccion TI';  Sede='Madrid';    Title='Tecnico Sistemas'},
    @{Sam='jfernandez'; Name='Javier Fernandez'; Dept='Comercial';     Sede='Madrid';    Title='Director Comercial'},
    @{Sam='mmartinez';  Name='Maria Martinez';   Dept='Comercial';     Sede='Madrid';    Title='Comercial'},
    @{Sam='alopez';     Name='Ana Lopez';         Dept='RRHH';          Sede='Madrid';    Title='Directora RRHH'},
    @{Sam='pgarcia';    Name='Pedro Garcia';      Dept='Finanzas';      Sede='Madrid';    Title='Director Finanzas'},
    @{Sam='csanchez';   Name='Clara Sanchez';     Dept='Comercial';     Sede='Barcelona'; Title='Comercial Senior'},
    @{Sam='djimenez';   Name='Diego Jimenez';     Dept='Finanzas';      Sede='Barcelona'; Title='Contable'},
    @{Sam='emoreno';    Name='Elena Moreno';       Dept='RRHH';          Sede='Barcelona'; Title='RRHH'},
    @{Sam='fherrera';   Name='Felipe Herrera';    Dept='Direccion TI';  Sede='Barcelona'; Title='Admin TI Barcelona'},
    @{Sam='gcastillo';  Name='Gloria Castillo';   Dept='Comercial';     Sede='Valencia';  Title='Comercial'},
    @{Sam='hromero';    Name='Hugo Romero';        Dept='Direccion TI';  Sede='Valencia';  Title='Admin TI Valencia'}
)

foreach ($u in $usuarios) {
    try {
        $adUser = Get-ADUser -Identity $u.Sam `
            -Properties Department,Title,Office,DistinguishedName,Enabled,UserPrincipalName `
            -ErrorAction Stop

        # Existe y habilitado
        if ($adUser.Enabled) {
            Pass "Usuario $($u.Sam) ($($u.Name)): existe y habilitado."
        } else {
            Fail "Usuario $($u.Sam): existe pero DESHABILITADO."
        }

        # UPN correcto  (@ dentro de cadena entre comillas simples no falla)
        $expectedUPN = $u.Sam + '@novatech.local'
        if ($adUser.UserPrincipalName -eq $expectedUPN) {
            Pass "  UPN correcto: $($adUser.UserPrincipalName)"
        } else {
            Fail "  UPN incorrecto: $($adUser.UserPrincipalName) (esperado: $expectedUPN)"
        }

        # Departamento
        if ($adUser.Department -eq $u.Dept) {
            Pass "  Departamento: $($adUser.Department)"
        } else {
            Fail "  Departamento incorrecto: '$($adUser.Department)' (esperado: '$($u.Dept)')"
        }

        # OU correcta
        $expectedOU = "OU=Usuarios,OU=$($u.Sede),$root"
        if ($adUser.DistinguishedName -like "*$expectedOU*") {
            Pass "  Ubicacion OU: $($u.Sede)\Usuarios"
        } else {
            Fail "  OU incorrecta. DN actual: $($adUser.DistinguishedName)"
        }

    } catch {
        Fail "Usuario $($u.Sam) NO encontrado en AD."
    }
}

# ==============================================================================
# BLOQUE 3 - GRUPOS Y AGDLP
# ==============================================================================
Write-Titulo "BLOQUE 3 - Grupos Globales, DL y membresias (AGDLP)"

# Grupos Globales por depto/sede
$deptos = @('TI','Comercial','RRHH','Finanzas')
foreach ($sede in $sedes) {
    foreach ($depto in $deptos) {
        $gName = "GRP-$depto-$sede"
        try {
            $g = Get-ADGroup -Identity $gName -ErrorAction Stop
            if ($g.GroupScope -eq 'Global') {
                Pass "Grupo Global: $gName"
            } else {
                Fail "Grupo $gName scope incorrecto: $($g.GroupScope) (esperado Global)"
            }
        } catch {
            Fail "Grupo Global NO encontrado: $gName"
        }
    }
}

# Grupos Admins de sede (Universal)
foreach ($sede in $sedes) {
    $gName = "Admins-$sede"
    try {
        $g = Get-ADGroup -Identity $gName -ErrorAction Stop
        if ($g.GroupScope -eq 'Universal') {
            Pass "Grupo Universal: $gName"
        } else {
            Fail "Grupo $gName scope incorrecto: $($g.GroupScope) (esperado Universal)"
        }
    } catch {
        Fail "Grupo NO encontrado: $gName"
    }
}

# Grupos Domain Local
$dlGroups = @(
    'DL-Comercial-Lectura','DL-Comercial-Escritura',
    'DL-RRHH-Lectura','DL-RRHH-Escritura',
    'DL-Finanzas-Lectura','DL-Finanzas-Escritura',
    'DL-TI-Control'
)
foreach ($dlName in $dlGroups) {
    try {
        $g = Get-ADGroup -Identity $dlName -ErrorAction Stop
        if ($g.GroupScope -eq 'DomainLocal') {
            Pass "Grupo DomainLocal: $dlName"
        } else {
            Fail "Grupo $dlName scope incorrecto: $($g.GroupScope) (esperado DomainLocal)"
        }
    } catch {
        Fail "Grupo DL NO encontrado: $dlName"
    }
}

# Membresias de grupos Globales (usuarios -> grupo)
$memberships = @(
    @{Group='GRP-TI-Madrid';           Members=@('cruiz','lgomez')},
    @{Group='GRP-Comercial-Madrid';    Members=@('jfernandez','mmartinez')},
    @{Group='GRP-RRHH-Madrid';         Members=@('alopez')},
    @{Group='GRP-Finanzas-Madrid';     Members=@('pgarcia')},
    @{Group='GRP-Comercial-Barcelona'; Members=@('csanchez')},
    @{Group='GRP-Finanzas-Barcelona';  Members=@('djimenez')},
    @{Group='GRP-RRHH-Barcelona';      Members=@('emoreno')},
    @{Group='GRP-TI-Barcelona';        Members=@('fherrera')},
    @{Group='GRP-Comercial-Valencia';  Members=@('gcastillo')},
    @{Group='GRP-TI-Valencia';         Members=@('hromero')},
    @{Group='Admins-Barcelona';        Members=@('fherrera')},
    @{Group='Admins-Valencia';         Members=@('hromero')}
)
foreach ($m in $memberships) {
    try {
        $groupMembers = Get-ADGroupMember -Identity $m.Group -ErrorAction Stop |
                        Select-Object -ExpandProperty SamAccountName
        foreach ($member in $m.Members) {
            if ($groupMembers -contains $member) {
                Pass "Membresia: $member en $($m.Group)"
            } else {
                Fail "Membresia FALTANTE: $member no esta en $($m.Group)"
            }
        }
    } catch {
        Fail "No se pudo leer membresia del grupo $($m.Group): $_"
    }
}

# Anidamiento G -> DL
$dlMemberships = @(
    @{DL='DL-Comercial-Lectura';   G=@('GRP-Comercial-Madrid','GRP-Comercial-Barcelona','GRP-Comercial-Valencia')},
    @{DL='DL-Comercial-Escritura'; G=@('GRP-Comercial-Madrid')},
    @{DL='DL-RRHH-Lectura';        G=@('GRP-RRHH-Madrid','GRP-RRHH-Barcelona')},
    @{DL='DL-RRHH-Escritura';      G=@('GRP-RRHH-Madrid')},
    @{DL='DL-Finanzas-Lectura';    G=@('GRP-Finanzas-Madrid','GRP-Finanzas-Barcelona')},
    @{DL='DL-Finanzas-Escritura';  G=@('GRP-Finanzas-Madrid')},
    @{DL='DL-TI-Control';          G=@('GRP-TI-Madrid','GRP-TI-Barcelona','GRP-TI-Valencia')}
)
foreach ($m in $dlMemberships) {
    try {
        $dlMembers = Get-ADGroupMember -Identity $m.DL -ErrorAction Stop |
                     Select-Object -ExpandProperty SamAccountName
        foreach ($g in $m.G) {
            if ($dlMembers -contains $g) {
                Pass "Anidamiento AGDLP: $g -> $($m.DL)"
            } else {
                Fail "Anidamiento AGDLP FALTANTE: $g no esta en $($m.DL)"
            }
        }
    } catch {
        Fail "No se pudo leer anidamiento de $($m.DL): $_"
    }
}

# ==============================================================================
# BLOQUE 4 - PROTECTED USERS
# ==============================================================================
Write-Titulo "BLOQUE 4 - Protected Users"

$protectedMembers = @('cruiz','lgomez','fherrera','hromero')
try {
    $puMembers = Get-ADGroupMember -Identity 'Protected Users' -ErrorAction Stop |
                 Select-Object -ExpandProperty SamAccountName
    foreach ($m in $protectedMembers) {
        if ($puMembers -contains $m) {
            Pass "Protected Users: $m incluido."
        } else {
            Fail "Protected Users: $m NO incluido."
        }
    }
} catch {
    Fail "No se pudo comprobar Protected Users: $_"
}

# ==============================================================================
# BLOQUE 5 - DELEGACION DE RESET DE CONTRASENAS
# ==============================================================================
Write-Titulo "BLOQUE 5 - Delegacion de reset de contrasenas"

$delegaciones = @(
    @{OU="OU=Usuarios,OU=Madrid,$root";    Grupo='Admins-Madrid'},
    @{OU="OU=Usuarios,OU=Barcelona,$root"; Grupo='Admins-Barcelona'},
    @{OU="OU=Usuarios,OU=Valencia,$root";  Grupo='Admins-Valencia'}
)
$resetGuid = [GUID]'00299570-246d-11d0-a768-00aa006e0529'

foreach ($d in $delegaciones) {
    try {
        $group    = Get-ADGroup -Identity $d.Grupo -ErrorAction Stop
        $acl      = Get-Acl -Path "AD:$($d.OU)" -ErrorAction Stop
        $hasRule  = $acl.Access | Where-Object {
            $_.IdentityReference -like "*$($d.Grupo)*" -and
            $_.ObjectType        -eq $resetGuid         -and
            $_.ActiveDirectoryRights -match 'ExtendedRight'
        }
        if ($hasRule) {
            Pass "Delegacion reset: $($d.Grupo) sobre $($d.OU)"
        } else {
            # Busqueda alternativa por SID
            $sid     = $group.SID.Value
            $bySID   = $acl.Access | Where-Object {
                $_.IdentityReference -like "*$sid*" -and
                $_.ObjectType        -eq $resetGuid
            }
            if ($bySID) {
                Pass "Delegacion reset (por SID): $($d.Grupo) sobre $($d.OU)"
            } else {
                Fail "Delegacion de reset NO encontrada: $($d.Grupo) en $($d.OU)"
            }
        }
    } catch {
        Warn "No se pudo verificar la delegacion en $($d.OU): $_"
    }
}

# ==============================================================================
# BLOQUE 6 - POLITICA DE CONTRASENAS DEL DOMINIO
# ==============================================================================
Write-Titulo "BLOQUE 6 - Politica de contrasenas del dominio"

try {
    $pwdPolicy = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop

    if ($pwdPolicy.MinPasswordLength -ge 12) {
        Pass "MinPasswordLength: $($pwdPolicy.MinPasswordLength) (minimo requerido: 12)"
    } else {
        Fail "MinPasswordLength: $($pwdPolicy.MinPasswordLength) -- debe ser 12 o mas"
    }

    if ($pwdPolicy.PasswordHistoryCount -ge 10) {
        Pass "PasswordHistoryCount: $($pwdPolicy.PasswordHistoryCount) (minimo: 10)"
    } else {
        Fail "PasswordHistoryCount: $($pwdPolicy.PasswordHistoryCount) -- debe ser 10 o mas"
    }

    if ($pwdPolicy.MaxPasswordAge.Days -le 90) {
        Pass "MaxPasswordAge: $($pwdPolicy.MaxPasswordAge.Days) dias (maximo: 90)"
    } else {
        Fail "MaxPasswordAge: $($pwdPolicy.MaxPasswordAge.Days) dias -- debe ser 90 dias o menos"
    }

    if ($pwdPolicy.ComplexityEnabled) {
        Pass "Complejidad de contrasena: habilitada."
    } else {
        Fail "Complejidad de contrasena: DESHABILITADA."
    }

    if (-not $pwdPolicy.ReversibleEncryptionEnabled) {
        Pass "Cifrado reversible: deshabilitado (correcto)."
    } else {
        Fail "Cifrado reversible HABILITADO -- deberia estar deshabilitado."
    }

    if ($pwdPolicy.LockoutThreshold -gt 0 -and $pwdPolicy.LockoutThreshold -le 5) {
        Pass "LockoutThreshold: $($pwdPolicy.LockoutThreshold) intentos."
    } else {
        Fail "LockoutThreshold: $($pwdPolicy.LockoutThreshold) -- debe ser entre 1 y 5"
    }

    if ($pwdPolicy.LockoutDuration.TotalMinutes -ge 30) {
        Pass "LockoutDuration: $($pwdPolicy.LockoutDuration.TotalMinutes) minutos (minimo: 30)"
    } else {
        Fail "LockoutDuration: $($pwdPolicy.LockoutDuration.TotalMinutes) min -- debe ser 30 o mas"
    }

} catch {
    Fail "No se pudo obtener la politica de contrasenas: $_"
}

# ==============================================================================
# BLOQUE 7 - FINE-GRAINED PASSWORD POLICY (PSO)
# ==============================================================================
Write-Titulo "BLOQUE 7 - Fine-Grained Password Policy (PSO-Admins-TI)"

try {
    $pso = Get-ADFineGrainedPasswordPolicy -Filter { Name -eq 'PSO-Admins-TI' } -ErrorAction Stop

    if ($pso) {
        Pass "PSO-Admins-TI encontrada."

        if ($pso.Precedence -eq 10) {
            Pass "  Precedence: $($pso.Precedence)"
        } else {
            Fail "  Precedence: $($pso.Precedence) -- debe ser 10"
        }

        if ($pso.MinPasswordLength -ge 16) {
            Pass "  MinPasswordLength: $($pso.MinPasswordLength) (minimo: 16)"
        } else {
            Fail "  MinPasswordLength: $($pso.MinPasswordLength) -- debe ser 16 o mas"
        }

        if ($pso.LockoutThreshold -gt 0 -and $pso.LockoutThreshold -le 3) {
            Pass "  LockoutThreshold: $($pso.LockoutThreshold)"
        } else {
            Fail "  LockoutThreshold: $($pso.LockoutThreshold) -- debe ser 3 o menos"
        }

        if ($pso.MaxPasswordAge.Days -le 60) {
            Pass "  MaxPasswordAge: $($pso.MaxPasswordAge.Days) dias (maximo: 60)"
        } else {
            Fail "  MaxPasswordAge: $($pso.MaxPasswordAge.Days) dias -- debe ser 60 o menos"
        }

        # Grupos TI aplicados a la PSO
        $psoSubjects = Get-ADFineGrainedPasswordPolicySubject 'PSO-Admins-TI' -ErrorAction SilentlyContinue |
                       Select-Object -ExpandProperty SamAccountName
        $tiGroups = @('GRP-TI-Madrid','GRP-TI-Barcelona','GRP-TI-Valencia')
        foreach ($tg in $tiGroups) {
            if ($psoSubjects -contains $tg) {
                Pass "  PSO aplicada a: $tg"
            } else {
                Fail "  PSO NO aplicada a: $tg"
            }
        }
    } else {
        Fail "PSO-Admins-TI no encontrada."
    }
} catch {
    Fail "No se pudo verificar la PSO: $_"
}

# ==============================================================================
# BLOQUE 8 - GPOs Y VINCULOS
# ==============================================================================
Write-Titulo "BLOQUE 8 - GPOs y vinculos"

$gpoDefinitions = @()
foreach ($sede in $sedes) {
    $gpoDefinitions += @{Name="GPO-$sede-Escritorio"; Target="OU=$sede,$root"}
    $gpoDefinitions += @{Name="GPO-$sede-Auditoria";  Target="OU=$sede,$root"}
}

foreach ($gpoDef in $gpoDefinitions) {
    $gpoName  = $gpoDef.Name
    $ouTarget = $gpoDef.Target
    try {
        $gpo = Get-GPO -Name $gpoName -ErrorAction Stop
        if ($gpo) {
            try {
                $inheritance = Get-GPInheritance -Target $ouTarget -ErrorAction Stop
                $linked = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $gpoName }
                if ($linked) {
                    Pass "GPO '$gpoName' existe y vinculada a $ouTarget"
                } else {
                    Fail "GPO '$gpoName' existe pero NO vinculada a $ouTarget"
                }
            } catch {
                Warn "No se pudo verificar vinculo de '$gpoName': $_"
            }
        }
    } catch {
        Fail "GPO NO encontrada: $gpoName"
    }
}

# ==============================================================================
# BLOQUE 9 - AUDITORIA AVANZADA
# ==============================================================================
Write-Titulo "BLOQUE 9 - Auditoria avanzada (auditpol)"

$subcategorias = @(
    @{GUID='{0CCE9235-69AE-11D9-BED3-505054503030}'; Nombre='Administracion de cuentas de usuario'},
    @{GUID='{0CCE9236-69AE-11D9-BED3-505054503030}'; Nombre='Administracion de cuentas de equipo'},
    @{GUID='{0CCE9237-69AE-11D9-BED3-505054503030}'; Nombre='Administracion de grupos de seguridad'}
)

foreach ($sub in $subcategorias) {
    $output = & auditpol /get /subcategory:"$($sub.GUID)" 2>&1
    $outputStr = $output -join ' '
    if ($outputStr -match 'rrecto y Error|Success and Failure') {
        Pass "Auditoria Exito+Error: $($sub.Nombre)"
    } elseif ($outputStr -match 'rrecto|Success') {
        Warn "Auditoria solo Exito (falta Error): $($sub.Nombre)"
    } else {
        Fail "Auditoria NO configurada: $($sub.Nombre)"
    }
}

# ==============================================================================
# BLOQUE 10 - SHARES SMB Y PERMISOS NTFS
# ==============================================================================
Write-Titulo "BLOQUE 10 - Shares SMB y permisos NTFS"

$shares = @(
    @{Name='Comercial'; Path='C:\Recursos\Comercial'},
    @{Name='RRHH';      Path='C:\Recursos\RRHH'},
    @{Name='Finanzas';  Path='C:\Recursos\Finanzas'},
    @{Name='TI-Admin';  Path='C:\Recursos\TI-Admin'}
)

foreach ($s in $shares) {
    if (Test-Path $s.Path) {
        Pass "Carpeta existe: $($s.Path)"
    } else {
        Fail "Carpeta NO encontrada: $($s.Path)"
    }
    $share = Get-SmbShare -Name $s.Name -ErrorAction SilentlyContinue
    if ($share) {
        Pass "Share SMB activo: $($s.Name) -> $($share.Path)"
    } else {
        Fail "Share SMB NO encontrado: $($s.Name)"
    }
}

# Permisos NTFS - grupos DL esperados en cada carpeta
$ntfsCheck = @(
    @{Path='C:\Recursos\Comercial'; Groups=@('NOVATECH\DL-Comercial-Lectura','NOVATECH\DL-Comercial-Escritura')},
    @{Path='C:\Recursos\RRHH';      Groups=@('NOVATECH\DL-RRHH-Lectura','NOVATECH\DL-RRHH-Escritura')},
    @{Path='C:\Recursos\Finanzas';  Groups=@('NOVATECH\DL-Finanzas-Lectura','NOVATECH\DL-Finanzas-Escritura')},
    @{Path='C:\Recursos\TI-Admin';  Groups=@('NOVATECH\DL-TI-Control')}
)

foreach ($check in $ntfsCheck) {
    if (-not (Test-Path $check.Path)) { continue }
    try {
        $acl        = Get-Acl $check.Path -ErrorAction Stop
        $identities = $acl.Access | Select-Object -ExpandProperty IdentityReference | ForEach-Object { $_.Value }
        foreach ($g in $check.Groups) {
            if ($identities -contains $g) {
                Pass "NTFS OK: $g en $($check.Path)"
            } else {
                Fail "NTFS FALTANTE: $g no tiene permisos en $($check.Path)"
            }
        }
    } catch {
        Warn "No se pudieron leer permisos NTFS de $($check.Path): $_"
    }
}

# ==============================================================================
# BLOQUE 11 - RESUMEN FINAL
# ==============================================================================
Write-Host ""
Write-Host "+--------------------------------------------------+" -ForegroundColor White
Write-Host "  RESUMEN - NovaTech Lab Verification" -ForegroundColor White
Write-Host "+--------------------------------------------------+" -ForegroundColor White
Write-Host "  OK   : $($script:OK)"   -ForegroundColor Green
Write-Host "  KO   : $($script:KO)"   -ForegroundColor Red
Write-Host "  WARN : $($script:WARN)" -ForegroundColor Yellow

$total = $script:OK + $script:KO + $script:WARN
if ($total -gt 0) {
    $pct = [math]::Round(($script:OK / $total) * 100, 1)
    Write-Host "  Total: $total comprobaciones | $pct% superadas" -ForegroundColor White
}
Write-Host "+--------------------------------------------------+" -ForegroundColor White

if ($script:KO -eq 0) {
    Write-Host "`n  [EXITO] Todas las comprobaciones superadas.`n" -ForegroundColor Green
} elseif ($script:KO -le 5) {
    Write-Host "`n  [ATENCION] $($script:KO) comprobacion(es) fallida(s). Revisa los [KO].`n" -ForegroundColor Yellow
} else {
    Write-Host "`n  [ERROR] $($script:KO) comprobaciones fallidas. El laboratorio puede estar incompleto.`n" -ForegroundColor Red
}
