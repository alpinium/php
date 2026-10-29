#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

BASE_PATH=$(readlink --canonicalize "${BASH_SOURCE:-$0}")
BASE_DIRECTORY="${BASE_PATH%/*}"

export DEBIAN_FRONTEND="noninteractive"

cat > '/etc/apt/preferences.d/no-debian-php' <<EOF
Package: php*
Pin: release *
Pin-Priority: -1
EOF

source "${BASE_DIRECTORY}/variables.sh"

apt-get update --assume-yes
apt-get dist-upgrade --assume-yes
apt-get install --assume-yes --no-install-recommends apt-transport-https ca-certificates libfcgi-bin lsb-release "${DEBIAN_PACKAGES[@]}"

rm --recursive --force /tmp/* 2>/dev/null || true
