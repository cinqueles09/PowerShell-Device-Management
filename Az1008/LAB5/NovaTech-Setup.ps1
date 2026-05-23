#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script de instalacion completa del laboratorio NovaTech Solutions - Modulo 5 AZ-1008
.DESCRIPTION
    Ejecuta todas las fases del laboratorio en orden:
      Fase 0 - Configuracion de red e IP estatica
      Fase 1 - Instalacion AD DS y promocion a DC
      Fase 2 - Estructura de OUs y delegacion
      Fase 3 - Usuarios, grupos y AGDLP
      Fase 4 - GPO, politicas de contrasena y PSO
      Fase 5 - Seguridad: NTLM, auditoria y restricciones
.NOTES
    Ejecutar como Administrador en Windows Server 2022
    Tras la Fase 1 el servidor se reinicia. Vuelve a ejecutar el script
    con el parametro -Fase para continuar desde donde tocaba:
      .\NovaTech-Setup.ps1 -Fase PostPromocion
#>

param(
    [ValidateSet('Todo','PrePromocion','PostPromocion')]
    [string]$Fase = 'Todo'
)

# --- Colores de consola --------------------------------------------------------
function Write-Titulo  ($t) { Write-Host "`n+-- $t --+" -ForegroundColor Cyan }
function Write-Ok      ($t) { Write-Host "  [OK] $t"    -ForegroundColor Green }
function Write-Info    ($t) { Write-Host "  [>>] $t"    -ForegroundColor Yellow }
function Write-Err     ($t) { Write-Host "  [!!] $t"    -ForegroundColor Red }

function Import-ADModule {
    if (-not (Get-Module -Name ActiveDirectory)) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
}

function Test-ADObjectExists {
    param(
        [Parameter(Mandatory)]
        [string]$Identity,

        [ValidateSet('OU','Group','User')]
        [string]$Type = 'OU'
    )

    try {
        switch ($Type) {
            'OU'    { Get-ADOrganizationalUnit -Identity $Identity -ErrorAction Stop | Out-Null }
            'Group' { Get-ADGroup -Identity $Identity -ErrorAction Stop | Out-Null }
            'User'  { Get-ADUser -Identity $Identity -ErrorAction Stop | Out-Null }
        }
        return $true
    } catch {
        return $false
    }
}

function Ensure-ADOrganizationalUnit {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Description = ''
    )

    $dn = "OU=$Name,$Path"
    if (Test-ADObjectExists -Identity $dn -Type OU) {
        Write-Ok "OU $Name ya existe."
        return $dn
    }

    $params = @{
        Name = $Name
        Path = $Path
        ProtectedFromAccidentalDeletion = $false
        ErrorAction = 'Stop'
    }
    if ($Description) {
        $params.Description = $Description
    }

    New-ADOrganizationalUnit @params | Out-Null
    Write-Ok "OU $Name creada."
    return $dn
}

function Ensure-GPOLinked {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Target
    )

    Import-Module GroupPolicy -ErrorAction Stop

    if (-not (Test-ADObjectExists -Identity $Target -Type OU)) {
        throw "No existe la OU destino para vincular la GPO: $Target"
    }

    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $Name -ErrorAction Stop
        Write-Ok "GPO $Name creada."
    }

    $inheritance = Get-GPInheritance -Target $Target -ErrorAction Stop
    $alreadyLinked = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $Name }
    if (-not $alreadyLinked) {
        New-GPLink -Name $Name -Target $Target -ErrorAction Stop | Out-Null
        Write-Ok "GPO $Name vinculada a $Target."
    } else {
        Write-Ok "GPO $Name ya esta vinculada."
    }
}

function Enable-AuditSubcategory {
    param(
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        & auditpol /set "/subcategory:$name" /success:enable /failure:enable *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Auditoria habilitada: $name"
            return
        }
    }

    throw "No se pudo habilitar la subcategoria de auditoria: $($Names -join ' / ')"
}

