<#
.SYNOPSIS
Conecta a Microsoft Entra ID y analiza dispositivos registrados, eliminando aquellos que no han tenido actividad durante más de 5 días.

.DESCRIPTION
Este script se conecta a Microsoft Entra ID y obtiene una lista de dispositivos. Analiza cada dispositivo registrado para identificar aquellos que tienen más de 5 días de inactividad y que son de tipo "Microsoft Entra Joined" o "Microsoft Entra Hybrid". 
Si se encuentran dispositivos que cumplen con estos criterios, se preparan para su eliminación y se registra la información relevante en un informe.

.OUTPUTS
Muestra una tabla con los dispositivos eliminados, incluyendo su nombre, ObjectId y tipo de unión.

.NOTES
Autor      : Ismael Morilla Orellana
Fecha      : 08/04/2024
Versión    : 1.0
Revisión   : 1.0

.EXAMPLES
Ejemplo 1: Ejecutar el script para eliminar dispositivos inactivos
PS C:\> .\Cleanup-RegisteredDevices.ps1

.LINK
Repositorio: [https://github.com/cinqueles09/PowerShell-Device-Management]
#>


#Conexión a Entra ID
#Connect-AzureAD

#Obtener lista de dispositivos
$Devices=Get-AzureADDevice -All $True | Select-Object objectid,DisplayName,DeviceOSType,DeviceTrustType,IsCompliant,ApproximateLastLogonTimeStamp | ForEach-Object {$_ -Replace '`t', ';'} 
$total=(echo $Devices | Measure-object -line).lines
$Remove = [System.Collections.Generic.List[Object]]::new()

#Obtener y analizar los dispositivos "Registered", comprobando que tengan mas de 5 dias de inactividad y dispongan de un dispositivo con tipo de combinacion "Microsoft Entra Joined" o "Microsoft Entra Hybrid"
for ($var=1; $var -le $total; $var++) {
    $Join=echo $Devices | select-object -First $var | Select-Object -last 1 | ForEach-Object { ([string]$_).Split(";")[3] } |  ForEach-Object { ([string]$_).Split("=")[1] }  |  ForEach-Object { ([string]$_).Split("}")[0] }

    #Comprobar si tiene registros "Workplace"
    if ($Join -ne 'Workplace')
    {   
        $Name=echo $Devices | select-object -First $var | Select-Object -last 1 | ForEach-Object { ([string]$_).Split(";")[1] } |  ForEach-Object { ([string]$_).Split("=")[1] }  |  ForEach-Object { ([string]$_).Split("}")[0] }
        $Record=(echo $Devices | Select-String "$Name" | Select-String "Workplace" | Measure-Object -Line).lines
        #echo "El dispositivo $Name es $Join y dispone de $Record entradas 'Registered'"
        
        #Si el dispositivo 'Entra Joined' o 'Hybrid Joined' dispone de entradas de registro 'Registered', se buscara su ID y comenzara a borrar los registros.
        if ($Record -gt 0)
        {
            $Registered=echo $Devices | Select-String "$Name" | Select-String "Workplace"
            for ($var1=1; $var1 -le $Record; $var1++) {
                $ID=echo $Registered | select-object -First $var1 | Select-Object -last 1 | ForEach-Object { ([string]$_).Split("=")[1] } |  ForEach-Object { ([string]$_).Split(";")[0] }
                $Join1=echo $Registered | select-object -First $var | Select-Object -last 1 | ForEach-Object { ([string]$_).Split(";")[3] } |  ForEach-Object { ([string]$_).Split("=")[1] }  |  ForEach-Object { ([string]$_).Split("}")[0] }
                #Remove-AzureADDevice -ObjectId $ID                

                if ($Join1 -eq "Workplace")
                {
                    $Reg="Microsoft Entra Registered"
                }

                $ReportLine = [PSCustomObject] @{
                DisplayName       = $Name
                ObjectId          = $ID
                JoinType          = $Reg
                }
                        
                $Remove.Add($ReportLine)
            }
        }

    }
}

#Al final de la ejecucion del script mostrara una tabla con los dispositivos que han sido eliminados
echo " "
echo "Dispositivos eliminados:"
$Remove
