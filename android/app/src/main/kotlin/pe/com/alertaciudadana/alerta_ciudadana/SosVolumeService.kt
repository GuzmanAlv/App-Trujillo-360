package pe.com.alertaciudadana.alerta_ciudadana

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class SosVolumeService : AccessibilityService() {
    private var presses = 0
    private var firstPress = 0L
    private var lastTrigger = 0L
    private val sending = AtomicBoolean(false)

    private fun vibrate(pattern: LongArray) {
        val vibrator = if (Build.VERSION.SDK_INT >= 31)
            getSystemService(VibratorManager::class.java).defaultVibrator
        else getSystemService(Vibrator::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_VOLUME_DOWN ||
            event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return false
        val (enabled, testOnly) = SosVolumeConfig.read(this)
        if (!enabled) return false
        val now = SystemClock.elapsedRealtime()
        if (now - lastTrigger < if (testOnly) 3_000L else 30_000L) return false
        if (now - firstPress > 2_000L) {
            presses = 0
            firstPress = now
        }
        presses++
        if (presses == 3) {
            presses = 0
            lastTrigger = now
            if (testOnly) {
                Log.i("SosVolumeService", "gesture_detected_test_only")
                vibrate(longArrayOf(0, 60, 80, 60))
                val power = getSystemService(PowerManager::class.java)
                val wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Trujillo360:SosCheck")
                wakeLock.acquire(40_000L)
                thread(name = "SosPreflight") {
                    try {
                        Log.i("SosVolumeService", if (SosNativeSender(this).checkOnly())
                            "preflight_ready" else "preflight_not_ready")
                    } catch (error: Exception) {
                        Log.w("SosVolumeService", "preflight_not_ready: ${error.javaClass.simpleName}")
                    } finally {
                        if (wakeLock.isHeld) wakeLock.release()
                    }
                }
            } else if (sending.compareAndSet(false, true)) {
                vibrate(longArrayOf(0, 35))
                val power = getSystemService(PowerManager::class.java)
                val wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Trujillo360:SosSend")
                wakeLock.acquire(150_000L)
                thread(name = "SosBackgroundSend") {
                    try {
                        if (SosNativeSender(this).send()) {
                            Log.i("SosVolumeService", "sos_confirmed")
                            vibrate(longArrayOf(0, 400))
                        } else {
                            Log.w("SosVolumeService", "sos_not_confirmed")
                            vibrate(longArrayOf(0, 70, 90, 70, 90, 70))
                        }
                    } catch (error: Exception) {
                        Log.w("SosVolumeService", "sos_not_confirmed: ${error.javaClass.simpleName}")
                        vibrate(longArrayOf(0, 70, 90, 70, 90, 70))
                    } finally {
                        if (wakeLock.isHeld) wakeLock.release()
                        sending.set(false)
                    }
                }
            }
        }
        return false
    }
}
