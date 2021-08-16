#!/usr/bin/env bash
set -euo pipefail

source "${TRAVIS_BUILD_DIR}/scripts/deploy/include.sh"

deploy_dir='codedeploy'
deploy_artifact="artifact-${TRAVIS_COMMIT}.zip"

function installTools() {
    printFunctionName

    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    aws --version
}

function prepareArtifact() {
    printFunctionName

    createPRYaml
    cleanImageManifest
    createImageManifest

    test -d "${deploy_dir}" || mkdir "${deploy_dir}"
    cp appspec.yml "${deploy_dir}/"
    cp -R scripts "${deploy_dir}/"
}

function pushArtifactToS3() {
    printFunctionName

    aws deploy push \
    --application-name "${CODEDEPLOY_APPLICATION_NAME}" \
    --ignore-hidden-files \
    --s3-location "s3://${S3_TARGET_BUCKET}/${deploy_artifact}" \
    --source "${TRAVIS_BUILD_DIR}/${deploy_dir}" > /dev/null 2>&1
}

function deployArtifact() {
    printFunctionName

    aws deploy create-deployment \
    --application-name ${CODEDEPLOY_APPLICATION_NAME} \
    --deployment-group-name master \
    --s3-location bucket=${S3_TARGET_BUCKET},key=$deploy_artifact,bundleType=zip
}

function main() {
    cd "${TRAVIS_BUILD_DIR}"

    prepareArtifact
    installTools
    pushArtifactToS3
    deployArtifact
}

main