# --- Variables globales --------------------------------------------------------
$DomainName     = 'novatech.local'
$DomainNetbios  = 'NOVATECH'
$DCName         = 'NOVATECH-DC01'
$BaseOU         = 'OU=NovaTech,DC=novatech,DC=local'
$DSRMPassword   = ConvertTo-SecureString 'P@ssw0rd.DSRM2024!' -AsPlainText -Force
$DefaultPass    = ConvertTo-SecureString 'Novatech2024!'      -AsPlainText -Force
$InterfaceIndex = (Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object -First 1).InterfaceIndex
$IPAddress      = '192.168.10.1'
$PrefixLength   = 24
$Gateway        = '192.168.10.254'

# ------------------------------------------------------------------------------
# FASE 0 - Preparacion del entorno
# ------------------------------------------------------------------------------
function Invoke-Fase0 {
    Write-Titulo "FASE 0 - Preparacion del entorno"

    # Nombre del equipo
    $currentName = $env:COMPUTERNAME
    if ($currentName -ne $DCName) {
        Write-Info "Cambiando nombre de equipo a $DCName..."
        Rename-Computer -NewName $DCName -Force
        Write-Ok "Nombre cambiado. Se aplicara tras el reinicio."
    } else {
        Write-Ok "Nombre de equipo ya es $DCName"
    }

    # IP estatica
    Write-Info "Configurando IP estatica $IPAddress/$PrefixLength..."
    try {
        $existing = Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($existing.IPAddress -ne $IPAddress) {
            Remove-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-NetRoute -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceIndex $InterfaceIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
        }
        Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses $IPAddress
        Write-Ok "IP estatica y DNS configurados."
    } catch {
        Write-Err "Error configurando red: $_"
    }
}

