package com.example.gabay

import androidx.annotation.NonNull
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val CHANNEL = "com.example.gabay/arcore"

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "checkArCoreAvailability" -> {
          try {
            val availability = ArCoreApk.getInstance().checkAvailability(this)

            // Return the full enum name so Flutter can make safer decisions.
            // Possible values include:
            // UNKNOWN_CHECKING, UNKNOWN_TIMED_OUT, UNSUPPORTED_DEVICE_NOT_CAPABLE,
            // SUPPORTED_NOT_INSTALLED, SUPPORTED_APK_TOO_OLD, SUPPORTED_INSTALLED, etc.
            result.success(availability.name)
          } catch (e: Exception) {
            result.error("ARCORE_CHECK_FAILED", e.message, null)
          }
        }
        else -> result.notImplemented()
      }
    }
  }
}
