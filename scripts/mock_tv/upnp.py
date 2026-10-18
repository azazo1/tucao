#!/usr/bin/env python3
"""UPnP 设备描述, 服务描述与 SOAP 报文模板.

mock 电视只需要让客户端发现设备, 调通 AVTransport 与 RenderingControl,
因此这里只声明实际实现的动作, 不做完整的状态变量建模.
"""

from xml.etree import ElementTree
from xml.sax.saxutils import escape

DEVICE_TYPE = "urn:schemas-upnp-org:device:MediaRenderer:1"
SERVICE_AVT = "urn:schemas-upnp-org:service:AVTransport:1"
SERVICE_RCS = "urn:schemas-upnp-org:service:RenderingControl:1"
SERVICE_CMS = "urn:schemas-upnp-org:service:ConnectionManager:1"

SOAP_NS = "http://schemas.xmlsoap.org/soap/envelope/"

# (服务类型, serviceId, SCPD 路径, 控制路径, 事件路径)
SERVICES = (
    (SERVICE_AVT, "urn:upnp-org:serviceId:AVTransport",
     "/AVTransport.xml", "/control/AVTransport", "/event/AVTransport"),
    (SERVICE_RCS, "urn:upnp-org:serviceId:RenderingControl",
     "/RenderingControl.xml", "/control/RenderingControl", "/event/RenderingControl"),
    (SERVICE_CMS, "urn:upnp-org:serviceId:ConnectionManager",
     "/ConnectionManager.xml", "/control/ConnectionManager", "/event/ConnectionManager"),
)

# 控制路径反查服务类型, 供 SOAP 分发使用.
CONTROL_TYPES = {path: service for service, _, _, path, _ in SERVICES}
SCPD_PATHS = {path: service for service, _, path, _, _ in SERVICES}

# 设备可播放的媒体类型, 客户端可能据此过滤设备, 尽量覆盖常见封装.
MEDIA_MIMES = (
    "video/mp4",
    "video/mpeg",
    "video/x-matroska",
    "video/webm",
    "video/x-msvideo",
    "video/x-flv",
    "video/quicktime",
    "audio/mpeg",
    "audio/mp4",
    "application/vnd.apple.mpegurl",
)

DLNA_OP = "DLNA.ORG_OP=01;DLNA.ORG_CI=0"
DLNA_FLAGS = "DLNA.ORG_FLAGS=01700000000000000000000000000000"

PROTOCOL_INFO = ",".join(
    f"http-get:*:{mime}:{DLNA_OP};{DLNA_FLAGS}" for mime in MEDIA_MIMES
)

def device_description(name: str, udn: str, base_url: str) -> str:
    """生成设备描述文档, 客户端据此发现服务与控制地址."""
    services = "".join(
        f"""
    <service>
      <serviceType>{service}</serviceType>
      <serviceId>{service_id}</serviceId>
      <SCPDURL>{scpd_path}</SCPDURL>
      <controlURL>{control_path}</controlURL>
      <eventSubURL>{event_path}</eventSubURL>
    </service>"""
        for service, service_id, scpd_path, control_path, event_path in SERVICES
    )
    return f"""<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:dlna="urn:schemas-dlna-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>{DEVICE_TYPE}</deviceType>
    <friendlyName>{escape(name)}</friendlyName>
    <manufacturer>tucao mock</manufacturer>
    <manufacturerURL>{escape(base_url)}/</manufacturerURL>
    <modelDescription>mock dlna renderer for casting tests</modelDescription>
    <modelName>Mock TV</modelName>
    <modelNumber>1</modelNumber>
    <modelURL>{escape(base_url)}/</modelURL>
    <serialNumber>mock-0001</serialNumber>
    <UDN>{udn}</UDN>
    <dlna:X_DLNADOC>DMR-1.50</dlna:X_DLNADOC>
    <serviceList>{services}
    </serviceList>
  </device>
</root>
"""


