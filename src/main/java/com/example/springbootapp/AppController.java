package com.example.springbootapp;

import java.time.Instant;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AppController {

    @Value("${app.name:${spring.application.name:unknown-app}}")
    private String appName;

    @GetMapping("/api/hello")
    public Map<String, String> hello() {
        return Map.of(
                "message", "Hello from Spring Boot 3 on Kind",
                "appName", appName,
                "timestamp", Instant.now().toString()
        );
    }
}