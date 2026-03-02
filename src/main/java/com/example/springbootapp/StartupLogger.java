package com.example.springbootapp;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
public class StartupLogger implements ApplicationRunner {

    private static final Logger logger = LoggerFactory.getLogger(StartupLogger.class);

    @Value("${app.name:${spring.application.name:unknown-app}}")
    private String appName;

    @Value("${spring.profiles.active:default}")
    private String activeProfile;

    @Override
    public void run(ApplicationArguments args) {
        logger.info("Application started with app.name='{}' and profile='{}'", appName, activeProfile);
    }
}