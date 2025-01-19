# Remediation-Tools

Esta carpeta contiene herramientas de detección y corrección diseñadas para automatizar la resolución de problemas comunes en dispositivos gestionados. Los scripts están organizados en subcarpetas según su propósito específico y cuentan con funcionalidades de detección y remediación para Intune.

## Subcarpetas y Scripts

### 1. **Account-Control**
   - **Descripción:** Scripts para detectar y remediar configuraciones relacionadas con el control de cuentas de usuario. Aseguran que los parámetros se ajusten a los estándares deseados.

   #### Scripts:
   - **Detect-AccountSettings.ps1**
     - **Descripción:** Detecta las configuraciones actuales de control de cuentas de usuario.

   - **Set-AccountControl.ps1**
     - **Descripción:** Ajusta las configuraciones de control de cuentas a los valores establecidos por la organización.

---

### 2. **BitLocker-Requirements**
   - **Descripción:** Scripts para verificar los requisitos de BitLocker en los equipos y generar un informe detallado sobre los valores incumplidos, ayudando a los administradores a solucionar problemas de cifrado.

   #### Scripts:
   - **Test-BitLockerRequirements-Intune.ps1**
     - **Descripción:** Revisa los requisitos de BitLocker en los dispositivos gestionados por Intune y genera un informe con los resultados.

---

### 3. **Keyboard-Settings**
   - **Descripción:** Scripts para detectar y corregir la configuración del teclado, asegurando que esté configurado en español (ES).

   #### Scripts:
   - **Detect-KeyboardLayout.ps1**
     - **Descripción:** Detecta si la configuración actual del teclado está en español (ES).

   - **Set-KeyboardLayoutES.ps1**
     - **Descripción:** Corrige la configuración del teclado a español (ES) si no está configurado correctamente.
