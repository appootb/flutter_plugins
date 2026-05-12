package dev.appootb.advanced_clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Mobile clipboard: only emits `text`, `html`, `url`, and `image` (same wire types as
 * common desktop payloads). Unmapped or proprietary items are skipped.
 */
class AdvancedClipboardPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "advanced_clipboard")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "advanced_clipboard_events")
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {}

                override fun onCancel(arguments: Any?) {}
            },
        )
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val ctx = appContext
        when (call.method) {
            "getPlatformVersion" ->
                result.success("Android ${Build.VERSION.RELEASE}")
            "startListening", "stopListening" -> result.success(null)
            "readCurrent" -> {
                if (ctx == null) {
                    result.success(null)
                    return
                }
                result.success(readPrimaryClip(ctx))
            }
            "write" -> result.success(false)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        appContext = null
    }

    private fun readPrimaryClip(context: Context): Map<String, Any?>? {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        if (!cm.hasPrimaryClip()) return null
        val clip = cm.primaryClip ?: return null

        val parts = mutableListOf<Map<String, Any?>>()
        for (i in 0 until clip.itemCount) {
            addClipItemParts(context, clip.getItemAt(i), parts)
        }
        if (parts.isEmpty()) return null

        val ts = System.currentTimeMillis()
        val uid = "snapshot-$ts"

        val ordered = parts.sortedBy { mobileTypeOrderIndex(it["type"] as? String) }

        return mapOf(
            "timestamp" to ts,
            "sourceApp" to mobileSourceAppMap(),
            "contents" to ordered,
            "uniqueIdentifier" to uid,
        )
    }

    /**
     * Fixed-shape `sourceApp` for mobile: name `Android`, `bundleId` = [Build.MODEL],
     * `icon` from [MOBILE_SOURCE_APP_ICON_BASE64_ANDROID].
     */
    private fun mobileSourceAppMap(): Map<String, Any?> {
        val model = Build.MODEL?.ifBlank { null } ?: "unknown"
        val iconB64 = MOBILE_SOURCE_APP_ICON_BASE64_ANDROID
        val icon: ByteArray? =
            if (iconB64.isNotBlank()) {
                runCatching { Base64.decode(iconB64, Base64.DEFAULT) }.getOrNull()
            } else {
                null
            }
        return mapOf(
            "name" to "Android",
            "bundleId" to model,
            "icon" to icon,
        )
    }

    private fun mobileTypeOrderIndex(type: String?): Int =
        when (type) {
            "image" -> 0
            "html" -> 1
            "url" -> 2
            "text" -> 3
            else -> 99
        }

    private fun addClipItemParts(
        context: Context,
        item: ClipData.Item,
        sink: MutableList<Map<String, Any?>>,
    ) {
        @Suppress("DEPRECATION")
        item.htmlText?.toString()?.takeIf { it.isNotEmpty() }?.let { h ->
            sink.add(contentPart("html", h.toByteArray(Charsets.UTF_8), null))
        }

        val textSeq = item.text
        textSeq?.toString()?.takeIf { it.isNotEmpty() }?.let { text ->
            val bytes = text.toByteArray(Charsets.UTF_8)
            val looksHttp =
                text.startsWith("http://") || text.startsWith("https://")
            if (looksHttp) {
                sink.add(contentPart("url", bytes, null))
                sink.add(contentPart("text", bytes, null))
            } else {
                val asUri = runCatching { Uri.parse(text) }.getOrNull()
                if (asUri != null && asUri.scheme == "file") {
                    appendMobileUri(context, asUri, sink)
                } else {
                    sink.add(contentPart("text", bytes, null))
                }
            }
        }

        val uri = item.uri ?: return
        appendMobileUri(context, uri, sink)
    }

    private fun appendMobileUri(
        context: Context,
        uri: Uri,
        sink: MutableList<Map<String, Any?>>,
    ) {
        val scheme = uri.scheme?.lowercase() ?: return
        when {
            scheme == "http" || scheme == "https" -> {
                val s = uri.toString()
                val b = s.toByteArray(Charsets.UTF_8)
                sink.add(contentPart("url", b, null))
                sink.add(contentPart("text", b, null))
            }
            scheme == "file" -> {
                val path = uri.path?.takeIf { it.isNotEmpty() } ?: run {
                    sink.add(contentPart("url", uri.toString().toByteArray(Charsets.UTF_8), null))
                    return
                }
                tryLoadImageFromPath(path)?.let { (data, fmt) ->
                    sink.add(contentPart("image", data, mapOf("format" to fmt)))
                } ?: run {
                    sink.add(contentPart("url", uri.toString().toByteArray(Charsets.UTF_8), null))
                }
            }
            else -> {
                val resolver = context.contentResolver
                val mime = resolver.getType(uri)
                if (mime != null && mime.startsWith("image/")) {
                    try {
                        resolver.openInputStream(uri)?.use { input ->
                            val data = input.readBytes()
                            if (data.isNotEmpty()) {
                                val fmt =
                                    when {
                                        mime.contains("png", ignoreCase = true) -> "png"
                                        mime.contains("jpeg", ignoreCase = true) ||
                                            mime.contains("jpg", ignoreCase = true)
                                        -> "jpeg"
                                        else -> "image"
                                    }
                                sink.add(
                                    contentPart(
                                        "image",
                                        data,
                                        mapOf("format" to fmt),
                                    ),
                                )
                            }
                        }
                    } catch (_: Exception) {
                    }
                } else {
                    sink.add(contentPart("url", uri.toString().toByteArray(Charsets.UTF_8), null))
                }
            }
        }
    }

    private fun tryLoadImageFromPath(path: String): Pair<ByteArray, String>? {
        val ext = path.substringAfterLast('.', "").lowercase()
        if (ext !in imagePathExtensions) return null
        val f = File(path)
        if (!f.isFile || f.length() > maxInlineImageBytes) return null
        return try {
            val raw = f.readBytes()
            if (raw.isEmpty()) return null
            if (ext == "png" || ext == "gif") {
                Pair(raw, ext)
            } else {
                val bmp = BitmapFactory.decodeFile(path) ?: return null
                val out = ByteArrayOutputStream()
                bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                Pair(out.toByteArray(), "png")
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun contentPart(
        type: String,
        raw: ByteArray,
        meta: Map<String, Any>?,
    ): Map<String, Any?> {
        val m = LinkedHashMap<String, Any?>()
        m["type"] = type
        m["raw"] = raw
        m["metadata"] = meta
        return m
    }

    companion object {
        /** Embedded 512dp Android mascot icon (PNG), raw base64. */
        const val MOBILE_SOURCE_APP_ICON_BASE64_ANDROID = "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"

        private const val maxInlineImageBytes = 40 * 1024 * 1024
        private val imagePathExtensions =
            setOf("png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif")
    }
}
