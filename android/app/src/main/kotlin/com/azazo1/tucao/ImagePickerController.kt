package com.azazo1.tucao

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 图评选图的平台侧实现.
 *
 * 用 ACTION_OPEN_DOCUMENT 打开系统选择器, 而不是申请相册权限: 站点只需要
 * 一张图片的字节, 而 SAF 会把选中文件的临时读取权限交还给调用方, 用户不
 * 授权整个相册也能用. 用户取消时返回 null, 由 Dart 侧当成没选.
 *
 * 字节在后台线程读取, 大图不会卡住主线程; 读出的字节数在 Dart 侧再按站点
 * 的 2MB 限制判断, 这里只拦住明显异常的巨型文件.
 */
class ImagePickerController(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "com.azazo1.tucao/image_picker"

        /** 选择图片的请求码, 只在本应用内使用. */
        const val REQUEST_PICK_IMAGE = 0x7A11

        /** 平台侧兜底上限, 超过的图本站点也不会接受. */
        const val MAX_BYTES = 10 * 1024 * 1024

        /** 拿不到文件名时用的默认名, 后缀保留图片类型. */
        const val DEFAULT_NAME = "image.jpg"
    }

    private var channel: MethodChannel? = null

    /** 等待结果的调用方, 为空表示当前没有进行中的选择. */
    private var pending: MethodChannel.Result? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pickImage") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("BUSY", "上一次选择还没有结束", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        pending = result
        try {
            activity.startActivityForResult(intent, REQUEST_PICK_IMAGE)
        } catch (e: Exception) {
            pending = null
            result.error("NO_PICKER", "系统里没有可用的图片选择器", e.message)
        }
    }

    /**
     * 由 MainActivity 转发选择结果.
     *
     * 返回 true 表示这个结果属于本控制器, 其它请求码交给框架继续分发.
     */
    fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_PICK_IMAGE) {
            return false
        }
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        readAsync(uri, result)
        return true
    }

    private fun readAsync(uri: Uri, result: MethodChannel.Result) {
        Thread {
            try {
                val bytes = activity.contentResolver.openInputStream(uri)?.use {
                    it.readBytes()
                } ?: throw IllegalStateException("读不到图片内容")
                if (bytes.size > MAX_BYTES) {
                    throw IllegalArgumentException("图片超过 10MB")
                }
                val payload = mapOf("bytes" to bytes, "name" to queryName(uri))
                activity.runOnUiThread { result.success(payload) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("READ_FAILED", "读取图片失败", e.message)
                }
            }
        }.start()
    }

    /** 取系统给出的显示名, 取不到时用带后缀的默认名. */
    private fun queryName(uri: Uri): String {
        var name = DEFAULT_NAME
        activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    cursor.getString(index)
                        ?.takeIf { it.isNotBlank() }
                        ?.let { name = it }
                }
            }
        }
        return name
    }
}
