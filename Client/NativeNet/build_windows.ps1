param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$buildDir = Join-Path $repoRoot "build\godot-native-net"

Write-Host "Configuring HongHuang Godot ENet extension..."
cmake -S $PSScriptRoot -B $buildDir -A x64 -DCMAKE_BUILD_TYPE=$Configuration
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)" }

Write-Host "Building native extension..."
cmake --build $buildDir --config $Configuration --parallel
if ($LASTEXITCODE -ne 0) { throw "Native extension build failed ($LASTEXITCODE)" }

$artifact = Join-Path $repoRoot "Client\HongHuangClient\bin\honghuang_native_net.dll"
if (!(Test-Path $artifact)) { throw "Expected extension artifact not found: $artifact" }
Write-Host "Build complete: $artifact"
