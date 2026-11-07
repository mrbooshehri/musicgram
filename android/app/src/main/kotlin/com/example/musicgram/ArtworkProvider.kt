package com.example.musicgram

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException
import java.util.UUID

/**
 * Exposes only images explicitly copied to the artwork cache.
 * Media browser clients such as Android Auto must be able to read these URIs.
 */
class ArtworkProvider : ContentProvider() {
    companion object {
        fun publish(context: Context, source: File): Uri {
            val directory = File(context.cacheDir, "shared_media_artwork")
            check(directory.isDirectory || directory.mkdirs())
            val name = "${UUID.randomUUID()}.img"
            source.copyTo(File(directory, name))
            directory.listFiles()?.sortedByDescending { it.lastModified() }
                ?.drop(20)?.forEach { it.delete() }
            return Uri.Builder().scheme("content")
                .authority("${context.packageName}.artwork")
                .appendPath(name).build()
        }
    }

    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r" || uri.pathSegments.size != 1 ||
            !uri.lastPathSegment.orEmpty().matches(Regex("[0-9a-f-]{36}\\.img"))) {
            throw FileNotFoundException("Invalid artwork")
        }
        val directory = File(requireNotNull(context).cacheDir, "shared_media_artwork")
        val file = File(directory, uri.lastPathSegment!!)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = "image/*"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                       selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?,
                        selectionArgs: Array<out String>?): Int = 0
}
