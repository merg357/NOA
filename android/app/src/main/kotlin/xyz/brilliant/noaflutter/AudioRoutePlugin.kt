package xyz.brilliant.noaflutter

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * AudioRoutePlugin — exposes Android communication-audio device management
 * to Flutter via a MethodChannel at "noa/audio_route".
 *
 * Supported methods:
 *   list_devices  → List<Map> of {id, name, type}
 *   get_current   → Map? {id, name, type} of currently selected device
 *   set_device    → Boolean, args: {id: String}
 *   clear_device  → void
 *
 * Requires API 31+ (Android S) for getAvailableCommunicationDevices /
 * setCommunicationDevice.  On older APIs, list_devices returns an empty list
 * and set/clear are no-ops so the Flutter side degrades gracefully.
 */
object AudioRoutePlugin {

    private const val CHANNEL = "noa/audio_route"

    fun register(messenger: BinaryMessenger, context: Context) {
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "list_devices" -> {
                    result.success(listDevices(audioManager))
                }
                "get_current" -> {
                    result.success(getCurrentDevice(audioManager))
                }
                "set_device" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("INVALID_ARG", "id is required", null)
                    } else {
                        result.success(setDevice(audioManager, id))
                    }
                }
                "clear_device" -> {
                    clearDevice(audioManager)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private fun listDevices(audioManager: AudioManager): List<Map<String, String>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return emptyList()
        return audioManager.availableCommunicationDevices.map { it.toMap() }
    }

    private fun getCurrentDevice(audioManager: AudioManager): Map<String, String>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return audioManager.communicationDevice?.toMap()
    }

    private fun setDevice(audioManager: AudioManager, id: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val device = audioManager.availableCommunicationDevices
            .firstOrNull { it.id.toString() == id }
            ?: return false
        return audioManager.setCommunicationDevice(device)
    }

    private fun clearDevice(audioManager: AudioManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        audioManager.clearCommunicationDevice()
    }

    private fun AudioDeviceInfo.toMap(): Map<String, String> = mapOf(
        "id" to id.toString(),
        "name" to productName.toString().ifEmpty { typeName() },
        "type" to typeName(),
    )

    private fun AudioDeviceInfo.typeName(): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "phone"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER  -> "speakerphone"
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wiredHeadset"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER      -> "bluetooth"
        else                                   -> "unknown"
    }
}
