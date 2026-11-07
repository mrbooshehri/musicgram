package com.example.musicgram

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.drinkless.tdlib.JsonClient

/** Minimal bridge used before an activity attaches to the shared engine. */
object TelegramSyncBridge {
    fun install(engine: FlutterEngine, service: TelegramSyncService) {
        val main = Handler(Looper.getMainLooper())
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
                            main.post { result.success(update) }
                        } catch (error: Exception) {
                            main.post { result.error("tdlib_error", error.message, null) }
                        }
                    }.start()
                    else -> result.notImplemented()
                }
            } catch (error: UnsatisfiedLinkError) {
                result.error("tdlib_unavailable", "TDLib is unavailable on this device architecture", null)
            } catch (error: Exception) {
                result.error("tdlib_error", error.message, null)
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "musicgram/library").setMethodCallHandler { call, result ->
            if (call.method == "telegramSyncNotification") {
                val message = call.argument<String>("message")
                if (message == null) service.stopSelf()
                else service.showProgress(message)
                result.success(null)
            } else result.notImplemented()
        }
    }
}
