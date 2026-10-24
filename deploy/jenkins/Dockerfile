# syntax=docker/dockerfile:1.7
#
FROM docker:28.5.2-cli AS dockercli
FROM jenkins/jenkins:latest-jdk25

USER root
ARG DOCKER_GID=998

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git \
  && rm -rf /var/lib/apt/lists/* \
  && case "${DOCKER_GID}" in *[!0-9]*|'') echo "DOCKER_GID must be numeric" >&2; exit 1;; esac \
  && if getent group "${DOCKER_GID}" >/dev/null; then DOCKER_GROUP="$(getent group "${DOCKER_GID}" | cut -d: -f1)"; else groupadd -g "${DOCKER_GID}" docker; DOCKER_GROUP=docker; fi \
  && usermod -aG "${DOCKER_GROUP}" jenkins

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

RUN mkdir -p /usr/local/lib/docker/cli-plugins \
  && chown -R jenkins:jenkins /usr/local/lib/docker
USER jenkins
