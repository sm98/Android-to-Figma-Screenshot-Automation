package com.sanoop.screenshotsync.data

import android.content.Context
import android.net.Uri
import android.util.Log
import com.sanoop.screenshotsync.network.MdnsResolver
import com.sanoop.screenshotsync.network.UploadClient
import com.sanoop.screenshotsync.network.UploadResult
import com.sanoop.screenshotsync.pairing.PairedMacStore
import kotlinx.coroutines.withTimeoutOrNull
import java.security.MessageDigest

private const val TAG = "UploadRepository"
private val GIVE_UP_AFTER_MILLIS = 24 * 60 * 60 * 1000L

/** Backoff schedule per PROTOCOL.md: 5s, 15s, 60s, 5min, then every 15min. */
private fun backoffMillis(attempt: Int): Long = when {
    attempt <= 1 -> 5_000L
    attempt == 2 -> 15_000L
    attempt == 3 -> 60_000L
    attempt == 4 -> 5 * 60_000L
    else -> 15 * 60_000L
}

class UploadRepository(private val context: Context) {

    private val dao = AppDatabase.get(context).pendingUploadDao()
    private val pairedMacStore = PairedMacStore(context)
    private val mdnsResolver = MdnsResolver(context)

    /** Reads the image now (in case the URI becomes invalid later), queues it, and tries immediately. */
    suspend fun enqueueAndTryNow(uri: Uri, filename: String) {
        val bytes = runCatching {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        }.getOrNull() ?: return

        val checksum = sha256Hex(bytes)
        if (dao.countByChecksum(checksum) > 0) return // already queued from an earlier detection

        val id = dao.insert(PendingUpload(uri = uri.toString(), filename = filename, checksumSha256 = checksum))
        attemptUpload(PendingUpload(id = id, uri = uri.toString(), filename = filename, checksumSha256 = checksum), bytes)
    }

    /** Call periodically (e.g. from the watcher service's loop) to retry anything that's due. */
    suspend fun retryDueUploads() {
        val due = dao.getReadyForRetry(System.currentTimeMillis())
        for (item in due) {
            if (System.currentTimeMillis() - item.createdAtMillis > GIVE_UP_AFTER_MILLIS) {
                Log.w(TAG, "Giving up on ${item.filename} after 24h of retries")
                dao.delete(item)
                continue
            }

            val bytes = runCatching {
                context.contentResolver.openInputStream(Uri.parse(item.uri))?.use { it.readBytes() }
            }.getOrNull()
            if (bytes == null) {
                dao.delete(item) // source file is gone; nothing more we can do
                continue
            }
            attemptUpload(item, bytes)
        }
    }

    private suspend fun attemptUpload(item: PendingUpload, bytes: ByteArray) {
        val paired = pairedMacStore.load() ?: return
        val resolved = withTimeoutOrNull(8_000L) { mdnsResolver.resolve(paired.macDeviceId) }

        val result = if (resolved == null) {
            UploadResult.Failure("Could not find Mac on the network")
        } else {
            UploadClient.upload(resolved.host, resolved.port, paired, bytes, item.filename, item.checksumSha256)
        }

        when (result) {
            is UploadResult.Success, is UploadResult.Duplicate -> {
                Log.i(TAG, "Upload of ${item.filename} succeeded ($result)")
                dao.delete(item)
            }
            is UploadResult.Failure -> {
                Log.w(TAG, "Upload of ${item.filename} failed: ${result.message}")
                val nextAttempt = item.attemptCount + 1
                dao.update(
                    item.copy(
                        attemptCount = nextAttempt,
                        nextRetryAtMillis = System.currentTimeMillis() + backoffMillis(nextAttempt)
                    )
                )
            }
        }
    }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
