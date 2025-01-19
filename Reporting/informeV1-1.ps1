# Autor: Ismael Morilla Orellana
# Versión: 2.1 
# Fecha: 01/01/2025
# Descripción: Este script analiza los informes exportados de Intune, Defender y Entra ID, proporcionando una visión general del estado de los dispositivos 
#               y generando un informe detallado de los equipos que requieren atención.

$lastLogonFile = Import-Csv -Path "lastlogon.csv"
$Defenderfile  = Import-Csv -Path "Defender.csv"
$Intunefile  = Import-Csv -Path "Intune.csv"
$Entrafile = Import-Csv -Path "Entra.csv"
$Users = Import-Csv -Path "Users.csv"
$Cumplimiento = Import-csv -Path "Cumplimiento.csv"

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

$W10UpdateOld=($Intunefile | Where-Object { $_.OSVersion -eq "$($OSv10_1)" -or ($_.$osVersion -eq "$($OSv10_2)") -and ($_.ManagedBy -eq "Intune")}).count
$W10UpdateNew= ($Intunefile | Where-Object { $_.OSVersion -eq "$($OSv10_New)" -and ($_.ManagedBy -eq "Intune")}).count
$W10UpdateDown= $Intunefile | Where-Object { $_.OSVersion -lt "$($OSv10_1)" -and ($_.OSVersion -like "10.0.19*") -and ($_.ManagedBy -eq "Intune")}
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

$W11UpdateOld=($Intunefile | Where-Object { $_.OSVersion -eq "$($OSv11_1)" -or ( $_.OSVersion -eq "$($OSv11_2)") -or ($_.OSVersion -eq "$($OSv11_11)") -or ($_.OSVersion -eq "$($OSv11_12)") -and ($_.ManagedBy -eq "Intune")}).count
$W11UpdateNew=($Intunefile | Where-Object { $_.OSVersion -eq "$($OSv11_New)" -or ($_.OSVersion -eq "$($OSv11_New2)") -and ($_.ManagedBy -eq "Intune")}).count
$W11UpdateDown=$Intunefile | Where-Object { $_.OSVersion -lt "$($OSv11_1)" -and ($_.OSVersion -like "10.0.22*") -and ($_.ManagedBy -eq "Intune")}
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
$W11All= ($Intunefile | Where-Object { $_.OSVersion -like "10.0.22*" -or ($_.OSVersion -like "10.0.26*") -and ($_.ManagedBy -eq "Intune")}).count

$AllDeviceIntune = $Intunefile | Where-Object { $_.ManagedBy -eq "Intune"}

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

$SGAF = $Intunefile | Where-Object { $_.DeviceName -like "SGAF*" -and ($_.ManagedBy -eq "Intune")}
$Final = $Intunefile | Where-Object { $_.DeviceName -notlike "SGAF*" -and ($_.ManagedBy -eq "Intune")}

