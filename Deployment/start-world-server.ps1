$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envFile)) {
    Write-Error 'Missing Deployment/.env. Copy .env.example to .env and configure the world server values.'
    exit 1
}

Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
        $parts = $line -split '=', 2
        [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), 'Process')
    }
}

$required = @('BACKEND_URL','WORLD_SERVER_NODE_KEY','WORLD_SERVER_API_KEY','WORLD_SERVER_ADVERTISE_HOST','WORLD_ID','WORLD_SERVER_INSTANCE_KEY')
foreach ($name in $required) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        Write-Error "Missing required setting: $name"
        exit 1
    }
}

$exe = Join-Path $repoRoot 'build\world-server\Release\world_server.exe'
if (-not (Test-Path $exe)) {
    Write-Error 'WorldServer executable not found. Run .\Deployment\build-world-server.ps1 first.'
    exit 1
}

Write-Host '[HongHuang] Starting WorldServer. Keep this window open; logs are printed below.'
& $exe
exit $LASTEXITCODE
