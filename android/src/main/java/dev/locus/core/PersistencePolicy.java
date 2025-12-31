package dev.locus.core;

final class PersistencePolicy {
    private PersistencePolicy() {}

    static boolean shouldPersist(ConfigManager config, String eventName) {
        if (config.batchSync) {
            return true;
        }
        if ("none".equals(config.persistMode)) {
            return false;
        }
        if ("all".equals(config.persistMode)) {
            return true;
        }
        if ("geofence".equals(config.persistMode)) {
            return "geofence".equals(eventName);
        }
        return "location".equals(config.persistMode) && !"geofence".equals(eventName);
    }
}
