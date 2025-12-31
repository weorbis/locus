package dev.locus.core;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.PowerManager;

import java.util.HashMap;
import java.util.Map;

public class SystemMonitor {
    public interface Listener {
        void onConnectivityChange(Map<String, Object> payload);
        void onPowerSaveChange(boolean enabled);
    }

    private final Context context;
    private final ConnectivityManager connectivityManager;
    private final Listener listener;
    private ConnectivityManager.NetworkCallback networkCallback;
    private BroadcastReceiver powerSaveReceiver;
    private Boolean lastPowerSaveState;

    public SystemMonitor(Context context, Listener listener) {
        this.context = context;
        this.listener = listener;
        this.connectivityManager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
    }

    public void registerConnectivity() {
        if (connectivityManager == null || networkCallback != null) {
            return;
        }
        networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network network) {
                notifyConnectivity();
            }

            @Override
            public void onLost(Network network) {
                notifyConnectivity();
            }

            @Override
            public void onCapabilitiesChanged(Network network, NetworkCapabilities networkCapabilities) {
                notifyConnectivity();
            }
        };
        try {
            connectivityManager.registerDefaultNetworkCallback(networkCallback);
        } catch (Exception ignored) {
        }
    }

    public void unregisterConnectivity() {
        if (connectivityManager != null && networkCallback != null) {
            try {
                connectivityManager.unregisterNetworkCallback(networkCallback);
            } catch (Exception ignored) {
            }
            networkCallback = null;
        }
    }

    public void registerPowerSave() {
        if (powerSaveReceiver != null) {
            return;
        }
        powerSaveReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                boolean enabled = readPowerSaveState();
                if (lastPowerSaveState != null && lastPowerSaveState == enabled) {
                    return;
                }
                lastPowerSaveState = enabled;
                if (listener != null) {
                    listener.onPowerSaveChange(enabled);
                }
            }
        };
        IntentFilter filter = new IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED);
        context.registerReceiver(powerSaveReceiver, filter);
    }

    public void unregisterPowerSave() {
        if (powerSaveReceiver != null) {
            try {
                context.unregisterReceiver(powerSaveReceiver);
            } catch (Exception ignored) {
            }
            powerSaveReceiver = null;
        }
    }

    public Map<String, Object> readConnectivityEvent() {
        Map<String, Object> payload = new HashMap<>();
        boolean connected = false;
        String networkType = "unknown";
        if (connectivityManager != null) {
            Network network = connectivityManager.getActiveNetwork();
            NetworkCapabilities capabilities = connectivityManager.getNetworkCapabilities(network);
            if (capabilities != null) {
                connected = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);
                if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    networkType = "wifi";
                } else if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                    networkType = "cellular";
                } else if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
                    networkType = "ethernet";
                }
            }
        }
        payload.put("connected", connected);
        payload.put("networkType", networkType);
        return payload;
    }

    public boolean readPowerSaveState() {
        PowerManager powerManager = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        if (powerManager == null) {
            return false;
        }
        return powerManager.isPowerSaveMode();
    }

    public boolean isAutoSyncAllowed(ConfigManager config) {
        if (connectivityManager == null) {
            return true;
        }
        Network network = connectivityManager.getActiveNetwork();
        NetworkCapabilities capabilities = connectivityManager.getNetworkCapabilities(network);
        if (capabilities == null || !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            return false;
        }
        if (config.disableAutoSyncOnCellular && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
            return false;
        }
        return true;
    }

    private void notifyConnectivity() {
        if (listener != null) {
            listener.onConnectivityChange(readConnectivityEvent());
        }
    }
}
