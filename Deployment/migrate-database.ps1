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

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker was not found in PATH.'
    }
    if ([string]::IsNullOrWhiteSpace($env:POSTGRES_USER)) { throw 'POSTGRES_USER is missing from .env.' }
    if ([string]::IsNullOrWhiteSpace($env:POSTGRES_DB)) { throw 'POSTGRES_DB is missing from .env.' }

    $files = @(
        '000001_initial_schema.up.sql',
        '000002_character_progression.up.sql',
        '000003_race_bloodline_techniques.up.sql',
        '000004_bloodline_awakening_technique_training.up.sql'
    )

    Write-Host '[HongHuang] Applying the four initial migrations to the local development database.'
    foreach ($file in $files) {
        $source = Join-Path (Join-Path $PSScriptRoot '..\Database\migrations') $file
        if (-not (Test-Path $source)) { throw "Migration file not found: $source" }

        $existing = docker compose --env-file .env exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -At -c "SELECT to_regclass('public.accounts') IS NOT NULL;"
        if ($LASTEXITCODE -ne 0) { throw 'Could not connect to PostgreSQL. Start infrastructure first.' }
        if (($existing | Out-String).Trim() -eq 't') {
            throw 'The accounts table already exists. Refusing to re-run non-idempotent initial migrations.'
        }
        break
    }

    foreach ($file in $files) {
        $source = Join-Path (Join-Path $PSScriptRoot '..\Database\migrations') $file
        $containerPath = "/tmp/$file"
        Write-Host "[HongHuang] Applying $file"
        docker cp $source "honghuang-postgres:$containerPath"
        if ($LASTEXITCODE -ne 0) { throw "Could not copy $file into PostgreSQL container." }

        docker compose --env-file .env exec -T postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -f $containerPath
        if ($LASTEXITCODE -ne 0) { throw "Migration failed: $file" }
    }

    Write-Host '[OK] All four initial migrations were applied.'
}
finally {
    Pop-Location
}
