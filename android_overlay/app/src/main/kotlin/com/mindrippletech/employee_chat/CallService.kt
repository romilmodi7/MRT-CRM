package com.mindrippletech.employee_chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Runs only while a voice call is on. It shows "Call in progress" and lets Android keep the microphone
 * and the connection alive when the app is in the background or the screen is off.
 */
class CallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val name = intent?.getStringExtra("name")?.takeIf { it.isNotBlank() } ?: "Voice call"
        val video = intent?.getBooleanExtra("video", false) ?: false
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = getSystemService(NotificationManager::class.java)
                val ch = NotificationChannel("oncall", "Call in progress", NotificationManager.IMPORTANCE_LOW)
                ch.setSound(null, null)
                ch.enableVibration(false)
                nm?.createNotificationChannel(ch)
            }
            val open = packageManager.getLaunchIntentForPackage(packageName)
            open?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pi = if (open != null) PendingIntent.getActivity(this, 7001, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) else null

            @Suppress("DEPRECATION")
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, "oncall") else Notification.Builder(this)
            b.setContentTitle(if (video) "Video call in progress" else "Call in progress")
                .setContentText(name)
                .setSmallIcon(android.R.drawable.stat_sys_phone_call)
                .setOngoing(true)
                .setShowWhen(false)
            if (pi != null) b.setContentIntent(pi)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val type = if (video) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                startForeground(7001, b.build(), type)
            } else {
                startForeground(7001, b.build())
            }
        } catch (t: Throwable) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** the app was swiped away: the call is over */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
    }
}
