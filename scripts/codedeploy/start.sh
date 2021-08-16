#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# quay info 
QUAY_SERVER='example-registry-quay-openshift-operators.router-default.apps-crc.testing'
QUAY_QUARANTINE="$QUAY_SERVER/quarantine"
QUAY_SANDBOX="$QUAY_SERVER/sandbox"
QUAY_LAB="$QUAY_SERVER/lab"
QUAY_STAGING="$QUAY_SERVER/staging"
QUAY_PROD="$QUAY_SERVER/production"

# GitHub info
GITHUB_REPO='crownych/quarantine-poc'

# fetch pr info
pr=$(cat $SCRIPTS_DIR/pull_request.txt)

# fetch image list
images=$(cat $SCRIPTS_DIR/image_manifest.txt)

# login private registry
podman login --tls-verify=false -u $QUAY_USER -p $QUAY_PASS $QUAY_SERVER

repos=()

for image in $images; do
    # pull image
    podman pull $image

    # prepare image repo
    OIFS="$IFS"
    IFS='/'
    read -a image_parts <<< "$image"
    if [ ${#image_parts[@]} -eq 1 ]; then
        repo="${image_parts[0]}"
    else
        repo="${image_parts[2]}"
    fi
    repos+=($repo)
    IFS=':'
    read -a repo_parts <<< "$repo"
    repo_name="${repo_parts[0]}"
    version="${repo_parts[1]}"
    IFS="$OIFS"
    
    quarantine_repo="$QUAY_QUARANTINE/$repo"

    # get access token (need to check api to get the token)
    # 有 client_id client_secret 試試也許可以透過 client_credentials 方式取得 token (注意以下的 response_type=token 與 code grant 的 response_type=code 不同)：
    # https://example-registry-quay-openshift-operators.router-default.apps-crc.testing/oauth/authorize?response_type=token&client_id=ZGTQYTQZL5IORKGKCSQ4&scope=org:admin%20repo:admin%20repo:create%20repo:read%20repo:write%20super:user%20user:admin%20user:read&redirect_uri=https://example-registry-quay-openshift-operators.router-default.apps-crc.testing/oauth/localapp
    # 20210812 目前看起來 login 後 cookie 裡會有 _csrf_token，有此 token 就可以直接打如下的 redirect_uri 取得 token
    # https://example-registry-quay-openshift-operators.router-default.apps-crc.testing/oauth/localapp?scope=org%3Aadmin+repo%3Aadmin+repo%3Acreate+repo%3Aread+repo%3Awrite+super%3Auser+user%3Aadmin+user%3Aread#access_token=6ZPqluIzF9xHfSwZMtcyEH8UwXYwhb2UsnSJoohx&token_type=Bearer&expires_in=315576000
    
    # check if image exists
    tag_exists=$(curl -L -k -s  -H "Authorization: Bearer ${QUAY_TOKEN}" "https://$QUAY_SERVER/api/v1/repository/quarantine/$repo_name/tag?specificTag=$version" | jq -r '.tags | length')

    if [ $tag_exists -eq 0 ]; then
        # add tag
        podman tag "$image" "$quarantine_repo"

        # push to quarantine
        podman push --tls-verify=false "$image" "$quarantine_repo"

        # get image digest
        digest=$(curl -L -k -s  -H "Authorization: Bearer ${QUAY_TOKEN}" "https://$QUAY_SERVER/api/v1/repository/quarantine/$repo_name/tag?specificTag=$version" | jq -r '.tags[0].manifest_digest')
        echo "digest: $digest"

        # waiting for image scanning to completed
        sleep 40
        
        # get security vulnerabilities
        scan_result=$(curl -L -k -s -H "Authorization: Bearer ${QUAY_TOKEN}" "https://$QUAY_SERVER/api/v1/repository/quarantine/$repo_name/manifest/$digest/security")
        feature_length=$(echo $scan_result | jq '.data.Layer.Features | length')
        if [ $feature_length -gt 0 ]; then
            vulnerabilities=$(echo "$scan_result" | jq -r '.data.Layer.Features[].Vulnerabilities[] | select(.Severity == "High" or .Severity == "Medium")' | jq -n '[inputs] | length')
            comment="[Security scan report](https://$QUAY_SERVER/repository/quarantine/$repo_name/manifest/$digest?tab=vulnerabilities)"
        else
            # Unsupported 打下列 API 回應範例如下，features length 為 0：
            # {"status": "scanned", "data": {"Layer": {"Name": "sha256:14380fabe70e0ea2687d44867b0253b2633a70985ada1d8c200e64bacd100928", "ParentName": "", "NamespaceName": "", "IndexedByVersion": 4, "Features": []}}}
            vulnerabilities=0
            comment='Security scan not supported'
        fi
        echo "vulnerabilities: $vulnerabilities"

        echo "=== GitHub API info ==="
        echo "https://api.github.com/repos/$GITHUB_REPO/issues/$pr/comments"
        echo "Authorization: Bearer $GITHUB_TOKEN"
        echo "{\"body\":\"$comment\"}"

        curl -X POST "https://api.github.com/repos/$GITHUB_REPO/issues/$pr/comments" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -d "{\"body\":\"$comment\"}"

        if [ $vulnerabilities -eq 0 ]; then
            if [ "$pr" = 'false' ]; then
                # 當 PR merge 時，push image to sandbox, lab, staging, production
                slsp_repos=("$QUAY_SANDBOX/$repo" "$QUAY_LAB/$repo" "$QUAY_STAGING/$repo" "$QUAY_PROD/$repo")
                for slsp_repo in ${slsp_repos[@]}; do
                    podman tag $image $slsp_repo
                    podman push --tls-verify=false $image $slsp_repo
                done
            else
                # 當 PR created 時，auto merge PR
                curl -X PUT "https://api.github.com/repos/$GITHUB_REPO/pulls/$pr/merge" \
                -H "Accept: application/vnd.github.v3+json" \
                -H "Authorization: Bearer $GITHUB_TOKEN" \
                -d '{"commit_title":"Image scan passed"}'
            fi    
        else
            # add comment to PR (not completed yet)
            echo 'High/Medium vulnerabilities found'
        fi
    else
        echo 'image already exists'
    fi    

done

unset image images repos tag_exists digest vulnerabilities quarantine_repo slsp_repos OIFS
