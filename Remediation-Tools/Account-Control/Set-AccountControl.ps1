# Autor: Ismael Morilla
# Versión: 1.0
# Fecha: 11/11/2024
# Descripción: Ajusta las configuraciones de control de cuentas a los valores establecidos por la organización.

net accounts /lockoutthreshold:8
net accounts /lockoutduration:30
net accounts /lockoutwindow:30
