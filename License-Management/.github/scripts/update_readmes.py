import os
from datetime import datetime

root_dir = "."

def generar_readme(carpeta):
    archivos = os.listdir(carpeta)
    archivos_md = [f"- {f}" for f in archivos if f != "README.md"]
    fecha = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    contenido = f"# {os.path.basename(carpeta)}\n\n"
    contenido += "## Archivos\n" + "\n".join(archivos_md) + "\n\n"
    contenido += f"*Última actualización: {fecha}*"
    
    return contenido

for dirpath, dirnames, filenames in os.walk(root_dir):
    if '.git' in dirpath:
        continue
    readme_path = os.path.join(dirpath, "README.md")
    nuevo_contenido = generar_readme(dirpath)
    
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(nuevo_contenido)
    
    print(f"README actualizado en: {dirpath}")
