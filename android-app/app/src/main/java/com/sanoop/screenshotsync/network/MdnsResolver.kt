package com.sanoop.screenshotsync.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import kotlinx.coroutines.suspendCancellableCoroutine

data class ResolvedMac(val host: String, val port: Int)

private const val SERVICE_TYPE = "_screenshotsync._tcp"
private const val TAG = "MdnsResolver"

/**
 * Browses for the Mac's Bonjour advertisement and resolves the current host/port for the
 * service instance whose TXT `id` matches [targetDeviceId]. This is how the app finds the Mac
 * again after its IP changes, without needing a fresh QR scan — the QR's embedded host/port is
 * only ever used for the very first connection during pairing.
 */
class MdnsResolver(private val context: Context) {

    suspend fun resolve(targetDeviceId: String): ResolvedMac? {
        val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager

        return suspendCancellableCoroutine { continuation ->
            var resolved = false
            lateinit var discoveryListener: NsdManager.DiscoveryListener

            fun finish(result: ResolvedMac?) {
                if (resolved) return
                resolved = true
                runCatching { nsdManager.stopServiceDiscovery(discoveryListener) }
                if (continuation.isActive) continuation.resumeWith(Result.success(result))
            }

            discoveryListener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String) {}

                override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                    nsdManager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                            Log.w(TAG, "Resolve failed for ${info.serviceName}: $errorCode")
                        }

                        override fun onServiceResolved(info: NsdServiceInfo) {
                            val id = info.attributes["id"]?.toString(Charsets.UTF_8)
                            if (id == targetDeviceId) {
                                val host = info.host?.hostAddress
                                if (host != null) finish(ResolvedMac(host, info.port))
                            }
                        }
                    })
                }

                override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
                override fun onDiscoveryStopped(serviceType: String) {}
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                    finish(null)
                }
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            }

            nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)

            continuation.invokeOnCancellation {
                runCatching { nsdManager.stopServiceDiscovery(discoveryListener) }
            }
        }
    }
}
