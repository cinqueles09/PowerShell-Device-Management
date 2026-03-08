# 📊 AUDIT & Governance Management

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue.svg)](https://microsoft.com/powershell)
[![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-API-573EBF?style=flat&logo=microsoftgraph&logoColor=white)](https://learn.microsoft.com/graph/overview)
[![Maintainer](https://img.shields.io/badge/Maintainer-cinqueles09-orange)](https://github.com/cinqueles09)

Este directorio contiene herramientas de auditoría diseñadas para evaluar el estado de configuración de **Microsoft Intune**. El objetivo es proporcionar visibilidad sobre las configuraciones críticas de seguridad y cumplimiento en el entorno.

## 🚀 Herramientas de Auditoría

### 1. `Get-AuditSetting.ps1`
Este script realiza una revisión exhaustiva de los pilares fundamentales de la configuración en Intune. Es la herramienta ideal para **Consultores de Modern Workplace** y **Equipos de Ciberseguridad** que inician un proceso de auditoría o Hardening del tenant.

**¿Qué analiza este script?**
- **Configuraciones Críticas:** Identifica parámetros de seguridad mal configurados o ausentes.
- **Políticas de Cumplimiento (Compliance):** Evalúa el estado de las reglas que rigen la flota de dispositivos.
- **Perfiles de Configuración:** Revisa las directivas aplicadas a Windows, iOS/Android y macOS.
- **Framework de Mejora:** Proporciona un punto de partida basado en datos reales para establecer un plan de optimización y remediación.

## 🛠️ Requisitos Técnicos

* **Permisos de API:** Requiere una *App Registration* o autenticación con permisos de lectura:
  - `DeviceManagementConfiguration.Read.All`
  - `DeviceManagementManagedDevices.Read.All`
* **Módulos:** Compatible con el SDK de **Microsoft Graph**.
* **Privilegios:** Recomendado ejecutar con rol de **Lector Global** o **Administrador de Intune**.

## 📖 Cómo utilizar el script

Para generar un análisis de la configuración actual, ejecuta:

```powershell
# Ejecutar el script de auditoría para obtener el informe
.\Get-AuditSetting.ps1
```
## ⚠️ Mejores Prácticas

> [!TIP]
> **Base de Referencia:** Se recomienda ejecutar este script de forma periódica (por ejemplo, trimestralmente) para detectar desviaciones en la configuración (**"Configuration Drift"**) respecto a las líneas base (*baselines*) de seguridad definidas por la organización.

> [!IMPORTANT]
> **Privacidad de Datos:** El informe generado puede contener información sensible sobre la infraestructura y políticas internas del tenant. Asegúrese de almacenar los resultados en una ubicación segura con acceso restringido.

---
[⬅️ Volver al Repositorio Principal](https://github.com/cinqueles09/PowerShell-Device-Management)
