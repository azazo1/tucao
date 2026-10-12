package com.azazo1.tucao

import android.content.res.Configuration
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /** 画中画状态与平台通道, 首次用到时创建. */
    private val pip by lazy { PipController(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pip.attach(flutterEngine.dartExecutor.binaryMessenger)
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
