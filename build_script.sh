#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

BASE_PATH=$(readlink --canonicalize "${BASH_SOURCE:-$0}")
BASE_DIRECTORY="${BASE_PATH%/*}"

source '/etc/os-release'
DEBIAN_CODENAME="$VERSION_CODENAME"
export DEBIAN_FRONTEND="noninteractive"

MACHINE_ARCHITECTURE="$(uname -m)"
CPU_LIMIT="$(nproc)"
DEBIAN_ARCHITECTURE="$(dpkg --print-architecture)"

case "$DEBIAN_ARCHITECTURE" in
    'amd64')
        GNU_ARCH='x86_64-linux-gnu'
        DEB_MULTI_ARCH='x86_64-linux-gnu'
        MARCH='x86-64-v2'
        ;;
    'arm64')
        GNU_ARCH='aarch64-linux-gnu'
        DEB_MULTI_ARCH='aarch64-linux-gnu'
        MARCH='armv8.2-a'
        ;;
    *) echo "Unknown architecture ${DEBIAN_ARCHITECTURE}" >&2
       exit 1
       ;;
esac

export GNU_ARCH
export DEB_MULTI_ARCH

if ! [[ $PHP_VERSION =~ ^([0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
    exit 1
fi

PHP_SHORT_VERSION="${BASH_REMATCH[1]}"

CPU_LIMIT="$(nproc)"
QUOTA='' PERIOD=''
IFS=' ' read -r QUOTA PERIOD < '/sys/fs/cgroup/cpu.max' 2>/dev/null || true
case "$QUOTA" in
    ''|'max')
        ;;
    *)
        LIMIT=$(( (QUOTA + PERIOD - 1) / PERIOD ))
        if [ "$LIMIT" -lt "$CPU_LIMIT" ]; then
            CPU_LIMIT="$LIMIT"
        fi
        ;;
esac

MEM_LIMIT=''
IFS=' ' read -r MEM_LIMIT < '/sys/fs/cgroup/memory.max' 2>/dev/null || true
case "$MEM_LIMIT" in
    ''|'max')
        MEM_LIMIT=$(( $(getconf _PHYS_PAGES) * $(getconf PAGESIZE) ))
        ;;
esac

apt-get update --assume-yes
apt-get dist-upgrade --assume-yes
apt-get install --assume-yes --no-install-recommends yq

OPTIONS=()
DEBIAN_PACKAGES=()
DEBIAN_DEV_PACKAGES=()
while read -r EXTENSION; do
    EXTENSION_OPTIONS=$(yq -r --arg extension "$EXTENSION" '.extensions[$extension].options // [] | @tsv' "${BASE_DIRECTORY}/configuration.yaml")
    OPTIONS+=($EXTENSION_OPTIONS)

    EXTENSION_DEBIAN_OPTIONS=$(yq -r --arg extension "$EXTENSION" --arg debian "$DEBIAN_CODENAME" '.extensions[$extension].debian[$debian].options // [] | @tsv' "${BASE_DIRECTORY}/configuration.yaml")
    OPTIONS+=($EXTENSION_DEBIAN_OPTIONS)

    EXTENSION_DEBIAN_PACKAGES=$(yq -r --arg extension "$EXTENSION" --arg debian "$DEBIAN_CODENAME" '.extensions[$extension].debian[$debian].packages // [] | @tsv' "${BASE_DIRECTORY}/configuration.yaml")
    DEBIAN_PACKAGES+=($EXTENSION_DEBIAN_PACKAGES)

    EXTENSION_DEBIAN_DEV_PACKAGES=$(yq -r --arg extension "$EXTENSION" --arg debian "$DEBIAN_CODENAME" '.extensions[$extension].debian[$debian].dev_packages // [] | @tsv' "${BASE_DIRECTORY}/configuration.yaml")
    DEBIAN_DEV_PACKAGES+=($EXTENSION_DEBIAN_DEV_PACKAGES)
    
done < <(yq -r --arg ver "$PHP_SHORT_VERSION" '.php_versions[$ver].extensions[]' "${BASE_DIRECTORY}/configuration.yaml")

echo "###########"
echo "MACHINE_ARCHITECTURE: ${MACHINE_ARCHITECTURE}"
echo "###########"
echo "CPU_LIMIT: ${CPU_LIMIT}"
echo "###########"
echo "MEMORY_LIMIT: $(( MEM_LIMIT / 1024 / 1024 )) MiB"
echo "###########"
echo "DEBIAN_ARCHITECTURE: ${DEBIAN_ARCHITECTURE}"
echo "###########"
echo "DEBIAN_CODENAME: ${DEBIAN_CODENAME}"
echo "###########"
echo "PHP_VERSION: ${PHP_VERSION}"
echo "###########"
echo "PHP_SHORT_VERSION: ${PHP_SHORT_VERSION}"
echo "###########"
echo "OPTIONS: ${OPTIONS[@]}"
echo "###########"
echo "DEBIAN_PACKAGES: ${DEBIAN_PACKAGES[@]}"
echo "###########"
echo "DEBIAN_DEV_PACKAGES: ${DEBIAN_DEV_PACKAGES[@]}"
echo "###########"

PHPIZE_PACKAGES=('autoconf' 'bison' 'build-essential' 'libtool' 'pkg-config' 're2c')

apt-get install --assume-yes --no-install-recommends lsb-release apt-transport-https ca-certificates curl gnupg tar xz-utils "${PHPIZE_PACKAGES[@]}" "${DEBIAN_DEV_PACKAGES[@]}"

PHP_URL="https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz"

PHP_SOURCE_PATH=$(mktemp)
PHP_SOURCE_DIRECTORY=$(mktemp --directory)

curl --fail --location --show-error --silent --output "$PHP_SOURCE_PATH" "$PHP_URL"
tar --xz --extract --file "$PHP_SOURCE_PATH" -C "$PHP_SOURCE_DIRECTORY" --strip-components=1

# PHP is built for its final paths and installed into OUTPUT_DIRECTORY,
# which is copied to / in the final image
OUTPUT_DIRECTORY='/output'
PREFIX='/usr/local'
SYSCONF_DIRECTORY='/etc'
CONFIG_VARIABLES='/mnt/docker/variables.sh'
CONFIG_FILE_PATH="${SYSCONF_DIRECTORY}/php"
CONFIG_FILE_SCAN_DIR="${SYSCONF_DIRECTORY}/php/conf.d"

mkdir --parents "$OUTPUT_DIRECTORY" "${CONFIG_VARIABLES%/*}"
declare -p DEBIAN_PACKAGES > "$CONFIG_VARIABLES"

pushd "$PHP_SOURCE_DIRECTORY" &> /dev/null

export CFLAGS="-g -O2 -march=${MARCH} -mtune=generic -fstack-protector-strong -fpic -fpie -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS='-Wl,-O1 -pie'
export MAKEFLAGS="-j${CPU_LIMIT}"

./buildconf --force

./configure \
    --build="$GNU_ARCH" \
    --prefix="$PREFIX" \
    --sysconfdir="$SYSCONF_DIRECTORY" \
    --with-config-file-path="$CONFIG_FILE_PATH" \
    --with-config-file-scan-dir="$CONFIG_FILE_SCAN_DIR" \
    "${OPTIONS[@]}"

make prof-gen
sapi/cli/php Zend/bench.php
sapi/cli/php Zend/micro_bench.php
make prof-clean
make prof-use
make install INSTALL_ROOT="$OUTPUT_DIRECTORY"

popd &> /dev/null

# Sample FPM configs installed by "make install", the real ones come from configure_script.sh
rm --force "${OUTPUT_DIRECTORY}${SYSCONF_DIRECTORY}/php-fpm.conf.default"
rm --recursive --force "${OUTPUT_DIRECTORY}${SYSCONF_DIRECTORY}/php-fpm.d"

COMPOSER_URL='https://getcomposer.org/download/latest-stable/composer.phar'
COMPOSER_DIRECTORY=$(mktemp --directory)

curl --fail --location --show-error --silent --output "${COMPOSER_DIRECTORY}/composer.phar" "$COMPOSER_URL"
install -D --mode=0755 "${COMPOSER_DIRECTORY}/composer.phar" "${OUTPUT_DIRECTORY}${PREFIX}/bin/composer"

rm --recursive --force /tmp/* 2>/dev/null || true
