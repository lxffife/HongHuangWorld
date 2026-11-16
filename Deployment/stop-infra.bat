@echo off
setlocal
cd /d "%~dp0"
where docker >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Docker was not found.
  exit /b 1
)
docker compose --env-file .env stop
if errorlevel 1 exit /b 1
echo [OK] Infrastructure services stopped. Persistent volumes were preserved.
endlocal
