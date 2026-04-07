# 📂 Active Directory Management Scripts
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue.svg)](https://microsoft.com/powershell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Maintainer](https://img.shields.io/badge/Maintainer-cinqueles09-orange)](https://github.com/cinqueles09)

Este directorio contiene herramientas de **PowerShell** diseñadas para la administración avanzada, auditoría y automatización de objetos en **Active Directory Domain Services (AD DS)**.

## 🚀 Contenido de la Carpeta

Los scripts incluidos aquí están enfocados en simplificar las tareas diarias de un Administrador de Sistemas en entornos locales e híbridos:

### 📋 Inventario de Scripts y Funcionalidades

| Script                     | Descripción Principal                                                                                                           | Salida / Output                                 |
|----------------------------|-------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------|
| Check-IntuneODJ            | Auditoría Técnica: Verifica prerrequisitos críticos para el conector de Autopilot (OS, .NET 4.7.2+, DNS, Conectividad MS y Estado del Servicio). | Reporte en Consola (Color-Coded)              |
| Export-GPOsByOU            | Analiza todas las OUs del dominio para listar GPOs vinculadas, estado de habilitación y si están forzadas (Enforced).          | CSV (Separador ;)                              |
| Export-XML_GPo             | Genera un informe detallado en formato XML para cada GPO del dominio. Incluye barra de progreso y manejo de caracteres especiales. | Archivos .XML individuales                     |
| Get-ADOrganizationalUnitDN | Extrae el DistinguishedName (DN) de las Unidades Organizativas y sus sub-OUs de forma jerárquica.                              | CSV en C:\                                    |
| Get-ComputerInfoFromADandIntune | Script Híbrido: Cruza datos de AD e Intune para obtener una visión 360° (SO, último login, usuario primario) de equipos gestionados y no gestionados. | Informe Consolidado                             |
| get-ComputersInfo          | Consulta rápida para obtener el inventario básico de todos los equipos registrados en el Directorio Activo.                    | Consola / Lista de objetos                     |
| Set-MemberGroupO365        | Proceso masivo que lee un .txt de equipos y los añade a un grupo de seguridad de AD, validando la existencia previa de cada objeto. | Log en pantalla (Éxito/Error)                 |

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
