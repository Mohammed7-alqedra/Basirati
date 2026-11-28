package com.baseerte.baseerte_ai

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Sends Volume Up presses to Flutter:
 *  - short press -> "volumeUpShort" (room number, later)
 *  - long press  -> "volumeUpLong"  (say the objects in front of the user)
 * The volume itself does not change while the app is open.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var downTime = 0L
    private var longPressSent = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "basirati/keys")
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            when (event.action) {
                KeyEvent.ACTION_DOWN -> {
                    if (event.repeatCount == 0) {
                        downTime = event.eventTime
                        longPressSent = false
                    } else if (!longPressSent && event.eventTime - downTime >= LONG_PRESS_MS) {
                        longPressSent = true
                        channel?.invokeMethod("volumeUpLong", null)
                    }
                }
                KeyEvent.ACTION_UP -> {
                    if (!longPressSent) channel?.invokeMethod("volumeUpShort", null)
                }
            }
            return true   // consume the key so the volume does not change
        }
        return super.dispatchKeyEvent(event)
    }

    companion object {
        private const val LONG_PRESS_MS = 600L
    }
}
