# 🔐 BitLocker & Encryption Management

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue.svg)](https://microsoft.com/powershell)
[![Azure AD](https://img.shields.io/badge/Azure%20AD-Escrow-0078D4?style=flat&logo=microsoft-azure&logoColor=white)](https://learn.microsoft.com/en-us/windows/security/information-protection/bitlocker/bitlocker-management-for-enterprises)
[![Maintainer](https://img.shields.io/badge/Maintainer-cinqueles09-orange)](https://github.com/cinqueles09)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Este directorio contiene herramientas para la gestión del cifrado de unidad BitLocker, asegurando que las claves de recuperación estén correctamente respaldadas en la nube y que los dispositivos cumplan con los estándares de seguridad organizacional.

## 🚀 Scripts y Herramientas

### 1. `Save-BitlockerRecoveryKey.ps1`
Este script automatiza el proceso de **Escrow** (depósito) de la clave de recuperación de BitLocker en **Azure Active Directory (Entra ID)**.
- **Detección:** Verifica si la unidad del sistema tiene protectores de BitLocker activos.
- **Identificación:** Localiza el `KeyProtectorId` de tipo *Recovery Password*.
- **Respaldo:** Fuerza el envío de la clave a la identidad del dispositivo en Azure AD mediante `BackupToAAD-BitLockerKeyProtector`.

### 2. `Test-BitlockerRequirements.ps1`
*(En desarrollo)* Herramienta de diagnóstico diseñada para verificar los requisitos mínimos de hardware y software (TPM, Secure Boot, particiones) antes de iniciar el cifrado automático.

### 3. `customCompliancePolicy`
Carpeta especializada para la creación de **Directivas de Cumplimiento Personalizadas (Custom Compliance)** en Microsoft Intune.
- **Objetivo:** Validar configuraciones avanzadas, como la exigencia del PIN de BitLocker durante el arranque, que no están disponibles en las directivas estándar.

## 📖 Instrucciones de Uso

### Respaldo de clave en Azure AD
Si un dispositivo está cifrado pero la clave no aparece en el portal de Intune/Azure, ejecuta el siguiente comando con privilegios de administrador:

```powershell
# Ejecutar el script para forzar el respaldo de la clave
.\Save-BitlockerRecoveryKey.ps1
```

## 🛠️ Requisitos Técnicos

* **Permisos:** Se requiere ejecutar PowerShell como **Administrador**.
* **Módulos:** Utiliza el módulo nativo de **BitLocker** incluido en Windows.
* **Conectividad:** El dispositivo debe estar unido a **Azure AD (Entra ID)** o **Hybrid Joined** para que el respaldo de la clave en la nube sea exitoso.

## ⚠️ Advertencias de Seguridad

> [!IMPORTANT]
> **Verificación Manual:** Tras ejecutar `Save-BitlockerRecoveryKey.ps1`, se recomienda verificar manualmente en el portal de Azure AD/Intune que la clave de recuperación ha sido depositada correctamente antes de realizar cambios críticos en el hardware o BIOS.

> [!WARNING]
> **Custom Compliance:** El uso de directivas de cumplimiento personalizadas requiere que los dispositivos tengan instalado y operativo el agente de **Intune Management Extension (IME)**.

---
[⬅️ Volver al Repositorio Principal](https://github.com/cinqueles09/PowerShell-Device-Management)
