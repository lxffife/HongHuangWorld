@echo off
setlocal
set "PROJECT_DIR=%~dp0.."
if "%HH_API_BASE%"=="" (
  echo HH_API_BASE is not set. Defaulting to http://127.0.0.1:8787
  set "HH_API_BASE=http://127.0.0.1:8787"
)
where godot >nul 2>nul
if errorlevel 1 (
  echo Godot 4.6 was not found in PATH. Add godot.exe to PATH and retry.
  pause
  exit /b 1
)
echo Starting HongHuang headless AI companion...
echo API: %HH_API_BASE%
godot --headless --path "%PROJECT_DIR%" --script res://scripts/ai_test_player.gd
pause
