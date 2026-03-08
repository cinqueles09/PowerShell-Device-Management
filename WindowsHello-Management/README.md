# 🔐 Windows Hello for Business Management

Este directorio contiene herramientas especializadas para la auditoría, detección y eliminación controlada de configuraciones de **Windows Hello for Business (WHfB)** en estaciones de trabajo Windows 10/11.

## 🚀 Scripts Disponibles

| Script | Funcionalidad Principal | Origen / Referencia |
| :--- | :--- | :--- |
| **`Detect&Remove-WindowsHello`** | Detecta si Windows Hello está activo y, de ser así, procede a eliminar la configuración de usuario. | Extensión basada en el script de *Martin Bengtsson*. |
| **`Remove-WindowsHello`** | Desactivación profunda: elimina datos biométricos, detiene servicios clave (Biometric Service) y limpia el registro de Windows. | Desarrollo propio para limpieza total. |

## 🛠️ Detalles Técnicos

### 1. Detect&Remove-WindowsHello.ps1
Ideal para flujos de automatización donde primero se necesita validar el estado del dispositivo. 
- **Lógica:** Escanea los contenedores de claves (*Ngc*) del usuario.
- **Acción:** Si se detecta una inscripción activa, el script la revoca para forzar un nuevo registro o cumplir con una directiva de desactivación.

### 2. Remove-WindowsHello.ps1
Diseñado para escenarios de "limpieza drástica" o cuando el PIN/Biometría presenta errores persistentes.
- **Servicios:** Detiene y reconfigura el servicio de biometría de Windows.
- **Registro:** Limpia las claves en `HKEY_LOCAL_MACHINE` y `HKEY_CURRENT_USER` relacionadas con el pasaporte de Windows.
- **Datos:** Borra la carpeta de datos de NGC (Next Generation Credentials).

## 📖 Instrucciones de Uso

> [!IMPORTANT]
> Estos scripts requieren privilegios de **Administrador Local** para modificar servicios y claves de registro del sistema.

### Ejecución recomendada:
```powershell
# Para una limpieza completa y borrado de biométricos:
.\Remove-WindowsHello.ps1
```
## ⚠️ Advertencias de Seguridad

> [!CAUTION]
> **Impacto al usuario:** Al ejecutar estos scripts, el usuario perderá su PIN, huella dactilar y reconocimiento facial actuales. Deberá realizar un nuevo enrolamiento en el próximo inicio de sesión si la directiva de Intune o GPO permanece activa.

> [!WARNING]
> **Entornos híbridos:** En dispositivos con **Azure AD Join** o **Hybrid Join**, asegúrese de que el usuario disponga de conexión a red estable para re-autenticarse correctamente tras la limpieza de las credenciales de Windows Hello.

---
[⬅️ Volver al Repositorio Principal](https://github.com/cinqueles09/PowerShell-Device-Management)
