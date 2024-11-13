New-WinUserLanguageList es-ES
Set-WinUserLanguageList -LanguageList es-ES -Force

$Result = $?

if ($Result -eq "True")
{
  Write-Output "Idioma cambiado con exito"
}
else
{
  Write-Output "Hubo un fallo en el cambio del idioma"
}