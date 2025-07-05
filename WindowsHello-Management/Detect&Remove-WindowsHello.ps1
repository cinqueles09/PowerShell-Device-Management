<#
.SYNOPSIS
    Detecta y elimina la configuración de Windows Hello para el usuario actual.

.DESCRIPTION
    Basado en el script de Martin Bengtsson para detectar Windows Hello, extendido para eliminar la configuración si está habilitada.

.NOTES
    Autor: Ismael Morilla Orellana
    Fecha: 05/07/2025
    Version: 1.0
#>

function Get-WindowsHelloStatus {
    $currentUserSID = (whoami /user /fo csv | ConvertFrom-Csv).SID
    $credentialProvider = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{D6886603-9D2F-4EB2-B667-1971041FA96B}"
    
    if (Test-Path -Path $credentialProvider) {
        $userSIDs = Get-ChildItem -Path $credentialProvider
        $registryItems = $userSIDs | ForEach-Object { Get-ItemProperty $_.PsPath }
    } else {
        return "UNKNOWN"
    }

    if (-not [string]::IsNullOrEmpty($currentUserSID)) {
        if ($registryItems.GetType().IsArray) {
            if ($registryItems.Where({ $_.PSChildName -eq $currentUserSID }).LogonCredsAvailable -eq 1) {
                return "ENROLLED"
            } else {
                return "NOTENROLLED"
            }
        } else {
            if (($registryItems.PSChildName -eq $currentUserSID) -and ($registryItems.LogonCredsAvailable -eq 1)) {
                return "ENROLLED"
            } else {
                return "NOTENROLLED"
            }
        }
    } else {
        return "UNKNOWN"
    }
}

function Remove-WindowsHelloConfig {
    Write-Host "Eliminando configuración de Windows Hello..."

    # Deshabilitar Windows Hello para empresas
    $passportKey = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
    if (!(Test-Path $passportKey)) {
        New-Item -Path $passportKey -Force | Out-Null
    }
    Set-ItemProperty -Path $passportKey -Name "Enabled" -Value 0

    # Eliminar datos biométricos
    $biometricPath = "$env:ProgramData\Microsoft\Biometrics"
    Remove-Item -Path $biometricPath -Recurse -Force -ErrorAction SilentlyContinue

    # Detener y deshabilitar servicio biométrico
    Stop-Service -Name "WbioSrvc" -Force -ErrorAction SilentlyContinue
    Set-Service -Name "WbioSrvc" -StartupType Disabled

    # Eliminar claves de PIN del registro
    $pinKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{D6886603-9D2F-4EB2-B667-1971041FA96B}"
    Remove-Item -Path $pinKey -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Configuración eliminada. Reinicia el equipo para aplicar los cambios."
}

# Ejecutar
$status = Get-WindowsHelloStatus
if ($status -eq "ENROLLED") {
    Remove-WindowsHelloConfig
    $result = @{ Status = "REMOVED" }
} elseif ($status -eq "NOTENROLLED") {
    $result = @{ Status = "NOTENROLLED" }
} else {
    $result = @{ Status = "UNKNOWN" }
}

# Devolver resultado en JSON
return $result | ConvertTo-Json -Compress
