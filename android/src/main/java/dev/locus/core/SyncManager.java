package dev.locus.core;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import dev.locus.storage.LocationStore;
import dev.locus.storage.QueueStore;

public class SyncManager {

    private static final String TAG = "locus";
    private final Context context;
    private final ConfigManager config;
    private final LocationStore locationStore;
    private final QueueStore queueStore;
    private final ExecutorService executor;
    private final SyncListener listener;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public interface SyncListener {
        void onHttpEvent(Map<String, Object> eventData);
        void onLog(String level, String message);
    }

    public SyncManager(Context context, ConfigManager config, LocationStore locationStore, QueueStore queueStore, SyncListener listener) {
        this.context = context;
        this.config = config;
        this.locationStore = locationStore;
        this.queueStore = queueStore;
        this.listener = listener;
        this.executor = Executors.newFixedThreadPool(4);
    }

    public void release() {
        executor.shutdown();
    }

    public void syncNow(Map<String, Object> currentPayload) {
        if (config.httpUrl == null || config.httpUrl.isEmpty()) {
            return;
        }
        if (config.batchSync) {
            syncStoredLocations(config.maxBatchSize);
            return;
        }
        if (currentPayload != null) {
            enqueueHttp(currentPayload, null, 0);
        }
    }
    
    public void attemptBatchSync() {
        int threshold = config.autoSyncThreshold > 0 ? config.autoSyncThreshold : config.maxBatchSize;
        if (threshold <= 0) {
            threshold = config.maxBatchSize;
        }
        int fetchLimit = Math.max(threshold, config.maxBatchSize);
        List<Map<String, Object>> records = locationStore.readLocations(fetchLimit);
        if (records.size() < threshold) {
            return;
        }
        int sendCount = Math.min(config.maxBatchSize, records.size());
        List<Map<String, Object>> batch = records.subList(0, sendCount);
        List<Map<String, Object>> payloads = new ArrayList<>();
        List<String> ids = new ArrayList<>();
        for (Map<String, Object> record : batch) {
            Map<String, Object> payload = buildPayloadFromRecord(record);
            if (!payload.isEmpty()) {
                payloads.add(payload);
            }
            Object id = record.get("id");
            if (id instanceof String) {
                ids.add((String) id);
            }
        }
        if (!payloads.isEmpty()) {
            enqueueHttpBatch(payloads, ids, 0);
        }
    }

    public void syncStoredLocations(int limit) {
        if (limit <= 0) {
            limit = config.maxBatchSize;
        }
        List<Map<String, Object>> records = locationStore.readLocations(limit);
        if (records.isEmpty()) {
            return;
        }
        List<Map<String, Object>> payloads = new ArrayList<>();
        List<String> ids = new ArrayList<>();
        for (Map<String, Object> record : records) {
            Map<String, Object> payload = buildPayloadFromRecord(record);
            if (!payload.isEmpty()) {
                payloads.add(payload);
            }
            Object id = record.get("id");
            if (id instanceof String) {
                ids.add((String) id);
            }
        }
        if (!payloads.isEmpty()) {
            enqueueHttpBatch(payloads, ids, 0);
        }
    }
    
    public int syncQueue(int limit) {
        if (config.httpUrl == null || config.httpUrl.isEmpty()) {
            return 0;
        }
        int fetchLimit = limit > 0 ? limit : config.maxBatchSize;
        List<Map<String, Object>> records = queueStore.readQueue(fetchLimit);
        int scheduled = 0;
        long now = System.currentTimeMillis();
        for (Map<String, Object> record : records) {
            Object nextRetryAt = record.get("nextRetryAt");
            if (nextRetryAt instanceof Number && ((Number) nextRetryAt).longValue() > now) {
                continue;
            }
            String id = record.get("id") instanceof String ? (String) record.get("id") : null;
            String payloadJson = record.get("payload") instanceof String ? (String) record.get("payload") : null;
            if (id == null || payloadJson == null) {
                continue;
            }
            try {
                Map<String, Object> payload = QueueStore.parsePayload(payloadJson);
                String type = record.get("type") instanceof String ? (String) record.get("type") : null;
                String key = record.get("idempotencyKey") instanceof String
                        ? (String) record.get("idempotencyKey")
                        : UUID.randomUUID().toString();
                int retryCount = record.get("retryCount") instanceof Number
                        ? ((Number) record.get("retryCount")).intValue()
                        : 0;
                enqueueQueueHttp(payload, id, type, key, retryCount);
                scheduled += 1;
            } catch (JSONException ignored) {
            }
        }
        return scheduled;
    }

