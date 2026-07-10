@echo off
setlocal
chcp 65001 >nul
set PYTHONIOENCODING=utf-8

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_ROOT=%%~fI"
set "HF_HOME=%PROJECT_ROOT%\models\huggingface"
set "HF_HUB_DISABLE_XET=1"
set "HF_HUB_DOWNLOAD_TIMEOUT=60"
echo Current bat location is: %SCRIPT_DIR%
mkdir logs
pushd "%PROJECT_ROOT%"
call ".\.venv\Scripts\python.exe" -s main.py --windows-standalone-build --listen %*
popd


