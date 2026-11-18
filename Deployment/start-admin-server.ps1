$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envFile)) { Write-Error 'Missing Deployment/.env. Copy .env.example to .env first.'; exit 1 }
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
        $parts = $line -split '=', 2
        [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), 'Process')
    }
}
if (-not $env:ADMIN_BOOTSTRAP_USERNAME -or -not $env:ADMIN_BOOTSTRAP_PASSWORD) {
    Write-Error 'ADMIN_BOOTSTRAP_USERNAME and ADMIN_BOOTSTRAP_PASSWORD are required for first startup.'
    exit 1
}
$backendDir = Join-Path $PSScriptRoot '..\Backend'
Set-Location $backendDir
if (-not (Get-Command go -ErrorAction SilentlyContinue)) { Write-Error 'Go was not found in PATH.'; exit 1 }
go run ./cmd/admin
exit $LASTEXITCODE
