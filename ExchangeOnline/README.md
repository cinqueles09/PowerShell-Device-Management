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

---

### `Delete-ContactsUser.ps1`
🗑 **Elimina todos los contactos de la carpeta principal de un usuario.**

- Útil para limpiar la libreta de direcciones antes de una sincronización completa.
- Requiere el UPN del usuario objetivo.

---

### `Add-ContactsGAL.ps1`
➕ **Añade de forma masiva los contactos corporativos a todos los usuarios licenciados.**

- Aplica la lógica de sincronización a todos los usuarios con licencia y atributo personalizado `extensionAttribute15 = 1`.
- Evita duplicados, actualiza contactos existentes y crea nuevos si es necesario.

---

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

