# 📁 Libreta de Direcciones Corporativa (GAL Sync)

Este repositorio contiene tres scripts de PowerShell diseñados para gestionar la libreta de direcciones corporativa (GAL) en entornos Microsoft 365 mediante Microsoft Graph API.

## 🎯 Objetivo

Automatizar la sincronización, actualización y limpieza de contactos corporativos en la libreta de direcciones de los usuarios licenciados del tenant.

---

## 📜 Scripts incluidos

### `UpdateGAL-User.ps1`
🔄 **Actualiza la libreta de direcciones de un único usuario.**

- Ideal para pruebas unitarias o validaciones antes de aplicar cambios masivos.
- Crea o actualiza contactos corporativos en la carpeta principal del usuario especificado.
- Elimina contactos duplicados y aquellos que ya no están en la lista de usuarios válidos.
- Mantiene la codificación UTF-8 para preservar caracteres especiales.

---

### `Delete-ContactsUser.ps1`
🗑 **Elimina todos los contactos de la carpeta principal de un usuario.**

- Útil para limpiar la libreta de direcciones antes de una sincronización completa.
- Requiere el UPN del usuario objetivo.
- Elimina contactos de todas las carpetas, incluyendo personalizadas.

---

### `Add-ContactsGAL.ps1`
➕ **Añade contactos corporativos a todos los usuarios licenciados.**

- Obtiene todos los usuarios de tipo "Member" con licencias asignadas.
- Añade como contactos a los demás usuarios con licencia, si aún no existen en su libreta.
- Evita duplicados y mantiene la libreta actualizada.

---

### `Clean-AddContactsMasive.ps1`
🧹 **Sincroniza contactos para usuarios con `extensionAttribute8 = "1"`.**

- Filtra usuarios destino mediante el atributo personalizado.
- Elimina contactos obsoletos que ya no están en Azure AD.
- Mantiene actualizada la libreta de direcciones de cada usuario destino.

---

### `RemoveContact-PerUser.ps1`
🧼 **Limpia y sincroniza contactos para un usuario específico.**

- Filtra usuarios con licencia y teléfono válido.
- Elimina contactos del usuario objetivo que ya no están en Azure AD.
- Útil para mantener la libreta de direcciones individual actualizada.

---

### `Sync-m365UserContacts.ps1`
🔁 **Sincroniza contactos de forma completa para múltiples usuarios.**

- Identifica usuarios destino con `extensionAttribute8 = "1"`.
- Construye la lista de contactos a partir de usuarios con licencia y teléfono.
- Para cada usuario destino:
  - Crea nuevos contactos si no existen.
  - Actualiza contactos ya existentes.
  - Elimina contactos duplicados.

---

### `Get-Contacts.ps1`
📊 **Consulta la cantidad de contactos por usuario.**

- Filtra usuarios con `extensionAttribute8 = "1"`.
- Muestra en consola el número de contactos por usuario.
- Permite exportar los resultados a CSV para análisis posterior.
## 🛠 Requisitos

- PowerShell 5.1 o superior.
- Aplicación registrada en Azure AD con permisos:
  - `Contacts.ReadWrite`
  - `User.Read.All`
- Variables de entorno configuradas:
  - `clientId`
  - `clientSecret`
  - `tenantId`

---

## 📌 Notas

- Todos los scripts utilizan Microsoft Graph API vía `Invoke-RestMethod` o `Invoke-WebRequest`.
- Se recomienda ejecutar primero `Delete-ContactsUser.ps1` antes de aplicar `Add-ContactsGAL.ps1` para evitar duplicados.

---

