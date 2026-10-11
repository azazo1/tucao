# just device::run [args...]
# 在已连接的设备上运行调试构建.
run *args:
    flutter run {{args}}

# just device::install [args...]
# 安装已构建的 Release APK 到已连接设备.
install *args:
    flutter install --release {{args}}

# 查看已连接设备上的应用日志.
logs:
    adb logcat -s flutter
