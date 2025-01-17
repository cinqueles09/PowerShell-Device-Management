# Autor: Ismael Morilla
# version: 1.3
# Fecha: 16/01/2025
# Descripción: Muestra el estado de los requisitos mínimos que debe cumplir un dispositivo para que se cifre con Bitlocker para un script de remediación.

###############VARIABLES
# Detectar Modo BIOS: BIOS/EFI/UEFI
$BIOS = Get-Content C:\Windows\Panther\SetupAct.log | Select-String "detected Boot Environment" | ForEach-Object { ([string]$_).Split(":")[4] } | ForEach-Object { ([string]$_).Split(" ")[1] }

# Detectar Arranque seguro activado
$SecureBoot = Confirm-SecureBootUEFI

# Detectar estado de la partición de recuperación (WinRe)
$WinRe = Reagentc /info | Select-String "BCD" | ForEach-Object { ([string]$_).Split(":")[1] } | ForEach-Object { ([string]$_).Split(" ")[1] }

# Detectar TPM
$Presente = (Get-Tpm).TpmPresent
$Ready = (Get-Tpm).TpmReady
$Habilitado = (Get-Tpm).TpmEnabled
$Version = (Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm).SpecVersion | ForEach-Object { ([string]$_).Split(",")[0] }

# Preautenticación
$Tmp = (Get-BitLockerVolume -MountPoint C).KeyProtector
if (($KeyProtec = $Tmp | ForEach-Object {$_ -match "TpmPin"}) -eq $true) {
    $PreAuth = "TpmPin"
} elseif (($KeyProtec = $Tmp | ForEach-Object {$_ -match "Tpm"}) -eq $true) {
    $PreAuth = "Tpm"
} else {
    $PreAuth = "No configurado"
}

# Crear reporte en una sola línea
$Reporte = @"
TPM: $Presente, version: $Version, Ready: $Ready, Habilitado: $Habilitado, WinRe: $WinRe, SecureBoot: $SecureBoot, BIOS: $BIOS, PreAuth: $PreAuth
"@

# Verificar TPM presente
if ($Presente -ne $True) {
    $Reporte += "* El dispositivo no dispone de TPM presente, por lo que no se podrá cifrar el dispositivo."
    Write-Output $Reporte
    Exit 1
}

# Obtener todas las unidades compatibles con BitLocker
$volumes = Get-BitLockerVolume

if ($volumes) {
    foreach ($volume in $volumes) {
        if ($volume.ProtectionStatus -eq "On") {
            $Reporte += "  Esta unidad está protegida por BitLocker."
            Write-Output $Reporte
            Exit 0
        } else {
            $Reporte += "  Esta unidad no está protegida por BitLocker."
            if ($Presente -ne $true) { $Reporte += " * El dispositivo no dispone de TPM presente, por lo que no se podrá cifrar el dispositivo." }
            if ($Habilitado -ne $true) { $Reporte += " * El chip TPM no está habilitado. Antes de continuar, habilítelo." }
            if ($Ready -ne $true) { $Reporte += " * El chip TPM no está preparado." }
            if ([decimal]$Version -lt 1.2) { $Reporte += " * La version del TPM no es compatible con BitLocker. Actualice a una version compatible." }
            if ($SecureBoot -ne $true) { $Reporte += " - El Arranque seguro no está activado. Revise que sea compatible." }
            if ($BIOS -eq "BIOS") { $Reporte += " - Cambie el 'Modo BIOS' a UEFI o EFI." }
            if ($WinRe -eq "00000000-0000-0000-0000-000000000000") { $Reporte += " - La partición de recuperación no existe o está corrupta." }
            Write-Output $Reporte
            Exit 1
        }
    }
}

# Si no hay volúmenes compatibles
$Reporte += "No se encontraron unidades compatibles con BitLocker."
Write-Output $Reporte
Exit 1
