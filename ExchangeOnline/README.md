# 📧 Exchange Online & Microsoft Graph Management

Este directorio contiene scripts avanzados de PowerShell que interactúan con **Microsoft Graph API** para la gestión automatizada de contactos, sincronización de la Global Address List (GAL) y mantenimiento de buzones en entornos Microsoft 365.

## 🚀 Scripts de Gestión de Contactos

Muchos de estos scripts utilizan lógica basada en atributos personalizados (`extensionAttribute`) para segmentar a qué usuarios aplicar las políticas de sincronización.

| Script | Funcionalidad Principal | Segmentación |
| :--- | :--- | :--- |
| **`Sync-M365UserContacts`** | **Sincronización Completa:** Crea, actualiza y elimina contactos de otros miembros del dominio. | `extensionAttribute15 = 1` |
| **`Add-contactsGAL`** | Añade masivamente a los usuarios con licencia como contactos personales de los demás miembros. | Usuarios "Member" con licencia |
| **`Update-GAL-User`** | Mantiene actualizada la libreta de un usuario objetivo, gestionando duplicados y caracteres especiales (UTF-8). | Atributo personalizado |
| **`Clean-AADContactsMasive`** | Limpieza masiva de contactos obsoletos basada en el estado de la licencia y teléfono válido. | `extensionAttribute8 = 1` |
| **`Remove-InvalidContacts`** | Identifica y elimina contactos del dominio `@dominio.com` que ya no existen en Azure AD. | `extensionAttribute8 = 1` |
| **`Delete-ContactsUser`** | Purga total: elimina todos los contactos de un buzón específico, incluyendo carpetas personalizadas. | UPN Específico |
| **`Get-Contacts`** | Herramienta de auditoría para contar la cantidad de contactos de los usuarios seleccionados. | `extensionAttribute8 = 1` |
| **`RemoveContact-PerUser`** | Sincronización individual para un UPN, eliminando contactos que ya no están presentes en el Directorio. | UPN Específico |

## ⚙️ Requisitos de Configuración (App Registration)

Para que estos scripts funcionen mediante el flujo de **Client Credentials**, debes registrar una aplicación en [Microsoft Entra ID](https://entra.microsoft.com/) con los siguientes permisos de API (Application Permissions):

* `User.Read.All`
* `Contacts.ReadWrite`
* `Organization.Read.All` (opcional para algunos reportes)

> [!IMPORTANT]  
> Recuerda configurar correctamente el `ClientID`, `TenantID` y `ClientSecret` dentro de los scripts o como variables de entorno.

## 💡 Detalles de Implementación

* **Soporte UTF-8:** Scripts como `Update-GAL-User` están optimizados para preservar caracteres especiales (acentos, "ñ"), evitando la corrupción de nombres en la agenda.
* **Optimización de API:** Se incluyen filtros de OData para recuperar solo usuarios con licencias activas, reduciendo el consumo de cuota de la API y mejorando la velocidad.
* **Mantenimiento Híbrido:** Uso de `onPremisesExtensionAttributes` para entornos que sincronizan atributos desde AD local.

---
[⬅️ Volver al Panel Principal](https://github.com/cinqueles09/PowerShell-Device-Management)
