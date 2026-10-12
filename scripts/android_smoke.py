"""仅供 CI 的 Android Release 黑盒冒烟测试, 不构建 APK.

默认必须验证四个页面. --startup-only 明确降级为仅安装和启动检查.
Flutter 未暴露语义树时 UI 模式失败, 不用固定坐标或截图猜测成功.
"""

from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

PACKAGE = "com.azazo1.tucao"
LOG = logging.getLogger("android-smoke")
BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
COMPONENT = re.compile(r"com\.azazo1\.tucao/(?:\.[\w.$]+|com\.azazo1\.tucao\.[\w.$]+)")


class SmokeFailure(RuntimeError):
    pass


def component_from(output: str) -> str:
    for line in output.splitlines():
        candidate = line.strip()
        if COMPONENT.fullmatch(candidate):
            return candidate
    raise SmokeFailure("未解析到指定包的 launcher Activity")


def parse_nodes(xml: str) -> list[ET.Element]:
    start = xml.find("<?xml")
    if start < 0:
        start = xml.find("<hierarchy")
    if start < 0:
        raise SmokeFailure("uiautomator 未返回有效层级, Flutter 语义可能未开启")
    try:
        return list(ET.fromstring(xml[start:]).iter("node"))
    except ET.ParseError as error:
        raise SmokeFailure("uiautomator 层级不完整") from error


def label_matches(node: ET.Element, label: str) -> bool:
    # Flutter 导航标签可能附带换行和 tab 序号, 不允许任意子串命中.
    return any(
        value == label or value.startswith(label + "\n")
        for value in (node.get("text", ""), node.get("content-desc", ""))
    )


def matching(nodes: list[ET.Element], label: str) -> list[ET.Element]:
    return [node for node in nodes
            if node.get("package") == PACKAGE
            and node.get("enabled", "true") == "true"
            and label_matches(node, label)]


