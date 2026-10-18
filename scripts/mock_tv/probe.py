#!/usr/bin/env python3
"""测试客户端: 以手机端身份验证 mock 电视.

依次执行 SSDP 发现, 取设备描述, SetAVTransportURI, Play, 轮询进度, Seek,
Pause, 再 Play, 最后 Stop. 每一步打印 OK/FAIL, 关键步骤失败时退出码非零.
这个脚本同时也是投屏客户端应有的调用顺序参考.
"""

import argparse
import json
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from xml.etree import ElementTree

import upnp
from netutil import local_ip

SEARCH_TARGET = upnp.DEVICE_TYPE
DEVICE_HEADERS = {"User-Agent": "probe/1.0 UPnP/1.1"}


def log(message: str) -> None:
    print(message, flush=True)


def ssdp_search(local_addr: str, timeout: float) -> list[dict]:
    """发 M-SEARCH, 返回收到的响应头."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    if local_addr:
        try:
            sock.bind((local_addr, 0))
            # 组播出口单独指定, 否则会跟着默认路由跑到 VPN 上.
            sock.setsockopt(
                socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
                socket.inet_aton(local_addr),
            )
        except OSError:
            pass
    request = (
        "M-SEARCH * HTTP/1.1\r\n"
        "HOST: 239.255.255.250:1900\r\n"
        'MAN: "ssdp:discover"\r\n'
        "MX: 2\r\n"
        f"ST: {SEARCH_TARGET}\r\n"
        "\r\n"
    ).encode()
    responses: list[dict] = []
    seen: set[str] = set()
    deadline = time.monotonic() + timeout
    sock.settimeout(0.4)
    sock.sendto(request, ("239.255.255.250", 1900))
    while time.monotonic() < deadline:
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            # 中途再补发一次, 丢包时不至于白等.
            if time.monotonic() < deadline - timeout / 2:
                sock.sendto(request, ("239.255.255.250", 1900))
            continue
        text = data.decode("utf-8", "replace")
        headers = {}
        for line in text.splitlines()[1:]:
            if ":" in line:
                key, value = line.split(":", 1)
                headers[key.strip().upper()] = value.strip()
        location = headers.get("LOCATION", "")
        if not location or location in seen:
            continue
        seen.add(location)
        headers["FROM"] = f"{addr[0]}:{addr[1]}"
        responses.append(headers)
    sock.close()
    return responses


def fetch_description(location: str) -> dict:
    with urllib.request.urlopen(location, timeout=5) as response:
        payload = response.read()
    root = ElementTree.fromstring(payload)
    result = {
        "location": location,
        "friendly_name": "",
        "udn": "",
        "device_type": "",
        "services": {},
    }
    for element in root.iter():
        tag = element.tag.split("}")[-1]
        if tag == "friendlyName" and element.text:
            result["friendly_name"] = element.text.strip()
        elif tag == "UDN" and element.text:
            result["udn"] = element.text.strip()
        elif tag == "deviceType" and element.text:
            result["device_type"] = element.text.strip()
        elif tag == "service":
            fields = {}
            for child in element:
                fields[child.tag.split("}")[-1]] = (child.text or "").strip()
            service_type = fields.get("serviceType", "")
            if service_type:
                result["services"][service_type] = fields
    return result


def soap(url: str, service: str, action: str, params: dict, timeout: float = 5) -> dict:
    body = upnp.soap_request(service, action, params).encode()
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPACTION": f'"{service}#{action}"',
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"{action} 失败 HTTP {exc.code}: {detail[:300]}") from None
    return upnp.response_values(payload, action)


def control_url(device: dict, service: str) -> str:
    fields = device["services"].get(service)
    if not fields:
        raise RuntimeError(f"设备没有声明 {service}")
    return urllib.parse.urljoin(device["location"], fields.get("controlURL", ""))


class Reporter:
    def __init__(self) -> None:
        self.failed = 0

    def check(self, index: int, title: str, ok: bool, detail: str = "") -> None:
        mark = "OK  " if ok else "FAIL"
        if not ok:
            self.failed += 1
        log(f"[{mark}] {index}. {title}" + (f": {detail}" if detail else ""))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="以手机端身份验证 mock 电视")
    parser.add_argument("--name", default="", help="按设备名筛选, 默认取第一个渲染器")
    parser.add_argument("--url", default="", help="投递的媒体地址, 默认取 mock 的样本")
    parser.add_argument("--local-addr", default="", help="M-SEARCH 使用的本机地址")
    parser.add_argument("--timeout", type=float, default=5.0, help="发现超时秒数")
    parser.add_argument("--no-stop", action="store_true", help="结束时不停机, 便于看状态页")
    args = parser.parse_args(argv)

    # 开了 VPN 时组播默认会走 tun, 必须显式绑到局域网网卡上.
    local_addr = args.local_addr or local_ip()
    log(f"本机地址 {local_addr}")
    report = Reporter()

    responses = ssdp_search(local_addr, args.timeout)
    report.check(1, "SSDP 发现", bool(responses), f"{len(responses)} 个响应")
    if not responses:
        log("      没有设备响应. 检查手机/电脑是否同一 Wi-Fi, 是否开了 AP 隔离,")
        log("      macOS 是否拦了本地网络访问, 以及 mock 是否在运行.")
        return 1

    devices = []
    for headers in responses:
        try:
            devices.append(fetch_description(headers["LOCATION"]))
        except Exception as exc:  # noqa: BLE001 - 单个设备失败不影响其他
            log(f"      读取描述失败 {headers['LOCATION']}: {exc}")
    renderers = [
        device for device in devices
        if "mediarenderer" in device["device_type"].lower()
        or any("AVTransport" in service for service in device["services"])
    ]
    if args.name:
        renderers = [
            device for device in renderers if args.name in device["friendly_name"]
        ]
    report.check(2, "取设备描述", bool(renderers),
                 ", ".join(device["friendly_name"] for device in renderers) or "没有渲染器")
    if not renderers:
        return 1

    device = renderers[0]
    avt = control_url(device, upnp.SERVICE_AVT)
    log(f"      控制地址 {avt}")

    url = args.url
    if not url:
        base = urllib.parse.urlsplit(device["location"])
        url = f"{base.scheme}://{base.netloc}/media/sample.mp4"
    report.check(3, "准备媒体地址", True, url)

    metadata = upnp.didl_metadata("probe sample", url)
    try:
        soap(avt, upnp.SERVICE_AVT, "SetAVTransportURI", {
            "InstanceID": "0", "CurrentURI": url, "CurrentURIMetaData": metadata,
        })
        report.check(4, "SetAVTransportURI", True)
    except RuntimeError as exc:
        report.check(4, "SetAVTransportURI", False, str(exc))
        return 1

    try:
        soap(avt, upnp.SERVICE_AVT, "Play", {"InstanceID": "0", "Speed": "1"})
        info = soap(avt, upnp.SERVICE_AVT, "GetTransportInfo", {"InstanceID": "0"})
        report.check(5, "Play", info.get("CurrentTransportState") == "PLAYING",
                     f"状态 {info.get('CurrentTransportState')}")
    except RuntimeError as exc:
        report.check(5, "Play", False, str(exc))
        return 1

    time.sleep(2)
    first = soap(avt, upnp.SERVICE_AVT, "GetPositionInfo", {"InstanceID": "0"})
    time.sleep(2)
    second = soap(avt, upnp.SERVICE_AVT, "GetPositionInfo", {"InstanceID": "0"})
    progressed = upnp_time(first.get("RelTime", "0")) < upnp_time(second.get("RelTime", "0"))
    report.check(
        6, "进度推进", progressed,
        f"{first.get('RelTime')} -> {second.get('RelTime')} (时长 {second.get('TrackDuration')})",
    )

    duration = upnp_time(second.get("TrackDuration", "0"))
    target = 10 if duration == 0 or duration > 20 else max(1, int(duration // 3))
    try:
        soap(avt, upnp.SERVICE_AVT, "Seek", {
            "InstanceID": "0", "Unit": "REL_TIME",
            "Target": f"00:00:{target:02d}",
        })
        after_seek = soap(avt, upnp.SERVICE_AVT, "GetPositionInfo", {"InstanceID": "0"})
        position = upnp_time(after_seek.get("RelTime", "0"))
        report.check(7, "Seek", abs(position - target) <= 2, f"目标 {target}s, 实际 {position:.0f}s")
    except RuntimeError as exc:
        report.check(7, "Seek", False, str(exc))

    try:
        soap(avt, upnp.SERVICE_AVT, "Pause", {"InstanceID": "0"})
        info = soap(avt, upnp.SERVICE_AVT, "GetTransportInfo", {"InstanceID": "0"})
        report.check(8, "Pause", info.get("CurrentTransportState") == "PAUSED_PLAYBACK",
                     f"状态 {info.get('CurrentTransportState')}")
        soap(avt, upnp.SERVICE_AVT, "Play", {"InstanceID": "0", "Speed": "1"})
        info = soap(avt, upnp.SERVICE_AVT, "GetTransportInfo", {"InstanceID": "0"})
        report.check(9, "恢复播放", info.get("CurrentTransportState") == "PLAYING")
    except RuntimeError as exc:
        report.check(8, "暂停与恢复", False, str(exc))

    if not args.no_stop:
        try:
            soap(avt, upnp.SERVICE_AVT, "Stop", {"InstanceID": "0"})
            info = soap(avt, upnp.SERVICE_AVT, "GetTransportInfo", {"InstanceID": "0"})
            report.check(10, "Stop", info.get("CurrentTransportState") == "STOPPED",
                         f"状态 {info.get('CurrentTransportState')}")
        except RuntimeError as exc:
            report.check(10, "Stop", False, str(exc))

    # 拉流结果由 mock 侧判定, 直接读它的状态页, 这正是防盗链问题的落点.
    base = device["location"].rsplit("/", 1)[0]
    try:
        with urllib.request.urlopen(f"{base}/state.json", timeout=5) as response:
            state = json.loads(response.read())
        report.check(11, "电视拉流结果", bool(state.get("probe_ok")),
                     state.get("probe_note", ""))
    except Exception as exc:  # noqa: BLE001
        log(f"[WARN] 读取 mock 状态失败: {exc}")

    log("")
    if report.failed:
        log(f"{report.failed} 项失败")
        return 1
    log("全部通过")
    return 0


def upnp_time(text: str) -> float:
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


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
