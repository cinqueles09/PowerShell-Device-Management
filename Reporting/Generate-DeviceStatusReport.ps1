# Autor: Ismael Morilla Orellana
# Versión: 2.1 
# Fecha: 01/01/2025
# Descripción: Este script analiza los informes exportados de Intune, Defender y Entra ID, proporcionando una visión general del estado de los dispositivos 
#               y generando un informe detallado de los equipos que requieren atención.

#$lastLogonFile = Import-Csv -Path "lastlogon.csv"
$Defenderfile  = Import-Csv -Path "Defender.csv"
$Intunefile  = Import-Csv -Path "Intune.csv"
$Entrafile = Import-Csv -Path "Entra.csv"
$Users = Import-Csv -Path "Users.csv"

$OSv10_1="10.0.19045.5131"
$OSv10_2="10.0.19045.5198"
$OSv10_New="10.0.19045.5247"
$OSv11_1="10.0.22631.4460"
$OSv11_2="10.0.22631.4541"
$OSv11_11="10.0.26100.2314"
$OSv11_12="10.0.26100.2454"
$OSv11_New="10.0.22631.4602"
$OSv11_New2="10.0.26100.2605"

#Declaración de tablas
$DeviceInfo = @()
$W1XDevice = @()

$Export= Test-Path "Export"

if ($Export -ne "True")
{
    mkdir "Export"
}

##### UPDATES

$W10UpdateOld=($Intunefile | Where-Object { $_.OSVersion -eq "$($OSv10_1)" -or ($_.$osVersion -eq "$($OSv10_2)") -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed")) }).count
$W10UpdateNew= ($Intunefile | Where-Object { $_.OSVersion -eq "$($OSv10_New)" -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed")) }).count
$W10UpdateDown= $Intunefile | Where-Object { $_.OSVersion -lt "$($OSv10_1)" -and ($_.OSVersion -like "10.0.19*") -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}
$Updatew10Pending = @()
foreach ($updateDevice in $W10UpdateDown) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $UpdateDevice.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $UpdateDevice.PrimaryUserUPN }).officeLocation
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $UpdateDevice.deviceName }
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $UpdateDevice.deviceName }


    $Updatew10Pending += [PSCustomObject]@{
            DeviceName  = $updateDevice.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
    }
}
$Updatew10Pending | Export-Csv -Path "Export/W10Updatedown.csv" -NoTypeInformation -Encoding UTF8

$W10All = ($Intunefile | Where-Object { $_.OSVersion -like "10.0.19*" -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}).count

$W11UpdateOld=($Intunefile | Where-Object { $_.OSVersion -eq "$($OSv11_1)" -or ( $_.OSVersion -eq "$($OSv11_2)") -or ($_.OSVersion -eq "$($OSv11_11)") -or ($_.OSVersion -eq "$($OSv11_12)") -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}).count
$W11UpdateNew=($Intunefile | Where-Object { $_.OSVersion -eq "$($OSv11_New)" -or ($_.OSVersion -eq "$($OSv11_New2)") -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}).count
$W11UpdateDown=$Intunefile | Where-Object { $_.OSVersion -lt "$($OSv11_1)" -and ($_.OSVersion -like "10.0.22*") -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}
$Updatew11Pending = @()
foreach ($updateDevice in $W11UpdateDown) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $UpdateDevice.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $UpdateDevice.PrimaryUserUPN }).officeLocation
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $UpdateDevice.deviceName }
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $UpdateDevice.deviceName }


    $Updatew11Pending += [PSCustomObject]@{
            DeviceName  = $updateDevice.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}
$Updatew11Pending | Export-Csv -Path "Export/W11Updatedown.csv" -NoTypeInformation -Encoding UTF8
$W11All= ($Intunefile | Where-Object { $_.OSVersion -like "10.0.22*" -or ($_.OSVersion -like "10.0.26*") -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}).count

$AllDeviceIntune = $Intunefile | Where-Object { $_.ManagedBy -eq "Intune" -or ($_.ManagedBy -eq "Co-managed")}

$DeviceInfo = [PSCustomObject]@{
    TotalW10       = $W10All
    ____W10UpdateOld   = $W10UpdateOld
    ____W10UpdateNew   = $W10UpdateNew
    ____W10updateDown  = $W10updateDown.count
    TotalW11       = $W11All
    ____W11UpdateOld   = $W11UpdateOld
    ____W11UpdateNew   = $W11UpdateNew
    ____W11updateDown  = $W11updateDown.count
}

#### Compliant

$Labvantage = $Intunefile | Where-Object { $_.PrimaryuserUPN -like "Labvantage*" -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}
$IqviaTraining = $Intunefile | Where-Object { $_.PrimaryuserUPN -like "IqviaTraining*" -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}
$Final = $Intunefile | Where-Object { ($_.PrimaryuserUPN -notlike "LabVantage*" -and ($_.PrimaryuserUPN -notlike "IqviaTraining*")) -and (($_.ManagedBy -eq "Intune") -or ($_.ManagedBy -eq "Co-managed"))}
$SCCM = $Intunefile | Where-Object {$_.Compliance -eq "ConfigManager"}

