# Health Check Service

A tiny Spring Boot service that reports its own liveness and build provenance.
It exists to be the thing you point a monitor at — and to be a complete,
working example of a hardened delivery pipeline around a trivial application.

| Endpoint   | Returns |
|------------|---------|
| `GET /`        | HTML landing page linking both endpoints |
| `GET /health`  | `{"status":"UP","uptimeSeconds":…,"checkedAt":…}` |
| `GET /version` | `{"version":…,"commit":…,"javaVersion":…}` |

## Architecture

Public traffic reaches nginx on port 80, which proxies to the application
container listening on `127.0.0.1:8080`. The container image is built and
vulnerability-scanned in CI, then pulled from GHCR onto the instance. The
application port is never exposed in the security group.

- Architecture source: [`.udap/architecture.d2`](.udap/architecture.d2)
- Pipeline diagram: [`docs/pipeline.d2`](docs/pipeline.d2)

Render either diagram locally with [d2](https://d2lang.com):

```bash
d2 .udap/architecture.d2 architecture.svg
d2 docs/pipeline.d2 pipeline.svg
```

## Running locally

Requires JDK 17 and Maven.

```bash
mvn spring-boot:run
curl localhost:8080/health
curl localhost:8080/version
```

Run the full quality suite exactly as CI does:

```bash
mvn checkstyle:check          # style gate
mvn verify                    # JUnit tests + JaCoCo 70% line coverage gate
mvn spotbugs:check            # static analysis
mvn dependency-check:check    # OWASP, fails on CVSS >= 7
```

Or run the container:

```bash
docker build -t health-check-service .
docker run --rm -p 8080:8080 health-check-service
```

## How it deploys

The pipeline is defined in [`.udap/pipeline.yaml`](.udap/pipeline.yaml); the
GitHub Actions workflows are rendered from it — edit the spec, not the
workflow files.

| Stage | What it does | Fails the build when |
|-------|--------------|----------------------|
| `lint` | Checkstyle against `checkstyle.xml` | any style violation |
| `test` | JUnit 5 tests, JaCoCo coverage, SpotBugs | a test fails, line coverage < 70%, or a Medium+ bug pattern |
| `security` | OWASP Dependency Check | a dependency CVE scores CVSS >= 7 |
| `build_push` | Multi-stage Docker build, Trivy scan, push to GHCR | HIGH/CRITICAL fixable image vulnerability |
| `provision` | `terraform apply` — EC2, Elastic IP, security group | any apply error |
| `configure` | `puppet apply` — Docker, nginx, run the image | any Puppet resource failure |
| `verify` | Smoke tests against the live Elastic IP | `/health` is not `UP`, `/version` lacks build metadata, or `/` does not serve |

Deployment is automatic: the pipeline runs through to `verify`, and the run is
only green once the live instance answers all three smoke tests.

## Configuration

No secret values live in this repository. These are supplied by the platform
as CI secrets.

| Name | Purpose | Source |
|------|---------|--------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Terraform provider auth | platform |
| `TF_STATE_BUCKET` | Remote terraform state bucket | platform |
| `PROJECT_NAME` | Resource name prefix and state key | platform |
| `SSH_USER` / `SSH_PRIVATE_KEY` / `SSH_PUBLIC_KEY` | Instance access for the configure stage | platform |
| `GITHUB_TOKEN` | GHCR push and pull | GitHub Actions |

Application settings live in
[`src/main/resources/application.properties`](src/main/resources/application.properties).
`APP_COMMIT` is injected into the container at run time and surfaces on
`/version`.

## Operations

The public address is the Elastic IP from the `public_ip` terraform output
(set after the first deploy). SSH in as the `SSH_USER` for the instance's OS.

```bash
# application logs
sudo docker logs -f health-check-service

# restart the application
sudo docker restart health-check-service

# what image is actually running
sudo docker inspect -f '{{.Config.Image}}' health-check-service

# nginx status and configuration test
sudo systemctl status nginx
sudo nginx -t
```

Re-applying the Puppet manifest is safe and idempotent: every exec is guarded,
so an unchanged apply makes no changes and causes no downtime.

### Rollback

The pipeline's rollback strategy is `rerun`. Redeploying an earlier commit
rebuilds and re-pulls that commit's image tag; the Puppet manifest replaces the
running container only when the image reference actually differs.

### Teardown

Destroying the project runs `.github/workflows/destroy.yml`, which executes
`terraform destroy` against the same remote state. The repository and its
configuration survive a teardown, so redeploying later needs no re-scaffolding.

## Project layout

```
src/main/java/com/example/app/   Application.java, HealthController.java
src/test/java/com/example/app/   ApplicationTests.java
src/main/resources/              application.properties, static/index.html
infra/                           Terraform: EC2, Elastic IP, security group
puppet/manifests/site.pp         Masterless Puppet: Docker, nginx, container
Dockerfile                       Multi-stage build, non-root, HEALTHCHECK
checkstyle.xml                   Checkstyle ruleset
.udap/pipeline.yaml              Pipeline spec (workflows render from this)
.udap/architecture.d2            Architecture source of truth
docs/pipeline.d2                 Pipeline diagram
```
