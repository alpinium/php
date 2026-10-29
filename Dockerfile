ARG DEBIAN_CODENAME=""
ARG PHP_VERSION=""

FROM debian:${DEBIAN_CODENAME}-slim AS build

ARG DEBIAN_CODENAME
ENV DEBIAN_CODENAME=${DEBIAN_CODENAME}
ARG PHP_VERSION
ENV PHP_VERSION=${PHP_VERSION}

RUN --mount=type=bind,source=build_script.sh,target=/mnt/docker/build_script.sh \
    --mount=type=bind,source=configuration.yaml,target=/mnt/docker/configuration.yaml \
    bash /mnt/docker/build_script.sh

RUN --mount=type=bind,source=configure_script.sh,target=/mnt/docker/configure_script.sh \
    bash /mnt/docker/configure_script.sh

FROM debian:${DEBIAN_CODENAME}-slim

ARG DEBIAN_CODENAME
ENV DEBIAN_CODENAME=${DEBIAN_CODENAME}
ARG PHP_VERSION
ENV PHP_VERSION=${PHP_VERSION}

COPY --from=build /output/ /

RUN --mount=type=bind,from=build,source=/mnt/docker/variables.sh,target=/mnt/docker/variables.sh \
    --mount=type=bind,source=install_script.sh,target=/mnt/docker/install_script.sh \
    bash /mnt/docker/install_script.sh

VOLUME /data

EXPOSE 9000

SHELL ["/bin/bash", "-c"]

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 | grep --quiet pong

CMD ["/usr/local/sbin/php-fpm", "--allow-to-run-as-root", "--nodaemonize"]

ARG VCS_REF
ARG BUILD_DATE
ARG SOURCE_URL=https://github.com/alpinium/php
ARG PHP_MAJOR
ARG DEBIAN_RELEASE
ARG DEBIAN_POINT_RELEASE

LABEL org.opencontainers.image.title="php" \
      org.opencontainers.image.description="PHP image for Alpinium projects" \
      org.opencontainers.image.vendor="Alpinium Tech" \
      org.opencontainers.image.authors="Alpinium Tech <alpinium@alpinium.tech>" \
      org.opencontainers.image.url="https://hub.docker.com/r/alpiniumtech/php" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.documentation="${SOURCE_URL}#readme" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${PHP_VERSION}-${DEBIAN_CODENAME}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="docker.io/library/debian:${DEBIAN_CODENAME}-slim" \
      php.version="${PHP_VERSION}" \
      php.major="${PHP_MAJOR}" \
      debian.codename="${DEBIAN_CODENAME}" \
      debian.release="${DEBIAN_RELEASE}" \
      debian.point-release="${DEBIAN_POINT_RELEASE}"
