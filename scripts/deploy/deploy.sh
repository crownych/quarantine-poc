#!/usr/bin/env bash
set -euo pipefail

function printFunctionName(){
    echo "$(tput bold;tput setaf 2 ) === ${FUNCNAME[1]} === $(tput sgr0)"
}

function createPRYaml() {
    printFunctionName

    echo "${TRAVIS_PULL_REQUEST}" > "${TRAVIS_BUILD_DIR}/scripts/codedeploy/pull_request.txt"
}

function cleanImageManifest() {
    printFunctionName

    if [ -f "image_manifest.txt" ]; then
        rm image_manifest.txt
    fi
}

function createImageManifest() {
    printFunctionName

    _images_diff_results=$(git diff master -- images)

    _image_manifest_file="${TRAVIS_BUILD_DIR}/scripts/codedeploy/image_manifest.txt"
    echo '' > "$_image_manifest_file"
    
    if [ $_images_diff_results != null ]; then
        _gitFiles=$(echo $_images_diff_results | grep -E "^\+{3}\sb\/images\/.+$" | cut -c7-)
        for _gitFile in $_gitFiles
        do
            _image=$(yq e '.image' $_gitFile)
            _versions=$(git diff master -- "$_gitFile" | grep -E "^\+{1}\s{2}-.+$" | cut -c6-)
            for _version in $_versions
            do
                echo "$_image:$_version" >> "$_image_manifest_file"
            done
        done
    fi  
    unset _version _versions _gitFile _gitFiles _images_diff_results
}

function main() {
    cd "${TRAVIS_BUILD_DIR}"

    createPRYaml
    cleanImageManifest
    createImageManifest
}

main
