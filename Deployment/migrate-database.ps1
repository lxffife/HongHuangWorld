$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $envFile = Join-Path $PSScriptRoot '.env'
    if (-not (Test-Path $envFile)) {
        throw 'Missing Deployment/.env. Copy .env.example and configure it first.'
    }

    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $parts = $line -split '=', 2
            [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), 'Process')
        }
    }

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker was not found in PATH.' }
    if ([string]::IsNullOrWhiteSpace($env:POSTGRES_USER)) { throw 'POSTGRES_USER is missing from .env.' }
    if ([string]::IsNullOrWhiteSpace($env:POSTGRES_DB)) { throw 'POSTGRES_DB is missing from .env.' }

    $files = @(
        '000001_initial_schema.up.sql',
        '000002_character_progression.up.sql',
        '000003_race_bloodline_techniques.up.sql',
        '000004_bloodline_awakening_technique_training.up.sql',
        '000005_items_inventory_drops.up.sql'
    )

    $existing = docker compose --env-file .env exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -At -c "SELECT to_regclass('public.accounts') IS NOT NULL;"
    if ($LASTEXITCODE -ne 0) { throw 'Could not connect to PostgreSQL. Start infrastructure first.' }

    docker compose --env-file .env exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS schema_migrations(version VARCHAR(16) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());"
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the migration ledger.' }

    $count = docker compose --env-file .env exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -At -c 'SELECT count(*) FROM schema_migrations;'
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the migration ledger.' }
    if (($count | Out-String).Trim() -eq '0' -and ($existing | Out-String).Trim() -eq 't') {
        throw 'The accounts table already exists but the migration ledger is empty. Refusing to guess the database version.'
    }

    foreach ($file in $files) {
        $version = $file.Substring(0, 6)
        $applied = docker compose --env-file .env exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -At -c "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version='$version');"
        if ($LASTEXITCODE -ne 0) { throw "Could not check migration version $version." }
        if (($applied | Out-String).Trim() -eq 't') {
            Write-Host "[HongHuang] Skipping already applied migration $version"
            continue
        }

        $source = Join-Path (Join-Path $PSScriptRoot '..\Database\migrations') $file
        if (-not (Test-Path $source)) { throw "Migration file not found: $source" }
        $containerPath = "/tmp/$file"
        Write-Host "[HongHuang] Applying $file"
        docker cp $source "honghuang-postgres:$containerPath"
        if ($LASTEXITCODE -ne 0) { throw "Could not copy $file into PostgreSQL container." }

        docker compose --env-file .env exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -f $containerPath
        if ($LASTEXITCODE -ne 0) { throw "Migration failed: $file" }

        docker compose --env-file .env exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -c "INSERT INTO schema_migrations(version) VALUES ('$version');"
        if ($LASTEXITCODE -ne 0) { throw "Could not record migration version $version." }
    }

    Write-Host '[OK] All pending database migrations were applied.'
}
finally {
    Pop-Location
}
