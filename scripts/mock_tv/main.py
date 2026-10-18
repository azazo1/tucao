#!/usr/bin/env python3
"""mock 电视入口.

模拟一台支持 DLNA 的电视: 能被客户端发现, 接受 AVTransport 控制, 像电视那样
自己去拉媒体地址, 并把发出去的请求头与结果留在状态页上. 用于在没有真机电视时
验证投屏功能, 包括站点防盗链导致的拉流失败.
"""

import argparse
import logging
import os
import shutil
import signal
import subprocess
import sys
import threading
import uuid

from logbuf import MemoryLogHandler
from netutil import local_ip
from renderer import MediaSink, Renderer
from server import Context, MockTvServer
from ssdp import SsdpResponder

LOG = logging.getLogger("mocktv")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_MEDIA_DIR = os.path.join(ROOT, ".tmp", "mock_tv", "media")
SAMPLE_NAME = "sample.mp4"


def ensure_sample(directory: str) -> str:
    """生成一段带时间码的测试视频, 让 ffplay 与进度条都有东西可看."""
    path = os.path.join(directory, SAMPLE_NAME)
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        return path
    if not shutil.which("ffmpeg"):
        LOG.warning("没有 ffmpeg, 跳过样本媒体生成, 请自行放入 %s", directory)
        return path
    os.makedirs(directory, exist_ok=True)
    command = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=25",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
        "-t", "120",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "veryfast",
        "-c:a", "aac", "-movflags", "+faststart",
        path,
    ]
    LOG.info("生成样本媒体 (约 120 秒), 请稍候: %s", path)
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        LOG.warning("样本生成失败: %s", result.stderr.strip()[:400])
    else:
        LOG.info("样本媒体就绪: %.1f MB", os.path.getsize(path) / 1024 / 1024)
    return path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="模拟一台 DLNA 电视, 用于测试投屏客户端",
    )
    parser.add_argument("--port", type=int, default=58920, help="HTTP 端口, 默认 58920")
    parser.add_argument(
        "--ip", default="",
        help="对外公布的局域网地址, 默认自动挑选物理网卡 (VPN 常会干扰自动判断)",
    )
    parser.add_argument("--name", default="Mock TV (tucao)", help="设备名, 客户端按它筛选")
    parser.add_argument("--media-dir", default=DEFAULT_MEDIA_DIR, help="本地媒体目录")
    parser.add_argument("--play", action="store_true", help="用 ffplay 真的显示画面")
    parser.add_argument(
        "--referer", default="",
        help="拉流时附带的 Referer, 留空即模拟真电视 (不带 Referer)",
    )
    parser.add_argument(
        "--tv-ua", default="Linux/3.14.0 UPnP/1.1 MockTV/1.0",
        help="电视拉流时使用的 UA",
    )
    parser.add_argument("--instant", action="store_true", help="M-SEARCH 立即响应, 不按 MX 抖动")
    parser.add_argument("--no-notify", action="store_true", help="不周期广播 ssdp:alive")
    parser.add_argument("--no-sample", action="store_true", help="不自动生成样本媒体")
    parser.add_argument(
        "--lenient", action="store_true",
        help="guard 路径也允许不带 Referer, 便于对比",
    )
    parser.add_argument("--verbose", action="store_true", help="输出调试日志")
    return parser.parse_args(argv)


def setup_logging(verbose: bool, handler: MemoryLogHandler) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    formatter = logging.Formatter("%(asctime)s %(levelname)-5s %(name)s: %(message)s", "%H:%M:%S")
    tree = logging.getLogger()
    tree.setLevel(level)
    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(formatter)
    handler.setFormatter(formatter)
    tree.addHandler(console)
    tree.addHandler(handler)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    log_handler = MemoryLogHandler()
    setup_logging(args.verbose, log_handler)

    media_dir = os.path.abspath(args.media_dir)
    os.makedirs(media_dir, exist_ok=True)
    if not args.no_sample:
        ensure_sample(media_dir)

    ip = local_ip(args.ip)
    base_url = f"http://{ip}:{args.port}"
    udn = f"uuid:{uuid.uuid5(uuid.NAMESPACE_DNS, 'mock-tv:' + args.name)}"

    renderer = Renderer()
    sink = MediaSink(args.tv_ua, args.referer, args.play)
    context = Context(
        name=args.name,
        udn=udn,
        base_url=base_url,
        renderer=renderer,
        sink=sink,
        log_handler=log_handler,
        media_dir=media_dir,
        guard_requires_referer=not args.lenient,
    )

    try:
        server = MockTvServer(("0.0.0.0", args.port), context)
    except OSError as exc:
        LOG.error("端口 %d 无法监听: %s", args.port, exc)
        return 1
    serving = threading.Thread(target=server.serve_forever, name="http", daemon=True)
    serving.start()

    ssdp = SsdpResponder(
        base_url=base_url,
        udn=udn,
        name=args.name,
        iface_ips=[ip, "127.0.0.1"],
        instant=args.instant,
        notify_interval=0 if args.no_notify else 30.0,
    )
    try:
        ssdp.start()
    except OSError as exc:
        LOG.error("SSDP 端口 1900 无法监听: %s", exc)
        server.shutdown()
        return 1

    sample = os.path.join(media_dir, SAMPLE_NAME)
    print(
        f"""
mock 电视已启动
  设备名     {args.name}
  设备 UDN   {udn}
  状态页     {base_url}/
  设备描述   {base_url}/desc.xml
  样本媒体   {base_url}/media/{SAMPLE_NAME}
  受限媒体   {base_url}/guard/{SAMPLE_NAME}  (需要 Referer, 用来验证防盗链)
  拉流参考   UA={args.tv_ua}  Referer={args.referer or '(不带)'}
  画面显示   {'ffplay' if args.play else '仅探测 (加 --play 显示画面)'}

手机需要与电脑在同一 Wi-Fi 下, 且路由器未开 AP 隔离.
按 Ctrl+C 退出.
"""
    )

    stop = threading.Event()

    def handle_signal(signum, _frame):
        LOG.info("收到信号 %s, 准备退出", signum)
        stop.set()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)
    # 关掉终端窗口时收到的是 SIGHUP, 不接住就会直接死掉, 来不及广播 byebye.
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, handle_signal)
    stop.wait()

    LOG.info("正在关闭 mock 电视")
    sink.stop()
    ssdp.stop()
    server.shutdown()
    server.server_close()
    LOG.info("已退出")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
