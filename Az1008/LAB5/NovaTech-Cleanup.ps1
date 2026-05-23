#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script de limpieza completa del laboratorio NovaTech Solutions
.DESCRIPTION
    Elimina en orden inverso todo lo creado por NovaTech-Setup.ps1:
      1. Shares SMB y carpetas de recursos
      2. GPOs y vinculos
      3. PSO
      4. Usuarios, grupos y OUs de AD
      5. Despromocion del DC (con reinicio)
      6. Desinstalacion del rol AD DS (requiere segunda ejecucion tras reinicio)

    Uso:
      Paso 1 - Limpia AD y despromociona: .\NovaTech-Cleanup.ps1
               (el servidor se reinicia automaticamente)
      Paso 2 - Tras el reinicio, elimina el rol:  .\NovaTech-Cleanup.ps1 -SoloRol
#>

param(
    [switch]$SoloRol,
    [switch]$Force
)

function Write-Titulo ($t) { Write-Host "`n+-- $t --+" -ForegroundColor Magenta }
function Write-Ok     ($t) { Write-Host "  [OK] $t"    -ForegroundColor Green }
function Write-Info   ($t) { Write-Host "  [>>] $t"    -ForegroundColor Yellow }
function Write-Err    ($t) { Write-Host "  [!!] $t"    -ForegroundColor Red }
function Import-ADModule {
    if (-not (Get-Module -Name ActiveDirectory)) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
}

# ------------------------------------------------------------------------------
# SOLO ROL - Se ejecuta tras el reinicio post-despromocion
# ------------------------------------------------------------------------------
if ($SoloRol) {
    Write-Titulo "Desinstalacion del rol AD DS"
    $feature = Get-WindowsFeature -Name AD-Domain-Services
    if ($feature.Installed) {
        Write-Info "Desinstalando AD-Domain-Services y herramientas..."
        Uninstall-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Remove | Out-Null
        Write-Ok "Rol AD DS eliminado. Reinicia el servidor para completar la limpieza."
    } else {
        Write-Ok "El rol AD DS ya no esta instalado."
    }
    exit
}

# ------------------------------------------------------------------------------
# Confirmacion
# ------------------------------------------------------------------------------
if (-not $Force) {
    Write-Host "`nATENCION: Este script eliminara TODO el entorno NovaTech del dominio" -ForegroundColor Red
    Write-Host "   y despromovera este servidor como DC.`n" -ForegroundColor Red
    $confirm = Read-Host "Continuar? Escribe 'SI' para confirmar"
    if ($confirm -ne 'SI') {
        Write-Host "Operacion cancelada." -ForegroundColor Yellow
        exit
    }
}

$isDC = (Get-WmiObject Win32_ComputerSystem).DomainRole -ge 4
if ($isDC) { Import-ADModule }

# ------------------------------------------------------------------------------
# PASO 1   Eliminar shares SMB y carpetas
# ------------------------------------------------------------------------------
Write-Titulo "PASO 1   Eliminar shares SMB y carpetas de recursos"

$shareNames = @('Comercial','RRHH','Finanzas','TI-Admin')
foreach ($name in $shareNames) {
    if (Get-SmbShare -Name $name -ErrorAction SilentlyContinue) {
        Remove-SmbShare -Name $name -Force
        Write-Ok "Share $name eliminado."
    }
}

if (Test-Path 'C:\Recursos') {
    Remove-Item -LiteralPath 'C:\Recursos' -Recurse -Force
    Write-Ok "Carpeta C:\Recursos eliminada."
}

# ------------------------------------------------------------------------------
# PASO 2   Eliminar GPOs (solo si es DC)
# ------------------------------------------------------------------------------
if ($isDC) {
    Write-Titulo "PASO 2   Eliminar GPOs"
    Import-Module GroupPolicy -ErrorAction SilentlyContinue

    $gpos = @(
        'GPO-Madrid-Escritorio','GPO-Barcelona-Escritorio','GPO-Valencia-Escritorio',
        'GPO-Madrid-Auditoria', 'GPO-Barcelona-Auditoria', 'GPO-Valencia-Auditoria'
    )
    foreach ($gpoName in $gpos) {
        try {
            $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
            if ($gpo) {
                # Elimina vinculos primero
                $gpo | Get-GPOReport -ReportType Xml -ErrorAction SilentlyContinue | Out-Null
                Remove-GPO -Name $gpoName -ErrorAction SilentlyContinue
                Write-Ok "GPO $gpoName eliminada."
            }
        } catch { Write-Err "No se pudo eliminar GPO $gpoName : $_" }
    }
}

# ------------------------------------------------------------------------------
# PASO 3   Eliminar PSO (solo si es DC)
# ------------------------------------------------------------------------------
if ($isDC) {
    Write-Titulo "PASO 3   Eliminar Fine-Grained Password Policy"
    try {
        $pso = Get-ADFineGrainedPasswordPolicy -Filter {Name -eq 'PSO-Admins-TI'} -ErrorAction SilentlyContinue
        if ($pso) {
            Set-ADFineGrainedPasswordPolicy 'PSO-Admins-TI' -ProtectedFromAccidentalDeletion $false
            Remove-ADFineGrainedPasswordPolicy 'PSO-Admins-TI' -Confirm:$false
            Write-Ok "PSO-Admins-TI eliminada."
        }
    } catch { Write-Err "Error eliminando PSO: $_" }
}

