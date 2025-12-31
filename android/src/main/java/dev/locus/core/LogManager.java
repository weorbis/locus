package dev.locus.core;

import dev.locus.storage.LogStore;

public class LogManager {
    private final ConfigManager config;
    private final LogStore logStore;

    public LogManager(ConfigManager config, LogStore logStore) {
        this.config = config;
        this.logStore = logStore;
    }

    public void log(String level, String message) {
        if (!shouldLog(level)) {
            return;
        }
        logStore.append(level, message, config.logMaxDays);
    }

    private boolean shouldLog(String level) {
        return logLevelRank(level) <= logLevelRank(config.logLevel);
    }

    private int logLevelRank(String level) {
        switch (level) {
            case "off":
                return 6;
            case "error":
                return 0;
            case "warning":
                return 1;
            case "info":
                return 2;
            case "debug":
                return 3;
            case "verbose":
                return 4;
            default:
                return 3;
        }
    }
}
