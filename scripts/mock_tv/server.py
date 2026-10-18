#!/usr/bin/env python3
"""HTTP 侧: 设备描述, SOAP 控制, 状态页与本地媒体服务.

媒体服务有两条路径: /media/ 直接下发, /guard/ 要求请求带 Referer,
后者用来复现站点防盗链, 也就是"手机能播, 电视拉不下来"的典型情况.
"""

import json
import logging
import mimetypes
import os
import re
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import upnp
from logbuf import MemoryLogHandler
from renderer import PLAYING, Renderer, format_time, parse_time

LOG = logging.getLogger("mocktv.http")

CHUNK = 64 * 1024


class UpnpError(Exception):
    """SOAP 层的失败, 按 UPnP 的错误码返回."""

    def __init__(self, code: int, description: str):
        super().__init__(description)
        self.code = code
        self.description = description


class Context:
    """所有组件共享的运行期状态."""

    def __init__(
        self,
        name: str,
        udn: str,
        base_url: str,
        renderer: Renderer,
        sink,
        log_handler: MemoryLogHandler,
        media_dir: str,
        guard_requires_referer: bool = True,
    ):
        self.name = name
        self.udn = udn
        self.base_url = base_url
        self.renderer = renderer
        self.sink = sink
        self.log_handler = log_handler
        self.media_dir = media_dir
        self.guard_requires_referer = guard_requires_referer
        self.started_at = time.time()
        self._probe_lock = threading.Lock()
        self._probing_uri = ""

    # --- 拉流与播放 -----------------------------------------------------

    def cast(self, uri: str, title: str = "未命名", referer: str | None = None) -> None:
        """设置媒体并开始拉流, 与客户端调 SetAVTransportURI + Play 等价."""
        if referer is not None:
            self.sink.referer = referer
        self.renderer.set_uri(uri, upnp.didl_metadata(title, uri))
        self.renderer.play()
        self._start_media(uri)

    def play_from_renderer(self) -> None:
        """Play 动作: 先回响应, 拉流放到后台, 与真电视的行为一致."""
        self.renderer.play()
        self._start_media(self.renderer.uri)

    def _start_media(self, uri: str) -> None:
        if not uri:
            return
        with self._probe_lock:
            if self._probing_uri == uri:
                return
            self._probing_uri = uri
        threading.Thread(
            target=self._probe_and_play, args=(uri,), name="media-probe", daemon=True
        ).start()

    def _probe_and_play(self, uri: str) -> None:
        ok, note, duration = self.sink.probe(uri)
        with self._probe_lock:
            if self._probing_uri == uri:
                self._probing_uri = ""
        # 探测期间可能已经换了媒体, 只把结果落到仍然匹配的那次上.
        if self.renderer.uri != uri:
            return
        self.renderer.probe_note = note
        self.renderer.probe_ok = ok
        if duration:
            self.renderer.duration = duration
        if ok:
            self.sink.start(uri)


