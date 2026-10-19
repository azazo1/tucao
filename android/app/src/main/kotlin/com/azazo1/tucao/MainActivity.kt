package com.azazo1.tucao

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /** 画中画状态与平台通道, 首次用到时创建. */
    private val pip by lazy { PipController(this) }

    /** 保存图片到相册的平台通道. */
    private val imageSaver by lazy { ImageSaverController(this) }

    /** 图评选图的平台通道. */
    private val imagePicker by lazy { ImagePickerController(this) }

    /** 更新包安装的平台通道. */
    private val apkInstaller by lazy { ApkInstallerController(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        pip.attach(messenger)
        imageSaver.attach(messenger)
        imagePicker.attach(messenger)
        apkInstaller.attach(messenger)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        // 先交给框架分发给各插件, 再处理本活动自己的请求码.
        super.onActivityResult(requestCode, resultCode, data)
        imagePicker.onActivityResult(requestCode, resultCode, data)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        pip.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        // 该回调只在 Android 8.0 及以上触发, 仍显式判断一次以通过 API 检查.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        }
        pip.onPictureInPictureModeChanged(isInPictureInPictureMode)
    }
}
