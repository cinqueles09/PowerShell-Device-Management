# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 17/10/2024


$Teclado = (Get-WinUserLanguageList).languageTag

if ($Teclado -eq "es-Es")
{
  Write-output "El teclado esta correctamente configurado"
  Exit 0
}
else
{
  Write-output "El teclado no esta en español"
  Exit 1
}