# ------------------------------------------------------------------------------
# FASE 1 - Instalacion AD DS y promocion a DC
# ------------------------------------------------------------------------------
function Invoke-Fase1 {
    Write-Titulo "FASE 1 - Instalacion AD DS y creacion del dominio"

    # Instala el rol si no esta
    $feature = Get-WindowsFeature -Name AD-Domain-Services
    if (-not $feature.Installed) {
        Write-Info "Instalando rol AD-Domain-Services..."
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
        Write-Ok "Rol instalado."
    } else {
        Write-Ok "Rol AD-Domain-Services ya instalado."
    }

    # Comprueba si ya es DC
    $isDC = (Get-WmiObject Win32_ComputerSystem).DomainRole -ge 4
    if ($isDC) {
        Write-Ok "El servidor ya es DC. Saltando promocion."
        return
    }

    Write-Info "Promoviendo a DC - dominio: $DomainName (el servidor se reiniciara)..."
    Import-Module ADDSDeployment
    Install-ADDSForest `
        -DomainName        $DomainName `
        -DomainNetbiosName $DomainNetbios `
        -DomainMode        'WinThreshold' `
        -ForestMode        'WinThreshold' `
        -InstallDns `
        -SafeModeAdministratorPassword $DSRMPassword `
        -Force

    # El servidor se reinicia aqui.
    # Despues del reinicio ejecuta: .\NovaTech-Setup.ps1 -Fase PostPromocion
}

# ------------------------------------------------------------------------------
# FASE 2 - Estructura de OUs y delegacion de control
# ------------------------------------------------------------------------------
function Invoke-Fase2 {
    Import-ADModule
    Write-Titulo "FASE 2 - Estructura de OUs y delegacion de control"

    $domainDN = (Get-ADDomain -ErrorAction Stop).DistinguishedName
    $root = Ensure-ADOrganizationalUnit -Name 'NovaTech' -Path $domainDN -Description 'OU raiz corporativa de NovaTech Solutions'

    foreach ($sede in @('Madrid','Barcelona','Valencia')) {
        $sedeOU = Ensure-ADOrganizationalUnit -Name $sede -Path $root -Description "Sede $sede"
        foreach ($sub in @('Usuarios','Grupos','Equipos')) {
            Ensure-ADOrganizationalUnit -Name $sub -Path $sedeOU | Out-Null
        }
    }

    Ensure-ADOrganizationalUnit -Name 'Cuentas de Servicio' -Path $root | Out-Null

    $sedeGrupos = @(
        @{Name='Admins-Madrid';    Path="OU=Grupos,OU=Madrid,$root";    Desc='Administradores de la sede Madrid'},
        @{Name='Admins-Barcelona'; Path="OU=Grupos,OU=Barcelona,$root"; Desc='Administradores de la sede Barcelona'},
        @{Name='Admins-Valencia';  Path="OU=Grupos,OU=Valencia,$root";  Desc='Administradores de la sede Valencia'}
    )
    foreach ($g in $sedeGrupos) {
        $groupName = $g.Name
        if (-not (Test-ADObjectExists -Identity $groupName -Type Group)) {
            New-ADGroup -Name $g.Name -SamAccountName $g.Name -GroupScope Universal -GroupCategory Security -Path $g.Path -Description $g.Desc -ErrorAction Stop
            Write-Ok "Grupo $($g.Name) creado."
        } else { Write-Ok "Grupo $($g.Name) ya existe." }
    }

    # Delegacion de reset de contrasenas
    function Delegate-PasswordReset ($ouDN, $groupName) {
        $group    = Get-ADGroup $groupName -ErrorAction Stop
        $groupSID = [System.Security.Principal.SecurityIdentifier] $group.SID
        $ouACL    = Get-Acl -Path "AD:$ouDN" -ErrorAction Stop
        $resetGuid = [GUID]'00299570-246d-11d0-a768-00aa006e0529'
        $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $groupSID,
            [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $resetGuid,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents
        )
        $ouACL.AddAccessRule($rule)
        Set-Acl -Path "AD:$ouDN" -AclObject $ouACL -ErrorAction Stop
    }

    Delegate-PasswordReset "OU=Usuarios,OU=Madrid,$root"    'Admins-Madrid'
    Delegate-PasswordReset "OU=Usuarios,OU=Barcelona,$root" 'Admins-Barcelona'
    Delegate-PasswordReset "OU=Usuarios,OU=Valencia,$root"  'Admins-Valencia'
    Write-Ok "Delegacion de reset de contrasenas configurada."
}

# ------------------------------------------------------------------------------
# FASE 3 - Usuarios, grupos y AGDLP
# ------------------------------------------------------------------------------
function Invoke-Fase3 {
    Import-ADModule
    Write-Titulo "FASE 3 - Usuarios, grupos y AGDLP"

    $root = "OU=NovaTech,DC=novatech,DC=local"

    # -- Usuarios --------------------------------------------------------------
    $usuarios = @(
        @{Sam='cruiz';     Name='Carlos Ruiz';       Dept='Direccion TI';  Sede='Madrid';    Title='Director TI'},
        @{Sam='lgomez';    Name='Laura Gomez';        Dept='Direccion TI';  Sede='Madrid';    Title='Tecnico Sistemas'},
        @{Sam='jfernandez';Name='Javier Fernandez';   Dept='Comercial';     Sede='Madrid';    Title='Director Comercial'},
        @{Sam='mmartinez'; Name='Maria Martinez';     Dept='Comercial';     Sede='Madrid';    Title='Comercial'},
        @{Sam='alopez';    Name='Ana Lopez';           Dept='RRHH';          Sede='Madrid';    Title='Directora RRHH'},
        @{Sam='pgarcia';   Name='Pedro Garcia';        Dept='Finanzas';      Sede='Madrid';    Title='Director Finanzas'},
        @{Sam='csanchez';  Name='Clara Sanchez';       Dept='Comercial';     Sede='Barcelona'; Title='Comercial Senior'},
        @{Sam='djimenez';  Name='Diego Jimenez';       Dept='Finanzas';      Sede='Barcelona'; Title='Contable'},
        @{Sam='emoreno';   Name='Elena Moreno';        Dept='RRHH';          Sede='Barcelona'; Title='RRHH'},
        @{Sam='fherrera';  Name='Felipe Herrera';      Dept='Direccion TI';  Sede='Barcelona'; Title='Admin TI Barcelona'},
        @{Sam='gcastillo'; Name='Gloria Castillo';     Dept='Comercial';     Sede='Valencia';  Title='Comercial'},
        @{Sam='hromero';   Name='Hugo Romero';         Dept='Direccion TI';  Sede='Valencia';  Title='Admin TI Valencia'}
    )
    foreach ($u in $usuarios) {
        $sam = $u.Sam
        if (-not (Test-ADObjectExists -Identity $sam -Type User)) {
            $ouPath = "OU=Usuarios,OU=$($u.Sede),$root"
            New-ADUser `
                -SamAccountName   $u.Sam `
                -Name             $u.Name `
                -GivenName        ($u.Name -split ' ')[0] `
                -Surname          ($u.Name -split ' ')[1] `
                -Department       $u.Dept `
                -Title            $u.Title `
                -Office           $u.Sede `
                -Path             $ouPath `
                -AccountPassword  $DefaultPass `
                -ChangePasswordAtLogon $true `
                -Enabled          $true `
                -UserPrincipalName "$($u.Sam)@novatech.local" `
                -ErrorAction      Stop
            Write-Ok "Usuario $($u.Name) creado."
        } else { Write-Ok "Usuario $($u.Sam) ya existe." }
    }

    # -- Grupos Globales por departamento y sede --------------------------------
    $sedes  = @('Madrid','Barcelona','Valencia')
    $deptos = @('Comercial','RRHH','Finanzas','TI')

    foreach ($sede in $sedes) {
        $gruposOU = "OU=Grupos,OU=$sede,$root"
        foreach ($depto in $deptos) {
            $nombre = "GRP-$depto-$sede"
            if (-not (Test-ADObjectExists -Identity $nombre -Type Group)) {
                New-ADGroup -Name $nombre -SamAccountName $nombre -GroupScope Global -GroupCategory Security -Path $gruposOU -Description "Grupo $depto - Sede $sede" -ErrorAction Stop
                Write-Ok "Grupo $nombre creado."
            }
        }
    }

    # -- Membresias de grupos Globales -----------------------------------------
    $memberships = @(
        @{Group='GRP-TI-Madrid';          Members=@('cruiz','lgomez')},
        @{Group='GRP-Comercial-Madrid';   Members=@('jfernandez','mmartinez')},
        @{Group='GRP-RRHH-Madrid';        Members=@('alopez')},
        @{Group='GRP-Finanzas-Madrid';    Members=@('pgarcia')},
        @{Group='GRP-Comercial-Barcelona';Members=@('csanchez')},
        @{Group='GRP-Finanzas-Barcelona'; Members=@('djimenez')},
        @{Group='GRP-RRHH-Barcelona';     Members=@('emoreno')},
        @{Group='GRP-TI-Barcelona';       Members=@('fherrera')},
        @{Group='GRP-Comercial-Valencia'; Members=@('gcastillo')},
        @{Group='GRP-TI-Valencia';        Members=@('hromero')},
        @{Group='Admins-Barcelona';       Members=@('fherrera')},
        @{Group='Admins-Valencia';        Members=@('hromero')}
    )
    foreach ($m in $memberships) {
        try {
            Add-ADGroupMember -Identity $m.Group -Members $m.Members -ErrorAction Stop
            Write-Ok "Membresia $($m.Group) configurada."
        } catch { Write-Err "Error en membresia $($m.Group): $_" }
    }

    # -- Protected Users -------------------------------------------------------
    try {
        Add-ADGroupMember -Identity 'Protected Users' -Members @('cruiz','lgomez','fherrera','hromero') -ErrorAction Stop
        Write-Ok "Protected Users configurado."
    } catch {
        Write-Err "Error configurando Protected Users: $_"
    }

    # -- AGDLP - Grupos Domain Local -------------------------------------------
    $dlOU = "OU=Grupos,OU=Madrid,$root"
    $gruposDL = @(
        @{Name='DL-Comercial-Lectura';   Desc='Acceso lectura a Comercial'},
        @{Name='DL-Comercial-Escritura'; Desc='Acceso escritura a Comercial'},
        @{Name='DL-RRHH-Lectura';        Desc='Acceso lectura a RRHH'},
        @{Name='DL-RRHH-Escritura';      Desc='Acceso escritura a RRHH'},
        @{Name='DL-Finanzas-Lectura';    Desc='Acceso lectura a Finanzas'},
        @{Name='DL-Finanzas-Escritura';  Desc='Acceso escritura a Finanzas'},
        @{Name='DL-TI-Control';          Desc='Control total carpeta TI-Admin'}
    )
    foreach ($dl in $gruposDL) {
        $dlName = $dl.Name
        if (-not (Test-ADObjectExists -Identity $dlName -Type Group)) {
            New-ADGroup -Name $dl.Name -SamAccountName $dl.Name -GroupScope DomainLocal -GroupCategory Security -Path $dlOU -Description $dl.Desc -ErrorAction Stop
            Write-Ok "Grupo DL $($dl.Name) creado."
        }
    }

    # -- Anidamiento G ? DL ----------------------------------------------------
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
            Add-ADGroupMember -Identity $m.DL -Members $m.G -ErrorAction SilentlyContinue
            Write-Ok "Anidamiento $($m.DL) configurado."
        } catch { Write-Err "Error anidando $($m.DL): $_" }
    }

    # -- Carpetas compartidas y permisos NTFS ----------------------------------
    $carpetas = @('Comercial','RRHH','Finanzas','TI-Admin')
    foreach ($c in $carpetas) {
        $path = "C:\Recursos\$c"
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-Ok "Carpeta $path creada."
        }
    }
    # Shares
    $domainSid = (Get-ADDomain).DomainSID.Value
    $domainAdmins = Get-ADGroup -Identity "$domainSid-512"
    $domainAdminsAccount = "$DomainNetbios\$($domainAdmins.SamAccountName)"
    $everyoneAccount = ([System.Security.Principal.SecurityIdentifier]'S-1-1-0').Translate([System.Security.Principal.NTAccount]).Value
    $shares = @(
        @{Name='Comercial'; Path='C:\Recursos\Comercial'; ReadAccess=$true},
        @{Name='RRHH';      Path='C:\Recursos\RRHH';      ReadAccess=$true},
        @{Name='Finanzas';  Path='C:\Recursos\Finanzas';  ReadAccess=$true},
        @{Name='TI-Admin';  Path='C:\Recursos\TI-Admin';  ReadAccess=$false}
    )
    foreach ($s in $shares) {
        if (-not (Get-SmbShare -Name $s.Name -ErrorAction SilentlyContinue)) {
            if ($s.ReadAccess) {
                New-SmbShare -Name $s.Name -Path $s.Path -FullAccess $domainAdminsAccount -ReadAccess $everyoneAccount | Out-Null
            } else {
                New-SmbShare -Name $s.Name -Path $s.Path -FullAccess $domainAdminsAccount | Out-Null
            }
            Write-Ok "Share $($s.Name) creado."
        } else { Write-Ok "Share $($s.Name) ya existe." }
    }

    # Permisos NTFS
    $ntfsRules = @(
        @{Path='C:\Recursos\Comercial'; Rules=@(
            @{Identity='NOVATECH\DL-Comercial-Lectura';   Rights='ReadAndExecute'; Inherit='ContainerInherit,ObjectInherit'},
            @{Identity='NOVATECH\DL-Comercial-Escritura'; Rights='Modify';         Inherit='ContainerInherit,ObjectInherit'},
            @{Identity=$domainAdminsAccount;               Rights='FullControl';    Inherit='ContainerInherit,ObjectInherit'}
        )},
        @{Path='C:\Recursos\RRHH'; Rules=@(
            @{Identity='NOVATECH\DL-RRHH-Lectura';        Rights='ReadAndExecute'; Inherit='ContainerInherit,ObjectInherit'},
            @{Identity='NOVATECH\DL-RRHH-Escritura';      Rights='Modify';         Inherit='ContainerInherit,ObjectInherit'},
            @{Identity=$domainAdminsAccount;               Rights='FullControl';    Inherit='ContainerInherit,ObjectInherit'}
        )},
        @{Path='C:\Recursos\Finanzas'; Rules=@(
            @{Identity='NOVATECH\DL-Finanzas-Lectura';    Rights='ReadAndExecute'; Inherit='ContainerInherit,ObjectInherit'},
            @{Identity='NOVATECH\DL-Finanzas-Escritura';  Rights='Modify';         Inherit='ContainerInherit,ObjectInherit'},
            @{Identity=$domainAdminsAccount;               Rights='FullControl';    Inherit='ContainerInherit,ObjectInherit'}
        )},
        @{Path='C:\Recursos\TI-Admin'; Rules=@(
            @{Identity='NOVATECH\DL-TI-Control';          Rights='FullControl';    Inherit='ContainerInherit,ObjectInherit'},
            @{Identity=$domainAdminsAccount;               Rights='FullControl';    Inherit='ContainerInherit,ObjectInherit'}
        )}
    )

    foreach ($folder in $ntfsRules) {
        $acl = Get-Acl $folder.Path
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($r in $folder.Rules) {
            try {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $r.Identity, $r.Rights, $r.Inherit, 'None', 'Allow'
                )
                $acl.AddAccessRule($rule)
            } catch {
                Write-Err "No se pudo agregar permiso $($r.Identity) en $($folder.Path): $_"
            }
        }
        Set-Acl $folder.Path $acl
        Write-Ok "Permisos NTFS aplicados en $($folder.Path)."
    }
}

