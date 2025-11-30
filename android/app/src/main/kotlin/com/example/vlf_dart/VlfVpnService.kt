package com.example.vlf_dart

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.vlf_dart.libbox.PlatformInterfaceWrapper
import com.example.vlf_dart.libbox.toList
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.Notification as LibboxNotification
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class VlfVpnService : VpnService(), PlatformInterfaceWrapper {

    companion object {
        private const val TAG = "VLF-VpnService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "vlf_vpn_channel"
        private const val ACTION_STOP = "com.example.vlf_dart.STOP_VPN"
        private val callbackHandler = Handler(Looper.getMainLooper())

        @Volatile
        private var instance: VlfVpnService? = null
        @Volatile
        private var statusCallback: ((String) -> Unit)? = null
        @Volatile
        private var logCallback: ((String) -> Unit)? = null
        @Volatile
        private var latestConfigJson: String? = null
        @Volatile
        private var latestConfigPath: String? = null

        fun setStatusCallback(callback: (String) -> Unit) {
            statusCallback = callback
        }

        fun clearStatusCallback() {
            statusCallback = null
        }

        fun setLogCallback(callback: (String) -> Unit) {
            logCallback = callback
        }

        fun clearLogCallback() {
            logCallback = null
        }

        private fun postToMain(block: () -> Unit) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                block()
            } else {
                callbackHandler.post(block)
            }
        }

        private fun notifyStatus(status: String) {
            postToMain { statusCallback?.invoke(status) }
        }

        private fun notifyLog(line: String) {
            postToMain { logCallback?.invoke(line) }
        }

        fun isRunning(): Boolean = instance != null

        fun updateConfig(json: String, path: String? = null) {
            latestConfigJson = json
            latestConfigPath = path
            val preview = json.take(200).replace('\n', ' ')
            Log.i(
                TAG,
                "Config JSON updated, length=${json.length}, path=${path ?: "n/a"}, preview=$preview"
            )
        }

        fun getLatestConfig(): String? = latestConfigJson
        fun getLatestConfigPath(): String? = latestConfigPath
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "vlf-vpn-core").apply { isDaemon = true }
    }

    private var currentConfigJson: String? = null
    private var currentConfigPath: String? = null
    private var coreStarted = false
    private var lastEngineError: String? = null
    private var boxService: BoxService? = null
    internal var fileDescriptor: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        currentConfigJson = getLatestConfig()
        currentConfigPath = getLatestConfigPath()
        notifyStatus("stopped")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand() action=${intent?.action}")
        return when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                START_NOT_STICKY
            }
            else -> {
                currentConfigJson = intent?.getStringExtra("configJson") ?: currentConfigJson ?: getLatestConfig()
                currentConfigPath = intent?.getStringExtra("configPath") ?: currentConfigPath ?: getLatestConfigPath()
                val configJson = currentConfigJson
                if (configJson.isNullOrEmpty()) {
                    lastEngineError = "Config JSON missing"
                    notifyStatus("error:${lastEngineError}")
                    stopSelf()
                    START_NOT_STICKY
                } else {
                    if (startVpn(configJson)) START_STICKY else START_NOT_STICKY
                }
            }
        }
    }

    private fun startVpn(configJson: String): Boolean {
        return try {
            notifyStatus("starting")
            startForeground(NOTIFICATION_ID, createNotification())
            startLibbox(configJson)
            true
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start VPN", t)
            notifyStatus("error:${t.message}")
            false
        }
    }

    private fun startLibbox(configJson: String) {
        executor.execute {
            try {
                Log.i(TAG, "Initializing libbox core")
                val resolvedPath = currentConfigPath ?: getLatestConfigPath()
                Log.i(TAG, "Using sing-box config path=${resolvedPath ?: "inline-json"}")
                Log.d(TAG, "Config preview: ${configJson.take(200).replace('\n', ' ')}")
                Libbox.setMemoryLimit(true)
                val service = Libbox.newService(configJson, this@VlfVpnService)
                boxService = service
                service.start()
                coreStarted = true
                mainHandler.post { notifyStatus("running") }
            } catch (t: Throwable) {
                Log.e(TAG, "Libbox start failed", t)
                lastEngineError = t.message
                mainHandler.post {
                    notifyStatus("error:${t.message}")
                    stopVpn()
                }
            }
        }
    }

    private fun stopVpn() {
        Log.i(TAG, "Stopping VPN service")
        notifyStatus("stopping")
        stopCoreEngine()
        closeTun()
        runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
        notifyStatus("stopped")
        stopSelf()
    }

    private fun stopCoreEngine() {
        if (!coreStarted && boxService == null) return
        executor.execute {
            try {
                boxService?.close()
            } catch (t: Throwable) {
                Log.e(TAG, "Error closing libbox service", t)
            } finally {
                boxService = null
                coreStarted = false
            }
        }
    }

    private fun closeTun() {
        try {
            fileDescriptor?.close()
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to close tun fd", t)
        } finally {
            fileDescriptor = null
        }
    }

    override fun onRevoke() {
        Log.w(TAG, "VPN permission revoked")
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG, "VlfVpnService destroyed")
        stopCoreEngine()
        closeTun()
        executor.shutdownNow()
        notifyStatus("stopped")
        instance = null
        super.onDestroy()
    }

    private fun createNotification(): Notification {
        createNotificationChannel()

        val stopIntent = Intent(this, VlfVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText("VLF VPN is running")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(openPendingIntent)
            .addAction(
                NotificationCompat.Action.Builder(
                    0,
                    getString(R.string.stop_vpn),
                    stopPendingIntent
                ).build()
            )
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(CHANNEL_ID, "VLF VPN", NotificationManager.IMPORTANCE_LOW)
        manager.createNotificationChannel(channel)
    }

    override fun writeLog(message: String) {
        Log.i(TAG, message)
        notifyLog(message)
    }

    override fun sendNotification(notification: LibboxNotification) {
        val manager = VlfApplication.notificationManager
        val channelId = notification.identifier
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                notification.typeName,
                NotificationManager.IMPORTANCE_HIGH
            )
            manager.createNotificationChannel(channel)
        }
        val builder = NotificationCompat.Builder(this, channelId)
            .setContentTitle(notification.title)
            .setContentText(notification.body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
        manager.notify(notification.typeID, builder.build())
    }
}
