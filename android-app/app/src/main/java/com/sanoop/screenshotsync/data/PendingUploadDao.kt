package com.sanoop.screenshotsync.data

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface PendingUploadDao {
    @Insert
    suspend fun insert(upload: PendingUpload): Long

    @Update
    suspend fun update(upload: PendingUpload)

    @Delete
    suspend fun delete(upload: PendingUpload)

    @Query("SELECT * FROM pending_uploads WHERE nextRetryAtMillis <= :now ORDER BY createdAtMillis ASC")
    suspend fun getReadyForRetry(now: Long): List<PendingUpload>

    @Query("SELECT * FROM pending_uploads ORDER BY createdAtMillis ASC")
    suspend fun getAll(): List<PendingUpload>

    @Query("SELECT COUNT(*) FROM pending_uploads WHERE checksumSha256 = :checksum")
    suspend fun countByChecksum(checksum: String): Int
}
