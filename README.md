# Sistema híbrido relacional-vectorial — Entrega 1

Proyecto de Bases de Datos Relacionales de la Universidad de Caldas para la
gestión de expedientes y cadena de custodia de evidencias forenses ficticias.

La implementación se encuentra en [`pj_bases_datos/`](pj_bases_datos/).
Incluye PostgreSQL con pgvector, el esquema de 14 tablas y pruebas de integridad
con datos sintéticos. El informe académico y sus anexos se entregan por separado.

## Inicio rápido en Windows

Con Docker Desktop instalado y abierto, ejecutar en PowerShell desde la raíz
de este repositorio:

```powershell
cd .\pj_bases_datos
.\scripts\validar_entrega.ps1
```

El script genera la configuración local si no existe, inicia PostgreSQL, crea
el esquema en una base vacía y ejecuta las pruebas. Las inserciones de prueba
se revierten mediante `ROLLBACK`.

Consultar el [README de la implementación](pj_bases_datos/README.md) para conocer
los archivos, los requisitos y los comandos de conexión.

## Alcance

Entrega 1: esquema relacional y vectorial, entorno Docker y validación SQL.
El procesamiento de documentos, los modelos de embeddings, el pipeline RAG y la
evaluación experimental corresponden a la entrega 2.

Las contraseñas locales y la carpeta de documentos están excluidas de Git.
La plantilla [`.env.example`](pj_bases_datos/.env.example) permite reproducir
la configuración sin compartir credenciales.
