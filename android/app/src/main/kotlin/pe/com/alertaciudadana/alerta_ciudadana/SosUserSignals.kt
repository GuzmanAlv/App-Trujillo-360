package pe.com.alertaciudadana.alerta_ciudadana

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator

/** Foreground call ringtone and bounded arrival cue. Never raises system volume. */
class SosUserSignals(private val context: Context) {
    private val ringHandler = Handler(Looper.getMainLooper())
    private val arrivalHandler = Handler(Looper.getMainLooper())
    private val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var ringtone: Ringtone? = null
    private var arrival: MediaPlayer? = null
    private var ringing = false
    private var deadline = 0L
    private fun allowed() = context.getSystemService(NotificationManager::class.java)
        .currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL
    private fun vibrate(pattern: LongArray) {
        if (Build.VERSION.SDK_INT >= 26) vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        else { @Suppress("DEPRECATION") vibrator.vibrate(pattern, -1) }
    }
    private val pulse = object : Runnable {
        override fun run() {
            if (!ringing || SystemClock.elapsedRealtime() >= deadline) { stopRing(); return }
            if (allowed()) {
                if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
                    try {
                        if (ringtone == null) ringtone = RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                        if (ringtone?.isPlaying != true) ringtone?.play()
                    } catch (_: RuntimeException) { }
                }
                if (audio.ringerMode != AudioManager.RINGER_MODE_SILENT) vibrate(longArrayOf(0, 550, 250, 550))
            }
            ringHandler.postDelayed(this, 2200)
        }
    }
    fun startRing() {
        deadline = SystemClock.elapsedRealtime() + 12000
        if (ringing) return
        ringing = true
        ringHandler.post(pulse)
    }
    fun stopRing() {
        ringing = false
        ringHandler.removeCallbacksAndMessages(null)
        ringtone?.stop()
        ringtone = null
        vibrator.cancel()
    }
    fun arrival() {
        stopArrival()
        if (!allowed()) return
        if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            try {
                val player = MediaPlayer()
                arrival = player
                player.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                context.resources.openRawResourceFd(R.raw.sos_arrival).use { fd ->
                    player.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                }
                player.prepare()
                player.start()
            } catch (_: Exception) { arrival?.release(); arrival = null }
        }
        if (audio.ringerMode != AudioManager.RINGER_MODE_SILENT) vibrate(longArrayOf(0, 200, 800, 200, 800, 200, 800, 200, 800, 200))
        arrivalHandler.postDelayed({ stopArrival() }, 5000)
    }
    fun stopArrival() {
        arrivalHandler.removeCallbacksAndMessages(null)
        arrival?.release()
        arrival = null
        if (!ringing) vibrator.cancel()
    }
    fun stop() { stopRing(); stopArrival() }
}
