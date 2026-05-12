package dev.appootb.advanced_clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

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

        return mapOf(
            "timestamp" to ts,
            "sourceApp" to
                mapOf<String, Any?>(
                    "name" to null,
                    "bundleId" to null,
                    "icon" to null,
                ),
            "contents" to parts,
            "uniqueIdentifier" to uid,
        )
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
                sink.add(contentPart("text", bytes, null))
            }
        }

        val uri = item.uri ?: return
        handleUri(context, uri, sink)
    }

    private fun handleUri(
        context: Context,
        uri: Uri,
        sink: MutableList<Map<String, Any?>>,
    ) {
        if ("file" == uri.scheme) {
            val path =
                uri.path?.takeIf { it.isNotEmpty() } ?: run {
                    sink.add(contentPart("url", uri.toString().toByteArray(Charsets.UTF_8), null))
                    return
                }
            sink.add(pathFilePart(path))
            return
        }

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
                                else -> "binary"
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
            return
        }

        uri.toString().takeIf { it.isNotEmpty() }?.let { s ->
            sink.add(contentPart("url", s.toByteArray(Charsets.UTF_8), null))
        }
    }

    private fun pathFilePart(path: String): Map<String, Any?> {
        val bytes = path.toByteArray(Charsets.UTF_8)
        val file = File(path)
        val meta =
            mutableMapOf<String, Any>()
        meta["isDirectory"] = file.isDirectory
        return contentPart("fileUrl", bytes, meta)
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
}