Write-Output `n
    $W1XDevice = [PSCustomObject] @{
        Labvantage    = $Labvantage.count
        ____LabvantageCompliant = ($Labvantage | Where-object {$_.Compliance -eq "Compliant"}).count
        ____LabvantagePGracia   = ($Labvantage | Where-object {$_.Compliance -like "InGracePeriod"}).count
        ____LabvantageNonCompliant  = ($Labvantage | Where-object {$_.Compliance -like "NonCompliant"}).count

        IqviaTraining    = $IqviaTraining.count
        ____IqviaTrainingCompliant = ($IqviaTraining | Where-object {$_.Compliance -eq "Compliant"}).count
        ____IqviaTrainingPGracia   = ($IqviaTraining | Where-object {$_.Compliance -like "InGracePeriod"}).count
        ____IqviaTrainingNonCompliant  = ($IqviaTraining | Where-object {$_.Compliance -like "NonCompliant"}).count

        PCFinales = $Final.count
        ____PCFinalesCompliant = ($Final | Where-object {$_.Compliance -eq "Compliant"}).count
        ____PCFinalesGracia = ($Final | Where-object {$_.Compliance -like "InGracePeriod"}).count
        ____PCFinalesNonCompliant = ($Final | Where-object {$_.Compliance -like "NonCompliant"}).count

        SCCM = $SCCM.count
    }

# Creacion del reporte de 'No compliant'
$NonCompliant = $Intunefile | Where-Object {$_.Compliance -eq "NonCompliant"} | Export-Csv -Path "Export/NonCompliant.csv" -NoTypeInformation -Encoding UTF8
#Comprobar cuantos equipos hay con conectividad
$Conectivity= ($AllDeviceIntune | Where-Object {$_.Lastcheckin -gt "2024-12-15 00:00:00.0000000"}).count

#### IDENTIDADES

$Registered = $Entrafile | Where-object {$_.joinType -eq 'Azure AD registered' -and ($_.operatingSystem -eq 'Windows')} 
$registered | Export-Csv -Path "Export/Registered.csv" -NoTypeInformation -Encoding UTF8

# Filtra los dispositivos sincronizados pero administrados
$SyncNoAdmin = $Entrafile | where-object {$_.joinType -eq 'Hybrid Azure AD joined' -and ($_.mdmdisplayname -eq '') -and ($_.RegistrationTime -ne 'Pending')} 
$SyncNoAdmin | Export-Csv -Path "Export/SyncNoAdmin.csv" -NoTypeInformation -Encoding UTF8

# Filtrar los dispositivos inscritos sin licencia el usuario primario
$Office365Mobile = $Entrafile | where-object {$_.mdmDisplayName -eq 'Office 365 Mobile'}
$Office365Mobile | Export-Csv -Path "Export/Office365mobile.csv" -NoTypeInformation -Encoding UTF8

# Filtra los dispositivos que estan huerfanos, es decir, dispositivos que se han formateado AD connect los detecta en la OU y los vuelve a sincronizar pero nunca se inscriben porque no existe equipo para terminar el proceso.
$Huerfano = $Entrafile | where-object {$_.mdmDisplayName -eq '' -and ($_.RegistrationTime -eq 'Pending')}
$Huerfano | Export-Csv -Path "Export/huerfano.csv" -NoTypeInformation -Encoding UTF8

# Filtra los dispositivos que deben corregir su identidad
$Correccion = $Entrafile | where-object {$_.mdmdisplayname -eq 'Microsoft Intune' -and ($_.RegistrationTime -eq 'Pending')}
$correccion | Export-Csv -Path "Export/CorreccionIdentidad.csv" -NoTypeInformation -Encoding UTF8

############### RESULTADO POR PANTALLA ######################
Function Resultado {
    Write-Output "##### DASHBOARD ####"
    Write-Output "Actualizaciones Windows" 
    $DeviceInfo 
    Write-Output `n
    Write-Output "Cumplimiento Windows" 
    $W1XDevice 
    Write-Output `n
    Write-Output "Con conectividad en Dic: $($Conectivity)"
    Write-Output `n
    Write-Output "##### ESTADO DE IDENTIDADES ####"
    Write-output "Entradas 'Microsoft Entra ID Registered': $($Registered.Count)"
    Write-output "Dispositivos sincronizados pero no administrados: $($SyncNoAdmin.count)"
    Write-Output "Dispositivos inscritos con usuario sin licencia: $($Office365Mobile.count)"
    Write-Output `n
    Write-output "## Dispositivos Pending"
    Write-output "Dispositivos huerfanos: $($huerfano.count)"
    Write-output "Dispositivos con necesidad de correccion de la identidad: $($correccion.count)"
}

# Llamar a la funcion 
cls
Resultado 

# Exportar el resultado a un archivo 
Resultado | Out-File -FilePath "Export\Resumen.txt" -Encoding UTF8
