# EntraID-and-Intune-Integration

Esta carpeta contiene scripts de PowerShell orientados a integrar y gestionar funcionalidades avanzadas entre Entra ID (Azure AD) e Intune. Los scripts permiten la automatización de tareas como la gestión de dispositivos, usuarios, grupos dinámicos, configuraciones de MFA y más.

## Scripts

1. **Export-MFAReport.ps1**
   - **Descripción:** Exporta un informe detallado del estado de MFA (Multi-Factor Authentication) para los usuarios, incluyendo sus configuraciones actuales.

2. **Remove-HashIds.ps1**
   - **Descripción:** Proporciona dos opciones: eliminar todos los hash ID existentes en Intune o eliminar únicamente los especificados en un archivo CSV.

3. **Upload-IntuneLogsToSharePoint.ps1**
   - **Descripción:** Recopila los registros de Intune y los sube a una ubicación específica en un sitio de SharePoint.

4. **Create-DynamicGroups.ps1**
   - **Descripción:** Crea grupos dinámicos en Entra ID basados en nombres especificados en una base de datos CSV.
     
5. **Set-LabDeviceTags.ps1**
   - **Descripción:** Etiqueta dispositivos en atributos de extensión (ExtensionAttributes) según programas detectados en los dispositivos.

6. **Set-LastLogonUserUPN.ps1**
   - **Descripción:** Cambia el nombre de usuario principal (UPN) al del primer usuario que haya iniciado sesión por última vez en el dispositivo.

7. **Add-SafeSenders.ps1**
   - **Descripción:** Añade remitentes seguros a la lista de todos los usuarios de la organización.

8. **Update-DeviceAttributes.ps1**
   - **Descripción:** Actualiza los atributos de extensión (ExtensionAttributes) de los dispositivos con valores obtenidos de los usuarios relacionados.

9. **Cleanup-RegisteredDevices.ps1**
   - **Descripción:** Este script se conecta a Microsoft Entra ID y obtiene una lista de dispositivos. Analiza cada dispositivo registrado para identificar aquellos que tienen más de 5 días de inactividad y que son de tipo "Microsoft Entra Joined" o "Microsoft Entra Hybrid". Si se encuentran dispositivos que cumplen con estos criterios, se preparan para su eliminación y se registra la información relevante en un informe.    
