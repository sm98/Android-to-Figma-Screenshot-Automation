package com.sanoop.screenshotsync.pairing

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

data class PairedMac(
    val macDeviceId: String,
    val macDeviceName: String,
    val bearerToken: String,
    val certFingerprint: String
)

/** Everything needed to reach a paired Mac again: no further QR scan required after this. */
class PairedMacStore(context: Context) {

    private val prefs = run {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "paired_mac",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    fun save(paired: PairedMac) {
        prefs.edit()
            .putString(KEY_DEVICE_ID, paired.macDeviceId)
            .putString(KEY_DEVICE_NAME, paired.macDeviceName)
            .putString(KEY_BEARER_TOKEN, paired.bearerToken)
            .putString(KEY_CERT_FINGERPRINT, paired.certFingerprint)
            .apply()
    }

    fun load(): PairedMac? {
        val deviceId = prefs.getString(KEY_DEVICE_ID, null) ?: return null
        val deviceName = prefs.getString(KEY_DEVICE_NAME, null) ?: return null
        val bearerToken = prefs.getString(KEY_BEARER_TOKEN, null) ?: return null
        val certFingerprint = prefs.getString(KEY_CERT_FINGERPRINT, null) ?: return null
        return PairedMac(deviceId, deviceName, bearerToken, certFingerprint)
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_DEVICE_ID = "mac_device_id"
        private const val KEY_DEVICE_NAME = "mac_device_name"
        private const val KEY_BEARER_TOKEN = "bearer_token"
        private const val KEY_CERT_FINGERPRINT = "cert_fingerprint"
    }
}
