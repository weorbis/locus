package dev.locus.core

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.PowerManager

class SystemMonitor(
    private val context: Context,
    private val listener: Listener?
) {
    interface Listener {
        fun onConnectivityChange(payload: Map<String, Any>)
        fun onPowerSaveChange(enabled: Boolean)
    }

    private val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var powerSaveReceiver: BroadcastReceiver? = null
    private var lastPowerSaveState: Boolean? = null

    fun registerConnectivity() {
        if (connectivityManager == null || networkCallback != null) return
        
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                notifyConnectivity()
            }

            override fun onLost(network: Network) {
                notifyConnectivity()
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                notifyConnectivity()
            }
        }
        
        runCatching {
            connectivityManager?.registerDefaultNetworkCallback(networkCallback!!)
        }
    }

    fun unregisterConnectivity() {
        networkCallback?.let { callback ->
            runCatching {
                connectivityManager?.unregisterNetworkCallback(callback)
            }
            networkCallback = null
        }
    }

    fun registerPowerSave() {
        if (powerSaveReceiver != null) return
        
        powerSaveReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val enabled = readPowerSaveState()
                if (lastPowerSaveState == enabled) return
                
                lastPowerSaveState = enabled
                listener?.onPowerSaveChange(enabled)
            }
        }
        
        val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        context.registerReceiver(powerSaveReceiver, filter)
    }

    fun unregisterPowerSave() {
        powerSaveReceiver?.let { receiver ->
            runCatching {
                context.unregisterReceiver(receiver)
            }
            powerSaveReceiver = null
        }
    }

    fun readConnectivityEvent(): Map<String, Any> {
        var connected = false
        var networkType = "unknown"
        
        connectivityManager?.let { cm ->
            val network = cm.activeNetwork ?: return@let
            val capabilities = cm.getNetworkCapabilities(network)
            
            capabilities?.let { caps ->
                connected = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                networkType = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                    else -> "unknown"
                }
            }
        }
        
        return mapOf(
            "connected" to connected,
            "networkType" to networkType
        )
    }

    fun readPowerSaveState(): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return powerManager.isPowerSaveMode
    }

    fun isAutoSyncAllowed(config: ConfigManager): Boolean {
        connectivityManager ?: return true
        
        val network = connectivityManager.activeNetwork
        val capabilities = connectivityManager.getNetworkCapabilities(network)
        
        if (capabilities == null || !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            return false
        }
        
        if (config.disableAutoSyncOnCellular && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
            return false
        }
        
        return true
    }

    private fun notifyConnectivity() {
        listener?.onConnectivityChange(readConnectivityEvent())
    }
}
