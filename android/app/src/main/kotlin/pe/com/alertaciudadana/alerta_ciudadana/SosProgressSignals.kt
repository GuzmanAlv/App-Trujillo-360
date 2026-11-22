package pe.com.alertaciudadana.alerta_ciudadana

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator

/** Low-volume duty cue or a short citizen vibration. Foreground lease only. */
class SosProgressSignals(private val context: Context, private val higherPriority: () -> Boolean) {
    private val handler = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    private var tone: ToneGenerator? = null
    private var mode = "none"
    private var deadline = 0L
    private val pulse = object : Runnable {
        override fun run() {
            if (mode == "none" || SystemClock.elapsedRealtime() >= deadline) { stop(); return }
            val allowed = context.getSystemService(NotificationManager::class.java)
                .currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL
            if (allowed && !higherPriority() && audio.mode == AudioManager.MODE_NORMAL) {
                if (mode == "operator" && audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
                    try {
                        if (tone == null) tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 20)
                        tone?.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
                    } catch (_: RuntimeException) { tone?.release(); tone = null }
                } else if (mode == "citizen" && audio.ringerMode != AudioManager.RINGER_MODE_SILENT) {
                    if (Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createOneShot(120, VibrationEffect.DEFAULT_AMPLITUDE))
                    else { @Suppress("DEPRECATION") vibrator.vibrate(120) }
                }
            }
            handler.postDelayed(this, if (mode == "citizen") 2000L else 6000L)
        }
    }
    fun update(value: String?) {
        if (value !in listOf("operator", "citizen")) { stop(); return }
        deadline = SystemClock.elapsedRealtime() + 12000L
        if (mode == value) return
        stop()
        mode = value!!
        handler.post(pulse)
    }
    fun stop() {
        mode = "none"
        handler.removeCallbacksAndMessages(null)
        tone?.release(); tone = null
        // Vibrations are bounded to 120 ms; never cancel another SOS/call cue.
    }
}
