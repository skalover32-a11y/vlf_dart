package com.example.vlf_dart

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.PluginRegistry

class VlfAndroidEngine : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, 
    ActivityAware, PluginRegistry.ActivityResultListener {
    
    private lateinit var channel: MethodChannel
    private lateinit var statusChannel: EventChannel
    private lateinit var logChannel: EventChannel
    private var statusSink: EventChannel.EventSink? = null
    private var logSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingMode: String = "tun"
    private var latestConfigJson: String? = null
    
    companion object {
        private const val VPN_REQUEST_CODE = 1001
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        
        channel = MethodChannel(binding.binaryMessenger, "vlf_android_engine")
        channel.setMethodCallHandler(this)
        Log.i("VLF", "VlfAndroidEngine attached")

        statusChannel = EventChannel(binding.binaryMessenger, "vlf_android_engine/status")
        statusChannel.setStreamHandler(this)
        logChannel = EventChannel(binding.binaryMessenger, "vlf_android_engine/logs")
        logChannel.setStreamHandler(logStreamHandler)
        
        // Регистрируем callback для получения статусов от VpnService
        VlfVpnService.setStatusCallback { status ->
            Log.d("VLF", "Status from VpnService: $status")
            statusSink?.success(status)
        }
        VlfVpnService.setLogCallback { line ->
            logSink?.success(line)
        }
    }

    private val logStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            logSink = events
            Log.d("VLF", "Log listener attached")
        }

        override fun onCancel(arguments: Any?) {
            logSink = null
            Log.d("VLF", "Log listener cancelled")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepareConfig" -> {
                val json = call.arguments as? String
                if (json.isNullOrEmpty()) {
                    Log.w("VLF", "prepareConfig called with empty json")
                    result.error("invalid_config", "Empty config", null)
                    return
                }
                latestConfigJson = json
                VlfVpnService.updateConfig(json)
                Log.i("VLF", "prepareConfig accepted, json length=${json.length}")
                result.success("ok")
            }
            "startTunnel" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val mode = args["mode"] as? String ?: "tun"
                pendingMode = mode
                val cfgLen = (args["configYaml"] as? String)?.length ?: 0
                Log.i("VLF", "AndroidEngine.startTunnel mode=$mode, configYaml.length=$cfgLen")
                
                try {
                    // Проверяем, запущен ли уже VPN
                    if (VlfVpnService.isRunning()) {
                        Log.w("VLF", "VPN already running")
                        result.success("already_running")
                        return
                    }
                    
                    // Проверяем разрешение VPN
                    val intent = VpnService.prepare(context)
                    if (intent != null) {
                        Log.i("VLF", "VPN permission required - requesting user approval")
                        // Нужно запросить разрешение
                        pendingResult = result
                        activity?.startActivityForResult(intent, VPN_REQUEST_CODE)
                            ?: run {
                                Log.e("VLF", "Activity is null, cannot request VPN permission")
                                result.error("no_activity", "Activity not available", null)
                            }
                    } else {
                        Log.i("VLF", "VPN permission already granted - starting service")
                        // Разрешение уже есть, запускаем сервис
                        startVpnService(mode)
                        result.success("ok")
                    }
                } catch (t: Throwable) {
                    Log.e("VLF", "startTunnel error", t)
                    statusSink?.success("error:${t.message}")
                    result.error("start_error", t.message, null)
                }
            }
            "stopTunnel" -> {
                Log.i("VLF", "AndroidEngine.stopTunnel")
                try {
                    stopVpnService()
                    result.success("ok")
                } catch (t: Throwable) {
                    statusSink?.success("error:${t.message}")
                    result.error("stop_error", t.message, null)
                }
            }
            "getStatus" -> {
                val status = if (VlfVpnService.isRunning()) "running" else "stopped"
                result.success(status)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.i("VLF", "VlfAndroidEngine detached")
        VlfVpnService.clearStatusCallback()
        VlfVpnService.clearLogCallback()
        context = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        statusSink = events
        // При подключении отправим текущий статус, чтобы синхронизировать UI
        val status = if (VlfVpnService.isRunning()) "running" else "stopped"
        statusSink?.success(status)
        Log.d("VLF", "EventChannel listener attached, initial status: $status")
    }

    override fun onCancel(arguments: Any?) {
        statusSink = null
        Log.d("VLF", "EventChannel listener cancelled")
    }
    
    // ActivityAware implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
        Log.d("VLF", "Attached to activity")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
    
    // ActivityResultListener implementation
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == VPN_REQUEST_CODE) {
            Log.i("VLF", "VPN permission result: resultCode=$resultCode")
            
            if (resultCode == Activity.RESULT_OK) {
                Log.i("VLF", "VPN permission granted by user")
                // Пользователь дал разрешение, запускаем сервис
                // Нужно получить параметры из pendingResult
                try {
                    startVpnService(pendingMode)
                    pendingResult?.success("ok")
                } catch (t: Throwable) {
                    Log.e("VLF", "Error starting VPN after permission granted", t)
                    pendingResult?.error("start_error", t.message, null)
                    statusSink?.success("error:${t.message}")
                }
            } else {
                Log.w("VLF", "VPN permission denied by user")
                pendingResult?.error("permission_denied", "User denied VPN permission", null)
                statusSink?.success("error:Permission denied")
            }
            
            pendingResult = null
            return true
        }
        return false
    }
    
    private fun startVpnService(mode: String) {
        val ctx = context ?: throw IllegalStateException("Context is null")
        
        val intent = Intent(ctx, VlfVpnService::class.java).apply {
            putExtra("mode", mode)
            latestConfigJson?.let { putExtra("configJson", it) }
        }
        
        Log.i("VLF", "Starting VlfVpnService...")
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            ctx.startForegroundService(intent)
        } else {
            ctx.startService(intent)
        }
        
        Log.i("VLF", "VlfVpnService start command sent")
    }
    
    private fun stopVpnService() {
        val ctx = context ?: throw IllegalStateException("Context is null")
        
        Log.i("VLF", "Stopping VPN service...")
        
        // Отправляем ACTION_STOP через Intent для корректной остановки
        val intent = Intent(ctx, VlfVpnService::class.java).apply {
            action = "com.example.vlf_dart.STOP_VPN"
        }
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            ctx.startForegroundService(intent)
        } else {
            ctx.startService(intent)
        }
        
        Log.i("VLF", "VlfVpnService stop command sent via ACTION_STOP")
    }
}