def center(node: ET.Element) -> tuple[int, int]:
    match = BOUNDS.fullmatch(node.get("bounds", ""))
    if match is None:
        raise SmokeFailure("语义节点没有有效屏幕范围")
    left, top, right, bottom = map(int, match.groups())
    if right <= left or bottom <= top:
        raise SmokeFailure("语义节点不可见, 禁止盲点坐标")
    return ((left + right) // 2, (top + bottom) // 2)


def clickable(nodes: list[ET.Element], label: str) -> ET.Element:
    targets = [node for node in matching(nodes, label)
               if node.get("clickable") == "true"]
    if len(targets) != 1:
        raise SmokeFailure(f"未找到唯一可操作语义节点: {label}")
    center(targets[0])
    return targets[0]


def crash_reason(crash: str, application: str) -> str | None:
    if re.search(r"Process:\s*" + re.escape(PACKAGE) + r"(?:,|\s|$)", crash):
        return "Android 记录了应用 Java 崩溃"
    if f">>> {PACKAGE} <<<" in crash:
        return "Android 记录了应用 native 崩溃"
    if re.search(r"Unhandled Exception:|Another exception was thrown:|FATAL EXCEPTION:", application):
        return "应用进程日志包含未处理异常"
    return None


class Adb:
    def __init__(self, serial: str, deadline: float, executable: str = "adb"):
        if not re.fullmatch(r"emulator-\d+", serial):
            raise SmokeFailure("只允许指定的 CI emulator, 不选择本地设备")
        self.prefix = [executable, "-s", serial]
        self.deadline = deadline

    def run(self, *args: str, timeout: float = 20, binary: bool = False,
            check: bool = True) -> str | bytes:
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise SmokeFailure("冒烟测试达到总超时")
        LOG.info("adb 阶段: %s", " ".join(args[:4]))
        try:
            result = subprocess.run(
                self.prefix + list(args), capture_output=True,
                timeout=min(timeout, remaining), check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise SmokeFailure(f"adb 子进程超时: {args[0]}") from error
        if check and result.returncode:
            detail = result.stderr.decode("utf-8", errors="replace")[-2000:]
            raise SmokeFailure(f"adb 返回 {result.returncode}: {detail}")
        if binary:
            return result.stdout
        return result.stdout.decode("utf-8", errors="replace")


class AndroidSmoke:
    def __init__(self, adb: Adb, output: Path, temporary: Path):
        self.adb = adb
        self.output = output
        self.temporary = temporary
        self.pid: str | None = None
        self.pages: list[str] = []

    def healthy(self) -> None:
        current = str(self.adb.run("shell", "pidof", PACKAGE, check=False)).strip()
        if not current or (self.pid is not None and current != self.pid):
            raise SmokeFailure("应用 native 进程退出或在检查期间重启")
        activity = str(self.adb.run("shell", "dumpsys", "activity", "activities"))
        if not any(PACKAGE + "/" in line and
                   ("mResumedActivity" in line or "topResumedActivity" in line)
                   for line in activity.splitlines()):
            raise SmokeFailure("应用 Activity 不在前台")

    def snapshot(self, name: str) -> list[ET.Element]:
        self.healthy()
        # 每次 dump 启动 UiAutomation, 只接受真实导出的应用语义节点.
        self.adb.run("shell", "uiautomator", "dump", "/sdcard/tucao-smoke.xml")
        xml = str(self.adb.run("shell", "cat", "/sdcard/tucao-smoke.xml"))
        (self.output / f"{name}.xml").write_text(xml, encoding="utf-8")
        return parse_nodes(xml)

    def wait_page(self, name: str, predicate, timeout: float = 35) -> list[ET.Element]:
        deadline = min(self.adb.deadline, time.monotonic() + timeout)
        last_error = "应用没有暴露足够的 Flutter 语义, 未验证 UI"
        while time.monotonic() < deadline:
            try:
                nodes = self.snapshot(name)
                if predicate(nodes):
                    self.capture_screen(name)
                    self.pages.append(name)
                    LOG.info("页面已确认: %s", name)
                    return nodes
            except SmokeFailure as error:
                last_error = str(error)
            time.sleep(0.5)
        raise SmokeFailure(f"页面验证超时: {name}. {last_error}")

    def capture_screen(self, name: str) -> None:
        image = self.adb.run("exec-out", "screencap", "-p", binary=True)
        if not image.startswith(b"\x89PNG\r\n\x1a\n"):
            raise SmokeFailure("模拟器未返回有效 PNG 截图")
        (self.output / f"{name}.png").write_bytes(image)

    def tap(self, nodes: list[ET.Element], label: str) -> None:
        x, y = center(clickable(nodes, label))
        LOG.info("操作可见节点: %s", label)
        self.adb.run("shell", "input", "tap", str(x), str(y))

    def logs(self) -> tuple[str, str]:
        crash = str(self.adb.run("logcat", "-d", "-b", "crash", "-t", "200"))
        application = ""
        if self.pid:
            application = str(self.adb.run("logcat", "-d", "--pid", self.pid,
                                           "-t", "800", "-v", "threadtime"))
        return crash, application

    def diagnostics(self) -> None:
        # 失败时另给有限诊断预算, 每个命令都有独立超时.
        self.adb.deadline = time.monotonic() + 40
        for name, command in [
            ("activity.txt", ("shell", "dumpsys", "activity", "activities")),
            ("crash.txt", ("logcat", "-d", "-b", "crash", "-t", "200")),
            ("logcat.txt", ("logcat", "-d", "-t", "800", "-v", "threadtime")),
        ]:
            try:
                data = str(self.adb.run(*command, timeout=8))
                (self.output / name).write_text(data[-150000:], encoding="utf-8")
            except (SmokeFailure, OSError) as error:
                LOG.warning("诊断收集失败: %s", error)
        try:
            self.capture_screen("failure")
        except (SmokeFailure, OSError) as error:
            LOG.warning("失败截图未取得: %s", error)

    def execute(self, apk: Path, startup_only: bool) -> dict:
        if not apk.is_file() or apk.suffix != ".apk":
            raise SmokeFailure("指定 APK 不存在或后缀无效")
        self.adb.run("wait-for-device", timeout=25)
        self.adb.run("logcat", "-c")
        installed = str(self.adb.run("install", "-r", "--no-streaming", str(apk), timeout=60))
        if "Success" not in installed.splitlines():
            raise SmokeFailure("adb 未确认 APK 安装成功")
        component = component_from(str(self.adb.run(
            "shell", "cmd", "package", "resolve-activity", "--brief",
            "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", PACKAGE,
        )))
        self.adb.run("shell", "am", "force-stop", PACKAGE)
        launch = str(self.adb.run("shell", "am", "start", "-W", "-n", component))
        if not re.search(r"^Status:\s*ok\s*$", launch, re.MULTILINE):
            raise SmokeFailure("am start 未确认 launcher 启动成功")
        # native 进程不能只在启动瞬间存在, 至少连续存活 5 秒.
        for _ in range(6):
            self.healthy()
            if self.pid is None:
                self.pid = str(self.adb.run("shell", "pidof", PACKAGE)).strip()
                if not re.fullmatch(r"\d+", self.pid):
                    raise SmokeFailure("主应用进程不是唯一 PID")
            time.sleep(1)
        if not startup_only:
            home = self.wait_page("home", lambda nodes: any(
                node.get("selected") == "true" for node in matching(nodes, "首页"))
                and bool(matching(nodes, "我的")))
            self.tap(home, "我的")
            mine = self.wait_page("mine", lambda nodes:
                bool(matching(nodes, "本地收藏")) and bool(matching(nodes, "离线缓存")))
            self.tap(mine, "离线缓存")
            self.wait_page("downloads", lambda nodes:
                bool(matching(nodes, "离线缓存")) and bool(matching(nodes, "缓存中"))
                and bool(matching(nodes, "已缓存")) and not matching(nodes, "本地收藏"))
            self.adb.run("shell", "input", "keyevent", "KEYCODE_BACK")
            mine = self.wait_page("mine-return", lambda nodes:
                bool(matching(nodes, "本地收藏")) and bool(matching(nodes, "离线缓存")))
            self.tap(mine, "本地收藏")
            self.wait_page("favorites", lambda nodes:
                bool(matching(nodes, "本地收藏")) and not matching(nodes, "离线缓存")
                and not matching(nodes, "我的"))
        self.healthy()
        crash, application = self.logs()
        (self.output / "crash.txt").write_text(crash, encoding="utf-8")
        (self.output / "application.txt").write_text(application, encoding="utf-8")
        reason = crash_reason(crash, application)
        if reason:
            raise SmokeFailure(reason)
        return {"status": "passed", "scope": "startup" if startup_only else "basic-pages",
                "package": PACKAGE, "activity": component, "pid": self.pid, "pages": self.pages}


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="CI Android Release 黑盒冒烟测试")
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--serial", default="emulator-5554")
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--startup-only", action="store_true",
                        help="只检查安装和启动, 不宣称基本页面已验证")
    args = parser.parse_args()
    if not 30 <= args.timeout <= 600:
        parser.error("总超时必须在 30 到 600 秒之间")
    workspace = Path(__file__).resolve().parents[1]
    output = workspace / ".tmp" / "android-smoke"
    output.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    report = {"status": "failed", "scope": "startup" if args.startup_only else "basic-pages"}
    adb = Adb(args.serial, started + args.timeout)
    with tempfile.TemporaryDirectory(prefix="android-smoke-", dir=workspace / ".tmp") as temporary:
        smoke = AndroidSmoke(adb, output, Path(temporary))
        try:
            report = smoke.execute(args.apk.resolve(), args.startup_only)
            LOG.info("冒烟测试通过, 范围: %s", report["scope"])
            code = 0
        except (SmokeFailure, OSError) as error:
            report.update(error=str(error), pages=smoke.pages, pid=smoke.pid)
            LOG.error("冒烟测试失败: %s", error)
            smoke.diagnostics()
            code = 1
        report["elapsed_seconds"] = round(time.monotonic() - started, 2)
        (output / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
