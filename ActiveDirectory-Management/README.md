# 📂 Active Directory Management Scripts

Este directorio contiene herramientas de **PowerShell** diseñadas para la administración avanzada, auditoría y automatización de objetos en **Active Directory Domain Services (AD DS)**.

## 🚀 Contenido de la Carpeta

Los scripts incluidos aquí están enfocados en simplificar las tareas diarias de un Administrador de Sistemas en entornos locales e híbridos:

- **Gestión de Usuarios:** Automatización de altas, bajas y modificaciones masivas.
- **Auditoría de Grupos:** Reportes de membresías y detección de grupos vacíos o críticos.
- **Limpieza de AD (Housekeeping):** Identificación de equipos y usuarios inactivos o con contraseñas expiradas.
- **Reportes de Seguridad:** Scripts para verificar el estado de cuentas privilegiadas y políticas de contraseñas.

## 🛠️ Requisitos Especiales

Para ejecutar los scripts de esta carpeta, asegúrate de cumplir con lo siguiente:

1. **RSAT instalado:** Debes tener instaladas las *Remote Server Administration Tools* (herramientas de administración remota del servidor) y el módulo de Active Directory:
   ```powershell
   # Verificar si el módulo está disponible
   Get-Module -ListAvailable ActiveDirectory
   ```
2. **Permisos de Dominio**: La mayoría de estos scripts requieren ejecutarse con una cuenta que tenga permisos de Domain Admin o permisos delegados sobre las Unidades Organizativas (OU) correspondientes.

3. **Controlador de Dominio**: Los scripts deben ejecutarse desde una máquina unida al dominio con conectividad directa al DC.

## 📖 Cómo utilizar estos scripts

1. **Importar el módulo (si es necesario):**
```powershell
Import-Module ActiveDirectory
Ejecutar un script de reporte (Ejemplo):

PowerShell
# Ejemplo de ejecución para generar un reporte de usuarios inactivos
.\Get-InactiveUsers.ps1 -DaysInactive 90 -ExportCSV
```
## ⚠️ Mejores Prácticas

* **Modo de Prueba:** Antes de ejecutar scripts que realicen cambios (`Set-ADUser`, `Remove-ADComputer`), utiliza siempre el parámetro `-WhatIf` para previsualizar los cambios sin aplicarlos.
* **Logs:** Se recomienda revisar las rutas de exportación dentro de cada script para asegurar que los reportes CSV se guarden en una ubicación válida.

---
[⬅️ Volver al repositorio principal](https://github.com/cinqueles09/PowerShell-Device-Management)
