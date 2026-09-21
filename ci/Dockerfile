FROM eclipse-temurin:21-jdk-jammy AS jdk
FROM docker:27-cli AS docker_cli

FROM node:20-bookworm

# Install Java at image-build time, not into Jenkins' shared tool cache.
COPY --from=jdk /opt/java/openjdk /opt/java/openjdk
# The E2E stage uses this already-allocated build container to start Compose
# and then runs Playwright in a sibling container.  This avoids requesting a
# second linux-build executor while the pipeline agent is still occupied.
COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Verify the JDK also works as the non-root Jenkins build user.
USER 1000:1000
RUN java -version && node --version && npm --version && docker --version && docker compose version
