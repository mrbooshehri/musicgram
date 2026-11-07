package com.example.musicgram

import android.Manifest
import android.content.ContentValues
import android.os.Environment
import java.io.File
import android.content.pm.PackageManager
import android.os.Build
import android.media.MediaMetadataRetriever
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.content.Context
import android.provider.MediaStore
import org.drinkless.tdlib.JsonClient
import java.util.concurrent.Executors
import kotlin.math.roundToInt
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
        @Volatile var bridgeAttached = false
    }
    private val artworkExecutor = Executors.newFixedThreadPool(2)
    private var upnpMulticastLock: WifiManager.MulticastLock? = null
    private var upnpMulticastRequests = 0
    private var pending: MethodChannel.Result? = null
    private val requestCode = 7101
    private var syncNotificationPermissionRequested = false
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        bridgeAttached = true
        MethodChannel(engine.dartExecutor.binaryMessenger, "musicgram/tdlib").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "create" -> result.success(JsonClient.createClientId())
                    "send" -> {
                        val id = call.argument<Int>("clientId")
                        val request = call.argument<String>("request")
                        if (id == null || request == null) result.error("invalid_argument", "Missing client ID or request", null)
                        else { JsonClient.send(id, request); result.success(null) }
                    }
                    "receive" -> Thread {
                        try {
                            val update = JsonClient.receive(1.0)
                            runOnUiThread { result.success(update) }
                        } catch (e: Exception) { runOnUiThread { result.error("tdlib_error", e.message, null) } }
                    }.start()
                    else -> result.notImplemented()
                }
            } catch (e: UnsatisfiedLinkError) {
                result.error("tdlib_unavailable", "TDLib is unavailable on this device architecture", null)
            } catch (e: Exception) { result.error("tdlib_error", e.message, null) }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "musicgram/library").setMethodCallHandler { call, result ->
            if (call.method == "telegramSyncNotification") {
                val message = call.argument<String>("message")
                if (message != null && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    if (!syncNotificationPermissionRequested) {
                        syncNotificationPermissionRequested = true
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7102)
                    }
                }
                try {
                    val intent = android.content.Intent(applicationContext, TelegramSyncService::class.java)
                    if (message == null) {
                        stopService(intent)
                    } else {
                        intent.action = TelegramSyncService.ACTION_UPDATE
                        intent.putExtra("message", message)
                        if (Build.VERSION.SDK_INT >= 26) applicationContext.startForegroundService(intent)
                        else applicationContext.startService(intent)
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("sync_service_failed", e.message, null)
                }
                return@setMethodCallHandler
            }
            if (call.method == "musicStorageUsage") {
                val tracked = call.argument<List<String>>("downloadUris") ?: emptyList()
                artworkExecutor.execute {
                    try {
                        val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
                        if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) throw SecurityException("Allow music access to analyze storage")
                        val ids = tracked.mapNotNull { value ->
                            try {
                                val uri = android.net.Uri.parse(value)
                                if (uri.authority != "media" || uri.pathSegments.firstOrNull() !in listOf("external", "external_primary")) null
                                else android.content.ContentUris.parseId(uri)
                            } catch (_: Exception) { null }
                        }.toSet()
                        val uri = if (Build.VERSION.SDK_INT >= 29) MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                        val columns = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.DATA, MediaStore.Audio.Media.SIZE, MediaStore.Audio.Media.IS_MUSIC)
                        val files = mutableListOf<Map<String, Any>>()
                        contentResolver.query(uri, columns, null, null, null)?.use { cursor ->
                            while (cursor.moveToNext()) {
                                val id = cursor.getLong(0)
                                val isTelegram = id in ids
                                if (!isTelegram && cursor.getInt(3) == 0) continue
                                val path = cursor.getString(1) ?: continue
                                val bytes = cursor.getLong(2)
                                if (bytes <= 0) continue
                                files.add(mapOf("folder" to (File(path).parent ?: "/"), "bytes" to bytes, "telegram" to isTelegram))
                            }
                        } ?: throw IllegalStateException("Music storage is unavailable")
                        @Suppress("DEPRECATION")
                        val stats = android.os.StatFs(Environment.getExternalStorageDirectory().path)
                        runOnUiThread { result.success(mapOf("capacity" to stats.totalBytes, "free" to stats.availableBytes, "files" to files)) }
                    } catch (e: Exception) { runOnUiThread { result.error("storage_analysis_failed", e.message, null) } }
                }
                return@setMethodCallHandler
            }
            if (call.method == "openNotificationSettings") {
                try {
                    val intent = if (Build.VERSION.SDK_INT >= 26) {
                        android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                    } else {
                        android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData(android.net.Uri.parse("package:$packageName"))
                    }
                    startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("settings_unavailable", "Could not open notification settings", null)
                }
                return@setMethodCallHandler
            }
            if (call.method == "acquireUpnpMulticast") {
                try {
                    val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    if (upnpMulticastLock?.isHeld != true) {
                        upnpMulticastLock = wifi.createMulticastLock("MusicGram UPnP discovery").apply {
                            setReferenceCounted(false)
                            acquire()
                        }
                    }
                    upnpMulticastRequests++
                    result.success(null)
                } catch (e: Exception) {
                    result.error("multicast_failed", "Could not enable Wi-Fi discovery.", null)
                }
                return@setMethodCallHandler
            }
            if (call.method == "releaseUpnpMulticast") {
                if (upnpMulticastRequests > 0) upnpMulticastRequests--
                if (upnpMulticastRequests == 0) {
                    upnpMulticastLock?.let { if (it.isHeld) it.release() }
                    upnpMulticastLock = null
                }
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method == "getMediaVolume" || call.method == "setMediaVolume") {
                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                if (call.method == "setMediaVolume") {
                    val value = call.argument<Double>("value")
                    if (value == null) {
                        result.error("invalid_argument", "Missing volume", null)
                        return@setMethodCallHandler
                    }
                    val index = (value.coerceIn(0.0, 1.0) * maximum).roundToInt()
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
                }
                result.success(if (maximum > 0) audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / maximum else 0.0)
                return@setMethodCallHandler
            }
            if (call.method == "appVersion") {
                val info = packageManager.getPackageInfo(packageName, 0)
                @Suppress("DEPRECATION")
                val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                result.success("${info.versionName ?: "Unknown"} ($code)")
                return@setMethodCallHandler
            }
            if (call.method == "downloadExists") {
                val value = call.argument<String>("uri")
                val exists = try { value != null && contentResolver.openFileDescriptor(android.net.Uri.parse(value), "r")?.use { true } == true } catch (_: Exception) { false }
                result.success(exists)
                return@setMethodCallHandler
            }
            if (call.method == "localAudioPath") {
                val value = call.argument<String>("uri")
                if (value == null) { result.error("invalid_argument", "Missing URI", null); return@setMethodCallHandler }
                artworkExecutor.execute {
                    try {
                        val file = File(cacheDir, "telegram-playback-${value.hashCode()}.audio")
                        contentResolver.openInputStream(android.net.Uri.parse(value))?.use { input -> file.outputStream().use { input.copyTo(it) } }
                            ?: throw IllegalStateException("Downloaded file is unavailable")
                        runOnUiThread { result.success(file.absolutePath) }
                    } catch (e: Exception) { runOnUiThread { result.error("local_audio_failed", e.message, null) } }
                }
                return@setMethodCallHandler
            }
            if (call.method == "saveTelegramDownload") {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                val folder = call.argument<String>("folder")
                val rootFolder = call.argument<String>("rootFolder") ?: "MusicGram"
                if (path == null || name == null || folder == null || Build.VERSION.SDK_INT < 29) {
                    result.error("unsupported", "Saving downloads requires Android 10 or later", null)
                    return@setMethodCallHandler
                }
                artworkExecutor.execute {
                    var uri: android.net.Uri? = null
                    try {
                        val values = ContentValues().apply {
                            put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                            put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/$rootFolder/$folder/")
                            put(MediaStore.Audio.Media.IS_PENDING, 1)
                        }
                        uri = contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("Unable to create download")
                        contentResolver.openOutputStream(uri)?.use { out -> File(path).inputStream().use { it.copyTo(out) } }
                            ?: throw IllegalStateException("Unable to write download")
                        values.clear()
                        values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                        if (contentResolver.update(uri, values, null, null) != 1) throw IllegalStateException("Unable to finish download")
                        val savedUri = uri.toString()
                        runOnUiThread { result.success(savedUri) }
                    } catch (e: Exception) {
                        uri?.let { contentResolver.delete(it, null, null) }
                        runOnUiThread { result.error("download_save_failed", e.message, null) }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "shareArtwork") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("invalid_argument", "Missing artwork path", null)
                    return@setMethodCallHandler
                }
                artworkExecutor.execute {
                    try {
                        val uri = ArtworkProvider.publish(applicationContext, File(path))
                        runOnUiThread { result.success(uri.toString()) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("artwork_share_failed", e.message, null) }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "artwork") {
                val path = call.argument<String>("path")
                artworkExecutor.execute {
                    val data = try {
                        val retriever = MediaMetadataRetriever()
                        try { retriever.setDataSource(path); retriever.embeddedPicture } finally { retriever.release() }
                    } catch (_: Exception) { null }
                    runOnUiThread { result.success(data) }
                }
                return@setMethodCallHandler
            }
            if (call.method != "songs" && call.method != "songsIfPermitted") { result.notImplemented(); return@setMethodCallHandler }
            val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
            if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) querySongs(result)
            else if (call.method == "songsIfPermitted") result.error("permission_denied", "Open MusicGram on your phone to grant music access.", null)
            else if (pending != null) result.error("busy", "Permission request already in progress", null)
            else { pending = result; requestPermissions(arrayOf(permission), requestCode) }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridgeAttached = false
        super.cleanUpFlutterEngine(flutterEngine)
    }
    override fun onDestroy() {
        upnpMulticastLock?.let { if (it.isHeld) it.release() }
        upnpMulticastLock = null
        upnpMulticastRequests = 0
        super.onDestroy()
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code != requestCode) return
        val result = pending ?: return
        pending = null
        if (results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED) querySongs(result)
        else result.error("permission_denied", "Music access was denied. Enable it in app settings to browse your library.", null)
    }
    private fun querySongs(result: MethodChannel.Result) {
        Thread {
            try {
                val songs = mutableListOf<Map<String, String>>()
                val volumes = if (Build.VERSION.SDK_INT >= 29) MediaStore.getExternalVolumeNames(this) + "internal" else setOf("external", "internal")
                for (volume in volumes) {
                    val uri = MediaStore.Audio.Media.getContentUri(volume)
                    val columns = arrayOf(MediaStore.Audio.Media.DATA, MediaStore.Audio.Media.DISPLAY_NAME, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION) + if (Build.VERSION.SDK_INT >= 30) arrayOf(MediaStore.Audio.Media.GENRE) else emptyArray()
                    contentResolver.query(uri, columns, "${MediaStore.Audio.Media.IS_MUSIC} != 0", null, "${MediaStore.Audio.Media.DISPLAY_NAME} COLLATE NOCASE ASC")?.use { cursor ->
                        while (cursor.moveToNext()) {
                            val path = cursor.getString(0) ?: continue
                            val name = cursor.getString(1) ?: continue
                            songs.add(mapOf("path" to path, "name" to name, "title" to (cursor.getString(2) ?: name), "artist" to (cursor.getString(3) ?: ""), "album" to (cursor.getString(4) ?: ""), "duration" to (cursor.getString(5) ?: ""), "genre" to (if (Build.VERSION.SDK_INT >= 30) cursor.getString(6) ?: "" else "")))
                        }
                    }
                }
                runOnUiThread { result.success(songs) }
            } catch (e: Exception) { runOnUiThread { result.error("scan_failed", e.message, null) } }
        }.start()
    }
}
