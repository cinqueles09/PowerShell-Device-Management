$buzones = Get-Mailbox -ResultSize Unlimited
$trustedSenderDomain = "[Remitente Seguro]"
foreach ($buzon in $buzones)
 
{
 
Write-Host "Configuración de correo electrónico no deseado para el buzón: $($buzon.DisplayName)"
$junkEmailConfig = Get-MailboxJunkEmailConfiguration -Identity $buzon.Identity
$junkEmailConfig.TrustedSendersAndDomains.Add($trustedSenderDomain)
Set-MailboxJunkEmailConfiguration -Identity $buzon.Identity -TrustedSendersAndDomains $junkEmailConfig.TrustedSendersAndDomains
 
}