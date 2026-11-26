#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/godot-native-net"

cmake -S "$ROOT/NativeNet" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR" --config Release --parallel

test -s "$ROOT/bin/libhonghuang_native_net.so"
echo "Build complete: bin/libhonghuang_native_net.so"
