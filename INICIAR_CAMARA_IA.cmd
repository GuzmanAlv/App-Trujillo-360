@echo off
title Trujillo 360 - Camara IA
set "PYTHONUTF8=1"
cd /d "%~dp0"
"vision\.venv-rtx\Scripts\python.exe" -u "vision\start_camera.py"
if errorlevel 1 pause
