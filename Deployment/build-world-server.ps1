$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$vcpkgRoot = $env:VCPKG_ROOT

if ([string]::IsNullOrWhiteSpace($vcpkgRoot)) {
    Write-Error 'VCPKG_ROOT is not set. Install vcpkg and set VCPKG_ROOT to its directory.'
    exit 1
}
$toolchain = Join-Path $vcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
if (-not (Test-Path $toolchain)) {
    Write-Error "vcpkg CMake toolchain not found: $toolchain"
    exit 1
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Error 'CMake 3.24+ was not found in PATH.'
    exit 1
}

$source = Join-Path $repoRoot 'GameServer\WorldServer'
$build = Join-Path $repoRoot 'build\world-server'
Write-Host '[HongHuang] Configuring C++ WorldServer (vcpkg manifest dependencies may be installed on first run)...'
cmake -S $source -B $build -A x64 "-DCMAKE_TOOLCHAIN_FILE=$toolchain"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)" }

Write-Host '[HongHuang] Building Release WorldServer...'
cmake --build $build --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw "WorldServer build failed ($LASTEXITCODE)" }

$exe = Join-Path $build 'Release\world_server.exe'
if (-not (Test-Path $exe)) { throw "WorldServer executable not found: $exe" }
Write-Host "[OK] Built $exe"
