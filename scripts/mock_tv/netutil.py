#!/usr/bin/env python3
"""取本机局域网地址.

开了 VPN 时, 默认路由可能落在 utun 上, 用 UDP connect 选路会拿到 VPN 地址,
投屏测试需要的是 Wi-Fi/网线那张网卡的地址, 所以优先解析网卡列表.
"""

import socket
import subprocess

PHYSICAL_PREFIXES = ("en", "eth", "wlan", "wlp")
PRIVATE_PREFIXES = ("192.168.", "10.", "172.16.", "172.17.", "172.18.", "172.19.",
                    "172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25.",
                    "172.26.", "172.27.", "172.28.", "172.29.", "172.30.", "172.31.")


def _ifconfig_ipv4() -> str:
    try:
        output = subprocess.run(
            ["ifconfig"], capture_output=True, text=True, timeout=3
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    candidates: list[tuple[int, str]] = []
    interface = ""
    for line in output.splitlines():
        if line and not line[0].isspace():
            interface = line.split(":")[0].split()[0]
            continue
        parts = line.split()
        if "inet" not in parts:
            continue
        try:
            address = parts[parts.index("inet") + 1]
        except IndexError:
            continue
        if not interface.startswith(PHYSICAL_PREFIXES):
            continue
        if address.startswith(("127.", "169.254.")):
            continue
        # 家用网段优先, 依次退到其他私网与公网地址.
        if address.startswith("192.168."):
            priority = 0
        elif address.startswith("10."):
            priority = 1
        elif address.startswith(PRIVATE_PREFIXES):
            priority = 2
        else:
            priority = 3
        candidates.append((priority, address))
    candidates.sort()
    return candidates[0][1] if candidates else ""


def _route_ipv4() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))  # 只用来选路, 不会真的发包
        return sock.getsockname()[0]
    except OSError:
        return ""
    finally:
        sock.close()


def local_ip(override: str = "") -> str:
    if override:
        return override
    return _ifconfig_ipv4() or _route_ipv4() or "127.0.0.1"
