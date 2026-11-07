package com.example.musicgram

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File

class TelegramSyncService : Service() {
    companion object {
        const val ACTION_UPDATE = "com.example.musicgram.SYNC_UPDATE"
        const val ACTION_CANCEL = "com.example.musicgram.SYNC_CANCEL"
        const val ACTION_FINISH = "com.example.musicgram.SYNC_FINISH"
        private const val CHANNEL = "telegram_sync"
        private const val NOTIFICATION_ID = 7103
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun cancelDartJob(method: String = "cancel") {
        val engine = FlutterEngineCache.getInstance().get(AudioServicePlugin.getFlutterEngineId())
        if (engine != null) {
            MethodChannel(engine.dartExecutor.binaryMessenger, "musicgram/telegram_sync_control")
                .invokeMethod(method, null)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> {
                // Persist cancellation before notifying Dart, including if the
                // process was restarted but the engine has not initialized yet.
                try {
                    val selection = File(filesDir, "telegram_active_session.txt")
                    val session = if (selection.exists()) selection.readText().trim() else "legacy"
                    if (session == "legacy" || Regex("^session_[a-zA-Z0-9_-]{1,64}$").matches(session)) {
                        File(filesDir, "telegram_sync_${session}.json.cancelled").writeText("cancelled")
                    }
                } catch (_: Exception) {
                    // Dart still receives the cancellation request below.
                }
                cancelDartJob()
                stopSelf()
            }
            ACTION_FINISH -> stopSelf()
            ACTION_UPDATE -> showProgress(intent.getStringExtra("message") ?: "Sync in progress")
            null -> {
                // START_STICKY restarts after process death with a null intent.
                showProgress("Restoring Telegram sync…")
                try {
                    val cache = FlutterEngineCache.getInstance()
                    val engineId = AudioServicePlugin.getFlutterEngineId()
                    if (cache.get(engineId) == null) {
                        val engine = FlutterEngine(applicationContext)
                        TelegramSyncBridge.install(engine, this)
                        engine.navigationChannel.setInitialRoute("/telegram-sync-recovery")
                        cache.put(engineId, engine)
                        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
                    } else {
                        val engine = cache.get(engineId)!!
                        if (!MainActivity.bridgeAttached) TelegramSyncBridge.install(engine, this)
                        requestRecovery(engine, 0)
                    }
                } catch (_: Exception) {
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
            else -> stopSelf()
        }
        return if (intent?.action == ACTION_CANCEL || intent?.action == ACTION_FINISH) START_NOT_STICKY else START_STICKY
    }

    private fun requestRecovery(engine: FlutterEngine, attempt: Int) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "musicgram/telegram_sync_recovery")
            .invokeMethod("resume", null, object : MethodChannel.Result {
                override fun success(result: Any?) = Unit
                override fun error(code: String, message: String?, details: Any?) = Unit
                override fun notImplemented() {
                    if (attempt < 20) Handler(Looper.getMainLooper()).postDelayed({ requestRecovery(engine, attempt + 1) }, 250)
                    else stopSelf()
                }
            })
    }

    fun showProgress(message: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Telegram music sync", NotificationManager.IMPORTANCE_LOW))
        }
        val cancel = Intent(this, TelegramSyncService::class.java).setAction(ACTION_CANCEL)
        val pendingCancel = PendingIntent.getService(this, 0, cancel, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Syncing Telegram music")
            .setContentText(message)
            .setProgress(0, 0, true)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", pendingCancel)
            .build()
        startForeground(NOTIFICATION_ID, notification)
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        cancelDartJob("interrupt")
        stopSelf(startId)
    }
}
