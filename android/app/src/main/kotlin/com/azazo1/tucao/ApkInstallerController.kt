package com.azazo1.tucao

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内更新包的安装.
 *
 * 下载好的 apk 放在外部应用专属目录, 系统安装器不接受直接给出的文件路径,
 * 因此经 FileProvider 换成 content uri 再发起安装意图.
 *
 * Android 8.0 起安装未知来源应用要由用户在系统设置里逐个应用放行,
 * canInstall 就是本应用的放行状态, 界面据此先引导用户去设置页.
 */
class ApkInstallerController(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "com.azazo1.tucao/apk_installer"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "canInstall" -> result.success(canInstall())
            "openInstallSettings" -> result.success(openInstallSettings())
            "install" -> result.success(install(call.argument<String>("path")))
            else -> result.notImplemented()
        }
    }

    /** Android 8.0 之前没有逐个应用的来源限制, 视为已经放行. */
    private fun canInstall(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return true
        }
        return activity.packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
            .setData(Uri.parse("package:${activity.packageName}"))
        return try {
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            // 少数精简系统没有这一页, 由界面提示用户手动放行.
            false
        }
    }

    private fun install(path: String?): Boolean {
        if (path.isNullOrEmpty()) {
            return false
        }
        val file = File(path)
        if (!file.isFile) {
            return false
        }
        return try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, APK_MIME)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            // 缺少安装权限, 路径不可共享或系统没有安装器时都走这里.
            false
        }
    }
}
