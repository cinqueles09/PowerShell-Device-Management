# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 31/10/2024
# Descripción:Este script automatiza el proceso de revisión del atributo extensionAttribute de un usuario en el entorno local (on-premise) 
#             y asigna este valor al dispositivo correspondiente como una propiedad. 
#             Esta acción permite sincronizar y asociar información adicional del usuario con el dispositivo de manera eficiente

#Connect-MgGraph -Identity -ClientId $clientId -Scopes Directory.ReadWrite.All

$Devices = Get-MgDevice -All | Where-Object {$_.TrustType -ne "Workplace"} | Select-Object id, DisplayName

$total = $Devices.Count

# Comprobación de propietario de dispositivo registrado en Azure AD (Híbrido o Azure AD Joined)
for ($var = 0; $var -lt $total; $var++) {
    $Device = $Devices[$var]
    $Owner=Get-MgDeviceRegisteredOwner -DeviceId $Device.id
    
    #Write-Output "El Dispositivo $($Device.DisplayName) tiene como propietario $($Owner.UserPrincipalName)"

    if ($Owner.id -ne $null)
    {
        $Properties= Get-MgUser -UserId $Owner.id -Property onPremisesExtensionAttributes | Select-Object -ExpandProperty onPremisesExtensionAttributes | select ExtensionAttribute2
        if ($Properties.displayName -like "Labvantage*")
        {
            $Attributes = @{
                "extensionAttributes" = @{
                "extensionAttribute1" = "LabVantage"}
            }  | ConvertTo-Json

            update-mgdevice -deviceid $Device.id -bodyparameter $Attributes
            Write-Output "El dispositivo $($Device.DisplayName) con propietario $($Properties.displayName) ha sido actualizado con el extensionAttribute LabVantage"
        }
        elseif ($Properties.displayName -notlike "LabVantage*")
        {
            $Attributes = @{
                "extensionAttributes" = @{
                "extensionAttribute1" = "$($Properties.Department)"}
            }  | ConvertTo-Json

            update-mgdevice -deviceid $Device.id -bodyparameter $Attributes
            Write-Output "El dispositivo $($Device.DisplayName) con propietario $($Properties.displayName) ha sido actualizado con el extensionAttribute $($Properties.Department)"
        }
    }
}

