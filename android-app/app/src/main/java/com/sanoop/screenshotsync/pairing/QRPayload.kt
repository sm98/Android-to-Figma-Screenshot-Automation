package com.sanoop.screenshotsync.pairing

import org.json.JSONObject

/** Mirrors the pairing QR JSON schema the Mac app encodes, per PROTOCOL.md. */
data class QRPayload(
    val v: Int,
    val deviceId: String,
    val deviceName: String,
    val host: String,
    val port: Int,
    val certFingerprint: String,
    val pairToken: String
) {
    companion object {
        fun parse(json: String): QRPayload? = try {
            val obj = JSONObject(json)
            QRPayload(
                v = obj.getInt("v"),
                deviceId = obj.getString("deviceId"),
                deviceName = obj.getString("deviceName"),
                host = obj.getString("host"),
                port = obj.getInt("port"),
                certFingerprint = obj.getString("certFingerprint"),
                pairToken = obj.getString("pairToken")
            )
        } catch (e: Exception) {
            null
        }
    }
}