    public void enqueueHttp(Map<String, Object> locationPayload, List<String> idsToDelete, int attempt) {
        executor.execute(() -> {
            try {
                JSONObject body = buildHttpBody(locationPayload, null);
                for (Map.Entry<String, Object> entry : config.httpParams.entrySet()) {
                    body.put(entry.getKey(), entry.getValue());
                }

                HttpURLConnection connection = (HttpURLConnection) new URL(config.httpUrl).openConnection();
                connection.setRequestMethod(config.httpMethod);
                connection.setConnectTimeout(config.httpTimeoutMs);
                connection.setReadTimeout(config.httpTimeoutMs);
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json");
                for (Map.Entry<String, Object> header : config.httpHeaders.entrySet()) {
                    connection.setRequestProperty(header.getKey(), String.valueOf(header.getValue()));
                }

                OutputStream output = connection.getOutputStream();
                output.write(body.toString().getBytes());
                output.flush();
                output.close();

                int status = connection.getResponseCode();
                java.io.InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
                if (stream == null) {
                    stream = new java.io.ByteArrayInputStream("".getBytes());
                }
                BufferedReader reader = new BufferedReader(new InputStreamReader(stream));
                StringBuilder responseText = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    responseText.append(line);
                }
                reader.close();

                boolean ok = status >= 200 && status < 300;
                if (ok && idsToDelete != null && !idsToDelete.isEmpty()) {
                    locationStore.deleteLocations(idsToDelete);
                }
                Map<String, Object> httpEvent = new HashMap<>();
                httpEvent.put("type", "http");
                Map<String, Object> data = new HashMap<>();
                data.put("status", status);
                data.put("ok", ok);
                data.put("responseText", responseText.toString());
                httpEvent.put("data", data);
                if (listener != null) listener.onHttpEvent(httpEvent);
                log("info", "http " + status);
                if (!ok) {
                    scheduleHttpRetry(locationPayload, idsToDelete, attempt + 1);
                }
            } catch (Exception e) {
                Log.e(TAG, "HTTP sync failed: " + e.getMessage());
                Map<String, Object> httpEvent = new HashMap<>();
                httpEvent.put("type", "http");
                Map<String, Object> data = new HashMap<>();
                data.put("status", 0);
                data.put("ok", false);
                data.put("responseText", e.getMessage());
                httpEvent.put("data", data);
                if (listener != null) listener.onHttpEvent(httpEvent);
                log("error", "http error " + e.getMessage());
                scheduleHttpRetry(locationPayload, idsToDelete, attempt + 1);
            }
        });
    }

    private void enqueueHttpBatch(List<Map<String, Object>> payloads, List<String> idsToDelete, int attempt) {
        executor.execute(() -> {
            try {
                JSONObject body = buildHttpBody(null, payloads);
                for (Map.Entry<String, Object> entry : config.httpParams.entrySet()) {
                    body.put(entry.getKey(), entry.getValue());
                }

                HttpURLConnection connection = (HttpURLConnection) new URL(config.httpUrl).openConnection();
                connection.setRequestMethod(config.httpMethod);
                connection.setConnectTimeout(config.httpTimeoutMs);
                connection.setReadTimeout(config.httpTimeoutMs);
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json");
                for (Map.Entry<String, Object> header : config.httpHeaders.entrySet()) {
                    connection.setRequestProperty(header.getKey(), String.valueOf(header.getValue()));
                }

                OutputStream output = connection.getOutputStream();
                output.write(body.toString().getBytes());
                output.flush();
                output.close();

                int status = connection.getResponseCode();
                java.io.InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
                if (stream == null) {
                    stream = new java.io.ByteArrayInputStream("".getBytes());
                }
                BufferedReader reader = new BufferedReader(new InputStreamReader(stream));
                StringBuilder responseText = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    responseText.append(line);
                }
                reader.close();

                boolean ok = status >= 200 && status < 300;
                if (ok && idsToDelete != null && !idsToDelete.isEmpty()) {
                    locationStore.deleteLocations(idsToDelete);
                }
                Map<String, Object> httpEvent = new HashMap<>();
                httpEvent.put("type", "http");
                Map<String, Object> data = new HashMap<>();
                data.put("status", status);
                data.put("ok", ok);
                data.put("responseText", responseText.toString());
                httpEvent.put("data", data);
                if (listener != null) listener.onHttpEvent(httpEvent);
                log("info", "http " + status);
                if (!ok) {
                    scheduleBatchRetry(payloads, idsToDelete, attempt + 1);
                }
            } catch (Exception e) {
                Log.e(TAG, "HTTP sync failed: " + e.getMessage());
                Map<String, Object> httpEvent = new HashMap<>();
                httpEvent.put("type", "http");
                Map<String, Object> data = new HashMap<>();
                data.put("status", 0);
                data.put("ok", false);
                data.put("responseText", e.getMessage());
                httpEvent.put("data", data);
                if (listener != null) listener.onHttpEvent(httpEvent);
                log("error", "http error " + e.getMessage());
                scheduleBatchRetry(payloads, idsToDelete, attempt + 1);
            }
        });
    }

    private void enqueueQueueHttp(Map<String, Object> payload, String id, String type, String idempotencyKey, int attempt) {
        executor.execute(() -> {
            try {
                JSONObject body = buildQueueBody(payload, id, type, idempotencyKey);
                for (Map.Entry<String, Object> entry : config.httpParams.entrySet()) {
                    body.put(entry.getKey(), entry.getValue());
                }

                HttpURLConnection connection = (HttpURLConnection) new URL(config.httpUrl).openConnection();
                connection.setRequestMethod(config.httpMethod);
                connection.setConnectTimeout(config.httpTimeoutMs);
                connection.setReadTimeout(config.httpTimeoutMs);
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json");
                for (Map.Entry<String, Object> header : config.httpHeaders.entrySet()) {
                    connection.setRequestProperty(header.getKey(), String.valueOf(header.getValue()));
                }
                if (config.idempotencyHeader != null && idempotencyKey != null) {
                    connection.setRequestProperty(config.idempotencyHeader, idempotencyKey);
                }

                OutputStream output = connection.getOutputStream();
                output.write(body.toString().getBytes());
                output.flush();
                output.close();

                int status = connection.getResponseCode();
                java.io.InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
                if (stream == null) {
                    stream = new java.io.ByteArrayInputStream("".getBytes());
                }
                BufferedReader reader = new BufferedReader(new InputStreamReader(stream));
                StringBuilder responseText = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    responseText.append(line);
                }
                reader.close();

                boolean ok = status >= 200 && status < 300;
                if (ok) {
                    List<String> ids = new ArrayList<>();
                    ids.add(id);
                    queueStore.deleteByIds(ids);
                }
                Map<String, Object> httpEvent = new HashMap<>();
                httpEvent.put("type", "http");
                Map<String, Object> data = new HashMap<>();
                data.put("status", status);
                data.put("ok", ok);
                data.put("responseText", responseText.toString());
                httpEvent.put("data", data);
                if (listener != null) listener.onHttpEvent(httpEvent);
                log("info", "http " + status);
                if (!ok) {
                    scheduleQueueRetry(payload, id, type, idempotencyKey, attempt + 1);
                }
            } catch (Exception e) {
                Log.e(TAG, "Queue HTTP sync failed: " + e.getMessage());
                Map<String, Object> httpEvent = new HashMap<>();
                httpEvent.put("type", "http");
                Map<String, Object> data = new HashMap<>();
                data.put("status", 0);
                data.put("ok", false);
                data.put("responseText", e.getMessage());
                httpEvent.put("data", data);
                if (listener != null) listener.onHttpEvent(httpEvent);
                log("error", "http error " + e.getMessage());
                scheduleQueueRetry(payload, id, type, idempotencyKey, attempt + 1);
            }
        });
    }

    private JSONObject buildHttpBody(Map<String, Object> locationPayload, List<Map<String, Object>> locations) throws JSONException {
        JSONObject body = new JSONObject();
        if (locations != null) {
            JSONArray list = new JSONArray();
            for (Map<String, Object> payload : locations) {
                list.put(new JSONObject(payload));
            }
            if (config.httpRootProperty != null && !config.httpRootProperty.isEmpty()) {
                body.put(config.httpRootProperty, list);
            } else {
                body.put("locations", list);
            }
        } else if (locationPayload != null) {
            JSONObject payload = new JSONObject(locationPayload);
            if (config.httpRootProperty != null && !config.httpRootProperty.isEmpty()) {
                body.put(config.httpRootProperty, payload);
            } else {
                body.put("location", payload);
            }
        }
        return body;
    }

    private JSONObject buildQueueBody(Map<String, Object> payload, String id, String type, String idempotencyKey) throws JSONException {
        JSONObject body = new JSONObject();
        JSONObject payloadJson = new JSONObject(payload);
        if (config.httpRootProperty != null && !config.httpRootProperty.isEmpty()) {
            body.put(config.httpRootProperty, payloadJson);
        } else {
            body.put("payload", payloadJson);
        }
        body.put("queueId", id);
        if (type != null) {
            body.put("type", type);
        }
        if (idempotencyKey != null) {
            body.put("idempotencyKey", idempotencyKey);
        }
        return body;
    }

    private void scheduleBatchRetry(List<Map<String, Object>> payloads, List<String> idsToDelete, int attempt) {
        if (attempt > config.maxRetry || config.httpUrl == null || config.httpUrl.isEmpty()) {
            return;
        }
        long delay = (long) (config.retryDelayMs * Math.pow(config.retryDelayMultiplier, Math.max(0, attempt - 1)));
        if (delay > config.maxRetryDelayMs) {
            delay = config.maxRetryDelayMs;
        }
        long finalDelay = Math.max(delay, config.retryDelayMs);
        mainHandler.postDelayed(() -> enqueueHttpBatch(payloads, idsToDelete, attempt), finalDelay);
    }

    private void scheduleHttpRetry(Map<String, Object> payload, List<String> idsToDelete, int attempt) {
        if (attempt > config.maxRetry || config.httpUrl == null || config.httpUrl.isEmpty()) {
            return;
        }
        long delay = (long) (config.retryDelayMs * Math.pow(config.retryDelayMultiplier, Math.max(0, attempt - 1)));
        if (delay > config.maxRetryDelayMs) {
            delay = config.maxRetryDelayMs;
        }
        long finalDelay = Math.max(delay, config.retryDelayMs);
        mainHandler.postDelayed(() -> enqueueHttp(payload, idsToDelete, attempt), finalDelay);
    }

    private void scheduleQueueRetry(Map<String, Object> payload, String id, String type, String idempotencyKey, int attempt) {
        if (attempt > config.maxRetry || config.httpUrl == null || config.httpUrl.isEmpty()) {
            return;
        }
        long delay = (long) (config.retryDelayMs * Math.pow(config.retryDelayMultiplier, Math.max(0, attempt - 1)));
        if (delay > config.maxRetryDelayMs) {
            delay = config.maxRetryDelayMs;
        }
        long finalDelay = Math.max(delay, config.retryDelayMs);
        long nextRetryAt = System.currentTimeMillis() + finalDelay;
        queueStore.updateRetry(id, attempt, nextRetryAt);
        mainHandler.postDelayed(() -> enqueueQueueHttp(payload, id, type, idempotencyKey, attempt), finalDelay);
    }
    
    private void log(String level, String message) {
        if (listener != null) {
            listener.onLog(level, message);
        }
    }
    
    public Map<String, Object> buildPayloadFromRecord(Map<String, Object> record) {
        Map<String, Object> payload = new HashMap<>();
        if (record == null) {
            return payload;
        }
        Object id = record.get("id");
        Object timestampValue = record.get("timestamp");
        Object latitude = record.get("latitude");
        Object longitude = record.get("longitude");
        Object accuracy = record.get("accuracy");
        Object speed = record.get("speed");
        Object heading = record.get("heading");
        Object altitude = record.get("altitude");
        if (latitude == null || longitude == null || accuracy == null || timestampValue == null) {
            return payload;
        }
        Map<String, Object> coords = new HashMap<>();
        coords.put("latitude", latitude);
        coords.put("longitude", longitude);
        coords.put("accuracy", accuracy);
        coords.put("speed", speed);
        coords.put("heading", heading);
        coords.put("altitude", altitude);

        Map<String, Object> activity = new HashMap<>();
        Object activityType = record.get("activity_type");
        if (activityType instanceof String) {
            activity.put("type", activityType);
        }
        Object activityConfidence = record.get("activity_confidence");
        if (activityConfidence instanceof Number) {
            activity.put("confidence", ((Number) activityConfidence).intValue());
        }

        payload.put("uuid", id instanceof String ? id : UUID.randomUUID().toString());
        long timestamp = timestampValue instanceof Number ? ((Number) timestampValue).longValue() : System.currentTimeMillis();
        payload.put("timestamp", Instant.ofEpochMilli(timestamp).toString());
        payload.put("coords", coords);
        if (!activity.isEmpty()) {
            payload.put("activity", activity);
        }
        payload.put("event", record.get("event"));
        payload.put("is_moving", record.get("is_moving"));
        if (record.get("odometer") != null) {
            payload.put("odometer", record.get("odometer"));
        }
        return payload;
    }
}
