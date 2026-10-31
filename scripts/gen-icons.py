#!/usr/bin/env python3

# 生成应用图标资源: adaptive icon 矢量层, 各密度 PNG, assets 里的 logo 与母版 SVG.
#
# 用法: uv run --no-project python scripts/gen-icons.py
# 依赖: PATH 上的 resvg (把 SVG 渲染成 PNG).
#
# 图形: 一台下沿拉出气泡尾巴的电视 (吐槽气泡), 里面镂空一个播放键.
# 画布按 adaptive icon 的 108dp 设计, 可见区域为中心 72dp, 主体收在中心 46dp 内.
# 播放键做成镂空而不是另涂颜色, 这样前景层可以直接当 Android 13 的单色主题图标用.

import logging
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
ASSETS = ROOT / "assets"

log = logging.getLogger("gen-icons")

GRADIENT = ("#FF5A85", "#DC2358")
FG = "#FFFFFF"

# 两根天线从机顶中点向上张开.
ANTENNA = "M45,31.5 L54,41 L63,31.5"
ANTENNA_WIDTH = 5

# 机身: 圆角矩形, 左下角拉出气泡尾巴.
BODY = (
    "M39,41 H69 A8,8 0 0 1 77,49 V64 A8,8 0 0 1 69,72 H51 L40,80 L42,72 H39 "
    "A8,8 0 0 1 31,64 V49 A8,8 0 0 1 39,41 Z"
)

# 播放键三角的顶点与圆角半径, 重心落在机身屏幕区域中心 (54, 56.5).
PLAY = [(50.21, 50.0), (50.21, 63.0), (61.58, 56.5)]
PLAY_RADIUS = 1.25

DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
LOGO_SIZE = 192


def rounded_triangle(points: list[tuple[float, float]], r: float) -> str:
    """三角形向外扩 r, 拐角用圆弧连接, 等价于给三角描一圈圆头描边."""
    cx = sum(p[0] for p in points) / 3
    cy = sum(p[1] for p in points) / 3
    normals = []
    for i in range(3):
        (x0, y0), (x1, y1) = points[i], points[(i + 1) % 3]
        length = math.hypot(x1 - x0, y1 - y0)
        nx, ny = (y1 - y0) / length, -(x1 - x0) / length
        # 法线要背离重心.
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        if nx * (mx - cx) + ny * (my - cy) < 0:
            nx, ny = -nx, -ny
        normals.append((nx, ny))

    area = sum(
        points[i][0] * points[(i + 1) % 3][1] - points[(i + 1) % 3][0] * points[i][1]
        for i in range(3)
    )
    sweep = 1 if area > 0 else 0

    def off(p, n):
        return f"{p[0] + r * n[0]:.2f},{p[1] + r * n[1]:.2f}"

    d = f"M{off(points[0], normals[2])}"
    for i in range(3):
        d += f" A{r},{r} 0 0 {sweep} {off(points[i], normals[i])}"
        d += f" L{off(points[(i + 1) % 3], normals[i])}"
    return d + " Z"


def glyph_path() -> str:
    return f"{BODY} {rounded_triangle(PLAY, PLAY_RADIUS)}"


def icon_svg(view_box: str = "0 0 108 108", clip: str | None = None) -> str:
    """完整图标 SVG. clip 为可选的裁切形状, 用于生成旧版 PNG 与 logo."""
    defs = (
        '<linearGradient id="bg" x1="0" y1="0" x2="108" y2="108" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{GRADIENT[0]}"/><stop offset="1" stop-color="{GRADIENT[1]}"/>'
        "</linearGradient>"
    )
    group_attr = ""
    if clip:
        defs += f'<clipPath id="clip">{clip}</clipPath>'
        group_attr = ' clip-path="url(#clip)"'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}">'
        f"<defs>{defs}</defs><g{group_attr}>"
        '<rect width="108" height="108" fill="url(#bg)"/>'
        f'<path d="{ANTENNA}" fill="none" stroke="{FG}" stroke-width="{ANTENNA_WIDTH}" '
        'stroke-linecap="round" stroke-linejoin="round"/>'
        f'<path d="{glyph_path()}" fill="{FG}" fill-rule="evenodd"/>'
        "</g></svg>\n"
    )


