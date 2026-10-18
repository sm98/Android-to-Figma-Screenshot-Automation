package com.sanoop.screenshotsync.network

import android.os.Build
import com.sanoop.screenshotsync.pairing.PairedMac
import com.sanoop.screenshotsync.pairing.PinnedTrustManager
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

sealed class UploadResult {
    data object Success : UploadResult()
    data object Duplicate : UploadResult()
    data class Failure(val message: String) : UploadResult()
}

/** POSTs one screenshot per PROTOCOL.md's /upload spec, over the same pinned-TLS approach used for pairing. */
object UploadClient {

    fun upload(
        host: String,
        port: Int,
        paired: PairedMac,
        bytes: ByteArray,
        filename: String,
        checksumSha256: String
    ): UploadResult {
        val trustManager = PinnedTrustManager(paired.certFingerprint)
        val client = OkHttpClient.Builder()
            .sslSocketFactory(trustManager.buildSocketFactory(), trustManager)
            .hostnameVerifier { _, _ -> true } // identity already verified by cert-fingerprint pinning above
            .connectTimeout(10, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .build()

        val body = bytes.toRequestBody("image/png".toMediaType())
        val request = Request.Builder()
            .url("https://$host:$port/upload")
            .header("Authorization", "Bearer ${paired.bearerToken}")
            .header("X-Device-Id", Build.MODEL ?: "android-device")
            .header("X-Filename", filename)
            .header("X-Checksum-Sha256", checksumSha256)
            .post(body)
            .build()

        return try {
            client.newCall(request).execute().use { response ->
                val text = response.body?.string().orEmpty()
                when {
                    response.code == 401 -> UploadResult.Failure("Unauthorized (pairing may have been revoked)")
                    !response.isSuccessful -> UploadResult.Failure("HTTP ${response.code}: $text")
                    text.contains("\"duplicate\"") -> UploadResult.Duplicate
                    else -> UploadResult.Success
                }
            }
        } catch (e: Exception) {
            UploadResult.Failure(e.message ?: "Unknown network error")
        }
    }
}
