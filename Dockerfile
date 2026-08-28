# syntax=docker/dockerfile:1

# ---- build stage: compile and package the jar ----
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /build

# Dependency layer first: re-resolved only when the POM changes.
COPY pom.xml ./
RUN mvn -B --no-transfer-progress dependency:go-offline

# Source layer: changes on every commit, so it comes last.
COPY checkstyle.xml ./
COPY src ./src
RUN mvn -B --no-transfer-progress package -DskipTests

# ---- runtime stage: JRE only, no build toolchain in the shipped image ----
FROM eclipse-temurin:17-jre-alpine

# Base images lag Alpine's package index by days to weeks, so the shipped
# openssl/libssl3/libcrypto3 are routinely a patch release behind and fail the
# Trivy fixable-CVE gate (e.g. CVE-2026-14456: 3.5.7-r0 -> 3.5.8-r0).
# Upgrading here picks up OS security patches on every rebuild instead of
# pinning a base tag that goes stale again next month.
# curl is required by the HEALTHCHECK below.
RUN apk upgrade --no-cache && apk add --no-cache curl

# Run as a dedicated non-root user (CIS Docker 4.1).
RUN addgroup -S app && adduser -S -G app app

WORKDIR /app
COPY --from=build --chown=app:app /build/target/app.jar /app/app.jar

USER app

# Inside the container the app must listen on all interfaces; the container
# network boundary replaces the loopback-only binding used on a bare host.
ENV SERVER_ADDRESS=0.0.0.0
ENV SERVER_PORT=8080
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