# 旧版启动器 (Android 8 以下) 不做遮罩, 自带圆角方形外形, 四周留一点边.
LEGACY_VIEW_BOX = "18 18 72 72"
LEGACY_CLIP = '<rect x="21" y="21" width="66" height="66" rx="12"/>'

VECTOR_HEAD = (
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"{extra}\n'
    '    android:width="108dp"\n'
    '    android:height="108dp"\n'
    '    android:viewportWidth="108"\n'
    '    android:viewportHeight="108">\n'
)


def foreground_xml() -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- 由 scripts/gen-icons.py 生成, 不要手改. -->\n"
        + VECTOR_HEAD.format(extra="")
        + f'    <path\n        android:pathData="{ANTENNA}"\n'
        f'        android:strokeColor="{FG}"\n'
        f'        android:strokeWidth="{ANTENNA_WIDTH}"\n'
        '        android:strokeLineCap="round"\n'
        '        android:strokeLineJoin="round" />\n'
        f'    <path\n        android:pathData="{glyph_path()}"\n'
        f'        android:fillColor="{FG}"\n'
        '        android:fillType="evenOdd" />\n'
        "</vector>\n"
    )


def background_xml() -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- 由 scripts/gen-icons.py 生成, 不要手改. -->\n"
        + VECTOR_HEAD.format(extra='\n    xmlns:aapt="http://schemas.android.com/aapt"')
        + '    <path android:pathData="M0,0 H108 V108 H0 Z">\n'
        '        <aapt:attr name="android:fillColor">\n'
        '            <gradient\n'
        '                android:type="linear"\n'
        '                android:startX="0"\n'
        '                android:startY="0"\n'
        '                android:endX="108"\n'
        '                android:endY="108">\n'
        f'                <item android:offset="0" android:color="{GRADIENT[0]}" />\n'
        f'                <item android:offset="1" android:color="{GRADIENT[1]}" />\n'
        "            </gradient>\n"
        "        </aapt:attr>\n"
        "    </path>\n"
        "</vector>\n"
    )


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- 由 scripts/gen-icons.py 生成, 不要手改. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    log.info("写入 %s", path.relative_to(ROOT))


def render_png(svg: str, size: int, out: Path, workdir: Path) -> None:
    src = workdir / f"{out.stem}-{size}.svg"
    src.write_text(svg, encoding="utf-8")
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["resvg", "-w", str(size), "-h", str(size), str(src), str(out)], check=True
    )
    log.info("渲染 %s (%dx%d)", out.relative_to(ROOT), size, size)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    if shutil.which("resvg") is None:
        log.error("找不到 resvg, 请先把它装到 PATH 上")
        return 1

    write_text(ASSETS / "icon/icon.svg", icon_svg())
    write_text(RES / "drawable/ic_launcher_foreground.xml", foreground_xml())
    write_text(RES / "drawable/ic_launcher_background.xml", background_xml())
    write_text(RES / "mipmap-anydpi-v26/ic_launcher.xml", ADAPTIVE_XML)

    legacy = icon_svg(LEGACY_VIEW_BOX, LEGACY_CLIP)
    with tempfile.TemporaryDirectory() as tmp:
        workdir = Path(tmp)
        for density, size in DENSITIES.items():
            render_png(legacy, size, RES / f"mipmap-{density}/ic_launcher.png", workdir)
        render_png(legacy, LOGO_SIZE, ASSETS / "images/logo.png", workdir)

    log.info("图标资源生成完成")
    return 0


if __name__ == "__main__":
    sys.exit(main())
