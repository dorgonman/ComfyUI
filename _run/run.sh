#!/bin/bash
set -e  
current_dir=$(pwd)
mkdir -p ${current_dir}/logs/
pushd ..
VENV_PYTHON_PATH=$(pwd)/.venv/Scripts/python
${VENV_PYTHON_PATH} -s main.py --windows-standalone-build --listen

popd


