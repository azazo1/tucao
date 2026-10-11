# just build::android [args...]
# 构建 Android Release APK.
android *args:
    flutter build apk --release --no-pub {{args}}

# just build::android-split [args...]
# 构建分 ABI 的 Android Release APK.
android-split *args:
    flutter build apk --release --split-per-abi --no-pub {{args}}

# just build::android-debug [args...]
# 构建 Android Debug APK, 用于本地调试.
android-debug *args:
    flutter build apk --debug --no-pub {{args}}

# just build::android-aab [args...]
# 构建用于应用商店发布的 Android App Bundle.
android-aab *args:
    flutter build appbundle --release --no-pub {{args}}
