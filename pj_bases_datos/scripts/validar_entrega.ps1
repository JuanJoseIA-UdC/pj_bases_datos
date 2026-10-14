# Ejecutar desde PowerShell: .\scripts\validar_entrega.ps1
# Crea el esquema solo si public esta vacio. Las pruebas terminan en ROLLBACK.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$evidencePath = Join-Path $projectRoot 'docs\evidencias\validacion_sql.txt'
$script:record = [System.Collections.Generic.List[string]]::new()

function Invoke-Docker {
    param([string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        # PowerShell 5 interpreta stderr nativo como ErrorRecord incluso en NOTICE.
        $ErrorActionPreference = 'Continue'
        $output = & $script:dockerCommand @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    foreach ($line in $output) {
        $text = $line.ToString()
        $script:record.Add($text)
        Write-Output $text
    }
    if ($exitCode -ne 0) { throw "Docker termino con codigo $exitCode." }
}

Push-Location $projectRoot
try {
    $dockerCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'),
        (Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe')
    )
    $availableDocker = Get-Command docker -ErrorAction SilentlyContinue
    if ($availableDocker) {
        $script:dockerCommand = $availableDocker.Source
    } else {
        $script:dockerCommand = $dockerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $script:dockerCommand) { throw 'Instala e inicia Docker Desktop antes de continuar.' }
    $env:PATH = "$(Split-Path -Parent $script:dockerCommand);$env:PATH"

    if (-not (Test-Path -LiteralPath '.env')) {
        $randomBytes = New-Object byte[] 24
        $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
        $password = [BitConverter]::ToString($randomBytes).Replace('-', '').ToLowerInvariant()
        $template = [IO.File]::ReadAllText((Join-Path $projectRoot '.env.example'))
        $content = $template.Replace('cambiar_por_clave_segura', $password)
        [IO.File]::WriteAllText((Join-Path $projectRoot '.env'), $content, [Text.UTF8Encoding]::new($false))
        Write-Host 'Creado .env con una clave aleatoria local.'
    }

    $date = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'SA Pacific Standard Time')
    $script:record.Add("Validacion entrega 1 - $($date.ToString('yyyy-MM-dd HH:mm:ss')) America/Bogota")
    Invoke-Docker -Arguments @('compose', 'config', '--quiet')
    # La configuracion resuelta contiene la clave: no imprimirla ni guardarla.
    $resolvedJson = & $script:dockerCommand compose config --format json
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo leer compose.yaml.' }
    $config = ($resolvedJson -join "`n") | ConvertFrom-Json
    $dbUser = $config.services.db.environment.POSTGRES_USER
    $dbName = $config.services.db.environment.POSTGRES_DB
    Remove-Variable resolvedJson, config

    Invoke-Docker -Arguments @('compose', 'up', '-d', '--wait', '--wait-timeout', '120', '--quiet-pull', 'db')
    Invoke-Docker -Arguments @('compose', 'ps')
    Invoke-Docker -Arguments @('version', '--format', '{{.Server.Version}}')
    Invoke-Docker -Arguments @('compose', 'version')
    Invoke-Docker -Arguments @('image', 'inspect', 'pgvector/pgvector:pg16', '--format', '{{json .RepoDigests}}')
    $psql = @('compose', 'exec', '-T', 'db', 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-P', 'pager=off', '-U', $dbUser, '-d', $dbName)
    $catalogQuery = "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';"
    $tableCount = @(Invoke-Docker -Arguments ($psql + @('-Atc', $catalogQuery)))[-1].Trim()
    if ($tableCount -eq '0') {
        Invoke-Docker -Arguments @('compose', 'cp', 'sql/schema.sql', 'db:/tmp/schema.sql')
        Invoke-Docker -Arguments ($psql + @('-f', '/tmp/schema.sql'))
    } elseif ($tableCount -eq '14') {
        Write-Host 'El esquema ya existe. Se ejecutaran las pruebas sin recrear tablas.'
        $script:record.Add('Esquema existente: no se vuelve a aplicar schema.sql.')
    } else {
        throw "Se encontraron $tableCount tablas en public. Revisa la base antes de aplicar el esquema."
    }

    $tables = @('funcionarios', 'expedientes_judiciales', 'evidencias', 'embalajes',
        'transferencias_custodia', 'peritajes', 'evidencias_analizadas', 'fotografias_evidencia',
        'documentos_forenses', 'embeddings_texto', 'embeddings_imagen', 'consultas',
        'resultados_recuperacion', 'evaluaciones')
    $countQuery = 'SELECT ' + (($tables | ForEach-Object { "(SELECT count(*) FROM public.$_)" }) -join ' + ') + ';'
    $before = @(Invoke-Docker -Arguments ($psql + @('-Atc', $countQuery)))[-1].Trim()
    Invoke-Docker -Arguments ($psql + @('-c', "SELECT current_database(), current_setting('server_version') AS postgresql; SELECT extname, extversion FROM pg_extension WHERE extname='vector';"))
    Invoke-Docker -Arguments @('compose', 'cp', 'sql/pruebas_schema.sql', 'db:/tmp/pruebas_schema.sql')
    Invoke-Docker -Arguments ($psql + @('-f', '/tmp/pruebas_schema.sql'))
    $after = @(Invoke-Docker -Arguments ($psql + @('-Atc', $countQuery)))[-1].Trim()
    if ($before -ne $after) { throw 'La cantidad de registros cambio despues de las pruebas.' }
    $summary = "OK: registros antes=$before, despues=$after. Validacion completada."
    $script:record.Add($summary)
    Write-Host $summary
} catch {
    $script:record.Add("FALLO: $($_.Exception.Message)")
    throw
} finally {
    New-Item -ItemType Directory -Path (Split-Path -Parent $evidencePath) -Force | Out-Null
    [IO.File]::WriteAllLines($evidencePath, $script:record, [Text.UTF8Encoding]::new($false))
    Pop-Location
}
