# PowerShell Device Management 🚀

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-blue.svg)](https://microsoft.com/powershell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Maintainer](https://img.shields.io/badge/Maintainer-cinqueles09-orange)](https://github.com/cinqueles09)

Conjunto de herramientas y scripts de **PowerShell** diseñados para optimizar la administración, diagnóstico y gestión de dispositivos en entornos empresariales, con especial enfoque en **Microsoft Intune** y **Microsoft Entra ID**.

## 📋 Descripción

Este repositorio centraliza scripts de automatización que permiten a los administradores de IT realizar tareas complejas de gestión de dispositivos de forma rápida y eficiente. Desde la extracción de hashes de hardware para Autopilot hasta la consulta de estados de cumplimiento mediante **Microsoft Graph API**.

## ✨ Características Principales

* **Automatización de Intune:** Scripts para interactuar con dispositivos gestionados y políticas.
* **Diagnóstico Remoto:** Herramientas para recolectar logs y verificar el estado de salud del sistema.
* **Reportes Dinámicos:** Generación de informes sobre el estado de la flota de dispositivos (Compliance, Enrolment, etc.).
* **Gestión de Autopilot:** Facilita la obtención de Hardware IDs y la subida de dispositivos al servicio.

## 🛠️ Requisitos Previos

Antes de utilizar los scripts, asegúrate de cumplir con lo siguiente:

1.  **Versión de PowerShell:** Compatible con PowerShell 5.1 o 7.x (Core).
2.  **Módulos Necesarios:**
    ```powershell
    # Instala el SDK de Microsoft Graph si el script lo requiere
    Install-Module Microsoft.Graph -Scope CurrentUser
    ```
3.  **Permisos:** Debes contar con roles de administrador (Intune Administrator / Cloud Device Administrator) en el tenant de destino.

## 🚀 Instalación y Uso

### 1. Clonar el repositorio
```bash
git clone [https://github.com/cinqueles09/PowerShell-Device-Management.git](https://github.com/cinqueles09/PowerShell-Device-Management.git)
```

### 2. Ejecución de Scripts

Navega a la carpeta del script que necesites y ejecútalo. Recuerda ajustar la política de ejecución si es necesario para la sesión actual:

```powershell
# Permitir la ejecución de scripts locales en la sesión actual
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process

# Ejecutar el script deseado
.\NombreDelScript.ps1
```

## 🤝 Contribuciones

¡Las contribuciones hacen que la comunidad de IT sea mejor! Para colaborar, sigue estos pasos:

1.  **Haz un Fork** del proyecto.
2.  **Crea una rama** para tu mejora:  
    `git checkout -b feature/NuevaMejora`
3.  **Haz un Commit** de tus cambios:  
    `git commit -m 'Añadida nueva funcionalidad'`
4.  **Haz un Push** a la rama:  
    `git push origin feature/NuevaMejora`
5.  **Abre un Pull Request**.

## 📄 Licencia

Este proyecto está bajo la Licencia **MIT**. 
