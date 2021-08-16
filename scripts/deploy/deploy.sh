#!/usr/bin/env bash
set -euo pipefail

source "${TRAVIS_BUILD_DIR}/scripts/deploy/include.sh"

function main() {
    cd "${TRAVIS_BUILD_DIR}"

    createPRYaml
    cleanImageManifest
    createImageManifest
}

main