def _action(name: str, ins: tuple = (), outs: tuple = ()) -> str:
    args = ""
    for arg, variable in ins:
        args += (
            f"<argument><name>{arg}</name><direction>in</direction>"
            f"<relatedStateVariable>{variable}</relatedStateVariable></argument>"
        )
    for arg, variable in outs:
        args += (
            f"<argument><name>{arg}</name><direction>out</direction>"
            f"<relatedStateVariable>{variable}</relatedStateVariable></argument>"
        )
    return f"<action><name>{name}</name><argumentList>{args}</argumentList></action>"


def _state(name: str, data_type: str = "string", send_events: str = "no") -> str:
    return (
        f'<stateVariable sendEvents="{send_events}"><name>{name}</name>'
        f"<dataType>{data_type}</dataType></stateVariable>"
    )


def _scpd(actions: tuple, variables: tuple) -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<scpd xmlns="urn:schemas-upnp-org:service-1-0">'
        "<specVersion><major>1</major><minor>0</minor></specVersion>"
        f"<actionList>{''.join(actions)}</actionList>"
        f"<serviceStateTable>{''.join(variables)}</serviceStateTable>"
        "</scpd>"
    )


_AVT_ACTIONS = (
    _action("SetAVTransportURI",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),
             ("CurrentURI", "AVTransportURI"),
             ("CurrentURIMetaData", "AVTransportURIMetaData"))),
    _action("SetNextAVTransportURI",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),
             ("NextURI", "NextAVTransportURI"),
             ("NextURIMetaData", "NextAVTransportURIMetaData"))),
    _action("GetMediaInfo",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),),
            (("NrTracks", "NumberOfTracks"),
             ("MediaDuration", "CurrentMediaDuration"),
             ("CurrentURI", "AVTransportURI"),
             ("CurrentURIMetaData", "AVTransportURIMetaData"),
             ("NextURI", "NextAVTransportURI"),
             ("NextURIMetaData", "NextAVTransportURIMetaData"),
             ("PlayMedium", "PlaybackStorageMedium"),
             ("RecordMedium", "RecordStorageMedium"),
             ("WriteStatus", "RecordMediumWriteStatus"))),
    _action("GetTransportInfo",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),),
            (("CurrentTransportState", "TransportState"),
             ("CurrentTransportStatus", "TransportStatus"),
             ("CurrentSpeed", "TransportPlaySpeed"))),
    _action("GetPositionInfo",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),),
            (("Track", "CurrentTrack"),
             ("TrackDuration", "CurrentTrackDuration"),
             ("TrackMetaData", "CurrentTrackMetaData"),
             ("TrackURI", "CurrentTrackURI"),
             ("RelTime", "RelativeTimePosition"),
             ("AbsTime", "AbsoluteTimePosition"),
             ("RelCount", "RelativeCounterPosition"),
             ("AbsCount", "AbsoluteCounterPosition"))),
    _action("GetDeviceCapabilities",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),),
            (("PlayMedia", "PossiblePlaybackStorageMedia"),
             ("RecMedia", "PossibleRecordStorageMedia"),
             ("RecQualityModes", "PossibleRecordQualityModes"))),
    _action("GetTransportSettings",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),),
            (("PlayMode", "CurrentPlayMode"),
             ("RecQualityMode", "CurrentRecordQualityMode"))),
    _action("GetCurrentTransportActions",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),),
            (("Actions", "CurrentTransportActions"),)),
    _action("Stop", (("InstanceID", "A_ARG_TYPE_InstanceID"),)),
    _action("Play",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),
             ("Speed", "TransportPlaySpeed"))),
    _action("Pause", (("InstanceID", "A_ARG_TYPE_InstanceID"),)),
    _action("Seek",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),
             ("Unit", "A_ARG_TYPE_SeekMode"),
             ("Target", "A_ARG_TYPE_SeekTarget"))),
    _action("Next", (("InstanceID", "A_ARG_TYPE_InstanceID"),)),
    _action("Previous", (("InstanceID", "A_ARG_TYPE_InstanceID"),)),
)