Write-Output `n
    $W1XDevice = [PSCustomObject] @{
        SGAF    = $SGAF.count
        ____SGAFCompliant = ($SGAF | Where-object {$_.Compliance -eq "Compliant"}).count
        ____SGAFPGracia   = ($SGAF | Where-object {$_.Compliance -like "InGracePeriod"}).count
        ____SGAFNonCompliant  = ($SGAF | Where-object {$_.Compliance -like "NonCompliant"}).count


        PCFinales = $Final.count
        ____PCFinalesCompliant = ($Final | Where-object {$_.Compliance -eq "Compliant"}).count
        ____PCFinalesGracia = ($Final | Where-object {$_.Compliance -like "InGracePeriod"}).count
        ____PCFinalesNonCompliant = ($Final | Where-object {$_.Compliance -like "NonCompliant"}).count

        SCCM = $SCCM.count
    }

# Creacion del reporte de 'No compliant'
$NonCompliant = $Intunefile | Where-Object {$_.Compliance -eq "NonCompliant"} 
$AllNonCompliant = @()
foreach ($PCNonCompliant in $NonCompliant) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCNonCompliant.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $PCNonCompliant.PrimaryUserUPN }).officeLocation
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCNonCompliant.deviceName }
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCNonCompliant.deviceName }


    $AllNonCompliant += [PSCustomObject]@{
            DeviceName  = $PCNonCompliant.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllNonCompliant | Export-Csv -Path "Export/NonCompliant.csv" -NoTypeInformation -Encoding UTF8

#Comprobar cuantos equipos hay con conectividad
$Conectivity= ($AllDeviceIntune | Where-Object {$_.Lastcheckin -gt "2024-11-01 00:00:00.0000000"}).count

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


#### MOTIVOS DE NO CUMPLIMIENTO

$Export= Test-Path "Export/NoCumplimiento"

if ($Export -ne "True")
{
    mkdir "Export/NoCumplimiento"
}

# Filtro de fallo antivirus
$NonAntivirus = $Cumplimiento | Where-Object {$_.SettingNm_loc -eq 'Antivirus' -or ($_.SettingNm_loc -like 'Antimalware*') -or ($_.SettingNm_loc -eq 'Antispyware') -or ($_.SettingNm_loc -like '*inteligencia de seguridad*')  -and ($_.OS -eq 'Windows')} 
$AllAntivirus = @()
foreach ($PCAntivirus in $NonAntivirus) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCAntivirus.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCAntivirus.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCAntivirus.deviceName }


    $AllAntivirus += [PSCustomObject]@{
            DeviceName  = $PCAntivirus.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCAntivirus.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllAntivirus | Export-Csv -Path "Export/NoCumplimiento/NonAntivirus.csv" -NoTypeInformation -Encoding UTF8


# Filtro de arranque seguro
$NonArranque = $Cumplimiento | Where-Object {$_.SettingNm_loc -eq 'Arranque seguro' -and ($_.OS -eq 'Windows')} 
$AllArranque = @()
foreach ($PCArranque in $NonArranque) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCArranque.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCArranque.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCArranque.deviceName }


    $AllArranque += [PSCustomObject]@{
            DeviceName  = $PCArranque.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCArranque.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllArranque | Export-Csv -Path "Export/NoCumplimiento/NonArranque.csv" -NoTypeInformation -Encoding UTF8

# Filtro de TPM
$NonTPM = $Cumplimiento | Where-Object {$_.SettingNm_loc -like '*(TPM)' -or ($_.SettingNm_loc -like 'Integridad*') -and ($_.OS -eq 'Windows')} 
$AllTPM = @()
foreach ($PCTPM in $NonTPM) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCTPM.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCTPM.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCTPM.deviceName }


    $AllTPM += [PSCustomObject]@{
            DeviceName  = $PCTPM.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCTPM.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllTPM | Export-Csv -Path "Export/NoCumplimiento/NonTPM.csv" -NoTypeInformation -Encoding UTF8

# Filtro de Firewall
$NonFirewall = $Cumplimiento | Where-Object {$_.SettingNm_loc -eq 'Firewall' -and ($_.OS -eq 'Windows')} 
$AllFirewall = @()
foreach ($PCFirewall in $NonFirewall) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCFirewall.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCFirewall.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCFirewall.deviceName }


    $AllFirewall += [PSCustomObject]@{
            DeviceName  = $PCFirewall.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCFirewall.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllFirewall | Export-Csv -Path "Export/NoCumplimiento/NonFirewall.csv" -NoTypeInformation -Encoding UTF8

# Filtro de BitLocker
$NonBitlocker = $Cumplimiento | Where-Object {$_.SettingNm_loc -eq 'Bitlocker' -and ($_.OS -eq 'Windows')} 
$AllBitlocker = @()
foreach ($PCBitlocker in $NonBitlocker) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCBitlocker.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCBitlocker.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCBitlocker.deviceName }


    $AllBitlocker += [PSCustomObject]@{
            DeviceName  = $PCBitlocker.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCBitlocker.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllBitlocker | Export-Csv -Path "Export/NoCumplimiento/NonBitlocker.csv" -NoTypeInformation -Encoding UTF8

# Filtro de Proteccion en tiempo real
$NonPreal = $Cumplimiento | Where-Object {$_.SettingNm_loc -like '*en tiempo real' -and ($_.OS -eq 'Windows')} 
$AllPreal = @()
foreach ($PCPreal in $NonPreal) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCPreal.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCPreal.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCPreal.deviceName }


    $AllPreal += [PSCustomObject]@{
            DeviceName  = $PCPreal.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCPreal.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllPreal | Export-Csv -Path "Export/NoCumplimiento/NonPReal.csv" -NoTypeInformation -Encoding UTF8

# Filtro de Riesgo
$NonRiesgo = $Cumplimiento | Where-Object {$_.SettingNm_loc -like 'Solicitar que el dispositivo tenga*' -and ($_.OS -eq 'Windows')} 
$AllRiesgo = @()
foreach ($PCRiesgo in $NonRiesgo) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCRiesgo.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCRiesgo.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCRiesgo.deviceName }


    $AllRiesgo += [PSCustomObject]@{
            DeviceName  = $PCRiesgo.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCRiesgo.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllRiesgo | Export-Csv -Path "Export/NoCumplimiento/NonRiesgo.csv" -NoTypeInformation -Encoding UTF8

# Filtro de Contraseña
$NonPasswd = $Cumplimiento | Where-Object {$_.SettingNm_loc -like '*Contrase*' -and ($_.OS -eq 'Windows')} 
$AllPasswd = @()
foreach ($PCPasswd in $NonPasswd) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCPasswd.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCPasswd.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCPasswd.deviceName }


    $AllPasswd += [PSCustomObject]@{
            DeviceName  = $PCPasswd.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCPasswd.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllPasswd | Export-Csv -Path "Export/NoCumplimiento/NonPasswd.csv" -NoTypeInformation -Encoding UTF8

# Filtro de Contraseña
$NonSO = $Cumplimiento | Where-Object {$_.SettingNm_loc -like 'Versi*' -and ($_.OS -eq 'Windows')} 
$AllSO = @()
foreach ($PCSO in $NonSO) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCSO.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCSO.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCSO.deviceName }


    $AllSO += [PSCustomObject]@{
            DeviceName  = $PCSO.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCSO.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllSO | Export-Csv -Path "Export/NoCumplimiento/NonSO.csv" -NoTypeInformation -Encoding UTF8


## Filtro de la directiva por defecto

# Filtro Activo
$NonActivo = $Cumplimiento | Where-Object {$_.SettingNm_loc -eq 'Activo' -and ($_.OS -eq 'Windows')} 
$AllActivo = @()
foreach ($PCActivo in $NonActivo) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCActivo.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCActivo.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCActivo.deviceName }


    $AllActivo += [PSCustomObject]@{
            DeviceName  = $PCActivo.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCActivo.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllActivo | Export-Csv -Path "Export/NoCumplimiento/NonActivo.csv" -NoTypeInformation -Encoding UTF8

# Filtro de Usuario inscrito
$NonUser = $Cumplimiento | Where-Object {$_.SettingNm_loc -eq 'Existe un usuario inscrito' -and ($_.OS -eq 'Windows')} 
$AllUser = @()
foreach ($PCUser in $NonUser) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCUser.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCUser.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCUser.deviceName }


    $AllUser += [PSCustomObject]@{
            DeviceName  = $PCUser.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCSUser.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllUser | Export-Csv -Path "Export/NoCumplimiento/NonUser.csv" -NoTypeInformation -Encoding UTF8

# Filtro de Directiva asignada
$NonDirectiva = $Cumplimiento | Where-Object {$_.SettingNm_loc -like '*directiva*' -and ($_.OS -eq 'Windows')} 
$AllDirectiva = @()
foreach ($PCDirectiva in $NonDirectiva) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCDirectiva.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCDirectiva.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCDirectiva.deviceName }


    $AllDirectiva += [PSCustomObject]@{
            DeviceName  = $PCDirectiva.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            MotiveCompliance  = $PCDirectiva.SettingNm_loc
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllDirectiva | Export-Csv -Path "Export/NoCumplimiento/NonDirectiva.csv" -NoTypeInformation -Encoding UTF8


###### DISPOSITIVOS DEFENDER

$Export= Test-Path "Export/Defender"

if ($Export -ne "True")
{
    mkdir "Export/Defender"
}

# Filtro de sugerencia de incorporacion
$SugerenciaDevice = $Defenderfile | Where-Object {$_.OnboardingStatus -eq 'Can be onboarded'} 
$AllSugerencia = @()
foreach ($PCSugerencia in $SugerenciaDevice) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCSugerencia.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCSugerencia.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCSugerencia.deviceName }


    $AllSugerencia += [PSCustomObject]@{
            DeviceName  = $PCSugerencia.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllSugerencia | Export-Csv -Path "Export/Defender/Sugerencia.csv" -NoTypeInformation -Encoding UTF8

# Filtro de no soportado
$NonSupportDevice = $Defenderfile | Where-Object {$_.OnboardingStatus -eq 'Unsupported'} 
$AllNoSupport = @()
foreach ($PCNoSupport in $NonSupportDevice) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCNoSupport.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCNoSupport.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCNoSupport.deviceName }


    $AllNoSupport += [PSCustomObject]@{
            DeviceName  = $PCNoSupport.DeviceName
            Version           = $DefenderDevice.OSDistribution
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
        }
}

$AllNoSupport | Export-Csv -Path "Export/Defender/NoSupport.csv" -NoTypeInformation -Encoding UTF8

# Filtro de inactivos
$InactiveDevice = $Defenderfile | Where-Object {$_.OnboardingStatus -eq 'Onboarded' -and ($_.HealthStatus -eq 'Inactive') -and ($_.ManagedBy -eq 'Intune')} 
$AllInactive = @()
foreach ($PCInactive in $InactiveDevice) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCInactive.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCInactive.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCInactive.deviceName }


    $AllInactive += [PSCustomObject]@{
            DeviceName  = $PCInactive.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllInactive | Export-Csv -Path "Export/Defender/Inactive.csv" -NoTypeInformation -Encoding UTF8


# Verificar que dispositivos aparecen como marcados de administracion Intune y en realidad no lo estan
$DefenderIntune = $Defenderfile | Where-Object {$_.OnboardingStatus -eq 'Onboarded' -and $_.ManagedBy -eq 'Intune'} 
$DefenderNoIntune = @()
foreach ($DefenderDevice in $DefenderIntune) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $DefenderDevice.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $DefenderDevice.deviceName }
    $EntraDevice = $Entrafile | Where-Object { $_.DisplayName -eq $DefenderDevice.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation

    if ($Intunefile.DeviceName -notcontains $DefenderDevice.devicename)
    {
        $DefenderNoIntune += [PSCustomObject]@{
            DeviceName  = $DefenderDevice.DeviceName
            DistinguishedName = $lastLogon.DistinguishedName
            LocationOffice    = $LocationOffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
            Registro          = $EntraDevice.registrationTime
        }  
    } 
}

$DefenderNoIntune | Export-Csv -Path "Export/Defender/NoIntune.csv" -NoTypeInformation -Encoding UTF8

#Dispositivos no administrados por Intune
$Defender = $Defenderfile | Where-Object {$_.OnboardingStatus -eq 'Onboarded' -and $_.ManagedBy -ne 'Intune'} 
$AllDefender = @()
foreach ($PCDefender in $Defender) {

    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $PCDefender.deviceName }
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $PCDefender.deviceName }
    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryUserUPN }).officeLocation
    $DefenderDevice = $Defenderfile | Where-Object { $_.DeviceName -eq $PCDefender.deviceName }


    $AllDefender += [PSCustomObject]@{
            DeviceName  = $PCDefender.DeviceName
            Version           = $IntuneDevice.OSVersion
            DistinguishedName = $lastlogon.DistinguishedName
            LocationOffice    = $Locationoffice
            UserPrincipalName = $IntuneDevice.PrimaryUserUPN
            LastlogonIntune   = $IntuneDevice.Lastcheckin
            LastlogonDefender = $DefenderDevice.Lastdeviceupdate
            LastLogonAD       = $lastLogon.LastLogonDate
        }
}

$AllDefender | Export-Csv -Path "Export/Defender/OnlyDefender.csv" -NoTypeInformation -Encoding UTF8

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
    Write-output "## DISPOSITIVOS PENDING"
    Write-output "Dispositivos huerfanos: $($huerfano.count)"
    Write-output "Dispositivos con necesidad de correccion de la identidad: $($correccion.count)"
    Write-output `n
    Write-output "## MOTIVO NO CUMPLIMIENTO ##"
    Write-output "Antivirus: $($AllAntivirus.count)"
    Write-output "Arranque seguro: $($AllArranque.count)"
    Write-output "TPM: $($AllTPM.count)"
    Write-output "Firewall: $($AllFirewall.count)"
    Write-output "BitLocker: $($AllBitlocker.count)"
    Write-output "Proteccion en tiempo real: $($AllPreal.count)"
    Write-output "Riesgo: $($AllRiesgo.count)"
    Write-output "Password: $($AllPasswd.count)"
    Write-output "Version minima de SO: $($AllSO.count)"
    Write-output `n
    Write-output "Activo: $($AllActivo.count)"
    Write-output "Directiva asignada: $($AllDirectiva.count)"
    Write-output "Usuario inscrito: $($AllUser.count)"
    write-output `n 
    Write-output "#### ESTADO DISPOSITIVOS DEFENDER ####"
    write-output "Dispositivos incorporados no activos: $($AllInactive.count)"
    Write-output "Dispositivos marcados por Intune pero no administrados por Intune: $($DefenderNoIntune.count)"
    Write-output "Dispositivos no administrados por Intune: $($AllDefender.count) "
    Write-output `n 
    Write-output "Dispositivos sugeridos para incorporacion: $($Sugerencia.count)"
    Write-output "Dispositivos no soportados por defender: $($AllNoSupport.count)"

}

# Llamar a la funcion 
cls
Resultado 

# Exportar el resultado a un archivo 
Resultado | Out-File -FilePath "Export\Resumen.txt" -Encoding UTF8