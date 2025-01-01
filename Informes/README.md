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


# Descripción de los scripts: 

## Eport-Informe

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