_AVT_STATES = (
    _state("A_ARG_TYPE_InstanceID", "ui4"),
    _state("A_ARG_TYPE_SeekMode"),
    _state("A_ARG_TYPE_SeekTarget"),
    _state("AVTransportURI"),
    _state("AVTransportURIMetaData"),
    _state("NextAVTransportURI"),
    _state("NextAVTransportURIMetaData"),
    _state("CurrentTrack", "ui4"),
    _state("CurrentTrackDuration"),
    _state("CurrentTrackMetaData"),
    _state("CurrentTrackURI"),
    _state("CurrentMediaDuration"),
    _state("NumberOfTracks", "ui4"),
    _state("PlaybackStorageMedium"),
    _state("RecordStorageMedium"),
    _state("RecordMediumWriteStatus"),
    _state("PossiblePlaybackStorageMedia"),
    _state("PossibleRecordStorageMedia"),
    _state("PossibleRecordQualityModes"),
    _state("CurrentPlayMode"),
    _state("CurrentRecordQualityMode"),
    _state("CurrentTransportActions"),
    _state("RelativeTimePosition"),
    _state("AbsoluteTimePosition"),
    _state("RelativeCounterPosition", "i4"),
    _state("AbsoluteCounterPosition", "i4"),
    _state("TransportState", send_events="yes"),
    _state("TransportStatus"),
    _state("TransportPlaySpeed"),
)

_RCS_ACTIONS = (
    _action("GetVolume",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),
             ("Channel", "A_ARG_TYPE_Channel")),
            (("CurrentVolume", "Volume"),)),
    _action("SetVolume",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),
             ("Channel", "A_ARG_TYPE_Channel"),
             ("DesiredVolume", "Volume"))),
    _action("GetMute",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),
             ("Channel", "A_ARG_TYPE_Channel")),
            (("CurrentMute", "Mute"),)),
    _action("SetMute",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),
             ("Channel", "A_ARG_TYPE_Channel"),
             ("DesiredMute", "Mute"))),
    _action("ListPresets",
            (("InstanceID", "A_ARG_TYPE_InstanceID"),),
            (("CurrentPresetNameList", "PresetNameList"),)),
)

_RCS_STATES = (
    _state("A_ARG_TYPE_InstanceID", "ui4"),
    _state("A_ARG_TYPE_Channel"),
    _state("Volume", "ui2"),
    _state("Mute", "boolean"),
    _state("PresetNameList"),
    _state("LastChange", send_events="yes"),
)

_CMS_ACTIONS = (
    _action("GetProtocolInfo", (),
            (("Source", "SourceProtocolInfo"),
             ("Sink", "SinkProtocolInfo"))),
    _action("GetCurrentConnectionIDs", (),
            (("ConnectionIDs", "CurrentConnectionIDs"),)),
    _action("GetCurrentConnectionInfo",
            (("ConnectionID", "A_ARG_TYPE_ConnectionID"),),
            (("RcsID", "A_ARG_TYPE_RcsID"),
             ("AVTransportID", "A_ARG_TYPE_AVTransportID"),
             ("ProtocolInfo", "A_ARG_TYPE_ProtocolInfo"),
             ("PeerConnectionManager", "A_ARG_TYPE_ConnectionManager"),
             ("PeerConnectionID", "A_ARG_TYPE_ConnectionID"),
             ("Direction", "A_ARG_TYPE_Direction"),
             ("Status", "A_ARG_TYPE_ConnectionStatus"))),
)

