package com.mindrippletech.employee_chat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        makeChannels()
    }

    /** Notification channels used by the push messages (the server picks one by name). Sound, vibration and pop-up are set here. */
    private fun makeChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        fun make(id: String, name: String, desc: String, importance: Int, loud: Boolean, vib: LongArray?) {
            val c = NotificationChannel(id, name, importance)
            c.description = desc
            if (loud) c.setSound(sound, attrs) else c.setSound(null, null)
            c.enableVibration(vib != null)
            if (vib != null) c.vibrationPattern = vib
            c.lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            nm.createNotificationChannel(c)
        }

        make("chat", "Chat messages", "New messages in team chat", NotificationManager.IMPORTANCE_HIGH, true, longArrayOf(0, 250, 150, 250))
        make("urgent", "Urgent shares", "Server, FTP and issue details shared with you", NotificationManager.IMPORTANCE_HIGH, true, longArrayOf(0, 600, 200, 600, 200, 600))
        make("private", "Private chat", "New messages in private chat", NotificationManager.IMPORTANCE_HIGH, true, longArrayOf(0, 250, 150, 250))
        make("quiet", "Silent messages", "Messages while the sound is switched off in the app", NotificationManager.IMPORTANCE_LOW, false, null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pc/secure").setMethodCallHandler { call, result ->
            if (call.method == "secure") {
                val on = call.arguments as? Boolean ?: true
                if (on) window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                result.success(true)
            } else result.notImplemented()
        }
    }
}
