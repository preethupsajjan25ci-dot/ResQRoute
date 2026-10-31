@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
  echo Python launcher 'py' was not found. Install Python 3 and try again.
  pause
  exit /b 1
)
py setup_flutter_windows.py
if errorlevel 1 (
  echo Flutter setup failed. Read the message above and check flutter doctor.
  pause
  exit /b 1
)
pause
