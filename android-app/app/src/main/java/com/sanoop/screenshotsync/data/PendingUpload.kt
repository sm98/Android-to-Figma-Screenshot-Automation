package com.sanoop.screenshotsync.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "pending_uploads")
data class PendingUpload(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val uri: String,
    val filename: String,
    val checksumSha256: String,
    val attemptCount: Int = 0,
    val nextRetryAtMillis: Long = 0L,
    val createdAtMillis: Long = System.currentTimeMillis()
)
