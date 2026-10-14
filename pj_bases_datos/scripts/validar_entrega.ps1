# scripts/validar_entrega.ps1
Write-Host "=== Validando conexión con Neon PostgreSQL ===" -ForegroundColor Cyan

if (-not (Test-Path ".env")) {
    Write-Error "No se encontró el archivo .env. Copie .env.example como .env y agregue su DATABASE_URL."
    exit 1
}

# Cargar variables del .env
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
    }
}

$dbUrl = [System.Environment]::GetEnvironmentVariable("DATABASE_URL")

Write-Host "Ejecutando esquema y pruebas..." -ForegroundColor Yellow
psql "$dbUrl" -f "sql/schema.sql"
if ($LASTEXITCODE -ne 0) { Write-Error "Error en schema.sql"; exit 1 }

psql "$dbUrl" -f "sql/pruebas_schema.sql"
if ($LASTEXITCODE -ne 0) { Write-Error "Error en pruebas_schema.sql"; exit 1 }

Write-Host "=== Validación exitosa en Neon ===" -ForegroundColor Green