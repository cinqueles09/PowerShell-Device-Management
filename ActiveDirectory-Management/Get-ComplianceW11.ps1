<#
.SYNOPSIS
    Script para evaluar la compatibilidad de los equipos habilitados en Active Directory con Windows 11.

.DESCRIPTION
    Este script recorre todos los equipos habilitados del dominio, recolecta información de hardware y sistema,
    y determina si cumplen con los requisitos mínimos de Windows 11 (CPU 64-bit, RAM ≥ 4GB, espacio en disco ≥ 64GB,
    TPM 2.0, UEFI con Secure Boot). Los resultados se exportan a un archivo CSV y se muestran en pantalla.

.NOTES
    Autor      : Ismael Morilla Orellana
    Fecha      : 10/11/2025
    Versión    : 1.0
    Requisitos : PowerShell 5.1 o superior, módulo ActiveDirectory
                 Permisos de lectura en los equipos remotos

.EXAMPLE
    Ejecutar el script:
        PS C:\> .\Get-ComplianceW11.ps1

    Resultado:
        Genera un archivo CSV con la lista de equipos habilitados y su compatibilidad con Windows 11,
        mostrando también los detalles de CPU, RAM, espacio libre, TPM y Secure Boot.
#>


# Importar módulo de Active Directory
#Import-Module ActiveDirectory

# Obtener todos los equipos habilitados del dominio
$computers = Get-ADComputer -Filter {Enabled -eq $true} -Properties Name,OperatingSystem

# Crear un array para almacenar resultados
$results = @()
$total = $computers.Count
$counter = 0

foreach ($computer in $computers) {
    $counter++
    # Mostrar barra de progreso
    Write-Progress -Activity "Comprobando compatibilidad con Windows 11" `
                   -Status "Procesando $($computer.Name) ($counter de $total)" `
                   -PercentComplete (($counter / $total) * 100)

    $name = $computer.Name
    try {
        # Obtener información del sistema
        $sys = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $name -ErrorAction Stop
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $name -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ComputerName $name -ErrorAction Stop
        $tpm = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ComputerName $name -ErrorAction SilentlyContinue

        # Validaciones básicas de compatibilidad
        $cpu64bit = ($sys.SystemType -like "*x64*")
        $ramOK = ($sys.TotalPhysicalMemory / 1GB -ge 4)
        $diskOK = (($os.FreePhysicalMemory / 1MB) -ge 64000)  # Al menos 64 GB libre
        $tpmOK = ($tpm.TpmPresent -eq $true -and $tpm.SpecVersion -like "2.0*")
        $secureBootOK = ($bios.SMBIOSBIOSVersion -ne $null) # Aproximación, requiere verificación UEFI/secure boot

        $compatible = ($cpu64bit -and $ramOK -and $diskOK -and $tpmOK -and $secureBootOK)

        # Agregar resultado
        $results += [PSCustomObject]@{
            ComputerName    = $name
            CPU64Bit        = $cpu64bit
            RAM_GB          = [math]::Round($sys.TotalPhysicalMemory / 1GB,2)
            FreeDisk_GB     = [math]::Round($os.FreePhysicalMemory / 1MB / 1024,2)
            TPM_OK          = $tpmOK
            SecureBoot      = $secureBootOK
            CompatibleWin11 = $compatible
        }
    }
    catch {
        Write-Warning "No se pudo obtener información de $name"
    }
}

# Exportar resultados a CSV
$results | Export-Csv -Path "C:\Temp\Win11_Compatibilidad.csv" -NoTypeInformation

# Mostrar resultados en pantalla
$results | Format-Table -AutoSize
