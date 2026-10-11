#!/usr/bin/env python3

# 语言无关的归档 helper, 复制到项目 scripts/archive.py.
# 需要同时复制 scripts/release_common.py.
#
# 由各语言的 scripts/dist.py 调用, 按统一规则拼接产物名并压缩:
#   PROJECT-VERSION-PLATFORM-ARCH[-VARIANT].EXT
# 平台无关的托管产物 (jar, 框架依赖 dll 程序集等) 设 PLATFORM_INDEPENDENT=1, 命名为:
#   PROJECT-VERSION[-VARIANT].EXT
#
# 必需的环境变量:
#   PROJECT_NAME           产物名前缀, 例如 dida
#   PROJECT_BUILD_VERSION  构建版本号, 不带 tag 前缀, 例如 0.1.2 或 0.1.2-a1b2c3d
# 可选的环境变量:
#   TARGET_PLATFORM        linux / macos / windows, 缺省按当前平台判断
#   TARGET_ARCH            x86_64 / aarch64, 缺省按当前架构判断
#   VARIANT                setup / portable, 只用于同一平台同一架构有多种分发形态的桌面应用
#   PLATFORM_INDEPENDENT   设为 1 时按平台无关规则命名
#   ARCHIVE_EXT            覆盖扩展名, 缺省 windows 用 zip, 其他平台用 tar.gz
#   DIST_DIR               产物输出目录, 缺省 dist
#
# 用法:
#   PROJECT_NAME=dida PROJECT_BUILD_VERSION=0.1.2 uv run --no-project python scripts/archive.py <staging-dir> [artifact...]
# 不传 artifact 时打包 staging 目录下的全部内容. tar.gz 与 zip 都用标准库生成,
# 不需要系统里有 tar / zip 命令, 也会保留文件的可执行位.

import os
import sys
import tarfile
import time
import zipfile

import release_common as rc


def staging_entries(staging, requested):
    """确定要打进包里的顶层条目."""
    if requested:
        for name in requested:
            if not os.path.exists(os.path.join(staging, name)):
                rc.die(f"staging 目录缺少产物: {os.path.join(staging, name)}")
        return list(requested)

    entries = sorted(os.listdir(staging))
    if not entries:
        rc.die(f"staging 目录为空, 没有可打包的内容: {staging}")
    return entries


def arc_name(path, staging):
    """把 staging 下的路径转成包内条目名, 分隔符统一用 /."""
    return os.path.relpath(path, staging).replace(os.sep, "/")


def write_zip_dir(archive, path, name):
    """写入目录条目, 权限位按目录设置, 便于解压端还原结构."""
    info = zipfile.ZipInfo(name.rstrip("/") + "/")
    info.external_attr = (0o40755 << 16) | 0x10
    info.date_time = time.localtime(os.path.getmtime(path))[:6]
    archive.writestr(info, b"")


def write_zip_entry(archive, staging, path, name):
    if os.path.isdir(path):
        write_zip_dir(archive, path, name)
        for root, dirs, files in os.walk(path):
            dirs.sort()
            for directory in dirs:
                full = os.path.join(root, directory)
                write_zip_dir(archive, full, arc_name(full, staging))
            for filename in sorted(files):
                full = os.path.join(root, filename)
                archive.write(full, arc_name(full, staging))
        return
    archive.write(path, name)


def make_archive(archive_path, staging, entries, ext):
    if ext in ("tar.gz", "tgz"):
        # tarfile 与 tar -czf 一致, 保留权限位与符号链接.
        with tarfile.open(archive_path, "w:gz") as tar:
            for name in entries:
                tar.add(os.path.join(staging, name), arcname=name)
        return

    if ext == "zip":
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for name in entries:
                write_zip_entry(archive, staging, os.path.join(staging, name), name)
        return

    rc.die(f"不支持的扩展名: {ext}")


def main():
    rc.configure_output_encoding()

    project_name = os.environ.get("PROJECT_NAME", "").strip()
    if not project_name:
        rc.die("缺少 PROJECT_NAME, 无法拼接产物名")

    version = os.environ.get("PROJECT_BUILD_VERSION", "").strip()
    if not version:
        rc.die("缺少 PROJECT_BUILD_VERSION, 无法拼接产物名")

    if len(sys.argv) < 2:
        rc.die(f"用法: PROJECT_NAME=<name> PROJECT_BUILD_VERSION=<version> {sys.argv[0]} <staging-dir> [artifact...]")

    staging = sys.argv[1]
    requested = sys.argv[2:]
    if not os.path.isdir(staging):
        rc.die(f"staging 目录不存在: {staging}")

    variant_suffix = f"-{os.environ['VARIANT']}" if os.environ.get("VARIANT") else ""

    platform_suffix = ""
    if os.environ.get("PLATFORM_INDEPENDENT") == "1":
        ext = os.environ.get("ARCHIVE_EXT") or "zip"
    else:
        target_platform = os.environ.get("TARGET_PLATFORM") or rc.detect_platform()
        target_arch = os.environ.get("TARGET_ARCH") or rc.detect_arch()
        platform_suffix = f"-{target_platform}-{target_arch}"
        default_ext = "zip" if target_platform == "windows" else "tar.gz"
        ext = os.environ.get("ARCHIVE_EXT") or default_ext

    dist_dir = os.environ.get("DIST_DIR") or "dist"
    os.makedirs(dist_dir, exist_ok=True)
    archive_path = os.path.join(dist_dir, f"{project_name}-{version}{platform_suffix}{variant_suffix}.{ext}")

    entries = staging_entries(staging, requested)
    if os.path.exists(archive_path):
        os.remove(archive_path)

    make_archive(archive_path, staging, entries, ext)
    print(f"已生成 {archive_path}")


if __name__ == "__main__":
    main()
