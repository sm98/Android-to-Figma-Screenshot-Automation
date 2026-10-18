package com.sanoop.screenshotsync.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import com.sanoop.screenshotsync.MainActivity
import com.sanoop.screenshotsync.data.UploadRepository
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

private const val RETRY_LOOP_INTERVAL_MILLIS = 10_000L

/**
 * MediaStore fires onChange multiple times while a screenshot is being written (an initial
 * low-res placeholder, then the final file) — this debounce window means we only act once no
 * further change for the same URI has arrived, avoiding uploading a half-written placeholder.
 */
private const val DEBOUNCE_MILLIS = 800L

/** Foreground service that watches MediaStore for newly-added screenshots and uploads them. */
class ScreenshotWatcherService : Service() {

    private lateinit var contentObserver: ContentObserver
    private lateinit var uploadRepository: UploadRepository
    private var serviceStartTimeSeconds: Long = 0L
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val debounceJobs = ConcurrentHashMap<Uri, Job>()

    override fun onCreate() {
        super.onCreate()
        serviceStartTimeSeconds = System.currentTimeMillis() / 1000
        uploadRepository = UploadRepository(applicationContext)
        createNotificationChannel()

        val notification = buildNotification("Watching for new screenshots…")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        registerObserver()
        startRetryLoop()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        contentResolver.unregisterContentObserver(contentObserver)
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerObserver() {
        contentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                if (uri != null) handleChange(uri)
            }
        }
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            contentObserver
        )
    }

    private fun handleChange(uri: Uri) {
        if (!isLikelyNewScreenshot(uri)) return

        // Debounce: MediaStore notifies once for the initial (sometimes placeholder-sized) insert
        // and again once the file is fully written. Only the last notification within the window
        // actually triggers an upload, so we always read the finished file, not a half-written one.
        debounceJobs[uri]?.cancel()
        debounceJobs[uri] = serviceScope.launch {
            delay(DEBOUNCE_MILLIS)
            debounceJobs.remove(uri)
            processConfirmedScreenshot(uri)
        }
    }

    private fun isLikelyNewScreenshot(uri: Uri): Boolean {
        val projection = arrayOf(
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.RELATIVE_PATH,
            MediaStore.Images.Media.DATE_ADDED
        )
        return try {
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return false
                val name = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME))
                    ?: return false
                val path = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.RELATIVE_PATH))
                    ?: ""
                val dateAdded = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED))

                val isScreenshot = path.contains("Screenshots", ignoreCase = true) ||
                    name.contains("Screenshot", ignoreCase = true)
                val isNew = dateAdded >= serviceStartTimeSeconds
                isScreenshot && isNew
            } ?: false
        } catch (e: Exception) {
            Log.w(TAG, "Failed to inspect changed media $uri", e)
            false
        }
    }

    private suspend fun processConfirmedScreenshot(uri: Uri) {
        val projection = arrayOf(MediaStore.Images.Media.DISPLAY_NAME)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val pendingProjection = arrayOf(MediaStore.Images.Media.IS_PENDING)
            val isPending = try {
                contentResolver.query(uri, pendingProjection, null, null, null)?.use { cursor ->
                    cursor.moveToFirst() &&
                        cursor.getInt(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.IS_PENDING)) == 1
                } ?: false
            } catch (e: Exception) {
                false
            }
            if (isPending) {
                Log.i(TAG, "Screenshot at $uri is still being written, skipping until it settles")
                return
            }
        }

        val name = try {
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME))
                } else null
            }
        } catch (e: Exception) {
            null
        } ?: return

        Log.i(TAG, "Uploading confirmed screenshot: $name (uri=$uri)")
        updateNotification("Sending: $name")
        uploadRepository.enqueueAndTryNow(uri, name)
        updateNotification("Watching for new screenshots…")
    }

    private fun startRetryLoop() {
        serviceScope.launch {
            while (isActive) {
                delay(RETRY_LOOP_INTERVAL_MILLIS)
                uploadRepository.retryDueUploads()
            }
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Screenshot Sync",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Watching for new screenshots to send to your Mac"
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent, PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Screenshot Sync")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(text))
    }

    companion object {
        private const val TAG = "ScreenshotWatcher"
        private const val CHANNEL_ID = "screenshot_watcher"
        private const val NOTIFICATION_ID = 1001
    }
}
