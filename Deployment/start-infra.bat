@echo off
setlocal
cd /d "%~dp0"

where docker >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Docker was not found. Install Docker Desktop and ensure it is running.
  exit /b 1
)

if not exist ".env" (
  echo [ERROR] Missing Deployment\.env
  echo Copy .env.example to .env and replace the example passwords first.
  exit /b 1
)

docker compose --env-file .env up -d
if errorlevel 1 (
  echo [ERROR] Failed to start infrastructure services.
  exit /b 1
)

echo [OK] PostgreSQL, Redis and NATS startup requested.
docker compose --env-file .env ps
endlocal
