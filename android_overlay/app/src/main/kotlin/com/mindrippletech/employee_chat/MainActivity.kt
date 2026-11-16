package com.mindrippletech.employee_chat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // voice calls
    private var ringtone: Ringtone? = null
    private var tone: ToneGenerator? = null
    private var prox: PowerManager.WakeLock? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        makeChannels()
    }

    override fun onDestroy() {
        ring(false)
        tone("stop")
        proximity(false)
        try {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            stopService(Intent(this, CallService::class.java))
        } catch (_: Throwable) {
        }
        super.onDestroy()
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

        // incoming voice call: the phone's own ringtone and a long vibration
        try {
            val call = NotificationChannel("call", "Incoming calls", NotificationManager.IMPORTANCE_HIGH)
            call.description = "Voice calls from team chat and private chat"
            call.setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            )
            call.enableVibration(true)
            call.vibrationPattern = longArrayOf(0, 800, 600, 800, 600, 800, 600, 800)
            call.lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            nm.createNotificationChannel(call)
        } catch (_: Throwable) {
        }
    }

    /* ------------------------------------------------------------------ voice calls */

    /** the phone's ringtone + vibration while a call comes in and the app is open */
    @Suppress("DEPRECATION")
    private fun ring(on: Boolean) {
        try {
            val vib = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (on) {
                val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                val mode = am?.ringerMode ?: AudioManager.RINGER_MODE_NORMAL
                if (mode == AudioManager.RINGER_MODE_NORMAL && ringtone == null) {
                    val r = RingtoneManager.getRingtone(applicationContext, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                    if (r != null) {
                        r.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) r.isLooping = true
                        r.play()
                        ringtone = r
                    }
                }
                if (mode != AudioManager.RINGER_MODE_SILENT && vib != null) {
                    val pattern = longArrayOf(0, 800, 700)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
                    } else {
                        vib.vibrate(pattern, 0)
                    }
                }
            } else {
                ringtone?.stop()
                ringtone = null
                vib?.cancel()
            }
        } catch (_: Throwable) {
        }
    }

    /** ringback (the caller hears it in the earpiece while the other phone rings), busy, end, stop */
    private fun tone(kind: String) {
        try {
            main.removeCallbacksAndMessages(null)
            tone?.stopTone()
            if (kind == "stop") {
                tone?.release()
                tone = null
                return
            }
            if (tone == null) tone = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 70)
            when (kind) {
                "ringback" -> tone?.startTone(ToneGenerator.TONE_SUP_RINGTONE)
                "busy" -> tone?.startTone(ToneGenerator.TONE_SUP_BUSY, 2400)
                else -> tone?.startTone(ToneGenerator.TONE_PROP_PROMPT, 250)
            }
            if (kind != "ringback") {
                main.postDelayed({
                    try {
                        tone?.release()
                    } catch (_: Throwable) {
                    }
                    tone = null
                }, 2800)
            }
        } catch (_: Throwable) {
        }
    }

    /** the screen goes dark while the phone is at the ear */
    private fun proximity(on: Boolean) {
        try {
            if (on) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
                if (prox == null && pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                    prox = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "mrtcrm:call")
                }
                if (prox?.isHeld == false) prox?.acquire(4 * 60 * 60 * 1000L)
            } else {
                if (prox?.isHeld == true) prox?.release()
            }
        } catch (_: Throwable) {
        }
    }

    private fun callService(on: Boolean, name: String, video: Boolean) {
        try {
            val i = Intent(this, CallService::class.java).putExtra("name", name).putExtra("video", video)
            if (on) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
            } else {
                stopService(i)
            }
        } catch (_: Throwable) {
        }
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mrt/call").setMethodCallHandler { call, result ->
            when (call.method) {
                "service" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    callService(on, call.argument<String>("name") ?: "", call.argument<Boolean>("video") ?: false)
                    result.success(true)
                }
                "ring" -> {
                    ring(call.arguments as? Boolean ?: false)
                    result.success(true)
                }
                "tone" -> {
                    tone(call.arguments as? String ?: "stop")
                    result.success(true)
                }
                "screen" -> {
                    if (call.arguments as? Boolean ?: false) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                }
                "proximity" -> {
                    proximity(call.arguments as? Boolean ?: false)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
