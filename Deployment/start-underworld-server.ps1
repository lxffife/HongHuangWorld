$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envFile)) { Write-Error 'Missing Deployment/.env. Configure the primary WorldServer first.'; exit 1 }

# Load shared backend URL and secret; overrides below affect this process only.
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
        $parts = $line -split '=', 2
        [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), 'Process')
    }
}

$required = @('BACKEND_URL','WORLD_SERVER_API_KEY','WORLD_SERVER_ADVERTISE_HOST')
foreach ($name in $required) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) { Write-Error "Missing required setting: $name"; exit 1 }
}

$env:WORLD_SERVER_NODE_KEY = 'honghuang-underworld-node-01'
$env:WORLD_ID = 'underworld_fengdu'
$env:WORLD_SERVER_INSTANCE_KEY = 'fengdu-local-1'
$env:WORLD_SERVER_UDP_PORT = '7778'
$env:WORLD_SERVER_BIND = '0.0.0.0'
$env:WORLD_SERVER_CAPACITY = '100'
$env:WORLD_SERVER_OUTBOX_PATH = Join-Path $repoRoot 'data\worldserver-underworld-outbox.sqlite3'

$exe = Join-Path $repoRoot 'build\world-server\Release\world_server.exe'
if (-not (Test-Path $exe)) { Write-Error 'WorldServer executable not found. Run .\Deployment\build-world-server.ps1 first.'; exit 1 }

Write-Host '[HongHuang] Starting the Fengdu Underworld WorldServer.'
Write-Host ('[HongHuang] World: {0} | UDP: {1}:{2}' -f $env:WORLD_ID, $env:WORLD_SERVER_ADVERTISE_HOST, $env:WORLD_SERVER_UDP_PORT)
Write-Host '[HongHuang] The Qingyun WorldServer on UDP 7777 is not modified.'
& $exe
exit $LASTEXITCODE