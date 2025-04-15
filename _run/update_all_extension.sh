#!/bin/bash
set -e
pushd .. > /dev/null
for i in $(find "custom_nodes" -type d -name '.git' -prune)
do
    repo=$(echo ${i%.git*})
    pushd $repo > /dev/null
        branch=$(git rev-parse --abbrev-ref HEAD)
        echo "updating $repo on branch $branch"
        git checkout -f --
        git pull origin ${branch}
    popd > /dev/null
done
popd > /dev/null