# ------------------------------------------------------------------------------
# FASE 4 - GPO y politicas de contrasena
# ------------------------------------------------------------------------------
function Invoke-Fase4 {
    Import-ADModule
    Write-Titulo "FASE 4 - GPO y politicas de contrasena"

    # Politica de contrasenas del dominio
    Set-ADDefaultDomainPasswordPolicy -Identity $DomainName `
        -MinPasswordLength    12 `
        -PasswordHistoryCount 10 `
        -MaxPasswordAge       (New-TimeSpan -Days 90) `
        -MinPasswordAge       (New-TimeSpan -Days 1) `
        -ComplexityEnabled    $true `
        -ReversibleEncryptionEnabled $false `
        -LockoutThreshold     5 `
        -LockoutDuration      (New-TimeSpan -Minutes 30) `
        -LockoutObservationWindow (New-TimeSpan -Minutes 30)
    Write-Ok "Politica de contrasenas del dominio configurada."

    # Fine-Grained Password Policy para admins TI
    if (-not (Get-ADFineGrainedPasswordPolicy -Filter {Name -eq 'PSO-Admins-TI'} -ErrorAction SilentlyContinue)) {
        New-ADFineGrainedPasswordPolicy `
            -Name                'PSO-Admins-TI' `
            -Precedence          10 `
            -MinPasswordLength   16 `
            -PasswordHistoryCount 24 `
            -MaxPasswordAge      (New-TimeSpan -Days 60) `
            -MinPasswordAge      (New-TimeSpan -Days 1) `
            -ComplexityEnabled   $true `
            -LockoutThreshold    3 `
            -LockoutDuration     (New-TimeSpan -Hours 1) `
            -LockoutObservationWindow (New-TimeSpan -Minutes 30) `
            -ProtectedFromAccidentalDeletion $true
        Write-Ok "PSO-Admins-TI creada."
    } else { Write-Ok "PSO-Admins-TI ya existe." }

    try {
        Add-ADFineGrainedPasswordPolicySubject 'PSO-Admins-TI' -Subjects @('GRP-TI-Madrid','GRP-TI-Barcelona','GRP-TI-Valencia') -ErrorAction Stop
        Write-Ok "PSO aplicada a grupos TI."
    } catch {
        Write-Err "No se pudo aplicar la PSO a los grupos TI: $_"
    }

    # GPOs de escritorio por sede (crea y vincula - configuracion manual en GPMC)
    $root = "OU=NovaTech,DC=novatech,DC=local"
    foreach ($sede in @('Madrid','Barcelona','Valencia')) {
        $gpoName = "GPO-$sede-Escritorio"
        try {
            Ensure-GPOLinked -Name $gpoName -Target "OU=$sede,$root"
        } catch {
            Write-Err "No se pudo crear o vincular GPO ${gpoName}: $_"
        }
    }
}