_CMS_STATES = (
    _state("A_ARG_TYPE_ConnectionID", "i4"),
    _state("A_ARG_TYPE_ConnectionManager"),
    _state("A_ARG_TYPE_RcsID", "i4"),
    _state("A_ARG_TYPE_AVTransportID", "i4"),
    _state("A_ARG_TYPE_ProtocolInfo"),
    _state("A_ARG_TYPE_ConnectionStatus"),
    _state("A_ARG_TYPE_Direction"),
    _state("SourceProtocolInfo", send_events="yes"),
    _state("SinkProtocolInfo", send_events="yes"),
    _state("CurrentConnectionIDs", send_events="yes"),
)

SCPD_XML = {
    SERVICE_AVT: _scpd(_AVT_ACTIONS, _AVT_STATES),
    SERVICE_RCS: _scpd(_RCS_ACTIONS, _RCS_STATES),
    SERVICE_CMS: _scpd(_CMS_ACTIONS, _CMS_STATES),
}


def soap_envelope(service: str, action: str, values: dict) -> str:
    """成功响应, values 为空时是带空体的 Response."""
    payload = "".join(
        f"<{key}>{escape(str(value))}</{key}>" for key, value in values.items()
    )
    return (
        '<?xml version="1.0" encoding="utf-8"?>'
        f'<s:Envelope xmlns:s="{SOAP_NS}" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        f"<s:Body><u:{action}Response xmlns:u=\"{service}\">"
        f"{payload}"
        f"</u:{action}Response></s:Body></s:Envelope>"
    )


def soap_request(service: str, action: str, values: dict) -> str:
    """客户端发出的动作报文, 测试客户端与外部调试都会用到."""
    payload = "".join(
        f"<{key}>{escape(str(value))}</{key}>" for key, value in values.items()
    )
    return (
        '<?xml version="1.0" encoding="utf-8"?>'
        f'<s:Envelope xmlns:s="{SOAP_NS}" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        f"<s:Body><u:{action} xmlns:u=\"{service}\">"
        f"{payload}"
        f"</u:{action}></s:Body></s:Envelope>"
    )


def soap_fault(code: int, description: str) -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>'
        f'<s:Envelope xmlns:s="{SOAP_NS}" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        "<s:Body><s:Fault><faultcode>s:Client</faultcode>"
        "<faultstring>UPnPError</faultstring><detail>"
        '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
        f"<errorCode>{code}</errorCode>"
        f"<errorDescription>{escape(description)}</errorDescription>"
        "</UPnPError></detail></s:Fault></s:Body></s:Envelope>"
    )


def parse_soap(header: str, body: bytes) -> tuple[str, dict]:
    """从 SOAPACTION 头与报文里取出动作名和参数, 忽略命名空间差异."""
    action = header.rsplit("#", 1)[-1].strip().strip('"') if header else ""
    params: dict[str, str] = {}
    if not body.strip():
        return action, params
    try:
        root = ElementTree.fromstring(body)
    except ElementTree.ParseError:
        return action, params
    for element in root.iter():
        if element.tag.split("}")[-1] != action:
            continue
        if not action:
            continue
        for child in element:
            params[child.tag.split("}")[-1]] = (child.text or "").strip()
        break
    return action, params


def response_values(payload: bytes, action: str) -> dict:
    """读取客户端侧响应里的字段, 供测试客户端复用."""
    values: dict[str, str] = {}
    try:
        root = ElementTree.fromstring(payload)
    except ElementTree.ParseError:
        return values
    for element in root.iter():
        if element.tag.split("}")[-1] != f"{action}Response":
            continue
        for child in element:
            values[child.tag.split("}")[-1]] = (child.text or "").strip()
        break
    return values


def didl_metadata(title: str, url: str, mime: str = "video/mp4") -> str:
    """构造 TrackMetaData, 真电视普遍要求 res 上带 protocolInfo."""
    return (
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        f"<dc:title>{escape(title)}</dc:title>"
        "<upnp:class>object.item.videoItem</upnp:class>"
        f'<res protocolInfo="http-get:*:{mime}:{DLNA_OP};{DLNA_FLAGS}">'
        f"{escape(url)}</res>"
        "</item></DIDL-Lite>"
    )

