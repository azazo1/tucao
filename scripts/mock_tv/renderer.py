#!/usr/bin/env python3
"""渲染器状态机与拉流探测.

状态机模拟电视的 TransportState, 位置按墙钟推进, 与真电视的 GetPositionInfo
行为一致. MediaSink 负责像电视那样去拉取媒体地址, 并把发出去的请求头记下来,
这正是判断站点直链能否被电视直接播放的关键.
"""

import logging
import re
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.request

LOG = logging.getLogger("mocktv.renderer")

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

STOPPED = "STOPPED"
PLAYING = "PLAYING"
PAUSED = "PAUSED_PLAYBACK"

STATE_LABELS = {STOPPED: "已停止", PLAYING: "播放中", PAUSED: "已暂停"}


def format_time(seconds: float) -> str:
    total = max(0, int(seconds))
    return f"{total // 3600:02d}:{total % 3600 // 60:02d}:{total % 60:02d}"


def parse_time(text: str) -> float:
    """解析 SOAP 里的 HH:MM:SS, 失败返回 0."""
    parts = text.strip().split(":")
    try:
        numbers = [float(part) for part in parts]
    except ValueError:
        return 0.0
    if len(numbers) == 3:
        return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
    if len(numbers) == 2:
        return numbers[0] * 60 + numbers[1]
    return numbers[0] if numbers else 0.0


def detect_container(prefix: bytes, uri: str) -> str:
    """按媒体头判断封装, 顺带对照地址后缀, 便于发现"看着是 mp4 其实是网页"."""
    if len(prefix) >= 12 and prefix[4:8] == b"ftyp":
        return "mp4"
    if prefix.startswith(b"FLV"):
        return "flv"
    if prefix.lstrip().startswith(b"#EXTM3U"):
        return "hls (m3u8)"
    if prefix.startswith(b"\x1a\x45\xdf\xa3"):
        return "mkv/webm"
    if prefix.startswith(b"RIFF") and b"AVI" in prefix[:16]:
        return "avi"
    if prefix.lstrip()[:1] == b"<":
        return "html (响应是网页)"
    suffix = uri.split("?")[0].rsplit(".", 1)[-1].lower() if "." in uri else ""
    return f"未知 (后缀 {suffix})" if suffix else "未知"


class Renderer:
    """只维护媒体地址, 传输状态, 位置与音量."""

    def __init__(self) -> None:
        self.uri = ""
        self.metadata = ""
        self.next_uri = ""
        self.state = STOPPED
        self.volume = 35
        self.mute = False
        self.duration = 0.0
        self.probe_note = "尚未拉流"
        self.probe_ok: bool | None = None
        self._base = 0.0
        self._anchor: float | None = None

    def set_uri(self, uri: str, metadata: str = "") -> None:
        self.uri = uri
        self.metadata = metadata
        self.state = STOPPED
        self._base = 0.0
        self._anchor = None
        self.duration = 0.0
        self.probe_note = "尚未拉流"
        self.probe_ok = None

    def play(self) -> None:
        self.state = PLAYING
        self._anchor = time.monotonic()

    def pause(self) -> None:
        self._base = self.position()
        self._anchor = None
        self.state = PAUSED

    def stop(self) -> None:
        self.state = STOPPED
        self._base = 0.0
        self._anchor = None

    def seek(self, target: float) -> None:
        self._base = max(0.0, target)
        if self.duration:
            self._base = min(self._base, self.duration)
        if self.state == PLAYING:
            self._anchor = time.monotonic()

    def position(self) -> float:
        if self.state != PLAYING or self._anchor is None:
            return self._base
        position = self._base + (time.monotonic() - self._anchor)
        return min(position, self.duration) if self.duration else position

    def transport_actions(self) -> str:
        if not self.uri:
            return ""
        if self.state == PLAYING:
            return "Pause,Stop,Seek"
        return "Play,Stop,Seek"

    def snapshot(self) -> dict:
        return {
            "uri": self.uri,
            "metadata": self.metadata,
            "next_uri": self.next_uri,
            "state": self.state,
            "state_label": STATE_LABELS.get(self.state, self.state),
            "position": round(self.position(), 2),
            "duration": round(self.duration, 2),
            "volume": self.volume,
            "mute": self.mute,
            "probe_note": self.probe_note,
            "probe_ok": self.probe_ok,
        }


