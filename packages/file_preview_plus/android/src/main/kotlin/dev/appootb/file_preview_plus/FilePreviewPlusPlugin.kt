package dev.appootb.file_preview_plus

import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/** FilePreviewPlusPlugin */
class FilePreviewPlusPlugin :
    FlutterPlugin,
    MethodCallHandler {
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val executor = Executors.newCachedThreadPool()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "file_preview_plus")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "getFileInfo" -> handleGetFileInfo(call, result)
            "getThumbnail" -> handleGetThumbnail(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}

private fun guessMimeType(path: String): String? {
    val ext = MimeTypeMap.getFileExtensionFromUrl(path).lowercase()
    if (ext.isBlank()) return null
    return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
}

private fun bitmapToPngBytes(bitmap: Bitmap): ByteArray {
    val out = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
    return out.toByteArray()
}

private fun isApk(path: String): Boolean = path.lowercase().endsWith(".apk")

private fun FilePreviewPlusPlugin.handleGetFileInfo(call: MethodCall, result: Result) {
    val path = call.argument<String>("path")
    if (path.isNullOrBlank()) {
        result.error("invalid_args", "Missing path", null)
        return
    }
    executor.execute {
        try {
            val f = File(path)
            val map = hashMapOf<String, Any?>(
                "path" to path,
                "name" to f.name,
                "size" to (if (f.exists()) f.length() else 0L),
                "modifiedMs" to (if (f.exists()) f.lastModified() else 0L),
                "isDirectory" to f.isDirectory
            )
            val mime = guessMimeType(path)
            if (mime != null) map["mimeType"] = mime
            result.success(map.filterValues { it != null })
        } catch (e: Exception) {
            result.error("file_info_failed", e.message, null)
        }
    }
}

private fun FilePreviewPlusPlugin.handleGetThumbnail(call: MethodCall, result: Result) {
    val path = call.argument<String>("path")
    if (path.isNullOrBlank()) {
        result.error("invalid_args", "Missing path", null)
        return
    }
    val width = (call.argument<Number>("width")?.toInt() ?: 256).coerceAtLeast(1)
    val height = (call.argument<Number>("height")?.toInt() ?: 256).coerceAtLeast(1)

    executor.execute {
        try {
            val bytes = createThumbnailBytes(appContext, path, width, height)
            result.success(bytes)
        } catch (e: Exception) {
            result.error("thumbnail_failed", e.message, null)
        }
    }
}

private fun createThumbnailBytes(context: Context, path: String, width: Int, height: Int): ByteArray? {
    val file = File(path)
    if (!file.exists()) return null

    if (isApk(path)) {
        val pm: PackageManager = context.packageManager
        val pi = pm.getPackageArchiveInfo(path, 0)
        if (pi != null) {
            val appInfo = pi.applicationInfo
            appInfo.sourceDir = path
            appInfo.publicSourceDir = path
            val drawable = pm.getApplicationIcon(appInfo)
            val bmp = drawableToBitmap(drawable, width, height)
            return bitmapToPngBytes(bmp)
        }
    }

    val uri = Uri.fromFile(file)
    val size = Size(width, height)

    // Android Q+: ContentResolver.loadThumbnail where possible.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        try {
            val bmp = context.contentResolver.loadThumbnail(uri, size, null)
            return bitmapToPngBytes(bmp)
        } catch (_: Throwable) {
            // fallback below
        }
    }

    // Best-effort fallback for images/videos.
    val mime = guessMimeType(path)
    val isVideo = mime?.startsWith("video/") == true
    val isImage = mime?.startsWith("image/") == true

    val bmp: Bitmap? = when {
        isVideo -> ThumbnailUtils.createVideoThumbnail(file, size, null)
        isImage -> ThumbnailUtils.createImageThumbnail(file, size, null)
        else -> null
    }

    if (bmp != null) return bitmapToPngBytes(bmp)

    // Final fallback: decode bounds and scale a bitmap (may fail for non-images).
    return try {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return null
        val sample = calculateInSampleSize(options.outWidth, options.outHeight, width, height)
        val opts2 = BitmapFactory.Options().apply { inSampleSize = sample }
        val decoded = BitmapFactory.decodeFile(path, opts2) ?: return null
        val scaled = Bitmap.createScaledBitmap(decoded, width, height, true)
        bitmapToPngBytes(scaled)
    } catch (_: Throwable) {
        null
    }
}

private fun calculateInSampleSize(srcW: Int, srcH: Int, dstW: Int, dstH: Int): Int {
    var inSampleSize = 1
    var halfW = srcW / 2
    var halfH = srcH / 2
    while (halfW / inSampleSize >= dstW && halfH / inSampleSize >= dstH) {
        inSampleSize *= 2
    }
    return inSampleSize.coerceAtLeast(1)
}

private fun drawableToBitmap(drawable: android.graphics.drawable.Drawable, width: Int, height: Int): Bitmap {
    val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = android.graphics.Canvas(bmp)
    drawable.setBounds(0, 0, width, height)
    drawable.draw(canvas)
    return bmp
}