# ------------------------------------------------------------------------------
# FASE 5 - Seguridad: auditoria y restricciones
# ------------------------------------------------------------------------------
function Invoke-Fase5 {
    Import-ADModule
    Write-Titulo "FASE 5 - Seguridad: auditoria y restricciones"

    # Auditoria avanzada
    try {
        Enable-AuditSubcategory -Names @('{0CCE9235-69AE-11D9-BED3-505054503030}','User Account Management','Administracion de cuentas de usuario')
        Enable-AuditSubcategory -Names @('{0CCE9236-69AE-11D9-BED3-505054503030}','Computer Account Management','Administracion de cuentas de equipo')
        Enable-AuditSubcategory -Names @('{0CCE9237-69AE-11D9-BED3-505054503030}','Security Group Management','Administracion de grupos de seguridad')
    } catch {
        Write-Err $_
    }

    # GPO de auditoria por sede
    $root = "OU=NovaTech,DC=novatech,DC=local"
    foreach ($sede in @('Madrid','Barcelona','Valencia')) {
        $gpoName = "GPO-$sede-Auditoria"
        try {
            Ensure-GPOLinked -Name $gpoName -Target "OU=$sede,$root"
        } catch {
            Write-Err "No se pudo crear o vincular GPO ${gpoName}: $_"
        }
    }

    # Denegar LogOn as Service a grupos Admins de sede
    Write-Info "Configurando 'Denegar inicio de sesion como servicio' via secedit..."
    $tmpCfg = "$env:TEMP\secpol_novatech.cfg"
    secedit /export /cfg $tmpCfg /areas USER_RIGHTS | Out-Null

    $content = Get-Content $tmpCfg
    $adminsGroups = @('Admins-Madrid','Admins-Barcelona','Admins-Valencia') | ForEach-Object {
        try {
            $sid = (Get-ADGroup $_ -ErrorAction Stop).SID.Value
            "*$sid"
        } catch {
            Write-Err "No se encontro el grupo $_ para configurar SeDenyServiceLogonRight."
        }
    }
    if (-not $adminsGroups) {
        Write-Err "No se configuro Denegar LogOn as Service porque no se encontraron grupos Admins-*."
        return
    }
    $sidList = $adminsGroups -join ','

    $newContent = $content | ForEach-Object {
        if ($_ -match '^SeDenyServiceLogonRight') {
            "SeDenyServiceLogonRight = $sidList"
        } else { $_ }
    }
    if (-not ($content -match 'SeDenyServiceLogonRight')) {
        $newContent += "SeDenyServiceLogonRight = $sidList"
    }
    $newContent | Set-Content $tmpCfg
    secedit /configure /cfg $tmpCfg /areas USER_RIGHTS /quiet | Out-Null
    Write-Ok "Denegar LogOn as Service configurado."

    # NTLM - info al alumno (requiere GPMC manual o ajuste de registro)
    Write-Info "NTLM: configura manualmente via GPMC en Default Domain Controllers Policy."
    Write-Info "Ruta: Conf. equipo > Directivas > Conf. Windows > Conf. seguridad > Directivas locales > Opciones de seguridad"
    Write-Info "Parametro: 'Restringir NTLM: Autenticacion NTLM en este dominio' = Denegar todo"
}

