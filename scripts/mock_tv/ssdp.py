#!/usr/bin/env python3
"""SSDP 发现: 响应 M-SEARCH, 并周期广播 ssdp:alive, 退出时发 ssdp:byebye."""

import logging
import random
import socket
import struct
import threading
from email.utils import formatdate

from upnp import DEVICE_TYPE, SERVICES

LOG = logging.getLogger("mocktv.ssdp")

SSDP_GROUP = ("239.255.255.250", 1900)
MAX_AGE = 1800
SERVER = "MockTV/1.0 UPnP/1.1 MockTV/1.0"


class SsdpResponder:
    """单个 UDP 1900 套接字同时承担发现响应与公告广播."""

    def __init__(
        self,
        base_url: str,
        udn: str,
        name: str,
        iface_ips: list[str],
        instant: bool = False,
        notify_interval: float = 30.0,
    ):
        self.base_url = base_url
        self.udn = udn
        self.name = name
        self.iface_ips = iface_ips or ["0.0.0.0"]
        self.instant = instant
        self.notify_interval = notify_interval
        self._socket: socket.socket | None = None
        self._closed = threading.Event()
        self._threads: list[threading.Thread] = []

    # --- 生命周期 -------------------------------------------------------

    def start(self) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            try:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
            except OSError:
                pass
        sock.bind(("", 1900))
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)

        joined = []
        for ip in self.iface_ips:
            try:
                request = struct.pack(
                    "4s4s",
                    socket.inet_aton(SSDP_GROUP[0]),
                    socket.inet_aton(ip),
                )
                sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, request)
                joined.append(ip)
            except OSError as exc:
                LOG.warning("加入组播失败 ip=%s: %s (可能有进程占用了同一组播)", ip, exc)
        sock.settimeout(0.5)
        self._socket = sock
        LOG.info("SSDP 监听 1900, 组播地址: %s", ", ".join(joined) or "默认接口")

        for name, target in (
            ("ssdp-recv", self._recv_loop),
            ("ssdp-notify", self._notify_loop),
        ):
            thread = threading.Thread(target=target, name=name, daemon=True)
            thread.start()
            self._threads.append(thread)

    def stop(self) -> None:
        self._closed.set()
        if self._socket is not None:
            try:
                self._notify("byebye")
            except OSError:
                pass
        for thread in self._threads:
            thread.join(timeout=1.0)
        if self._socket is not None:
            self._socket.close()
            self._socket = None

    # --- 报文 -----------------------------------------------------------

    def _targets(self) -> list[tuple[str, str]]:
        """ST 与 USN 的配对, uuid 那一条的 USN 不带后缀."""
        pairs = [
            ("upnp:rootdevice", f"{self.udn}::upnp:rootdevice"),
            (self.udn, self.udn),
            (DEVICE_TYPE, f"{self.udn}::{DEVICE_TYPE}"),
        ]
        pairs += [
            (service, f"{self.udn}::{service}") for service, *_ in SERVICES
        ]
        return pairs

    def _match(self, st: str) -> list[tuple[str, str]]:
        wanted = st.strip().lower()
        if not wanted or wanted == "ssdp:all":
            return self._targets()
        # 新版客户端会搜 MediaRenderer:2, 本设备可同时以 v1 与 v2 作答.
        if wanted == DEVICE_TYPE.lower().replace(":1", ":2"):
            return [(st.strip(), f"{self.udn}::{st.strip()}")]
        return [
            (target_st, usn)
            for target_st, usn in self._targets()
            if target_st.lower() == wanted
        ]

    @staticmethod
    def _parse_headers(text: str) -> dict[str, str]:
        headers: dict[str, str] = {}
        for line in text.splitlines()[1:]:
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            headers[key.strip().upper()] = value.strip()
        return headers

    def _search_response(self, st: str, usn: str) -> bytes:
        text = (
            "HTTP/1.1 200 OK\r\n"
            f"CACHE-CONTROL: max-age={MAX_AGE}\r\n"
            f"DATE: {formatdate(usegmt=True)}\r\n"
            "EXT:\r\n"
            f"LOCATION: {self.base_url}/desc.xml\r\n"
            f"SERVER: {SERVER}\r\n"
            f"ST: {st}\r\n"
            f"USN: {usn}\r\n"
            "BOOTID.UPNP.ORG: 1\r\n"
            "CONFIGID.UPNP.ORG: 1\r\n"
            "\r\n"
        )
        return text.encode()

    def _notify(self, nts: str) -> None:
        assert self._socket is not None
        for st, usn in self._targets():
            lines = [
                "NOTIFY * HTTP/1.1",
                "HOST: 239.255.255.250:1900",
                f"CACHE-CONTROL: max-age={MAX_AGE}",
            ]
            if nts == "alive":
                lines.append(f"LOCATION: {self.base_url}/desc.xml")
            lines += [
                f"NT: {st}",
                f"NTS: ssdp:{nts}",
                f"SERVER: {SERVER}",
                f"USN: {usn}",
                "BOOTID.UPNP.ORG: 1",
                "CONFIGID.UPNP.ORG: 1",
                "",
                "",
            ]
            try:
                self._socket.sendto("\r\n".join(lines).encode(), SSDP_GROUP)
            except OSError as exc:
                LOG.debug("发送 ssdp:%s 失败 st=%s: %s", nts, st, exc)

    # --- 线程 -----------------------------------------------------------

    def _recv_loop(self) -> None:
        assert self._socket is not None
        while not self._closed.is_set():
            try:
                data, addr = self._socket.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            self._handle_search(data, addr)

    def _handle_search(self, data: bytes, addr: tuple[str, int]) -> None:
        text = data.decode("utf-8", "replace")
        if not text.upper().startswith("M-SEARCH"):
            return
        headers = self._parse_headers(text)
        if "ssdp:discover" not in headers.get("MAN", "").lower():
            LOG.debug("忽略 MAN 不合规的 M-SEARCH from %s", addr[0])
            return
        st = headers.get("ST", "")
        matches = self._match(st)
        LOG.info(
            "M-SEARCH from %s:%s ST=%s 命中 %d 项",
            addr[0], addr[1], st or "(空)", len(matches),
        )
        if not matches:
            return
        try:
            mx = float(headers.get("MX", "1"))
        except ValueError:
            mx = 1.0
        window = 0.0 if self.instant else min(max(mx, 0.0), 3.0)
        for target_st, usn in matches:
            packet = self._search_response(target_st, usn)
            delay = random.uniform(0.0, window) if window > 0 else 0.0
            timer = threading.Timer(delay, self._send, args=(packet, addr))
            timer.daemon = True
            timer.start()

    def _send(self, packet: bytes, addr: tuple[str, int]) -> None:
        if self._socket is None:
            return
        try:
            self._socket.sendto(packet, addr)
        except OSError as exc:
            LOG.debug("响应 M-SEARCH 失败 %s: %s", addr, exc)

    def _notify_loop(self) -> None:
        """先广播一次 alive, 之后按间隔重复, 让客户端不必总靠搜索."""
        self._notify("alive")
        LOG.info("已广播 ssdp:alive")
        while not self._closed.wait(self.notify_interval):
            self._notify("alive")
