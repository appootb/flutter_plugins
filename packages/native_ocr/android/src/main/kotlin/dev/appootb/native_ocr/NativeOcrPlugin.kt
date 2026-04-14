package dev.appootb.native_ocr

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

/** NativeOcrPlugin */
class NativeOcrPlugin :
    FlutterPlugin,
    MethodCallHandler {
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "native_ocr")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "recognizeText" -> handleRecognizeText(call, result)
            "recognizeTextFromBytes" -> handleRecognizeTextFromBytes(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun handleRecognizeText(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val imagePath = args?.get("imagePath") as? String
        if (imagePath.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Missing or invalid 'imagePath'.", null)
            return
        }

        val file = File(imagePath)
        if (!file.exists()) {
            result.error("INVALID_IMAGE", "Image file does not exist.", imagePath)
            return
        }

        val bitmap = BitmapFactory.decodeFile(imagePath)
        if (bitmap == null) {
            result.error("INVALID_IMAGE", "Failed to decode image file.", imagePath)
            return
        }

        val image = InputImage.fromBitmap(bitmap, 0)
        recognizer.process(image)
            .addOnSuccessListener { visionText ->
                mainHandler.post { result.success(visionText.text ?: "") }
            }
            .addOnFailureListener { e ->
                mainHandler.post { result.error("OCR_ERROR", "ML Kit OCR failed.", e.localizedMessage) }
            }
    }

    private fun handleRecognizeTextFromBytes(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val imageBytes = args?.get("imageBytes")
        val bytes =
            when (imageBytes) {
                is ByteArray -> imageBytes
                // Defensive fallback: some callers may pass List<int>.
                is List<*> ->
                    imageBytes
                        .mapNotNull { (it as? Number)?.toInt() }
                        .map { it.coerceIn(0, 255).toByte() }
                        .toByteArray()
                else -> null
            }
        if (bytes == null || bytes.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Missing or invalid 'imageBytes'.", null)
            return
        }

        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        if (bitmap == null) {
            result.error("INVALID_IMAGE", "Failed to decode image bytes.", null)
            return
        }

        val image = InputImage.fromBitmap(bitmap, 0)
        recognizer.process(image)
            .addOnSuccessListener { visionText ->
                mainHandler.post { result.success(visionText.text ?: "") }
            }
            .addOnFailureListener { e ->
                mainHandler.post { result.error("OCR_ERROR", "ML Kit OCR failed.", e.localizedMessage) }
            }
    }
}
