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

/** Foreground-only double beep. Lease prevents a lost Flutter session ringing forever. */
class SosIncomingAlarm(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    private var tone: ToneGenerator? = null
    private var running = false
    private var deadline = 0L
    private val pulse = object : Runnable {
        override fun run() {
            if (!running || SystemClock.elapsedRealtime() >= deadline) { stop(); return }
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val notifications = context.getSystemService(NotificationManager::class.java)
            if (notifications.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL) {
                if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
                    try {
                        if (tone == null) tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 65)
                        tone?.startTone(ToneGenerator.TONE_PROP_BEEP, 160)
                        handler.postDelayed({
                            if (running && SystemClock.elapsedRealtime() < deadline)
                                tone?.startTone(ToneGenerator.TONE_PROP_BEEP, 160)
                        }, 420)
                    } catch (_: RuntimeException) { /* Sound is best effort. */ }
                }
                if (audio.ringerMode != AudioManager.RINGER_MODE_SILENT) {
                    val timings = longArrayOf(0, 200, 180, 200)
                    if (Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createWaveform(timings, -1))
                    else { @Suppress("DEPRECATION") vibrator.vibrate(timings, -1) }
                }
            }
            handler.postDelayed(this, 4000)
        }
    }
    fun start() {
        deadline = SystemClock.elapsedRealtime() + 12000
        if (running) return
        running = true
        handler.post(pulse)
    }
    fun stop() {
        running = false
        handler.removeCallbacksAndMessages(null)
        vibrator.cancel()
        tone?.stopTone()
        tone?.release()
        tone = null
    }
}