def handle_action(ctx: Context, service: str, action: str, params: dict) -> dict:
    """把一个 SOAP 动作落到状态机上, 返回出参."""
    renderer = ctx.renderer

    if action == "SetAVTransportURI":
        uri = params.get("CurrentURI", "")
        meta = params.get("CurrentURIMetaData", "")
        LOG.info("收到投屏地址: %s", uri)
        renderer.set_uri(uri, meta)
        return {}

    if action == "SetNextAVTransportURI":
        renderer.next_uri = params.get("NextURI", "")
        return {}

    if action == "Play":
        if not renderer.uri:
            raise UpnpError(701, "Transition not available")
        if renderer.state != PLAYING:
            LOG.info("开始播放: %s", renderer.uri)
            ctx.play_from_renderer()
        return {}

    if action == "Pause":
        if renderer.state != PLAYING:
            raise UpnpError(701, "Transition not available")
        renderer.pause()
        ctx.sink.stop()
        LOG.info("已暂停在 %s", format_time(renderer.position()))
        return {}

    if action == "Stop":
        renderer.stop()
        ctx.sink.stop()
        LOG.info("已停止")
        return {}

    if action == "Seek":
        target = parse_time(params.get("Target", "0"))
        renderer.seek(target)
        if renderer.state == PLAYING:
            ctx.sink.start(renderer.uri, start_at=renderer.position())
        LOG.info("跳转到 %s", format_time(renderer.position()))
        return {}

    if action in ("Next", "Previous"):
        raise UpnpError(701, "Transition not available")

    if action == "GetTransportInfo":
        return {
            "CurrentTransportState": renderer.state,
            "CurrentTransportStatus": "OK",
            "CurrentSpeed": "1",
        }

    if action == "GetPositionInfo":
        position = format_time(renderer.position())
        return {
            "Track": "1",
            "TrackDuration": format_time(renderer.duration),
            "TrackMetaData": renderer.metadata,
            "TrackURI": renderer.uri,
            "RelTime": position,
            "AbsTime": position,
            "RelCount": "2147483647",
            "AbsCount": "2147483647",
        }

    if action == "GetMediaInfo":
        return {
            "NrTracks": "1" if renderer.uri else "0",
            "MediaDuration": format_time(renderer.duration),
            "CurrentURI": renderer.uri,
            "CurrentURIMetaData": renderer.metadata,
            "NextURI": renderer.next_uri,
            "NextURIMetaData": "",
            "PlayMedium": "NETWORK",
            "RecordMedium": "NOT_IMPLEMENTED",
            "WriteStatus": "NOT_IMPLEMENTED",
        }

    if action == "GetDeviceCapabilities":
        return {
            "PlayMedia": "NETWORK",
            "RecMedia": "NOT_IMPLEMENTED",
            "RecQualityModes": "NOT_IMPLEMENTED",
        }

    if action == "GetTransportSettings":
        return {"PlayMode": "NORMAL", "RecQualityMode": "NOT_IMPLEMENTED"}

    if action == "GetCurrentTransportActions":
        return {"Actions": renderer.transport_actions()}

    if service == upnp.SERVICE_RCS:
        channel = params.get("Channel", "Master")
        if channel != "Master":
            raise UpnpError(402, "Invalid Args")
        if action == "GetVolume":
            return {"CurrentVolume": str(renderer.volume)}
        if action == "SetVolume":
            try:
                renderer.volume = max(0, min(100, int(params.get("DesiredVolume", "35"))))
            except ValueError:
                raise UpnpError(402, "Invalid Args") from None
            LOG.info("音量调整为 %d", renderer.volume)
            return {}
        if action == "GetMute":
            return {"CurrentMute": "1" if renderer.mute else "0"}
        if action == "SetMute":
            renderer.mute = params.get("DesiredMute", "0") in ("1", "true", "True")
            return {}
        if action == "ListPresets":
            return {"CurrentPresetNameList": "FactoryDefaults"}

    if service == upnp.SERVICE_CMS:
        if action == "GetProtocolInfo":
            return {"Source": "", "Sink": upnp.PROTOCOL_INFO}
        if action == "GetCurrentConnectionIDs":
            return {"ConnectionIDs": "0"}
        if action == "GetCurrentConnectionInfo":
            return {
                "RcsID": "0",
                "AVTransportID": "0",
                "ProtocolInfo": "",
                "PeerConnectionManager": "",
                "PeerConnectionID": "-1",
                "Direction": "Input",
                "Status": "OK",
            }

    raise UpnpError(401, "Invalid Action")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "MockTV/1.0"
    sys_version = ""

    @property
    def ctx(self) -> Context:
        return self.server.context  # type: ignore[attr-defined]

    # --- 通用输出 -------------------------------------------------------

    def _send(self, status: int, body: bytes, content_type: str, head: bool = False) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def _send_json(self, payload: dict, head: bool = False, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode()
        self._send(status, body, "application/json; charset=utf-8", head)

    def log_message(self, fmt: str, *args) -> None:
        LOG.debug("%s %s", self.address_string(), fmt % args)

    # --- 路由 -----------------------------------------------------------

    def do_GET(self) -> None:
        self._dispatch_get(head=False)

    def do_HEAD(self) -> None:
        self._dispatch_get(head=True)

    def _dispatch_get(self, head: bool) -> None:
        ctx = self.ctx
        path = urllib.parse.urlparse(self.path).path
        if path in ("/", "/index.html"):
            self._send(200, render_status(ctx).encode(), "text/html; charset=utf-8", head)
        elif path == "/desc.xml":
            body = upnp.device_description(ctx.name, ctx.udn, ctx.base_url)
            self._send(200, body.encode(), 'text/xml; charset="utf-8"', head)
        elif path in upnp.SCPD_PATHS:
            body = upnp.SCPD_XML[upnp.SCPD_PATHS[path]]
            self._send(200, body.encode(), 'text/xml; charset="utf-8"', head)
        elif path == "/state.json":
            self._send_json(ctx.renderer.snapshot(), head)
        elif path == "/log.json":
            self._send_json({"lines": ctx.log_handler.lines()}, head)
        elif path.startswith("/media/"):
            self._serve_media(path[len("/media/"):], require_referer=False, head=head)
        elif path.startswith("/guard/"):
            self._serve_media(
                path[len("/guard/"):],
                require_referer=ctx.guard_requires_referer,
                head=head,
            )
        elif path == "/favicon.ico":
            self._send(204, b"", "image/x-icon", head)
        else:
            self._send(404, "not found\n".encode(), "text/plain; charset=utf-8", head)

    def do_POST(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path in upnp.CONTROL_TYPES:
            self._handle_soap(path)
        elif path == "/remote":
            self._handle_remote()
        else:
            self._send(404, "not found\n".encode(), "text/plain; charset=utf-8")

    def do_SUBSCRIBE(self) -> None:
        self._handle_event()

    def do_UNSUBSCRIBE(self) -> None:
        self._handle_event()

    # --- SOAP -----------------------------------------------------------

    def _handle_soap(self, path: str) -> None:
        ctx = self.ctx
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        body = self.rfile.read(length) if length else b""
        service = upnp.CONTROL_TYPES[path]
        action, params = upnp.parse_soap(self.headers.get("SOAPACTION", ""), body)
        shown = {key: (value[:96] + "...") if len(value) > 96 else value for key, value in params.items()}
        LOG.info("SOAP %s %s", action or "(未知动作)", shown)
        if not action:
            self._send_fault(400, "Invalid Action")
            return
        try:
            values = handle_action(ctx, service, action, params)
        except UpnpError as exc:
            LOG.warning("动作 %s 失败: %s (%s)", action, exc.description, exc.code)
            self._send_fault(exc.code, exc.description)
            return
        payload = upnp.soap_envelope(service, action, values)
        self._send(200, payload.encode(), 'text/xml; charset="utf-8"')

    def _send_fault(self, code: int, description: str) -> None:
        payload = upnp.soap_fault(code, description)
        self._send(500, payload.encode(), 'text/xml; charset="utf-8"')

    def _handle_event(self) -> None:
        """只回一个订阅号, 不做真正的 GENA 通知, 客户端据此仍可正常工作."""
        self.send_response(200)
        self.send_header("SID", f"uuid:{time.time_ns()}")
        self.send_header("TIMEOUT", "Second-1800")
        self.send_header("Content-Length", "0")
        self.end_headers()

    # --- 状态页上的遥控器与手动投递 -------------------------------------

    def _handle_remote(self) -> None:
        ctx = self.ctx
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        raw = self.rfile.read(length).decode() if length else ""
        form = urllib.parse.parse_qs(raw)
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        merged = {key: values[0] for key, values in form.items()}
        merged.update({key: values[0] for key, values in query.items()})
        action = merged.get("action", "")
        renderer = ctx.renderer
        try:
            if action == "play":
                if not renderer.uri:
                    raise UpnpError(701, "Transition not available")
                ctx.play_from_renderer()
            elif action == "pause":
                renderer.pause()
                ctx.sink.stop()
            elif action == "stop":
                renderer.stop()
                ctx.sink.stop()
            elif action == "volume_up":
                renderer.volume = min(100, renderer.volume + 5)
            elif action == "volume_down":
                renderer.volume = max(0, renderer.volume - 5)
            elif action == "cast":
                url = merged.get("url", "").strip()
                if not url:
                    raise UpnpError(402, "Invalid Args")
                referer = merged.get("referer", "").strip()
                LOG.info("状态页手动投递: %s (Referer=%r)", url, referer)
                ctx.cast(url, title=url.rsplit("/", 1)[-1], referer=referer)
            else:
                raise UpnpError(402, "Invalid Args")
        except UpnpError as exc:
            self._send_json({"ok": False, "error": exc.description}, status=400)
            return
        self._send_json({"ok": True, "state": renderer.snapshot()})

    # --- 本地媒体服务 ---------------------------------------------------

    def _serve_media(self, raw_name: str, require_referer: bool, head: bool) -> None:
        ctx = self.ctx
        name = urllib.parse.unquote(raw_name.split("?")[0])
        if not name or "/" in name or name.startswith("."):
            self._send(404, "not found\n".encode(), "text/plain; charset=utf-8", head)
            return
        path = os.path.join(ctx.media_dir, name)
        if not os.path.isfile(path):
            LOG.warning("媒体不存在: %s (目录 %s)", name, ctx.media_dir)
            self._send(404, "not found\n".encode(), "text/plain; charset=utf-8", head)
            return

        referer = self.headers.get("Referer", "")
        agent = self.headers.get("User-Agent", "")
        range_header = self.headers.get("Range", "")
        LOG.info(
            "媒体请求 %s UA=%r Referer=%r Range=%r",
            name, agent, referer, range_header,
        )
        if require_referer and not referer:
            LOG.warning(
                "拒绝 403: %s 缺少 Referer, 真电视就是这么拉不到防盗链站点", name
            )
            body = (
                b"403: this endpoint requires a Referer header\n"
                b"real TVs do not send one, so the phone has to proxy\n"
            )
            self._send(403, body, "text/plain; charset=utf-8", head)
            return

        size = os.path.getsize(path)
        start, end = 0, size - 1
        status = 200
        match = re.match(r"bytes=(\d*)-(\d*)$", range_header.strip())
        if match and size:
            first, last = match.groups()
            if first:
                start = int(first)
                end = int(last) if last else size - 1
            elif last:
                start = max(0, size - int(last))
            start = min(start, size - 1)
            end = min(end, size - 1)
            if start > end:
                self._send(416, b"", "text/plain; charset=utf-8", head)
                return
            status = 206

        content_type = mimetypes.guess_type(name)[0] or "application/octet-stream"
        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head:
            return
        with open(path, "rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining > 0:
                chunk = handle.read(min(CHUNK, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    LOG.info("客户端提前断开: %s", name)
                    return
                remaining -= len(chunk)


STATUS_PAGE = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mock TV</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 24px; background: #12141a; color: #e6e8ee;
         font: 14px/1.6 -apple-system, "Segoe UI", "PingFang SC", sans-serif; }
  h1 { font-size: 18px; margin: 0 0 4px; }
  h2 { font-size: 13px; color: #9aa3b2; margin: 24px 0 8px;
       text-transform: uppercase; letter-spacing: 1px; }
  .card { background: #1a1d26; border: 1px solid #262b38; border-radius: 10px;
          padding: 14px 16px; }
  .row { display: flex; gap: 16px; flex-wrap: wrap; }
  .row > div { min-width: 150px; }
  .k { color: #8e97a8; font-size: 12px; }
  .v { font-variant-numeric: tabular-nums; word-break: break-all; }
  .state-playing { color: #4ade80; }
  .state-paused { color: #fbbf24; }
  .state-stopped { color: #94a3b8; }
  .ok { color: #4ade80; } .bad { color: #f87171; } .unknown { color: #94a3b8; }
  button { background: #2563eb; color: #fff; border: 0; border-radius: 8px;
           padding: 8px 14px; font-size: 13px; cursor: pointer; margin: 0 6px 6px 0; }
  button.ghost { background: #2b3140; }
  input { background: #0f1116; border: 1px solid #303647; color: #e6e8ee;
          border-radius: 8px; padding: 8px 10px; font-size: 13px; width: 100%;
          box-sizing: border-box; margin-bottom: 8px; }
  pre { margin: 0; max-height: 360px; overflow: auto; font-size: 12px;
        line-height: 1.5; white-space: pre-wrap; word-break: break-all;
        color: #b9c1d0; font-family: ui-monospace, Menlo, monospace; }
  .bar { height: 6px; background: #262b38; border-radius: 3px; overflow: hidden;
         margin-top: 6px; }
  .bar > i { display: block; height: 100%; background: #2563eb; width: 0; }
  .muted { color: #8e97a8; font-size: 12px; }
</style>
</head>
<body>
<h1>Mock TV</h1>
<div class="muted" id="addr"></div>

<h2>传输状态</h2>
<div class="card">
  <div class="row">
    <div><div class="k">状态</div><div class="v" id="state"></div></div>
    <div><div class="k">位置 / 时长</div><div class="v" id="pos"></div></div>
    <div><div class="k">音量</div><div class="v" id="volume"></div></div>
  </div>
  <div class="bar"><i id="progress"></i></div>
  <div class="k" style="margin-top:10px">当前媒体</div>
  <div class="v" id="uri"></div>
  <div class="k" style="margin-top:10px">拉流结果</div>
  <div class="v" id="probe"></div>
</div>

<h2>遥控器</h2>
<div class="card">
  <button onclick="remote('play')">播放</button>
  <button class="ghost" onclick="remote('pause')">暂停</button>
  <button class="ghost" onclick="remote('stop')">停止</button>
  <button class="ghost" onclick="remote('volume_down')">音量 -</button>
  <button class="ghost" onclick="remote('volume_up')">音量 +</button>
</div>

<h2>手动投递 (代替客户端)</h2>
<div class="card">
  <form onsubmit="cast(event)">
    <input id="url" placeholder="http://192.168.x.x:58920/guard/sample.mp4">
    <input id="referer" placeholder="Referer (可选, 留空模拟真电视)">
    <button type="submit">投递</button>
  </form>
  <div class="muted">guard 路径要求 Referer, media 路径不要求. 用前者验证防盗链判断.</div>
</div>

<h2>最近日志</h2>
<div class="card"><pre id="log"></pre></div>

<script>
const base = "__BASE__";
function fmt(seconds) {
  seconds = Math.max(0, Math.floor(seconds));
  const h = String(Math.floor(seconds / 3600)).padStart(2, "0");
  const m = String(Math.floor(seconds % 3600 / 60)).padStart(2, "0");
  const s = String(seconds % 60).padStart(2, "0");
  return h + ":" + m + ":" + s;
}
function paint(state) {
  const el = document.getElementById("state");
  el.textContent = state.state_label + " (" + state.state + ")";
  el.className = "v state-" + state.state.toLowerCase().split("_")[0];
  document.getElementById("pos").textContent =
    fmt(state.position) + " / " + (state.duration ? fmt(state.duration) : "--:--:--");
  const ratio = state.duration ? Math.min(100, state.position / state.duration * 100) : 0;
  document.getElementById("progress").style.width = ratio + "%";
  document.getElementById("volume").textContent = state.volume + (state.mute ? " (静音)" : "");
  document.getElementById("uri").textContent = state.uri || "(无)";
  const probe = document.getElementById("probe");
  probe.textContent = state.probe_note;
  probe.className = "v " + (state.probe_ok === true ? "ok" : state.probe_ok === false ? "bad" : "unknown");
}
async function tick() {
  try {
    const state = await (await fetch("/state.json")).json();
    paint(state);
    const log = await (await fetch("/log.json")).json();
    const box = document.getElementById("log");
    box.textContent = log.lines.slice(-120).join("\\n");
    box.scrollTop = box.scrollHeight;
  } catch (error) {
    document.getElementById("state").textContent = "连接中断: " + error;
  }
}
async function remote(action) {
  await fetch("/remote", { method: "POST", body: new URLSearchParams({ action }) });
  tick();
}
async function cast(event) {
  event.preventDefault();
  const url = document.getElementById("url").value.trim();
  const referer = document.getElementById("referer").value.trim();
  if (!url) return;
  await fetch("/remote", {
    method: "POST",
    body: new URLSearchParams({ action: "cast", url, referer }),
  });
  tick();
}
document.getElementById("addr").textContent = base;
document.getElementById("url").value = base + "/guard/sample.mp4";
tick();
setInterval(tick, 1500);
</script>
</body>
</html>
"""


def render_status(ctx: Context) -> str:
    return STATUS_PAGE.replaceAll("__BASE__", ctx.base_url)


class MockTvServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], context: Context):
        super().__init__(address, Handler)
        self.context = context
