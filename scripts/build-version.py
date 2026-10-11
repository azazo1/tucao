#!/usr/bin/env python3

# 计算构建版本号, 复制到项目 scripts/build-version.py.
# 需要同时复制 scripts/release_common.py.
# 只改下面的 TAG_PREFIX, 不要改后面的 tag / dirty 算法.
#
# 输出 (stdout):
#   uv run --no-project python scripts/build-version.py                        -> 1.2.3, 1.2.3-a1b2c3d
#   uv run --no-project python scripts/build-version.py --with-prefix          -> v1.2.3, v1.2.3-a1b2c3d
#   uv run --no-project python scripts/build-version.py --strip-prefix v1.2.3  -> 1.2.3 (不读 git)
#
# 规则: HEAD 正好在版本 tag 上时只给 tag; 非 tag commit 追加 - 与 7 位短 hash;
# 工作区有未提交改动时改用 ^ 分隔. 仓库还没有任何版本 tag 时, 用
# PROJECT_PACKAGE_VERSION 传入的包版本兜底, 缺这个变量时报出具体原因后失败.
#
# 二进制内显示的版本用 --with-prefix (跟随 tag 样式), 产物名用默认输出
# (已剥掉 TAG_PREFIX), 两者样式不同是刻意的.

import argparse
import os
import subprocess
import sys

import release_common as rc

# 版本 tag 前缀, 与项目的 tag 惯例保持一致.
TAG_PREFIX = "v"


def git(*args):
    """返回 git 命令的 stdout (去掉行尾 CR 与两端空白); 命令失败或输出为空时返回 None."""
    result = subprocess.run(
        ["git", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        return None
    text = result.stdout.decode("utf-8", "replace").replace("\r", "").strip()
    return text or None


def first_line(text):
    if not text:
        return None
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line
    return None


def select_version_tag(tags):
    """从多行 tag 里挑第一个版本 tag.

    与 describe 的 --match 保持一致: 设了 TAG_PREFIX 时只接受带前缀的 tag,
    免得同一个 tag 在 HEAD 上被当成版本号, 不在 HEAD 上却解析失败.
    """
    if not tags:
        return None
    for line in tags.splitlines():
        line = line.strip()
        if not line:
            continue
        if not TAG_PREFIX or line.startswith(TAG_PREFIX):
            return line
    return None


def strip_tag_prefix(version):
    """剥掉 TAG_PREFIX, 避免产物名出现双前缀."""
    if TAG_PREFIX and version.startswith(TAG_PREFIX):
        return version[len(TAG_PREFIX):]
    return version


def diagnose_missing_tag():
    """取不到版本 tag 时说明具体原因.

    区分"仓库确实没有 tag", "有 tag 但没一个匹配 TAG_PREFIX"
    和"本地没有 tag 对象 (浅克隆或没 fetch tags)"三种情况.
    """
    all_tags = git("tag", "--list")
    matched_tags = git("tag", "--list", f"{TAG_PREFIX}*") if TAG_PREFIX else all_tags
    first_tag = first_line(all_tags)
    first_matched = first_line(matched_tags)

    if not first_matched and git("rev-parse", "--is-shallow-repository") == "true":
        return "本地是浅克隆, 取不到远端 tag"
    if not first_tag:
        return "仓库里没有任何 tag"
    if not first_matched:
        return f"本地 tag 没有一个匹配 TAG_PREFIX={TAG_PREFIX} (现有第一个 tag 是 {first_tag})"
    return f"本地有版本 tag ({first_matched}), 但 describe 从 HEAD 取不到它"


def read_package_version():
    """仓库还没有任何版本 tag 时的兜底基础版本号, 由调用方提供.

    各语言模块给出该生态的结构化 metadata 读取命令, 在 just dist 或 CI 里先算出包版本,
    再用 PROJECT_PACKAGE_VERSION 传进来; 不要在本脚本里正则扫清单文件.
    """
    reason = diagnose_missing_tag()
    package_version = os.environ.get("PROJECT_PACKAGE_VERSION", "").strip()

    if not package_version:
        print(f"{reason}, 且未提供 PROJECT_PACKAGE_VERSION", file=sys.stderr)
        print(
            "按语言模块给出的结构化命令读出包版本后传给 PROJECT_PACKAGE_VERSION, "
            "或先打一个版本 tag (检查 TAG_PREFIX 前缀, 浅克隆要 fetch tags)",
            file=sys.stderr,
        )
        sys.exit(1)

    normalized = strip_tag_prefix(package_version)
    print(f"警告: {reason}; 基础版本号改用包版本 {normalized} 加短 hash", file=sys.stderr)
    return normalized


def describe_latest_tag():
    if TAG_PREFIX:
        return git("describe", "--tags", "--abbrev=0", "--match", f"{TAG_PREFIX}*", "HEAD")
    return git("describe", "--tags", "--abbrev=0", "HEAD")


def compute_display_version():
    """算出带 TAG_PREFIX 的构建版本号, 例如 v1.2.3-a1b2c3d 或 v1.2.3^a1b2c3d."""
    rc.repo_root()

    exact_tag = None
    tags = git("tag", "--points-at", "HEAD")
    if tags:
        exact_tag = select_version_tag(tags)

    if exact_tag:
        tag = exact_tag
    else:
        tag = describe_latest_tag()
        if not tag:
            tag = f"{TAG_PREFIX}{read_package_version()}"

    commit = git("rev-parse", "--short=7", "HEAD")
    dirty = False
    if commit:
        result = subprocess.run(
            ["git", "diff-index", "--quiet", "HEAD", "--"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        dirty = result.returncode == 1

    if not commit:
        return tag
    if dirty:
        return f"{tag}^{commit}"
    if exact_tag:
        return tag
    return f"{tag}-{commit}"


def main():
    rc.configure_output_encoding()

    parser = argparse.ArgumentParser(description="计算构建版本号")
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--with-prefix",
        action="store_true",
        help="输出带 TAG_PREFIX 的版本号, 供二进制注入使用",
    )
    group.add_argument(
        "--strip-prefix",
        metavar="VERSION",
        help="只把给定版本号去掉 TAG_PREFIX 后输出, 不读取 git",
    )
    args = parser.parse_args()

    if args.strip_prefix is not None:
        print(strip_tag_prefix(args.strip_prefix.strip()))
        return

    display = compute_display_version()
    print(display if args.with_prefix else strip_tag_prefix(display))


if __name__ == "__main__":
    main()
