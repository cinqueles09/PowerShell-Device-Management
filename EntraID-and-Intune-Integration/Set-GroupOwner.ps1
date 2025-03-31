<#
    .SYNOPSIS
    Script de PowerShell para gestionar propietarios en grupos de Azure AD.

    .DESCRIPTION
    Este script se conecta a Microsoft Graph y verifica un grupo fuente de Azure Active Directory (AAD).
    Obtiene los miembros del grupo fuente y los agrega como propietarios en todos los grupos que comienzan con
    "Intune - app". Si el grupo fuente no tiene miembros, elimina a los propietarios existentes de los grupos de destino.

    .EXAMPLE
    .\AsignarPropietarios.ps1
    Ejecuta el script para asignar propietarios a los grupos cuyo nombre comienza con "Intune - app".

    .NOTES
    - Requiere permisos de Administrador Global o Privilegios adecuados en Azure AD.
    - Asegúrese de que el módulo Microsoft.Graph esté instalado.

    .AUTHOR
    Ismael Morilla Orellana

    .VERSION
    1.0

    .DATE
    31 de marzo de 2025
#>


# Requiere permisos de Administrador Global o Privilegios adecuados en Azure AD
# Debe instalar el modulo Microsoft.Graph si no esta instalado

# Verificar si ya hay una sesion activa con Microsoft Graph
if (-not (Get-MgContext)) {
    Write-Host "Conectando a Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "Group.ReadWrite.All","User.Read.All"
} else {
    Write-Host "Ya hay una sesion activa en Microsoft Graph." -ForegroundColor Green
}

# Definir el grupo fuente (reemplazar con el ObjectId o DisplayName correcto)
$sourceGroupName = "Propietarios - Test" 

# Obtener el ObjectId del grupo fuente
$sourceGroup = Get-MgGroup -Filter "displayName eq '$sourceGroupName'"
if (-not $sourceGroup) {
    Write-Host "[ERROR] No se encontro el grupo fuente: $sourceGroupName" -ForegroundColor Red
    exit
}

# Obtener los miembros del grupo fuente
$members = Get-MgGroupMember -GroupId $sourceGroup.Id | Select-Object -ExpandProperty Id

# Obtener nombres de los miembros
$memberNames = @{}
foreach ($memberId in $members) {
    $user = Get-MgUser -UserId $memberId
    $memberNames[$memberId] = $user.DisplayName
}

if ($members.Count -eq 0) {
    Write-Host "[ERROR] El grupo fuente no tiene miembros." -ForegroundColor Red
    exit
}

# Buscar grupos que comiencen con "Intune - app"
$targetGroups = Get-MgGroup -Filter "startswith(displayName, 'Intune - app')"
if ($targetGroups.Count -eq 0) {
    Write-Host "[WARNING] No se encontraron grupos con el prefijo 'Intune - app'" -ForegroundColor Yellow
    exit
}

# Agregar y remover propietarios en los grupos destino
foreach ($group in $targetGroups) {
    Write-Host "Procesando grupo: $($group.DisplayName)" -ForegroundColor Cyan
    
    # Obtener los propietarios actuales del grupo
    $currentOwners = Get-MgGroupOwner -GroupId $group.Id | Select-Object -ExpandProperty Id
    
    # Obtener nombres de los propietarios
    $ownerNames = @{}
    foreach ($ownerId in $currentOwners) {
        $user = Get-MgUser -UserId $ownerId
        $ownerNames[$ownerId] = $user.DisplayName
    }

    # Agregar miembros que no sean propietarios
    foreach ($memberId in $members) {
        if ($currentOwners -contains $memberId) {
            Write-Host " -> El usuario $($memberNames[$memberId]) ya es propietario en $($group.DisplayName)" -ForegroundColor Yellow
        } else {
            try {
                New-MgGroupOwner -GroupId $group.Id -DirectoryObjectId $memberId
                Write-Host " -> Agregado $($memberNames[$memberId]) como propietario en $($group.DisplayName)" -ForegroundColor Green
            } catch {
                Write-Host "[ERROR] No se pudo agregar $($memberNames[$memberId]) a $($group.DisplayName): $_" -ForegroundColor Red
            }
        }
    }
    
    # Remover propietarios que ya no esten en el grupo fuente
    foreach ($ownerId in $currentOwners) {
        if ($members -notcontains $ownerId) {
            try {
                Remove-MgGroupOwnerByRef -GroupId $group.Id -DirectoryObjectId $ownerId
                Write-Host " -> Eliminado $($ownerNames[$ownerId]) como propietario de $($group.DisplayName)" -ForegroundColor Magenta
            } catch {
                Write-Host "[ERROR] No se pudo eliminar $($ownerNames[$ownerId]) de $($group.DisplayName): $_" -ForegroundColor Red
            }
        }
    }
}

Write-Host "Proceso finalizado." -ForegroundColor Green
