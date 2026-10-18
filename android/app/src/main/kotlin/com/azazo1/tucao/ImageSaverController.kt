package com.azazo1.tucao

import android.app.Activity
import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/**
 * 把图片字节写进系统相册的平台侧实现.
 *
 * Android 10 起走 MediaStore, 写入 Pictures/Tucao, 不需要申请存储权限;
 * 更早的版本没有分区存储, 只能写应用自己的外部图片目录, 再通知相册刷新,
 * 因此返回值会给出真实落盘位置, 由 Dart 侧原样提示给用户.
 */
class ImageSaverController(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "com.azazo1.tucao/image_saver"

        /** 相册里的子目录名. */
        const val ALBUM = "Tucao"

        /** 文件名里不允许出现的字符. */
        val ILLEGAL_NAME_CHARS = Regex("[\\\\/:*?\"<>|\\s]+")
    }

    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save") {
            result.notImplemented()
            return
        }
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
            result.error("EMPTY_IMAGE", "图片内容为空", null)
            return
        }
        val name = normalizeName(call.argument<String>("fileName"))
        // 写文件不能占着主线程, 结果回到主线程再回复.
        Thread {
            try {
                val location = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveToMediaStore(bytes, name)
                } else {
                    saveToAppPictures(bytes, name)
                }
                activity.runOnUiThread { result.success(location) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("SAVE_FAILED", e.message ?: "保存失败", null)
                }
            }
        }.start()
    }

    /** 写入系统相册, 返回相册内的相对位置. */
    private fun saveToMediaStore(bytes: ByteArray, name: String): String {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mimeOf(name))
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                "${Environment.DIRECTORY_PICTURES}/$ALBUM",
            )
            // 写完之前不让其他应用看到这张半成品.
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = activity.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("系统没有返回新的图片位置")
        try {
            val stream = resolver.openOutputStream(uri)
                ?: throw IllegalStateException("无法写入相册")
            stream.use { it.write(bytes) }
        } finally {
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return "${Environment.DIRECTORY_PICTURES}/$ALBUM/$name"
    }

    /** Android 9 及以下: 写应用外部目录并让相册扫描到它. */
    private fun saveToAppPictures(bytes: ByteArray, name: String): String {
        val root = activity.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            ?: activity.filesDir
        val dir = File(root, ALBUM)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建图片目录")
        }
        val file = File(dir, name)
        file.writeBytes(bytes)
        MediaScannerConnection.scanFile(
            activity,
            arrayOf(file.absolutePath),
            arrayOf(mimeOf(name)),
            null,
        )
        return file.absolutePath
    }

    private fun normalizeName(raw: String?): String {
        val trimmed = raw?.trim().orEmpty()
        val base = if (trimmed.isEmpty()) "tucao" else trimmed
        val safe = base.replace(ILLEGAL_NAME_CHARS, "_")
        return if (safe.contains('.')) safe else "$safe.jpg"
    }

    private fun mimeOf(name: String): String =
        when (name.substringAfterLast('.', "").lowercase(Locale.ROOT)) {
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }
}
