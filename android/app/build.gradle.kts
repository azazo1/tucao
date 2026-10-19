import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.azazo1.tucao"
    compileSdk = flutter.compileSdkVersion
    // ci 上用镜像预装的 NDK (24.04 与 26.04 都是 27.3.13750724), 免得每个任务现下约 600MB;
    // 本地沿用 Flutter 默认版本, 不为了构建再装一份 NDK.
    // app 模块没有自己的 native 源码, 这里只用于 strip 预编译 so; 唯一自编译 native 的
    // jni 插件已自带 16KB 对齐链接参数, 因此 ci 上降到 27.3 不影响产物.
    ndkVersion = if (providers.environmentVariable("CI").isPresent) {
        providers.gradleProperty("tucao.ndkVersion").get()
    } else {
        flutter.ndkVersion
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 测试包可以传 -PappIdSuffix=.test 构建, 与正式包装在同一台设备上互不覆盖.
        val appIdSuffix = providers.gradleProperty("appIdSuffix").getOrElse("")
        applicationId = "com.azazo1.tucao$appIdSuffix"
        // 两个包同时在桌面上时按后缀区分名称.
        manifestPlaceholders["appLabel"] = if (appIdSuffix.isEmpty()) {
            "吐槽"
        } else {
            "吐槽${appIdSuffix}"
        }
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 发布构建的签名, 密钥由 ci 从 secrets 还原到 android/key.properties.
    // 本地没有该文件时回落到调试签名, 保证直接构建不失败.
    val keyProperties = Properties().also {
        val file = rootProject.file("key.properties")
        if (file.exists()) {
            it.load(file.inputStream())
        }
    }

    val releaseSigning = keyProperties.getProperty("storeFile")?.let { storeFile ->
        signingConfigs.create("release") {
            this.storeFile = file(storeFile)
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            signingConfig = releaseSigning ?: signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 更新包经 FileProvider 换成 content uri 交给系统安装器, 这里显式声明,
    // 免得依赖某个插件把 androidx.core 传递进来.
    implementation("androidx.core:core:1.13.1")
}
