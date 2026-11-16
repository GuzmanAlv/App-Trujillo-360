package pe.com.alertaciudadana.alerta_ciudadana

import android.content.Context
import android.util.AtomicFile
import java.io.DataInputStream

internal object SosVolumeConfig {
    private fun file(context: Context) = AtomicFile(context.filesDir.resolve("sos_volume_state"))

    fun read(context: Context): Pair<Boolean, Boolean> = try {
        DataInputStream(file(context).openRead()).use { input ->
            input.readBoolean() to input.readBoolean()
        }
    } catch (_: Exception) {
        val previous = context.getSharedPreferences("sos_volume", Context.MODE_PRIVATE)
        if (previous.contains("enabled")) {
            val state = previous.getBoolean("enabled", false) to previous.getBoolean("test_only", true)
            write(context, state.first, state.second)
            state
        } else false to true
    }

    fun write(context: Context, enabled: Boolean, testOnly: Boolean) {
        val atomic = file(context)
        val output = atomic.startWrite()
        try {
            output.write(if (enabled) 1 else 0)
            output.write(if (testOnly) 1 else 0)
            atomic.finishWrite(output)
        } catch (error: Exception) {
            atomic.failWrite(output)
            throw error
        }
    }
}
