#!/bin/bash
set -e  
pushd ..
git fetch origin master
git stash || true
git rebase origin/master
git stash pop || true


pip install virtualenv


if [ ! -d ".venv" ]; then
  /c/Python312/python -m virtualenv .venv
fi

VENV_PYTHON_PATH=$(pwd)/.venv/Scripts/python
VENV_PIP_PATH=$(pwd)/.venv/Scripts/pip


$VENV_PYTHON_PATH --version
$VENV_PYTHON_PATH -m pip install --upgrade pip

$VENV_PIP_PATH install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126
$VENV_PIP_PATH install -r requirements.txt
popd
