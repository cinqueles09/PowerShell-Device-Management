# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 25/05/2024
# Descripción: Script de detección para habilitar PIN de Bitlocker

$Tmp = (Get-BitLockerVolume -MountPoint C).KeyProtector
$KeyProtec = $Tmp | %{$_ -match "TpmPin"}
if ($KeyProtec -eq $true)
{
Write-Host "Habilitado Tmp con PIN"
Exit 0
}
else
{

Write-Host "Seguimos sin habilitar el PIN"
Exit 1618
}
