package com.example.app;

import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Exposes the service's two operational endpoints: {@code /health} for
 * liveness checks and {@code /version} for build provenance.
 */
@RestController
public class HealthController {

    /** Process start time, used to report uptime on /health. */
    private final Instant startedAt = Instant.now();

    /** Application version, injected from the Maven project version. */
    private final String version;

    /** Git commit the running artifact was built from. */
    private final String commit;

    /**
     * Creates the controller with build metadata supplied by configuration.
     *
     * @param appVersion   the application version
     * @param buildCommit  the source commit identifier
     */
    public HealthController(
            @Value("${app.version:unknown}") final String appVersion,
            @Value("${app.commit:unknown}") final String buildCommit) {
        this.version = appVersion;
        this.commit = buildCommit;
    }

    /**
     * Reports service liveness and how long the process has been running.
     *
     * @return a map rendered as the health JSON document
     */
    @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
    public Map<String, Object> health() {
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", "UP");
        body.put("uptimeSeconds", Duration.between(startedAt, Instant.now()).getSeconds());
        body.put("checkedAt", Instant.now().toString());
        return body;
    }

    /**
     * Reports the version and commit of the running artifact.
     *
     * @return a map rendered as the version JSON document
     */
    @GetMapping(value = "/version", produces = MediaType.APPLICATION_JSON_VALUE)
    public Map<String, Object> version() {
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("version", version);
        body.put("commit", commit);
        body.put("javaVersion", System.getProperty("java.version"));
        return body;
    }
}
