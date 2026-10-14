# Entrega 1 — Sistema híbrido relacional-vectorial

Proyecto de Bases de Datos Relacionales, Universidad de Caldas. Dominio:
gestión de expedientes y cadena de custodia de evidencias forenses ficticias.

## Contenido

| Archivo | Propósito |
|---|---|
| `compose.yaml` | PostgreSQL 16 con pgvector, puerto local y volumen persistente. |
| `.env.example` | Plantilla de configuración, sin credenciales reales. |
| `sql/schema.sql` | DDL de 14 tablas, restricciones, seis triggers y dos índices HNSW. |
| `sql/pruebas_schema.sql` | Casos válidos e inválidos con datos ficticios y `ROLLBACK`. |
| `scripts/validar_entrega.ps1` | Arranque, creación inicial del esquema y validación en PowerShell. |

El informe académico, los anexos y la guía del docente se mantienen localmente
en `docs/` y se entregan por separado. Esa carpeta está excluida de Git y no
forma parte de una copia descargada del repositorio.

## Ejecutar y comprobar

Requisitos en Windows: PowerShell 5.1 o posterior y Docker Desktop abierto con
el motor Linux funcionando.
En PowerShell, desde esta carpeta:

```powershell
.\scripts\validar_entrega.ps1
```

El script crea `.env` con una contraseña aleatoria si no existe, inicia el
servicio y espera a que esté disponible. Crea el esquema únicamente cuando
`public` está vacío. Si ya existen 14 tablas, ejecuta las pruebas sin volver a
crear el esquema; si la estructura no corresponde al proyecto, la validación
falla. No borra tablas ni volúmenes.

Las pruebas insertan datos ficticios en las 14 tablas, comprueban restricciones
y consultas vectoriales básicas y revierten la transacción. El registro final
se genera localmente en `docs/evidencias/validacion_sql.txt`, incluyendo los fallos
si los hubiera. El script crea esa carpeta si no existe; su contenido no se sube
a GitHub. La configuración resuelta y la contraseña no se escriben en ese archivo.

Para otro sistema operativo, configurar `.env` a partir de `.env.example` e
iniciar el servicio con `docker compose up -d --wait db`. Ejecutar
`sql/schema.sql` una sola vez en una base vacía y luego `sql/pruebas_schema.sql`
con `psql -X -v ON_ERROR_STOP=1` conectado al servidor.

## Uso cotidiano

```powershell
# Estado del contenedor
docker compose ps

# Consola SQL con los valores predeterminados de .env.example
docker compose exec db psql -X -U postgres -d cadena_custodia

# Detener y volver a iniciar sin eliminar el volumen
docker compose stop db
docker compose up -d --wait db
```

En la consola SQL, `\dt` lista las tablas y `\q` permite salir.
Desde una herramienta externa, conectar a `127.0.0.1:5433`, base
`cadena_custodia`, usuario `postgres` y la contraseña del archivo local `.env`.
Si se personalizan usuario o base en `.env`, adaptar el comando de consola.

## Estado de la entrega

Verificado el **13/10/2026** con PostgreSQL **16.15** y pgvector **0.8.7**:
14 tablas creadas, dos índices HNSW coseno, pruebas SQL aprobadas y cero registros
de prueba persistentes. El script reportó 33 comprobaciones SQL correctas y pudo
repetirse sin recrear las tablas. Los vectores utilizados son sintéticos; estas
pruebas no certifican calidad semántica, rendimiento ni concurrencia entre sesiones.

Esta entrega contiene diseño, configuración, esquema y pruebas. Los modelos de
embeddings, la ingesta de archivos, el pipeline RAG y la evaluación experimental
se implementarán en la entrega 2. Sus tablas se incluyen ahora porque son parte
del diseño requerido.

El informe académico y el plan de experimento de chunking forman parte de la
entrega documental separada. Las evidencias pueden obtenerse ejecutando el script
y adjuntando el archivo de resultados generado localmente.

`.env` está excluido de Git y debe permanecer local. `docker compose down -v`
elimina el volumen: no se necesita para ejecutar ni repetir estas pruebas.
