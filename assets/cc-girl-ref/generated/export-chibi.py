"""按独立轮廓拆分透明底 Q 版三视图, 导出应用素材."""

import logging
from collections import deque
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
root = Path(__file__).resolve().parent
sheet = Image.open(root / "cc-chibi-sheet.png").convert("RGBA")
pixels = np.array(sheet)
mask = pixels[:, :, 3] > 0
if mask.all():
    raise ValueError("生成图没有完全透明的像素")
height, width = mask.shape
seen = np.zeros(mask.shape, dtype=bool)
components = []
for y, x in zip(*np.nonzero(mask)):
    if seen[y, x]:
        continue
    seen[y, x] = True
    queue = deque([(int(y), int(x))])
    points = []
    while queue:
        cy, cx = queue.popleft()
        points.append((cy, cx))
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    if len(points) > 10000:
        components.append(np.array(points))
if len(components) != 3:
    raise ValueError(f"预计三个独立角色, 实际检测到 {len(components)} 个")
components.sort(key=lambda points: points[:, 1].mean())
exports = []
for name, points in zip(("front", "three-quarter", "back"), components):
    isolated = np.zeros_like(pixels)
    ys, xs = points[:, 0], points[:, 1]
    isolated[ys, xs] = pixels[ys, xs]
    figure = Image.fromarray(isolated)
    bounds = figure.getchannel("A").getbbox()
    figure = figure.crop(bounds)
    for size in (512, 256, 128):
        scaled = figure.copy()
        scaled.thumbnail((round(size * 0.88), round(size * 0.88)), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        canvas.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
        target = root / f"cc-chibi-{name}-{size}.png"
        canvas.save(target, optimize=True)
        exports.append(target)
        logging.info("已导出 %s, 原始角色边界=%s", target.name, bounds)

preview = Image.new("RGB", (768, 512), "#f6f7fa")
preview.paste(Image.new("RGB", (384, 512), "#20242d"), (384, 0))
front = Image.open(root / "cc-chibi-front-256.png")
preview.paste(front, (64, 16), front)
preview.paste(front, (448, 16), front)
small = Image.open(root / "cc-chibi-front-128.png")
preview.paste(small, (128, 320), small)
preview.paste(small, (512, 320), small)
preview.save(root / "cc-chibi-ui-preview.jpg", quality=94)
with ZipFile(root / "cc-chibi-app-assets.zip", "w", ZIP_DEFLATED) as archive:
    for path in exports:
        archive.write(path, path.name)
    archive.write(root / "cc-chibi-sheet.png", "cc-chibi-sheet.png")
logging.info("已打包 9 张独立 PNG 和原始三视图")
