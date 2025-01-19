# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 07/05/2024
# Descripción: Script de evaluación de cumplimiento para evaluar si un dispositivo dispone de Pin Bitlocker activado

$Tmp = (Get-BitLockerVolume -MountPoint C).KeyProtector
$KeyProtec = $Tmp | %{$_ -match "TpmPin"}
if ($KeyProtec -eq $true)
{
    $PIN="TpmPin"
}
else {
    $PIN="Nulo"
}

$hash = @{ TPMAuth = $PIN} 
return $hash | ConvertTo-Json -Compress
