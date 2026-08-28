package com.example.app;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Verifies the two operational endpoints and that the context loads.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ApplicationTests {

    /** Injected MVC test client. */
    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("application context loads")
    void contextLoads() {
        // Context startup failure fails this test.
    }

    @Test
    @DisplayName("/health reports UP with an uptime value")
    void healthReportsUp() throws Exception {
        mockMvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.uptimeSeconds").isNumber())
                .andExpect(jsonPath("$.checkedAt").isNotEmpty());
    }

    @Test
    @DisplayName("/version reports version, commit and java version")
    void versionReportsBuildMetadata() throws Exception {
        mockMvc.perform(get("/version"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.version").isNotEmpty())
                .andExpect(jsonPath("$.commit").isNotEmpty())
                .andExpect(jsonPath("$.javaVersion").isNotEmpty());
    }

    @Test
    @DisplayName("unknown routes return 404")
    void unknownRouteReturnsNotFound() throws Exception {
        mockMvc.perform(get("/no-such-endpoint"))
                .andExpect(status().isNotFound());
    }
}
