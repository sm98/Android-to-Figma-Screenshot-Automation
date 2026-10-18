package com.sanoop.screenshotsync.pairing

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

sealed class PairingResult {
    data class Success(val paired: PairedMac) : PairingResult()
    data class Failure(val message: String) : PairingResult()
}

/** Performs the one-time /pair handshake described in PROTOCOL.md. Blocking — call off the main thread. */
object PairingClient {

    fun pair(payload: QRPayload, androidDeviceName: String): PairingResult {
        val trustManager = PinnedTrustManager(payload.certFingerprint)
        val client = OkHttpClient.Builder()
            .sslSocketFactory(trustManager.buildSocketFactory(), trustManager)
            .hostnameVerifier { _, _ -> true } // identity is already verified by cert-fingerprint pinning above
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val bodyJson = JSONObject().apply {
            put("pairToken", payload.pairToken)
            put("androidDeviceName", androidDeviceName)
        }
        val body = bodyJson.toString().toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("https://${payload.host}:${payload.port}/pair")
            .post(body)
            .build()

        return try {
            client.newCall(request).execute().use { response ->
                val text = response.body?.string().orEmpty()
                if (!response.isSuccessful) {
                    return PairingResult.Failure("Mac rejected pairing (HTTP ${response.code}): $text")
                }
                val json = JSONObject(text)
                PairingResult.Success(
                    PairedMac(
                        macDeviceId = json.getString("deviceId"),
                        macDeviceName = json.getString("macDeviceName"),
                        bearerToken = json.getString("bearerToken"),
                        certFingerprint = payload.certFingerprint
                    )
                )
            }
        } catch (e: Exception) {
            PairingResult.Failure(e.message ?: "Unknown error connecting to Mac")
        }
    }
}
