#!/bin/bash

# Builds images locally the same way as .github/workflows/build.yml,
# runs the smoke test and keeps the result in the local Docker image store.
# Nothing is pushed anywhere.
#
# Usage: ./debug_script.sh [PHP] [DEBIAN] [PLATFORM]
#   PHP       - PHP minor version from configuration.yaml (e.g. 8.4), default: all
#   DEBIAN    - Debian codename (e.g. trixie), default: all
#   PLATFORM  - target platform (e.g. linux/arm64), default: native platform
#
# Examples:
#   ./debug_script.sh                       # all combinations, native platform
#   ./debug_script.sh 8.4                   # PHP 8.4 on all Debian releases
#   ./debug_script.sh 8.4 trixie linux/arm64

set -euo pipefail
IFS=$'\n\t'

BASE_PATH=$(readlink --canonicalize "${BASH_SOURCE:-$0}")
BASE_DIRECTORY="${BASE_PATH%/*}"

FILTER_PHP="${1:-}"
FILTER_DEBIAN="${2:-}"
PLATFORM="${3:-}"
IMAGE="php-debug"

for COMMAND in docker yq jq; do
    if ! command -v "$COMMAND" > /dev/null; then
        echo "Missing required command: ${COMMAND}"
        exit 1
    fi
done

CONFIG=$(yq -o=json "${BASE_DIRECTORY}/configuration.yaml")

TARGETS=$(echo "$CONFIG" | jq -r --arg php "$FILTER_PHP" --arg debian "$FILTER_DEBIAN" '
    .php_versions | to_entries[]
    | select($php == "" or .key == $php)
    | .key as $PHP
    | .value.php.version as $VERSION
    | .value.debian[]
    | select($debian == "" or . == $debian)
    | [$PHP, $VERSION, .] | @tsv')

if [ -z "$TARGETS" ]; then
    echo "No PHP × Debian combination matches PHP='${FILTER_PHP}' DEBIAN='${FILTER_DEBIAN}'"
    exit 1
fi

PLATFORM_ARGS=()
if [ -n "$PLATFORM" ]; then
    PLATFORM_ARGS=(--platform "$PLATFORM")
fi

FAILED=()
SUCCEEDED=()
while read -r -u 3 PHP VERSION DEBIAN; do
    TAG="${IMAGE}:${VERSION}-${DEBIAN}"

    echo "###########"
    echo "PHP_VERSION: ${VERSION}"
    echo "DEBIAN_CODENAME: ${DEBIAN}"
    echo "PLATFORM: ${PLATFORM:-native}"
    echo "IMAGE: ${TAG}"
    echo "###########"

    # Same labels as in CI, the point release is read from the base image
    if ! DEBIAN_POINT_RELEASE=$(docker run --rm --pull always "${PLATFORM_ARGS[@]}" "debian:${DEBIAN}-slim" cat /etc/debian_version); then
        FAILED+=("${TAG} (Debian release)")
        continue
    fi
    echo "DEBIAN_POINT_RELEASE: ${DEBIAN_POINT_RELEASE}"

    if ! docker buildx build \
        --load \
        "${PLATFORM_ARGS[@]}" \
        --build-arg "DEBIAN_CODENAME=${DEBIAN}" \
        --build-arg "PHP_VERSION=${VERSION}" \
        --build-arg "PHP_MAJOR=${PHP}" \
        --build-arg "DEBIAN_RELEASE=${DEBIAN_POINT_RELEASE%%.*}" \
        --build-arg "DEBIAN_POINT_RELEASE=${DEBIAN_POINT_RELEASE}" \
        --tag "$TAG" \
        "$BASE_DIRECTORY"; then
        FAILED+=("${TAG} (build)")
        continue
    fi

    # set -e is ignored inside "if", so every test is checked explicitly
    SMOKE_TESTS=(
        "php -v"
        "php -r 'exit(PHP_VERSION === \"${VERSION}\" ? 0 : 1);'"
        "php -m"
        "php-fpm -t"
        "composer --version"
        "grep -q VERSION_CODENAME=${DEBIAN} /etc/os-release"
    )
    SMOKE_FAILED=()
    for SMOKE_TEST in "${SMOKE_TESTS[@]}"; do
        echo "+ ${SMOKE_TEST}"
        if ! docker run --rm "${PLATFORM_ARGS[@]}" "$TAG" sh -c "$SMOKE_TEST"; then
            SMOKE_FAILED+=("$SMOKE_TEST")
        fi
    done

    if [ "${#SMOKE_FAILED[@]}" -gt 0 ]; then
        for SMOKE_TEST in "${SMOKE_FAILED[@]}"; do
            FAILED+=("${TAG} (smoke test: ${SMOKE_TEST})")
        done
        continue
    fi

    SUCCEEDED+=("$TAG")
done 3<<< "$TARGETS"

echo "###########"
for TAG in "${SUCCEEDED[@]}"; do
    echo "OK:     ${TAG}"
done
for TAG in "${FAILED[@]}"; do
    echo "FAILED: ${TAG}"
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    exit 1
fi
