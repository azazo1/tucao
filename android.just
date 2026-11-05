[private]
default:
    @just --list --justfile {{justfile_directory()}}/android.just

# gradle/jvm 不认 HTTPS_PROXY 这类环境变量, 只认 JVM 系统属性, 这里从 HTTPS_PROXY 推出来注入.
# 支持 http:// 与 https:// 形态, socks5:// 形态按 http 代理端口处理 (适配 clash 这类混合端口).
# 未设置 HTTPS_PROXY (含小写与 HTTP_PROXY 回退) 时不注入任何参数.
proxy_url := trim(env("HTTPS_PROXY", env("https_proxy", env("HTTP_PROXY", env("http_proxy", "")))))
proxy_strip_socksh := trim_start_matches(proxy_url, "socks5h://")
proxy_strip_socks5 := trim_start_matches(proxy_strip_socksh, "socks5://")
proxy_strip_socks := trim_start_matches(proxy_strip_socks5, "socks://")
proxy_strip_https := trim_start_matches(proxy_strip_socks, "https://")
proxy_hostport := trim_end_matches(trim_start_matches(proxy_strip_https, "http://"), "/")
proxy_host := replace_regex(proxy_hostport, ":[0-9]+$", "")
proxy_port := replace_regex(proxy_hostport, "^.*:", "")

# 省掉端口时只给 host, 让 JVM 走默认端口 80 与 443.
jvm_proxy_opts := if proxy_host == "" {
    ""
} else if proxy_host == proxy_hostport {
    "-Dhttp.proxyHost=" + proxy_host + " -Dhttps.proxyHost=" + proxy_host
} else {
    "-Dhttp.proxyHost=" + proxy_host + " -Dhttp.proxyPort=" + proxy_port + " -Dhttps.proxyHost=" + proxy_host + " -Dhttps.proxyPort=" + proxy_port
}

# 保留调用者已有的参数, 只追加代理.
jvm_java_opts := trim(env("JAVA_OPTS", "") + " " + jvm_proxy_opts)
jvm_gradle_opts := trim(env("GRADLE_OPTS", "") + " " + jvm_proxy_opts)

# 获取 Flutter 依赖.
[group('依赖与环境')]
deps:
    flutter pub get

# 检查可更新的 Flutter 依赖.
[group('依赖与环境')]
outdated:
    flutter pub outdated

# 显示 Flutter 开发环境诊断信息.
[group('依赖与环境')]
doctor:
    flutter doctor -v

# 显示 Flutter 可用设备.
[group('依赖与环境')]
devices:
    flutter devices

# 清理项目构建产物.
[group('依赖与环境')]
clean:
    flutter clean

# 运行 Dart 和 Flutter 静态检查.
[group('检查')]
analyze:
    flutter analyze

# just android test [args...]
# 运行 Flutter 测试.
[group('检查')]
test *args:
    flutter test {{args}}

# just android build [args...]
# 构建 Android Release APK.
[group('构建')]
[env('JAVA_OPTS', jvm_java_opts)]
[env('GRADLE_OPTS', jvm_gradle_opts)]
build *args:
    flutter build apk --release --no-pub {{args}}

# just android build-split [args...]
# 构建分 ABI 的 Android Release APK.
[group('构建')]
[env('JAVA_OPTS', jvm_java_opts)]
[env('GRADLE_OPTS', jvm_gradle_opts)]
build-split *args:
    flutter build apk --release --split-per-abi --no-pub {{args}}

# just android build-debug [args...]
# 构建 Android Debug APK, 用于本地调试.
[group('构建')]
[env('JAVA_OPTS', jvm_java_opts)]
[env('GRADLE_OPTS', jvm_gradle_opts)]
build-debug *args:
    flutter build apk --debug --no-pub {{args}}

# just android bundle [args...]
# 构建用于应用商店发布的 Android App Bundle.
[group('构建')]
[env('JAVA_OPTS', jvm_java_opts)]
[env('GRADLE_OPTS', jvm_gradle_opts)]
bundle *args:
    flutter build appbundle --release --no-pub {{args}}

# 生成发布产物 (按架构拆分的 release apk).
[group('构建')]
dist:
    uv run --no-project python scripts/dist.py

# just android run [args...]
# 在已连接的设备上运行调试构建.
[group('运行')]
run *args:
    flutter run {{args}}

# just android install [args...]
# 安装已构建的 Release APK 到已连接设备.
[group('运行')]
install *args:
    flutter install --release {{args}}

# 查看已连接设备上的应用日志.
[group('运行')]
logs:
    adb logcat -s flutter

# 需要 PATH 上有 resvg. 图形与配色定义在 scripts/gen-icons.py 开头.
# 生成应用图标资源 (adaptive icon, 各密度 PNG 与 logo).
[group('生成')]
icons:
    uv run --no-project python scripts/gen-icons.py

# 生成启动画面资源.
[group('生成')]
splash:
    dart run flutter_native_splash:create
