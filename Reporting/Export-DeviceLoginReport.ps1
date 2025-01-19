# Autor: Ismael Morilla
# Versión: 3.0
# Fecha: 25/05/2024
# Descripción: Este script automatiza la recopilación de información de dispositivos en Intune y utiliza un archivo CSV para obtener el último inicio de sesión de cada dispositivo.

$lastLogonFile = Import-Csv -Path "lastlogon.csv"
$Defenderfile  = Import-Csv -Path "Defender.csv"
$Intunefile  = Import-Csv -Path "Intune.csv"
$Entrafile = Import-Csv -Path "Entra.csv"
$Users = Import-Csv -Path "Users.csv"
$deviceInfoList = @()

foreach ($defenderDevice in $DefenderFile) {
    
    $lastLogon = $lastLogonFile | Where-Object { $_.Name -eq $DefenderDevice.deviceName }

    if (-not $lastLogon) {
        $lastLogon = "No disponible en el archivo"
    }
    
    $IntuneDevice = $Intunefile | Where-Object { $_.DeviceName -eq $DefenderDevice.deviceName }

    if (-not $IntuneDevice) {
        $IntuneDevice = "No identificado en Intune"
    }

    $EntraDevice = $Entrafile | Where-Object { $_.DisplayName -eq $DefenderDevice.deviceName }

    if (-not $EntraDevice) {
        $EntraDevice = "No identificado en Intune"
    }

    $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $IntuneDevice.PrimaryuserUPN }).officeLocation

    # Crear el objeto con los datos combinados para dispositivos
    $deviceInfoList += [PSCustomObject]@{
        DeviceName              = $defenderDevice.DeviceName
        EntraDeviceEnable       = $EntraDevice.accountEnabled
        PrimaryUser             = $IntuneDevice.PrimaryuserUPN
        Domain                  = $defenderDevice.Domain
        IntuneMDM               = $IntuneDevice.Managedby
        EntraMDM                = $EntraDevice.mdmDisplayname
        DefenderMDM             = $defenderDevice.ManagedBy
        SyncIntune              = $IntuneDevice.Lastcheckin
        SyncDefender            = $DefenderDevice.Lastdeviceupdate
        LastLogonAD             = $lastLogon.LastLogonDate
        Platform                = $IntuneDevice.OS
        Version                 = $IntuneDevice.OSVersion
        TrustType               = $EntraDevice.joinType
        Registration            = $EntraDevice.registrationTime
        LocationAD              = $lastLogon.DistinguishedName
        LocationOffice          = $LocationOffice
    }
}

foreach ($ADDevice in $lastLogonFile) {

    if (-not ($Intunefile.DeviceName -contains $ADDevice.Name))
    {
        $EntraDevice = $Entrafile | Where-Object { $_.DisplayName -eq $ADDevice.Name }

        if (-not $EntraDevice) {
            $EntraDevice = "No identificado en Intune"
        }

        $LocationOffice = ($Users | Where-Object { $_.UserPrincipalName -eq $EntraDevice.userNames }).officeLocation
        #Write-Output "El dispositivo $($ADDevice.Name) tiene el ultimo logon $($ADDevice.LastLogonDate), esta inscrito $($EntraDevice.joinType)"
        
        $deviceInfoList += [PSCustomObject]@{
            DeviceName              = $ADDevice.Name
            EntraDeviceEnable       = $EntraDevice.accountEnabled
            PrimaryUser             = $EntraDevice.userNames
            Domain                  = "Garnicaplywood"
            IntuneMDM               = "-"
            EntraMDM                = $EntraDevice.mdmDisplayname
            DefenderMDM             = "-"
            SyncIntune              = "-"
            SyncDefender            = "-"
            LastLogonAD             = $ADDevice.LastLogonDate
            Platform                = "-"
            Version                 = "-"
            TrustType               = $EntraDevice.joinType
            Registration            = $EntraDevice.registrationTime
            LocationAD              = $ADDevice.DistinguishedName
            LocationOffice          = $LocationOffice
        }
    }
}

# Mostrar la información en consola
$deviceInfoList

# Exportar los datos a un archivo CSV
$deviceInfoList | Export-Csv -Path "AllIntuneDevicesWithLastLogon.csv" -NoTypeInformation -Encoding UTF8
Write-Output "Datos combinados de Intune y el archivo de último inicio de sesión exportados a AllIntuneDevicesWithLastLogon.csv"
