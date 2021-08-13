#!/usr/bin/env bash
set -euo pipefail

function printFunctionName(){
    echo "$(tput bold;tput setaf 2 ) === ${FUNCNAME[1]} === $(tput sgr0)"
}

function createPRYaml() {
    printFunctionName

    echo "${TRAVIS_PULL_REQUEST}" > "${TRAVIS_BUILD_DIR}/scripts/codedeploy/pull_request.txt"
    echo "=== pull_request ==="
    cat ${TRAVIS_BUILD_DIR}/scripts/codedeploy/pull_request.txt
}

function cleanImageManifest() {
    printFunctionName

    if [ -f "image_manifest.txt" ]; then
        rm image_manifest.txt
    fi
}

function createImageManifest() {
    printFunctionName

    _image_manifest_file="${TRAVIS_BUILD_DIR}/scripts/codedeploy/image_manifest.txt"
    if [ ! -f $_image_manifest_file ]; then
        touch $_image_manifest_file
    fi

    if [ "${TRAVIS_PULL_REQUEST}" = 'false' ]; then
        _images_diff_results=$(git diff HEAD~ -- images/)
    else
        _images_diff_results=$(git diff origin/master...${TRAVIS_PULL_REQUEST_SHA} -- images/)
    fi

    if [ ! -z "_images_diff_results" ]; then
        _images_diff_results=$(echo "$_images_diff_results" | { grep -E "^\+{3}\sb\/images\/.+$" || :; })
        echo "$_images_diff_results" | while read -r -d$'\n' _images_diff_result
        do 
            if [ ! -z "$_images_diff_result" ]; then
                _gitFile=$(echo "$_images_diff_result" | cut -c7-)
                _image=$(cat $_gitFile | yq e '.image' -)
                _versions=$(git diff origin/master -- "$_gitFile" | { grep -E "^\+{1}\s{2}-.+$" || :; })
                echo "$_versions" | while read -r -d$'\n' _version
                do
                    if [ ! -z "$_version" ]; then
                        _version=$(echo "$_version" | cut -c6-)                
                        echo "$_image:$_version" >> "$_image_manifest_file"
                    fi
                done
            fi    
        done
    fi
    
    echo "=== image_manifest ==="
    cat $_image_manifest_file

    manifest=$(cat "$_image_manifest_file")
    if [ -z "$manifest" ]; then
        echo 'no images to deploy'
        exit 0
    fi
}
