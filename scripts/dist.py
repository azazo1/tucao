#!/usr/bin/env python3

# 吐槽客户端的发布产物打包脚本, 由 just dist 与 ci 调用.
#
# Flutter 不在技能的既有语言模块内, 这里按技能的同一套槽位自行推导:
#   分发判定  二进制应用, 用户从 GitHub Release 取 apk
#   版本来源  git tag (vX.Y.Z), 无 tag 时用 pubspec 的包版本兜底
#   版本注入  PROJECT_BUILD_VERSION 环境变量, 经 --dart-define 写入 [BuildConfig]
#   构建命令  flutter build apk
#   平台目标  android, 架构 arm64-v8a / armeabi-v7a / x86_64
#   归档      apk 本身就是分发格式, 按统一命名规则命名, 无需二次压缩
#
# apk 无法在构建机上运行, 因此不做 --version 冒烟, 改为校验 zip 结构与
# 关键文件存在性, 参照技能对无法直接运行产物的替代路径.
#
# 用法:
#   uv run --no-project python scripts/dist.py
#   PROJECT_BUILD_VERSION=v1.2.3 uv run --no-project python scripts/dist.py
#
# 可选环境变量:
#   TARGET_ARCH   只构建单个架构, 缺省构建全部架构
#   DIST_DIR      产物输出目录, 缺省 dist

import os
import re
import sys
import zipfile

import release_common as rc

PROJECT_NAME = "tucao"

# android 平台下按架构拆分的 apk 后缀.
ARCHES = ("arm64-v8a", "armeabi-v7a", "x86_64")

APK_OUTPUT_DIR = os.path.join("build", "app", "outputs", "flutter-apk")


def package_version():
    """读 pubspec.yaml 里的包版本, 供仓库还没有版本 tag 时兜底.

    只取 version 行的 `+` 之前的部分, 构建号不进版本号.
    """
    path = "pubspec.yaml"
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = re.match(r"^version:\s*(\S+)\s*$", line)
            if match:
                return match.group(1).split("+")[0]
    return None


def build_apk(build_version):
    """调用 flutter build 生成按架构拆分的 release apk."""
    env = os.environ.copy()
    # 版本号注入到应用内, 由 lib/build_config.dart 读取.
    env["PROJECT_BUILD_VERSION"] = build_version

    rc.run(
        [
            "flutter",
            "build",
            "apk",
            "--release",
            "--split-per-abi",
            "--dart-define=BUILD_VERSION=" + build_version,
        ],
        env=env,
        capture=False,
    )


def apk_path(arch):
    return os.path.join(APK_OUTPUT_DIR, f"app-{arch}-release.apk")


def check_apk(path, expected_version):
    """apk 无法在构建机上启动, 改为校验 zip 结构与版本号.

    apk 是 zip 容器, 断言清单, dex 与 Dart AOT 快照存在, 并检查注入的版本号
    确实出现在 libapp.so 里, 避免 --dart-define 没生效却静默发布.
    Dart 的常量字符串进的是 libapp.so, 不是 dex, 因此只在 so 里查找.
    """
    if not os.path.isfile(path):
        rc.die(f"apk 不存在: {path}")

    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        for required in ("AndroidManifest.xml", "classes.dex"):
            if required not in names:
                rc.die(f"{path} 缺少 {required}, 不是有效的 apk")

        libs = [name for name in names if name.startswith("lib/")]
        if not libs:
            rc.die(f"{path} 里没有任何 lib/, 架构拆分产物异常")

        snapshots = [name for name in libs if name.endswith("libapp.so")]
        if not snapshots:
            rc.die(f"{path} 里没有 libapp.so, 不是有效的 release 产物")

        found = any(
            expected_version.encode("utf-8") in archive.read(name)
            for name in snapshots
        )
        if not found:
            rc.die(f"{path} 里找不到注入的版本号 {expected_version}, dart-define 未生效")

    print(f"apk 校验通过: {path}")


def main():
    rc.configure_output_encoding()
    root = rc.repo_root()

    dist_dir = os.environ.get("DIST_DIR") or "dist"
    os.makedirs(dist_dir, exist_ok=True)

    build_version_script = rc.script_path("build-version.py")
    display, archive_version = rc.resolve_versions(
        build_version_script, package_version=package_version
    )
    print(f"构建版本: {display} (产物名使用 {archive_version})")

    build_apk(display)

    arches = os.environ.get("TARGET_ARCH")
    selected = (arches,) if arches else ARCHES
    if arches and arches not in ARCHES:
        rc.die(f"不支持的架构 {arches}, 可选: {', '.join(ARCHES)}")

    produced = []
    for arch in selected:
        source = apk_path(arch)
        if not os.path.isfile(source):
            rc.die(f"缺少 {arch} 的构建产物: {source}")
        # 统一命名: PROJECT-VERSION-android-ARCH.apk, apk 本身即分发格式.
        target = os.path.join(
            dist_dir, f"{PROJECT_NAME}-{archive_version}-android-{arch}.apk"
        )
        if os.path.exists(target):
            os.remove(target)
        os.replace(source, target)
        produced.append(target)

    for path in produced:
        # 校验放在改名前不安全 (源文件已移走), 因此这里对最终产物校验.
        check_apk(path, display)

    print(f"已生成 {len(produced)} 个 apk:")
    for path in produced:
        print(f"  {os.path.relpath(path, root)}")


if __name__ == "__main__":
    main()
