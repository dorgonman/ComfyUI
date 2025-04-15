@echo off
setlocal
chcp 65001 >nul
set PYTHONIOENCODING=utf-8

set "SCRIPT_DIR=%~dp0"
echo Current bat location is: %SCRIPT_DIR%
mkdir logs
pushd ..
call .\.venv\Scripts\python -s main.py --windows-standalone-build --listen
popd