# ------------------------------------------------------------------------------
# VERIFICACION FINAL
# ------------------------------------------------------------------------------
function Invoke-Verificacion {
    Import-ADModule
    Write-Titulo "VERIFICACION FINAL"

    Write-Host "`n-- OUs del dominio --" -ForegroundColor Cyan
    Get-ADOrganizationalUnit -Filter * -SearchBase 'OU=NovaTech,DC=novatech,DC=local' |
        Select-Object Name, DistinguishedName | Format-Table -AutoSize

    Write-Host "`n-- Usuarios por sede --" -ForegroundColor Cyan
    Get-ADUser -Filter * -SearchBase 'OU=NovaTech,DC=novatech,DC=local' -Properties Office |
        Group-Object Office | Select-Object Name, Count | Format-Table -AutoSize

    Write-Host "`n-- Grupos DL (AGDLP) --" -ForegroundColor Cyan
    Get-ADGroup -Filter {GroupScope -eq 'DomainLocal'} | Select-Object Name | Format-Table -AutoSize

    Write-Host "`n-- Miembros de Protected Users --" -ForegroundColor Cyan
    Get-ADGroupMember 'Protected Users' | Select-Object Name, SamAccountName | Format-Table -AutoSize

    Write-Host "`n-- PSO activa --" -ForegroundColor Cyan
    Get-ADFineGrainedPasswordPolicy -Filter * | Select-Object Name, Precedence, MinPasswordLength | Format-Table -AutoSize

    Write-Host "`n-- Auditoria --" -ForegroundColor Cyan
    auditpol /get /subcategory:'{0CCE9235-69AE-11D9-BED3-505054503030}'

    Write-Host "`n-- Shares SMB --" -ForegroundColor Cyan
    Get-SmbShare | Where-Object {$_.Name -in @('Comercial','RRHH','Finanzas','TI-Admin')} |
        Select-Object Name, Path | Format-Table -AutoSize
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
switch ($Fase) {
    'PrePromocion' {
        Invoke-Fase0
        Invoke-Fase1
        # El script se detiene aqui porque el servidor se reinicia
    }
    'PostPromocion' {
        Invoke-Fase2
        Invoke-Fase3
        Invoke-Fase4
        Invoke-Fase5
        Invoke-Verificacion
    }
    'Todo' {
        $isDC = (Get-WmiObject Win32_ComputerSystem).DomainRole -ge 4
        if (-not $isDC) {
            Write-Host "`n[INFO] El servidor aun no es DC. Ejecutando Fase 0 y Fase 1..." -ForegroundColor Yellow
            Write-Host "[INFO] Tras el reinicio, vuelve a ejecutar: .\NovaTech-Setup.ps1 -Fase PostPromocion" -ForegroundColor Yellow
            Invoke-Fase0
            Invoke-Fase1
        } else {
            Write-Host "`n[INFO] Servidor ya es DC. Continuando con fases post-promocion..." -ForegroundColor Green
            Invoke-Fase2
            Invoke-Fase3
            Invoke-Fase4
            Invoke-Fase5
            Invoke-Verificacion
        }
    }
}

Write-Host "`n[DONE] Script finalizado.`n" -ForegroundColor Green
