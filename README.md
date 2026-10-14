Aquí tienes la versión actualizada del **`README.md`**, adaptada por completo a **Neon (PostgreSQL Serverless + pgvector)** y eliminando cualquier referencia a Docker:

```markdown
# Sistema híbrido relacional-vectorial — Entrega 1

Proyecto de Bases de Datos Relacionales de la Universidad de Caldas para la
gestión de expedientes y cadena de custodia de evidencias forenses ficticias.

La implementación se encuentra en [`pj_bases_datos/`](pj_bases_datos/).
Incluye el esquema de 14 tablas relacionales y vectoriales desplegado sobre 
**Neon Serverless PostgreSQL** con la extensión `pgvector`, índices HNSW y 
pruebas de integridad transaccionales con datos sintéticos. El informe académico 
y sus anexos se entregan por separado.

## Requisitos previos

- Cliente de PostgreSQL (`psql`) instalado y disponible en el `PATH` del sistema.
- Acceso a una instancia de base de datos en [Neon](https://neon.tech) (PostgreSQL 16) con la extensión `vector` habilitada.
- PowerShell (en Windows) o terminal compatible para ejecutar los scripts de automatización.

## Inicio rápido

1. Clonar el repositorio y navegar a la carpeta de implementación:
   ```powershell
   cd .\pj_bases_datos

```

2. Configurar las variables de entorno:
Copiar la plantilla de ejemplo y crear el archivo local `.env`:
```powershell
Copy-Item .env.example .env

```


Abrir el archivo `.env` y asignar la cadena de conexión directa de su proyecto en Neon:
```env
DATABASE_URL="postgresql://usuario:password@ep-ejemplo-123456.us-east-2.aws.neon.tech/cadena_custodia?sslmode=require"

```


3. Ejecutar la validación del esquema y pruebas de integridad:
```powershell
.\scripts\validar_entrega.ps1

```



El script carga las variables del `.env`, se conecta a la instancia de Neon, habilita la extensión `pgvector`, crea el esquema completo (tablas, restricciones, triggers e índices HNSW) y ejecuta las pruebas de integridad. Las inserciones de prueba se revierten automáticamente mediante `ROLLBACK`.

Consultar el [README de la implementación](https://www.google.com/search?q=pj_bases_datos/README.md) para conocer
el detalle de los archivos, estructura de directorios y evidencias de ejecución.

## Alcance

* **Entrega 1:** Universo del discurso, diseño conceptual (ERD en notación Chen), diseño lógico normalizado en 3FN, esquema SQL (14 tablas relacionales y vectoriales con `pgvector`), entorno ejecutable en la nube con Neon, plan experimental de chunking y validación de integridad.

Las credenciales y variables de conexión están estrictamente excluidas de Git mediante `.gitignore`.
La plantilla [`.env.example`](https://www.google.com/search?q=pj_bases_datos/.env.example) permite reproducir el entorno en cualquier instancia compatible sin compartir credenciales de acceso.

```