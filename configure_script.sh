#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

if ! [[ $PHP_VERSION =~ ^([0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
    exit 1
fi

PHP_SHORT_VERSION="${BASH_REMATCH[1]}"

# /output/etc/ is copied to /etc/ in the final image
CONFIG_DIRECTORY='/output/etc'

mkdir --parents "${CONFIG_DIRECTORY}/php/conf.d"

# PHP 8.5+ has OPcache always built in, older versions load it as a shared extension
if [ "$PHP_SHORT_VERSION" != '8.5' ]; then
    cat <<EOF > "${CONFIG_DIRECTORY}/php/conf.d/10-opcache.ini"
zend_extension = opcache
EOF
fi

cat <<EOF > "${CONFIG_DIRECTORY}/php-fpm.conf"
[global]

error_log = /proc/self/fd/2
include=/etc/php-fpm.d/*.conf

EOF


mkdir --parents "${CONFIG_DIRECTORY}/php-fpm.d"
cat <<EOF > "${CONFIG_DIRECTORY}/php-fpm.d/project.conf"
[project]

user = root
group = root

listen = 9000

; Used by HEALTHCHECK in Dockerfile
ping.path = /ping
ping.response = pong

pm = dynamic
pm.max_children = 10
pm.start_servers = 1
pm.min_spare_servers = 1
pm.max_spare_servers = 3

chdir = /data

access.log = /proc/self/fd/1
access.format = "%R - %u %t \"%m %r\" %s"

php_admin_value[error_log] = /proc/self/fd/2
php_admin_flag[log_errors] = on

php_admin_value[display_errors] = off
php_admin_value[display_startup_errors] = off
php_admin_value[upload_tmp_dir] = /tmp
php_admin_value[session.save_path] = /tmp

EOF

rm --recursive --force /tmp/* 2>/dev/null || true
