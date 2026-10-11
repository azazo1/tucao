#!/usr/bin/env python3

# 各语言 dist.py 共用的基础能力, 复制到项目 scripts/release_common.py.
# 只用 Python 标准库, 需要 3.8 及以上.
#
# 放在这里的都是跨语言共用的部分: 平台与架构识别, 版本号解析, 子进程封装,
# staging 准备, 冒烟检查与归档调用. 具体语言怎么构建由各语言的 scripts/dist.py 自己写.

import os
import platform
import shutil
import subprocess
import sys


def configure_output_encoding():
    """把 stdout 与 stderr 切到 UTF-8.

    Windows 控制台默认是本地代码页, 输出中文会抛 UnicodeEncodeError,
    而 GitHub Actions 日志按 UTF-8 解码, 所以统一按 UTF-8 输出.
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError, OSError):
            pass


def die(message):
    """打印错误信息到 stderr 并以退出码 1 结束."""
    print(message, file=sys.stderr)
    sys.exit(1)


def run(argv, env=None, capture=True):
    """执行命令.

    capture 为真时返回去掉两端空白的 stdout, 命令失败时打印命令行与输出后退出;
    capture 为假时把输出直接透传到终端, 适合构建这类需要实时日志的命令.
    capture 为真时 stderr 不丢弃: 子脚本的警告信息照常转发到 stderr, 免得被静默吞掉.
    """
    result = subprocess.run(
        argv,
        env=env,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        encoding="utf-8",
        errors="replace",
    )
    if capture and result.returncode == 0 and result.stderr:
        # 成功的子进程 stderr 里通常是警告 (例如包版本兜底), 照常转发, 免得被静默吞掉.
        sys.stderr.write(result.stderr)
    if result.returncode != 0:
        detail = ((result.stderr or "") + (result.stdout or "")).strip()
        message = f"命令失败 (退出码 {result.returncode}): {' '.join(argv)}"
        die(f"{message}\n{detail}" if detail else message)
    return (result.stdout or "").strip()


def try_run(argv, env=None):
    """执行命令并返回去掉两端空白的 stdout, 失败时返回 None.

    用于读包版本这类可选探测: 读不到不算错, 由调用方决定怎么兜底.
    """
    result = subprocess.run(
        argv,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        return None
    return (result.stdout or "").strip() or None


def repo_root():
    """切到项目根目录 (脚本所在目录的上一级) 并返回该路径."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    return root


def script_path(name):
    """返回同目录下另一个脚本的绝对路径."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), name)


def detect_platform():
    system = platform.system()
    if system == "Linux":
        return "linux"
    if system == "Darwin":
        return "macos"
    if system == "Windows":
        return "windows"
    die(f"无法识别平台 {system}, 请显式设置 TARGET_PLATFORM")


def detect_arch():
    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        return "x86_64"
    if machine in ("arm64", "aarch64"):
        return "aarch64"
    die(f"无法识别架构 {platform.machine()}, 请显式设置 TARGET_ARCH")


def target_platform():
    """产物命名用的平台: TARGET_PLATFORM 优先, 否则按当前系统判断."""
    return os.environ.get("TARGET_PLATFORM") or detect_platform()


def target_arch():
    """产物命名用的架构: TARGET_ARCH 优先, 否则按当前机器判断."""
    return os.environ.get("TARGET_ARCH") or detect_arch()


def stage_dir(path="dist/stage"):
    """重建 staging 目录, 清掉上一轮的残留."""
    if os.path.isdir(path):
        shutil.rmtree(path)
    elif os.path.exists(path):
        os.remove(path)
    os.makedirs(path)
    return path


def resolve_versions(build_version_script, package_version=None):
    """解析构建版本, 返回 (二进制内显示的版本, 产物名用的版本).

    显示版本跟随 tag 样式, 通常带 v 前缀, 例如 v1.2.3-a1b2c3d;
    产物名的版本段剥掉 TAG_PREFIX, 例如 1.2.3-a1b2c3d.
    已经设置了 PROJECT_BUILD_VERSION 时直接采信, 否则让 build-version.py 计算,
    仓库还没有版本 tag 时用 package_version 兜底. package_version 可以是常量,
    也可以是函数 (只在真的需要兜底时才求值, 免得白跑一次 cargo metadata 这类命令).
    """
    env = os.environ.copy()
    display = env.get("PROJECT_BUILD_VERSION", "").strip()
    if not display:
        if callable(package_version):
            package_version = package_version()
        if package_version and not env.get("PROJECT_PACKAGE_VERSION"):
            env["PROJECT_PACKAGE_VERSION"] = str(package_version)
        display = run([sys.executable, build_version_script, "--with-prefix"], env=env)
    # 用 = 形式传值, 免得版本号以 - 开头时被 argparse 当成参数名.
    archive_version = run(
        [sys.executable, build_version_script, f"--strip-prefix={display}"], env=env
    )
    return display, archive_version


def smoke_check(command, smoke_args, expected_version):
    """运行产物并断言它报出的版本号与注入值一致.

    command 是产物本身, framework-dependent 的 .NET 程序集这类需要解释器的产物,
    把解释器一起写进来, 例如 ["dotnet", "dist/stage/PROJECT.dll"].
    """
    reported = run([*command, *smoke_args])
    if expected_version not in reported:
        die(f"版本号校验失败: 期望 {expected_version}, 实际输出 {reported}")
    print(f"版本号校验通过: {expected_version}")


def check_binary_format(path, expected_platform):
    """交叉编译的产物无法在本机运行, 改为检查可执行文件头."""
    magics = {
        "linux": (b"\x7fELF",),
        "macos": (
            b"\xfe\xed\xfa\xce",  # 32 位大端
            b"\xfe\xed\xfa\xcf",  # 64 位大端
            b"\xce\xfa\xed\xfe",  # 32 位小端
            b"\xcf\xfa\xed\xfe",  # 64 位小端
            b"\xca\xfe\xba\xbe",  # 通用二进制
            b"\xbe\xba\xfe\xca",
        ),
        "windows": (b"MZ",),
    }
    expected = magics.get(expected_platform)
    if expected is None:
        die(f"没有为 {expected_platform} 定义可执行文件头, 请在 release_common.py 里补充")
    if not os.path.isfile(path):
        die(f"产物不存在: {path}")
    with open(path, "rb") as handle:
        header = handle.read(4)
    if not any(header.startswith(magic) for magic in expected):
        die(f"{path} 的文件头不符合 {expected_platform} 可执行文件格式: {header!r}")
    print(f"文件格式检查通过: {path} ({expected_platform})")


def archive(
    staging,
    artifacts,
    project_name,
    version,
    target=None,
    platform_independent=False,
    variant=None,
    archive_ext=None,
    dist_dir="dist",
):
    """调用 scripts/archive.py 打包, 并打印生成的产物路径.

    target 是 (平台, 架构) 元组, platform_independent 为真时按平台无关规则命名;
    artifacts 为空表示打包 staging 目录下的全部内容.
    """
    env = os.environ.copy()
    env["PROJECT_NAME"] = project_name
    env["PROJECT_BUILD_VERSION"] = version
    env["DIST_DIR"] = dist_dir
    if platform_independent:
        env["PLATFORM_INDEPENDENT"] = "1"
    else:
        if not target:
            die("按平台命名产物时必须给出 target=(平台, 架构)")
        env["TARGET_PLATFORM"], env["TARGET_ARCH"] = target
    if variant:
        env["VARIANT"] = variant
    if archive_ext:
        env["ARCHIVE_EXT"] = archive_ext
    print(run([sys.executable, script_path("archive.py"), staging, *artifacts], env=env))
