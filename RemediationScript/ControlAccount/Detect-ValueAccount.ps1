# Script de PowerShell para obtener los valores de "Umbral de bloqueo", "Ventana de obs. de bloqueo" y "Duración de bloqueo"

# Ejecutar el comando 'net accounts' y almacenar el resultado
$resultado = net accounts

# Inicializar un hash table para almacenar los valores
$valores = @{
    "Umbral de bloqueo" = $null
    "Ventana de obs. de bloqueo" = $null
    "Duracion de bloqueo" = $null
}

# Valores predefinidos
$valoresPredefinidos = @{
    "Umbral de bloqueo" = 8
    "Ventana de obs. de bloqueo" = 30
    "Duracion de bloqueo" = 30
}

# Buscar y extraer los valores correspondientes
foreach ($linea in $resultado) {
    if ($linea -match "Umbral de bloqueo:\s+(\d+)") {
        $valores["Umbral de bloqueo"] = $matches[1]
    }
    elseif ($linea -match "Ventana de obs. de bloqueo \(minutos\):\s+(\d+)") {
        $valores["Ventana de obs. de bloqueo"] = $matches[1]
    }
    elseif ($linea -match "n de bloqueo \(minutos\):\s+(\d+)") {
        $valores["Duracion de bloqueo"] = $matches[1]
    }
}

foreach ($clave in $valores.Keys) {
    if ($valores[$clave] -ne $valoresPredefinidos[$clave]) {
        Write-Output "El valor de '$clave' no coincide: $($valores[$clave]) (esperado: $($valoresPredefinidos[$clave]))"
        exit 1
    }
}

# Si todos los valores coinciden
Write-output "Todos los valores son correctos"
exit 0
