# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 25/05/2024
# Descripción: Muestra el estado de los requisitos mínimos que debe cumplir un dispositivo para que se cifre con Bitlocker

###############VARIABLES
#Detectar Modo BIOS: BIOS/EFI/UEFI
$BIOS=Get-Content C:\Windows\Panther\SetupAct.log | Select-String "detected Boot Environment" | ForEach-Object { ([string]$_).Split(":")[4] } | ForEach-Object { ([string]$_).Split(" ")[1] }
#Detectar Arranque seguro activado
$SecureBoot=Confirm-SecureBootUEFI
#Detectar estado de la partición de recuperación (WinRe)
$WinRe=Reagentc /info | select-string "BCD" | ForEach-Object { ([string]$_).Split(":")[1] } | ForEach-Object { ([string]$_).Split(" ")[1] }

#Detectar TPM
$Presente=(get-tpm).tpmpresent
$Ready=(get-tpm).tpmReady
$Habilitado=(get-tpm).tpmEnabled
$Version=(Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm).SpecVersion | ForEach-Object { ([string]$_).Split(",")[0] }

#Preautenticación
$Tmp = (Get-BitLockerVolume -MountPoint C).KeyProtector
if (($KeyProtec = $Tmp | %{$_ -match "TpmPin"}) -eq 'True')
{
    $PreAuth = "TpmPin"
}
elseif (($KeyProtec = $Tmp | %{$_ -match "Tpm"}) -eq 'True')
 {
    $PreAuth = "Tpm"
}



$TPM = [System.Collections.Generic.List[Object]]::new()
$ReportLine = [PSCustomObject] @{
    TPM               = $Presente
    Version           = $Version
    Ready             = $Ready
    Habilitado        = $Habilitado
    WinRe             = $WinRe
    SecureBoot        = $SecureBoot
    BIOS              = $BIOS
    PreAuth           = $PreAuth
}
$TPM.Add($ReportLine)

#Reporte
cls
Write-Output "###################################################"
Write-Output "        Cumplimiento de los requisitos             "
Write-Output "###################################################"
$TPM | fl

# Recomendaciones

Write-Output "###################################################"
Write-Output "           Correcciones a realizar                 "
Write-Output "###################################################"


if ($WinRe -eq "00000000-0000-0000-0000-000000000000")
{
    Write-Output "- La particion de recuperacion no existe o está corrupta."
}
if ($Presente -ne "True")
{
    Write-Output "- El dispositivo no dispone de TPM presente, por lo que no se podra cifrar el dispositivo"
}
elseif ($Presente -eq "True" -and ($Habilitado -ne "True"))
{
    Write-Output "- El chip TPM no esta habilitado. Antes de continuar habilitelo"
}
elseif ($Presente -eq "True" -and ($Habilitado -eq "True") -and ($Ready -ne "True"))
{
    Write-Output "- El chitp TPM no esta preparado."
}
elseif ($Presente -eq "True" -and ($Habilitado -eq "True") -and ($Ready -ne "True") -and ($Version -lt "1.2"))
{
    Write-Output "- La version del TPM es compatible con BitLocker"
}
if ($SecureBoot -ne "True")
{
    Write-Output "- El Arranque seguro no esta activado. Revisa que sea compatible."
}
if ($BIOS -eq "BIOS")
{
    Write-Output "- Cambia el 'Modo BIOS' a UEFI o EFI."
}




