package com.example.vlf_dart

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.FileDescriptor

/**
 * VPN Service для VLF tunnel.
 * Поднимает TUN-интерфейс, устанавливает маршруты и DNS.
 * Пока без интеграции mihomo - просто "тупой" VPN для проверки базовой функциональности.
 */
class VlfVpnService : VpnService() {
    
    companion object {
        private const val TAG = "VLF-VpnService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "vlf_vpn_channel"
        private const val ACTION_STOP = "com.example.vlf_dart.STOP_VPN"
        
        @Volatile
        private var instance: VlfVpnService? = null
        
        @Volatile
        private var statusCallback: ((String) -> Unit)? = null

        @Volatile
        private var latestConfigJson: String? = null
        
        fun setStatusCallback(callback: (String) -> Unit) {
            statusCallback = callback
            Log.d(TAG, "Status callback registered")
        }
        
        fun clearStatusCallback() {
            statusCallback = null
            Log.d(TAG, "Status callback cleared")
        }
        
        private fun notifyStatus(status: String) {
            Log.d(TAG, "Notifying status: $status")
            statusCallback?.invoke(status)
        }
        
        fun isRunning(): Boolean = instance != null

        fun updateConfig(json: String) {
            latestConfigJson = json
            Log.i(TAG, "Config JSON updated, length=${json.length}")
        }

        fun getLatestConfig(): String? = latestConfigJson
    }
    
    private var vpnInterface: ParcelFileDescriptor? = null
    private var configYaml: String? = null
    private var workMode: String = "tun"
    private var currentConfigJson: String? = null
    private val coreEngine = AndroidCoreEngine()
    private var coreStarted = false
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.i(TAG, "onCreate() called")
        currentConfigJson = getLatestConfig()
        currentConfigJson?.let {
            Log.i(TAG, "Using prepared config JSON length=${it.length}")
            coreEngine.start(it)
            coreStarted = true
        } ?: Log.w(TAG, "No config JSON available in onCreate()")
        notifyStatus("stopped")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand() - action: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "Stop action received")
                stopVpn()
                return START_NOT_STICKY
            }
            else -> {
                configYaml = intent?.getStringExtra("configYaml")
                workMode = intent?.getStringExtra("mode") ?: "tun"
                currentConfigJson = intent?.getStringExtra("configJson") ?: currentConfigJson ?: getLatestConfig()
                currentConfigJson?.let {
                    Log.i(TAG, "Starting with config JSON length=${it.length}")
                    if (!coreStarted) {
                        coreEngine.start(it)
                        coreStarted = true
                    }
                } ?: Log.w(TAG, "Starting without config JSON - placeholder engine")
                
                Log.i(TAG, "Starting VPN - mode: $workMode, configYaml length: ${configYaml?.length ?: 0}")
                
                if (startVpn()) {
                    notifyStatus("running")
                    return START_STICKY
                } else {
                    notifyStatus("error:Failed to start VPN interface")
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
    }
    
    private fun startVpn(): Boolean {
        return try {
            Log.d(TAG, "Building VPN interface...")
            notifyStatus("starting")
            
            // Создаем foreground notification
            val notification = createNotification()
            startForeground(NOTIFICATION_ID, notification)
            Log.d(TAG, "Foreground notification started")
            
            // Настраиваем TUN интерфейс
            val builder = Builder()
                .setSession("VLF Tunnel")
                .addAddress("10.0.0.2", 24)  // Виртуальный IP адрес TUN интерфейса
                .addRoute("0.0.0.0", 0)       // Маршрут всего трафика через VPN
                .addDnsServer("8.8.8.8")      // Google DNS
                .addDnsServer("1.1.1.1")      // Cloudflare DNS
                .setMtu(1500)
                .setBlocking(false)
            
            Log.d(TAG, "VPN Builder configured: address=10.0.0.2/24, route=0.0.0.0/0, DNS=8.8.8.8,1.1.1.1, MTU=1500")
            
            vpnInterface = builder.establish()
            
            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN interface - builder.establish() returned null")
                return false
            }
            
            Log.i(TAG, "✅ VPN interface established successfully - fd: ${vpnInterface?.fd}")
            Log.i(TAG, "VPN is now active - system traffic should route through TUN interface")
            
            // TODO: В будущем здесь запустим mihomo с этим file descriptor
            // для проксирования трафика через VLESS
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting VPN", e)
            notifyStatus("error:${e.message}")
            false
        }
    }
    
    private fun stopVpn() {
        Log.i(TAG, "Stopping VPN...")
        notifyStatus("stopping")
        
        try {
            // Закрываем VPN интерфейс
            vpnInterface?.close()
            vpnInterface = null
            Log.d(TAG, "VPN interface closed")
        } catch (e: Exception) {
            Log.e(TAG, "Error closing VPN interface", e)
        }
        
        // Убираем foreground notification и останавливаем сервис
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
            Log.d(TAG, "Foreground notification removed")
        } catch (e: Exception) {
            Log.e(TAG, "Error removing foreground", e)
        }
        
        // Уведомляем о завершении ПЕРЕД stopSelf(), чтобы Flutter получил статус
        notifyStatus("stopped")
        Log.i(TAG, "VPN stopped, status sent to Flutter")
        
        stopSelf()
    }
    
    override fun onRevoke() {
        Log.w(TAG, "⚠️ onRevoke() called - User revoked VPN permission from system settings")
        
        // Закрываем интерфейс и уведомляем о статусе
        try {
            vpnInterface?.close()
            vpnInterface = null
            Log.d(TAG, "VPN interface closed in onRevoke()")
        } catch (e: Exception) {
            Log.e(TAG, "Error closing VPN interface in onRevoke()", e)
        }
        
        notifyStatus("stopped")
        Log.i(TAG, "VPN revoked by system, status sent to Flutter")
        
        // stopSelf() будет вызван системой, не вызываем вручную
        super.onRevoke()
    }
    
    override fun onDestroy() {
        Log.i(TAG, "onDestroy() called")
        
        // Закрываем VPN интерфейс если ещё открыт
        try {
            vpnInterface?.close()
            vpnInterface = null
            Log.d(TAG, "VPN interface closed in onDestroy()")
        } catch (e: Exception) {
            Log.e(TAG, "Error in onDestroy", e)
        }
        
        // Убираем foreground notification
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            // Может быть уже удалено
        }

        if (coreStarted) {
            coreEngine.stop()
            coreStarted = false
        }
        
        // Уведомляем о завершении
        notifyStatus("stopped")
        Log.i(TAG, "Service destroyed, status sent to Flutter")
        
        instance = null
        super.onDestroy()
    }
    
    private fun createNotification(): Notification {
        createNotificationChannel()
        
        // Intent для остановки VPN при нажатии на уведомление
        val stopIntent = Intent(this, VlfVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent для открытия приложения
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("VLF Tunnel активен")
            .setContentText("Безопасное подключение установлено")
            .setSmallIcon(android.R.drawable.ic_dialog_info) // TODO: заменить на свою иконку
            .setOngoing(true)
            .setContentIntent(openPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Остановить",
                stopPendingIntent
            )
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VLF VPN Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Уведомления о статусе VPN подключения"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }
}
