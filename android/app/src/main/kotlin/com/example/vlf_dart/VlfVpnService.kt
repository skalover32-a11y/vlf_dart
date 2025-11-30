package com.example.vlf_dart

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log

class VlfVpnService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundInternal()
        setupTunnel()
        return START_STICKY
    }

    override fun onDestroy() {
        tunInterface?.close()
        tunInterface = null
        super.onDestroy()
    }

    override fun onRevoke() {
        stopSelf()
        super.onRevoke()
    }

    private fun setupTunnel() {
        try {
            tunInterface?.close()
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to close existing TUN", t)
        }

        val builder = Builder()
            .setSession("vlf-tun")
            .setMtu(1500)
            .addAddress("10.0.0.2", 24)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("1.1.1.1")
            .allowBypass(false)

        // Ensure the service is foreground before establishing the interface.
        startForegroundInternal()

        tunInterface = builder.establish()
        if (tunInterface == null) {
            Log.e(TAG, "Failed to establish the TUN interface")
            stopSelf()
        } else {
            Log.i(TAG, "TUN interface established: fd=${tunInterface?.fd}")
        }
    }

    private fun startForegroundInternal() {
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VLF Tunnel",
                NotificationManager.IMPORTANCE_LOW
            )
            notificationManager.createNotificationChannel(channel)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val notification: Notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("VLF Tunnel active")
            .setContentText("Traffic is routed through sing-box")
            .setSmallIcon(android.R.drawable.stat_sys_vpn_lock)
            .setContentIntent(pendingIntent)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    companion object {
        private const val TAG = "VlfVpnService"
        private const val CHANNEL_ID = "vlf_tunnel"
        private const val NOTIFICATION_ID = 1
    }
}
