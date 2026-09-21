FROM docker:27-cli AS docker_cli

FROM mcr.microsoft.com/playwright:v1.51.1-jammy

USER root
COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

RUN docker --version && docker compose version

USER pwuser