class MediaSink:
    """像电视一样拉流: 记请求头, 判可播性, 可选交给 ffplay 显示画面."""

    def __init__(
        self,
        tv_ua: str,
        referer: str = "",
        use_ffplay: bool = False,
    ):
        self.tv_ua = tv_ua
        self.referer = referer
        self.use_ffplay = use_ffplay
        self._player: subprocess.Popen | None = None
        self._lock = threading.Lock()

    def headers(self) -> dict[str, str]:
        headers = {"User-Agent": self.tv_ua, "Connection": "close"}
        if self.referer:
            headers["Referer"] = self.referer
        return headers

    def probe(self, uri: str) -> tuple[bool, str, float]:
        """发一次与真电视相当的请求, 返回 (是否可播, 说明, 时长)."""
        LOG.info("电视拉流: %s", uri)
        LOG.info("  请求头: %s", self.headers())
        status = None
        content_type = ""
        prefix = b""
        error = ""
        try:
            request = urllib.request.Request(uri, headers=self.headers())
            with urllib.request.urlopen(request, timeout=8) as response:
                status = response.status
                content_type = response.headers.get("Content-Type", "")
                prefix = response.read(2048)
        except urllib.error.HTTPError as exc:
            status = exc.code
            content_type = exc.headers.get("Content-Type", "") if exc.headers else ""
            prefix = exc.read(512)
        except Exception as exc:  # noqa: BLE001 - 网络异常都按不可播处理
            error = f"{type(exc).__name__}: {exc}"

        if error:
            note = f"请求失败: {error}"
            LOG.warning("  拉流失败: %s", error)
            return False, note, 0.0

        container = detect_container(prefix, uri)
        ok = status in (200, 206) and not container.startswith("html")
        duration = self._duration(uri) if ok else 0.0
        note = (
            f"HTTP {status}, Content-Type: {content_type or '无'}, "
            f"封装: {container}, 首包 {len(prefix)} 字节, 时长 {format_time(duration)}"
        )
        if status == 403:
            note += " | 403 通常是站点校验 Referer/UA, 电视端拿不到, 需要手机侧代理转发"
            LOG.warning(
                "  拉流被拒 403, 真电视同样会失败: 直链需要 Referer/UA, 应考虑本地代理"
            )
        elif ok:
            LOG.info("  拉流成功: %s", note)
        else:
            LOG.warning("  拉流异常: %s", note)
        return ok, note, duration

    def _duration(self, uri: str) -> float:
        """用 ffprobe 量时长, 只用于让进度条有总长, 不影响可播性判断."""
        if not shutil.which("ffprobe"):
            return 0.0
        command = ["ffprobe", "-v", "error"]
        if self.referer:
            command += ["-headers", f"Referer: {self.referer}\r\n"]
        command += [
            "-show_entries", "format=duration",
            "-of", "default=nw=1:nk=1", uri,
        ]
        try:
            result = subprocess.run(
                command, capture_output=True, text=True, timeout=10
            )
            value = result.stdout.strip()
            return float(value) if value else 0.0
        except (subprocess.SubprocessError, ValueError):
            return 0.0

    def start(self, uri: str, start_at: float = 0.0) -> None:
        self.stop()
        if not self.use_ffplay:
            LOG.info("未启用 ffplay, 仅记录拉流结果 (加 --play 可显示画面)")
            return
        if not shutil.which("ffplay"):
            LOG.warning("找不到 ffplay, 跳过画面显示")
            return
        command = [
            "ffplay", "-loglevel", "warning", "-autoexit",
            "-window_title", "Mock TV",
        ]
        if start_at > 0.5:
            command += ["-ss", f"{start_at:.1f}"]
        if self.referer:
            command += ["-headers", f"Referer: {self.referer}\r\n"]
        command += ["-i", uri]
        with self._lock:
            self._player = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
        LOG.info("ffplay 已启动 (pid=%s)", self._player.pid)
        threading.Thread(
            target=self._drain, args=(self._player,), name="ffplay-stderr",
            daemon=True,
        ).start()

    @staticmethod
    def _drain(player: subprocess.Popen) -> None:
        assert player.stderr is not None
        # 版本横幅与 macOS 输入法噪声都不是播放问题, 过滤掉免得刷屏.
        noise = (
            "ffplay version", "built with", "configuration:", "libav", "libsw",
            "Keyboard Layouts", "TISFileInterrogator", "ffplay[",
        )
        for line in player.stderr:
            line = ANSI.sub("", line).strip()
            if not line or any(marker in line for marker in noise):
                continue
            LOG.warning("ffplay: %s", line)

    def stop(self) -> None:
        with self._lock:
            player, self._player = self._player, None
        if player is None:
            return
        if player.poll() is None:
            player.terminate()
            try:
                player.wait(timeout=2)
            except subprocess.TimeoutExpired:
                player.kill()
        LOG.info("ffplay 已关闭")
