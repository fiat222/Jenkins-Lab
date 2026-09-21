FROM eclipse-temurin:21-jdk-jammy AS jdk

FROM node:20-bookworm

# Install Java at image-build time, not into Jenkins' shared tool cache.
COPY --from=jdk /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Verify the JDK also works as the non-root Jenkins build user.
USER 1000:1000
RUN java -version && node --version && npm --version
