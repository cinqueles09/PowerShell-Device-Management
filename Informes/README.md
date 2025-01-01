# Scripts de PowerShell para la Creación de Informes

Bienvenidos a esta carpeta donde encontrarás una colección de scripts diseñados para facilitar la creación de tus propios informes utilizando PowerShell.

### Características

- **Cruce de CSV**: Si necesitas cruzar varios archivos CSV y no obtienes el resultado esperado, aquí encontrarás la solución.
- **Actualizaciones continuas**: Se irán subiendo varias versiones de los scripts para adaptarse a tus necesidades, ya sea en entornos solo nube, híbridos, co-administrados, etc.

### Cómo Empezar

1. **Revisa los scripts disponibles**: Cada script está documentado con instrucciones detalladas para su uso.
2. **Personalización**: Los scripts pueden ser modificados según tus necesidades específicas.
3. **Contribuciones**: ¡Tus contribuciones son bienvenidas! Si mejoras o adaptas un script, no dudes en compartirlo.

### Contacto

Si tienes alguna pregunta o sugerencia, por favor, abre un issue en el repositorio o contacta al administrador del mismo.


# Descripción de los scripts 

## Export-Informe

Este script de PowerShell está diseñado para automatizar la recopilación de información detallada sobre los dispositivos gestionados en Intune. Utiliza varios archivos CSV para combinar datos y generar un informe completo. Entre los datos que recopila y cruza se incluyen:

- Información de dispositivos de Microsoft Defender
- Información de dispositivos de Intune
- Información de dispositivos de Entra
- Datos de último inicio de sesión desde el AD

### Cómo Funciona

1. **Importación de Datos**: El script importa varios archivos CSV que contienen información relevante sobre los dispositivos y usuarios.
2. **Cruce de Datos**: Utiliza bucles para recorrer los dispositivos y comparar información entre los diferentes archivos CSV.
3. **Generación de Informes**: Compila la información combinada en un objeto PowerShell personalizado y la muestra en consola. Finalmente, exporta los datos a un archivo CSV llamado `AllIntuneDevicesWithLastLogon.csv`.

Este informe es útil para administradores que necesitan un resumen completo y consolidado del estado de los dispositivos y sus actividades de inicio de sesión.

## DeviceStatusReporter

### Descripción
Este script analiza los informes exportados de Intune, Defender y Entra ID, proporcionando una visión general del estado de los dispositivos y generando un informe detallado de los equipos que requieren atención.

### Funcionalidades Principales

1. **Importación de Datos:**
   - Importa datos desde archivos CSV de Intune, Defender, Entra ID y usuarios.

2. **Definición de Versiones de SO:**
   - Define varias versiones de Windows 10 y Windows 11 para su comparación.

3. **Creación de Directorio de Exportación:**
   - Verifica si existe un directorio de exportación y lo crea si no existe.

4. **Análisis de Actualizaciones de Windows 10:**
   - Cuenta dispositivos con versiones antiguas, nuevas y pendientes de actualización.
   - Genera un informe CSV de dispositivos pendientes de actualización.

5. **Análisis de Actualizaciones de Windows 11:**
   - Similar al análisis de Windows 10, pero para Windows 11.
   - Genera un informe CSV de dispositivos pendientes de actualización.

6. **Generación de Información de Dispositivos:**
   - Crea un objeto con información resumida sobre el estado de las actualizaciones de Windows 10 y 11.

7. **Cumplimiento de Dispositivos:**
   - Analiza el cumplimiento de dispositivos para diferentes grupos de usuarios.
   - Genera informes CSV de dispositivos no conformes.

8. **Análisis de Identidades:**
   - Filtra y exporta dispositivos registrados, sincronizados pero no administrados, inscritos sin licencia y dispositivos huérfanos.
   - Genera informes CSV para cada categoría.

9. **Generación de Resultados:**
   - Muestra un resumen en pantalla con información sobre actualizaciones, cumplimiento y estado de identidades.
   - Exporta el resumen a un archivo de texto.

### Uso
Para ejecutar el script, siga estos pasos en un entorno de PowerShell. Asegúrese de que los archivos CSV necesarios estén en el mismo directorio que el script. Los archivos CSV requeridos son los siguientes:

- **Exportación del inventario de dispositivos Windows de Intune**
- **Lista de dispositivos de Defender**
- **Lista de dispositivos de Entra ID**
- **Lista de usuarios de Entra ID**
