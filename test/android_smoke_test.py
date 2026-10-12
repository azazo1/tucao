"""Android 冒烟脚本的标准库离线测试, 不连接 adb 或站点."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("android_smoke", ROOT / "scripts" / "android_smoke.py")
smoke = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(smoke)


def node(label, *, selected=False, clickable=False, package=smoke.PACKAGE,
         bounds="[10,10][110,60]"):
    return (f'<node text="{label}" package="{package}" enabled="true" '
            f'clickable="{str(clickable).lower()}" selected="{str(selected).lower()}" '
            f'bounds="{bounds}" />')


def hierarchy(*nodes):
    return '<hierarchy rotation="0">' + ''.join(nodes) + '</hierarchy>'


class FakeAdb:
    """可控模拟器, 所有命令只在内存中返回."""
    def __init__(self, *, missing_ui=False, launch="Status: ok", crash=""):
        self.deadline = time.monotonic() + 100
        self.commands = []
        self.page = "home"
        self.missing_ui = missing_ui
        self.launch = launch
        self.crash = crash
        self.pid = "123"

    def run(self, *args, **kwargs):
        self.commands.append(args)
        if args[0] == "install":
            return "Success\n"
        if args[:4] == ("shell", "cmd", "package", "resolve-activity"):
            return smoke.PACKAGE + "/.MainActivity\n"
        if args[:3] == ("shell", "am", "start"):
            return self.launch
        if args[:2] == ("shell", "pidof"):
            return self.pid
        if args[:3] == ("shell", "dumpsys", "activity"):
            return "mResumedActivity: ActivityRecord{0 " + smoke.PACKAGE + "/.MainActivity}"
        if args[:2] == ("shell", "cat"):
            if self.missing_ui:
                return hierarchy(node("", package="android"))
            pages = {
                "home": hierarchy(node("首页", selected=True), node("我的", clickable=True)),
                "mine": hierarchy(node("本地收藏", clickable=True), node("离线缓存", clickable=True)),
                "downloads": hierarchy(node("离线缓存"), node("缓存中"), node("已缓存")),
                "favorites": hierarchy(node("本地收藏")),
            }
            return pages[self.page]
        if args[:3] == ("shell", "input", "tap"):
            self.page = {"home": "mine", "mine": "downloads" if self.commands.count(args) == 2 else "favorites"}.get(self.page, self.page)
            return ""
        if args[:3] == ("shell", "input", "keyevent"):
            self.page = "mine"
            return ""
        if args[:2] == ("exec-out", "screencap"):
            return b"\x89PNG\r\n\x1a\nfixture"
        if args[:4] == ("logcat", "-d", "-b", "crash"):
            return self.crash
        return ""


class AndroidSmokeTest(unittest.TestCase):
    def setUp(self):
        (ROOT / ".tmp").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="smoke-test-", dir=ROOT / ".tmp")
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)
        self.apk = self.output / "fixture.apk"
        self.apk.write_bytes(b"not-installed-test-fixture")

    def create(self, adb):
        return smoke.AndroidSmoke(adb, self.output, self.output)

    def test_activity_rejects_wrong_package_and_noise(self):
        self.assertEqual(smoke.component_from("priority=0\ncom.azazo1.tucao/.MainActivity\n"), "com.azazo1.tucao/.MainActivity")
        for value in ["com.other/.MainActivity", "No activity found", "com.azazo1.tucao/.MainActivity;cmd"]:
            with self.assertRaises(smoke.SmokeFailure):
                smoke.component_from(value)

    def test_ui_selection_requires_package_unique_clickable_and_real_bounds(self):
        nodes = smoke.parse_nodes(hierarchy(node("我的", clickable=True), node("我的", package="android", clickable=True)))
        self.assertEqual(smoke.center(smoke.clickable(nodes, "我的")), (60, 35))
        self.assertFalse(smoke.label_matches(smoke.parse_nodes(hierarchy(node("我的设置")))[0], "我的"))
        nodes += smoke.parse_nodes(hierarchy(node("我的", clickable=True)))
        with self.assertRaises(smoke.SmokeFailure):
            smoke.clickable(nodes, "我的")
        for bounds in ["", "[0,0][0,0]", "[-1,0][10,10]", "[10,0][5,5]"]:
            with self.assertRaises(smoke.SmokeFailure):
                smoke.center(smoke.parse_nodes(hierarchy(node("我的", bounds=bounds)))[0])
        with self.assertRaises(smoke.SmokeFailure):
            smoke.parse_nodes("ERROR: could not get idle state")

    def test_crashes_only_fail_for_this_application(self):
        self.assertIsNone(smoke.crash_reason("Process: com.other, PID: 99", ""))
        self.assertIsNotNone(smoke.crash_reason("Process: com.azazo1.tucao, PID: 99", ""))
        self.assertIsNotNone(smoke.crash_reason(">>> com.azazo1.tucao <<<", ""))
        self.assertIsNotNone(smoke.crash_reason("", "E/flutter: Unhandled Exception: fixture"))

    def test_adb_argv_timeout_and_no_shell(self):
        adb = smoke.Adb("emulator-5554", time.monotonic() + 10)
        with patch.object(smoke.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"ok", b"")) as run:
            self.assertEqual(adb.run("install", "space name.apk"), "ok")
            self.assertEqual(run.call_args.args[0], ["adb", "-s", "emulator-5554", "install", "space name.apk"])
            self.assertNotIn("shell", run.call_args.kwargs)
            self.assertLessEqual(run.call_args.kwargs["timeout"], 10)
        with patch.object(smoke.subprocess, "run", side_effect=subprocess.TimeoutExpired(["adb"], 1)):
            with self.assertRaises(smoke.SmokeFailure):
                adb.run("wait-for-device")
        for serial in ["device-123", "emulator-5554;rm", ""]:
            with self.assertRaises(smoke.SmokeFailure):
                smoke.Adb(serial, time.monotonic() + 10)

    def test_launch_only_reports_no_pages_and_never_taps(self):
        adb = FakeAdb()
        with patch.object(smoke.time, "sleep"):
            report = self.create(adb).execute(self.apk, True)
        self.assertEqual(report["scope"], "startup")
        self.assertEqual(report["pages"], [])
        self.assertFalse(any(command[:2] == ("shell", "input") for command in adb.commands))

    def test_basic_pages_require_real_nodes_for_every_transition(self):
        adb = FakeAdb()
        with patch.object(smoke.time, "sleep"):
            report = self.create(adb).execute(self.apk, False)
        self.assertEqual(report["scope"], "basic-pages")
        self.assertEqual(report["pages"], ["home", "mine", "downloads", "mine-return", "favorites"])
        self.assertEqual(len(list(self.output.glob("*.png"))), 5)
        self.assertFalse(any("register" in " ".join(command) or "download" in " ".join(command) for command in adb.commands))

    def test_missing_semantics_never_passes_or_falls_back_to_coordinates(self):
        adb = FakeAdb(missing_ui=True)
        runner = self.create(adb)
        with patch.object(smoke.time, "monotonic", side_effect=[0, 0, 1, 2, 3]), patch.object(smoke.time, "sleep"):
            with self.assertRaisesRegex(smoke.SmokeFailure, "页面验证超时"):
                runner.wait_page("home", lambda nodes: bool(smoke.matching(nodes, "首页")), timeout=1)
        self.assertEqual(runner.pages, [])
        self.assertFalse(any(command[:3] == ("shell", "input", "tap") for command in adb.commands))

    def test_launch_crash_and_changed_pid_are_failures(self):
        for adb in [FakeAdb(launch="Error: Activity not started"), FakeAdb(crash="Process: com.azazo1.tucao, PID: 123")]:
            with patch.object(smoke.time, "sleep"):
                with self.assertRaises(smoke.SmokeFailure):
                    self.create(adb).execute(self.apk, True)
        adb = FakeAdb()
        runner = self.create(adb)
        runner.pid = "456"
        with self.assertRaisesRegex(smoke.SmokeFailure, "重启"):
            runner.healthy()

    def test_diagnostics_are_bounded_and_save_screenshot(self):
        adb = FakeAdb()
        self.create(adb).diagnostics()
        self.assertTrue((self.output / "failure.png").is_file())
        self.assertTrue((self.output / "crash.txt").is_file())
        self.assertIn(("logcat", "-d", "-t", "800", "-v", "threadtime"), adb.commands)


if __name__ == "__main__":
    unittest.main()