# ------------------------------------------------------------------------------
# PASO 4   Eliminar usuarios, grupos y OUs de AD (solo si es DC)
# ------------------------------------------------------------------------------
if ($isDC) {
    Write-Titulo "PASO 4   Eliminar objetos de AD (usuarios, grupos, OUs)"

    # Usuarios
    $userSams = @('cruiz','lgomez','jfernandez','mmartinez','alopez','pgarcia',
                  'csanchez','djimenez','emoreno','fherrera','gcastillo','hromero')
    foreach ($sam in $userSams) {
        try {
            $u = Get-ADUser -Identity $sam -ErrorAction SilentlyContinue
            if ($u) {
                # Quita de Protected Users antes de eliminar
                Remove-ADGroupMember -Identity 'Protected Users' -Members $sam -Confirm:$false -ErrorAction SilentlyContinue
                Remove-ADUser -Identity $sam -Confirm:$false
                Write-Ok "Usuario $sam eliminado."
            }
        } catch { Write-Err "Error eliminando usuario $sam : $_" }
    }

    # Grupos DL
    $dlGroups = @('DL-Comercial-Lectura','DL-Comercial-Escritura','DL-RRHH-Lectura',
                  'DL-RRHH-Escritura','DL-Finanzas-Lectura','DL-Finanzas-Escritura','DL-TI-Control')
    foreach ($g in $dlGroups) {
        try {
            if (Get-ADGroup -Identity $g -ErrorAction SilentlyContinue) {
                Remove-ADGroup -Identity $g -Confirm:$false
                Write-Ok "Grupo DL $g eliminado."
            }
        } catch { Write-Err "Error eliminando grupo $g : $_" }
    }

    # Grupos Globales de sede/depto
    $globalGroups = @(
        'GRP-TI-Madrid','GRP-Comercial-Madrid','GRP-RRHH-Madrid','GRP-Finanzas-Madrid',
        'GRP-TI-Barcelona','GRP-Comercial-Barcelona','GRP-RRHH-Barcelona','GRP-Finanzas-Barcelona',
        'GRP-TI-Valencia','GRP-Comercial-Valencia','GRP-RRHH-Valencia','GRP-Finanzas-Valencia',
        'Admins-Madrid','Admins-Barcelona','Admins-Valencia'
    )
    foreach ($g in $globalGroups) {
        try {
            if (Get-ADGroup -Identity $g -ErrorAction SilentlyContinue) {
                Remove-ADGroup -Identity $g -Confirm:$false
                Write-Ok "Grupo $g eliminado."
            }
        } catch { Write-Err "Error eliminando grupo $g : $_" }
    }

    # OUs   hay que eliminarlas de dentro hacia afuera
    $root = 'OU=NovaTech,DC=novatech,DC=local'
    $subOUs = @('Usuarios','Grupos','Equipos')

    foreach ($sede in @('Madrid','Barcelona','Valencia')) {
        foreach ($sub in $subOUs) {
            $dn = "OU=$sub,OU=$sede,$root"
            try {
                $ou = Get-ADOrganizationalUnit -Identity $dn -ErrorAction SilentlyContinue
                if ($ou) {
                    Set-ADOrganizationalUnit -Identity $dn -ProtectedFromAccidentalDeletion $false
                    Remove-ADOrganizationalUnit -Identity $dn -Confirm:$false -Recursive
                    Write-Ok "OU $dn eliminada."
                }
            } catch { Write-Err "Error eliminando OU $dn : $_" }
        }
        $sedeDN = "OU=$sede,$root"
        try {
            $ou = Get-ADOrganizationalUnit -Identity $sedeDN -ErrorAction SilentlyContinue
            if ($ou) {
                Set-ADOrganizationalUnit -Identity $sedeDN -ProtectedFromAccidentalDeletion $false
                Remove-ADOrganizationalUnit -Identity $sedeDN -Confirm:$false -Recursive
                Write-Ok "OU $sedeDN eliminada."
            }
        } catch { Write-Err "Error eliminando OU $sedeDN : $_" }
    }

    # OU Cuentas de Servicio
    $svcDN = "OU=Cuentas de Servicio,$root"
    try {
        if (Get-ADOrganizationalUnit -Identity $svcDN -ErrorAction SilentlyContinue) {
            Set-ADOrganizationalUnit -Identity $svcDN -ProtectedFromAccidentalDeletion $false
            Remove-ADOrganizationalUnit -Identity $svcDN -Confirm:$false -Recursive
            Write-Ok "OU Cuentas de Servicio eliminada."
        }
    } catch { Write-Err "Error eliminando OU Cuentas de Servicio: $_" }

    # OU raiz NovaTech
    try {
        if (Get-ADOrganizationalUnit -Identity $root -ErrorAction SilentlyContinue) {
            Set-ADOrganizationalUnit -Identity $root -ProtectedFromAccidentalDeletion $false
            Remove-ADOrganizationalUnit -Identity $root -Confirm:$false -Recursive
            Write-Ok "OU raiz NovaTech eliminada."
        }
    } catch { Write-Err "Error eliminando OU raiz: $_" }
}

# ------------------------------------------------------------------------------
# PASO 5 - Despromocion del DC
# ------------------------------------------------------------------------------
Write-Titulo "PASO 5 - Despromocion del Controlador de Dominio"

if (-not $isDC) {
    Write-Ok "Este servidor ya no es DC. Nada que despromocionar."
} else {
    Write-Info "Despromoviendo el DC (ultimo DC del dominio - el dominio se eliminara)..."
    Write-Info "El servidor se reiniciara automaticamente al finalizar."

    $localAdminPass = Read-Host "Introduce la contrasena para la cuenta Administrador local" -AsSecureString

Uninstall-ADDSDomainController `
    -LastDomainControllerInDomain:$true `
    -DemoteOperationMasterRole:$true `
    -RemoveApplicationPartitions:$true `
    -LocalAdministratorPassword $pass `
    -Force:$true

    # El servidor se reinicia aqu .
    # Tras el reinicio ejecuta: .\NovaTech-Cleanup.ps1 -SoloRol
}
