#!/usr/bin/env bash
set -euo pipefail

function createPRYaml() {
    echo "pr: ${TRAVIS_PULL_REQUEST}" > "${TRAVIS_BUILD_DIR}/scripts/codedeploy/pull_request.txt"
    echo "sha: ${TRAVIS_PULL_REQUEST_SHA}" >> "${TRAVIS_BUILD_DIR}/scripts/codedeploy/pull_request.txt"
}

function cleanImageManifest() {
    if [ -f "image_manifest.txt" ]; then
        rm image_manifest.txt
    fi
}

function createImageManifest() {
    _gitFiles=$(git diff master -- images | grep -E "^\+{3}\sb\/images\/.+$" | cut -c7-)
    for _gitFile in $_gitFiles
    do
        _image=$(yq e '.image' $_gitFile)
        _versions=$(git diff master -- "$_gitFile" | grep -E "^\+{1}\s{2}-.+$" | cut -c6-)
        for _version in $_versions
        do
            echo "$_image:$_version" >> "${TRAVIS_BUILD_DIR}/scripts/codedeploy/image_manifest.txt"
        done
    done
    unset _version _versions _gitFile _gitFiles
}

function main() {
    createPRYaml
    cleanImageManifest
    createImageManifest
}

main