package com.azazo1.tucao

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.util.Rational
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * 画中画 (Picture-in-Picture) 的平台侧实现.
 *
 * 只有 Android 8.0 及以上且系统声明了该特性时才可用, 其余情况 isSupported
 * 返回 false, Dart 侧据此隐藏入口.
 *
 * 自动进入的条件由 Dart 侧按播放状态给出: Android 12 起交给系统的
 * setAutoEnterEnabled, 更早的版本在 onUserLeaveHint 里判断, 两条路径不会同时生效.
 */
class PipController(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "com.azazo1.tucao/pip"

        /** 画面尺寸未知时按 16:9 处理. */
        const val DEFAULT_ASPECT_WIDTH = 16
        const val DEFAULT_ASPECT_HEIGHT = 9

        /** 系统接受的宽高比区间, 越界会直接抛异常. */
        val MIN_ASPECT = 1f / 2.39f
        val MAX_ASPECT = 2.39f
    }

    private var channel: MethodChannel? = null

    /** 回到桌面时是否自动进入小窗. */
    private var autoEnter = false

    /** 宽高比的来源尺寸, 取自当前视频画面. */
    private var aspectWidth = DEFAULT_ASPECT_WIDTH
    private var aspectHeight = DEFAULT_ASPECT_HEIGHT

    val supported: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(supported)
            "enter" -> {
                readAspect(call)
                result.success(enterPip(call))
            }
            "setAutoEnter" -> {
                readAspect(call)
                autoEnter = call.argument<Boolean>("enabled") ?: false
                applyAutoEnter()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /** 用户离开当前界面时调用, Android 12 起自动进入由系统参数接管. */
    fun onUserLeaveHint() {
        if (!autoEnter || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return
        }
        enterPip(null)
    }

    /** 小窗状态变化时通知 Dart 侧切换布局. */
    fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        channel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }

    private fun readAspect(call: MethodCall?) {
        val width = call?.argument<Number>("width")?.toInt() ?: 0
        val height = call?.argument<Number>("height")?.toInt() ?: 0
        if (width > 0 && height > 0) {
            aspectWidth = width
            aspectHeight = height
        }
    }

    private fun enterPip(call: MethodCall?): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return enterPipFromOreo(call)
        }
        return false
    }

    /** Android 8.0 起才有画中画, 这里可以放心使用相关 API. */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun enterPipFromOreo(call: MethodCall?): Boolean {
        if (!supported || isInPip() || activity.isFinishing || activity.isDestroyed) {
            return false
        }
        val builder = PictureInPictureParams.Builder().setAspectRatio(aspectRatio())
        readSourceRect(call)?.let { builder.setSourceRectHint(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
        }
        return try {
            activity.enterPictureInPictureMode(builder.build())
        } catch (e: IllegalStateException) {
            // Activity 还没回到前台等情况下系统会拒绝, 由界面给出提示.
            false
        } catch (e: IllegalArgumentException) {
            false
        }
    }

    /** Android 12 起用系统参数表达 "离开时自动进入小窗", 应用不必再猜时机. */
    private fun applyAutoEnter() {
        if (!supported) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applyAutoEnterFromS()
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun applyAutoEnterFromS() {
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(aspectRatio())
            .setAutoEnterEnabled(autoEnter)
            .build()
        try {
            activity.setPictureInPictureParams(params)
        } catch (e: IllegalArgumentException) {
            // 参数不被接受时保持现状, 显式进入仍然可用.
        }
    }

    private fun isInPip(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return activity.isInPictureInPictureMode
        }
        return false
    }

    /** 宽高比收敛到系统区间, 用千分位整数表达, 避免出现零分母. */
    private fun aspectRatio(): Rational {
        val raw = aspectWidth.toFloat() / aspectHeight.toFloat()
        return Rational((raw.coerceIn(MIN_ASPECT, MAX_ASPECT) * 1000).roundToInt(), 1000)
    }

    /** 小窗动画的起点, 由 Dart 侧按播放器区域给出, 单位是设备像素. */
    private fun readSourceRect(call: MethodCall?): Rect? {
        if (call == null) {
            return null
        }
        val left = call.argument<Number>("left")?.toInt() ?: return null
        val top = call.argument<Number>("top")?.toInt() ?: return null
        val right = call.argument<Number>("right")?.toInt() ?: return null
        val bottom = call.argument<Number>("bottom")?.toInt() ?: return null
        if (right <= left || bottom <= top) {
            return null
        }
        return Rect(left, top, right, bottom)
    }
}
