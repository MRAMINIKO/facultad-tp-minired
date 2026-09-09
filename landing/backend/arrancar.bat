@echo off
REM Levanta el backend en Windows. Correr desde tp\landing\backend\
cd /d "%~dp0"
if not exist node_modules (
  echo Instalando dependencias...
  call npm install
)
set DB_HOST=172.20.0.101
set DB_PORT=47291
set DB_USER=sa
set DB_NAME=MiniRed_DW
set /p DB_PASSWORD=Clave de sa:
set PORT=3000
node server.js
