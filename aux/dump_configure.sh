#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

BASE_PATH=$(readlink --canonicalize "${BASH_SOURCE:-$0}")
BASE_DIRECTORY="${BASE_PATH%/*}"

OUTPUT_DIRECTORY="${BASE_DIRECTORY}/configure"

VERSIONS=('8.1' '8.2' '8.3' '8.4' '8.5')

TEMPORARY_FILES=()
function TrapExit()
{
    rm --recursive --force "${TEMPORARY_FILES[@]}"
}

trap TrapExit EXIT


for VERSION in "${VERSIONS[@]}"; do
    echo "PHP ${VERSION}"

    TEMPORARY_FILE="$(mktemp)"
    TEMPORARY_FILES+=("$TEMPORARY_FILE")
    TEMPORARY_DIRECTORY="$(mktemp --directory)"
    TEMPORARY_FILES+=("$TEMPORARY_DIRECTORY")

    curl --location --fail --silent --show-error --location --output "$TEMPORARY_FILE" --url "https://www.php.net/releases/index.php?json&version=${VERSION}"
    FULL_VERSION=$(jq --raw-output '.version' "$TEMPORARY_FILE")
    DOWNLOAD_URL="https://www.php.net/distributions/php-${FULL_VERSION}.tar.gz"

    curl --fail --silent --show-error --location --output "$TEMPORARY_FILE" --url "$DOWNLOAD_URL"

    tar --extract --gzip --file "$TEMPORARY_FILE" --directory "$TEMPORARY_DIRECTORY"
    SOURCE_DIRECTORY=$(find "$TEMPORARY_DIRECTORY" -mindepth 1 -maxdepth 1 -type d)

    mkdir --parents "${OUTPUT_DIRECTORY}/${VERSION}"
    OUTPUT_FILE="${OUTPUT_DIRECTORY}/${VERSION}/configure.txt"

    pushd "$SOURCE_DIRECTORY" &> /dev/null

    './configure' --help > "$OUTPUT_FILE"

    popd &> /dev/null

done
