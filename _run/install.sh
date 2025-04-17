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




pushd .. > /dev/null
projectRoot=$(pwd)
for i in $(find "custom_nodes" -type d -name '.git' -prune)
do
    repo=$(echo ${i%.git*})
    pushd $repo > /dev/null
       # check if requirements.txt exists
       if [ -f "requirements.txt" ]; then
           echo "Installing requirements for $repo"
           cmd="$VENV_PIP_PATH install -r ${projectRoot}/$repo/requirements.txt"
           echo $cmd
           eval $cmd
       fi    

    popd > /dev/null
done
popd > /dev/null
