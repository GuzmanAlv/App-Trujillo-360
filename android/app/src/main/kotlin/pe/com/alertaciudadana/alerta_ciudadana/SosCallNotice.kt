package pe.com.alertaciudadana.alerta_ciudadana

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

/** Local, truthful notice while waiting. Never sent into the call microphone. */
class SosCallNotice(context: Context) {
    private var requested = false
    private var ready = false
    private var engine: TextToSpeech? = null
    init {
        engine = TextToSpeech(context.applicationContext) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready && requested) speak()
        }
    }
    private fun speak() {
        val tts = engine ?: return
        var result = tts.setLanguage(Locale("es", "PE"))
        if (result < 0) result = tts.setLanguage(Locale("es", "ES"))
        if (result < 0) return
        tts.setSpeechRate(1.0f)
        tts.speak("Este canal es para emergencias reales. El uso malicioso de las llamadas puede ocasionar la revisión y suspensión de tu cuenta.", TextToSpeech.QUEUE_FLUSH, null, "sos_notice")
    }
    fun play() { requested = true; if (ready) speak() }
    fun stop() { requested = false; engine?.stop() }
    fun dispose() { stop(); engine?.shutdown(); engine = null }
}
