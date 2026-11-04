# -*- coding: utf-8 -*-
"""
把 AI 生成的猫插画处理成适合 E Ink 显示的位图

做的事：裁白边 -> (可选)切掉顶部 -> 缩放到目标高度 -> 提对比度加深线条。
直接 `python prep_cat.py` 就会从 assets/cats/src/ 里的原图重建全部 5 张运行时用图。

为什么不手工修图：原图留着不动，参数全写在这里，想改尺寸或换裁切比例重跑一次就行，
不用再去翻聊天记录找当初裁了多少。
"""
from pathlib import Path

from PIL import Image, ImageOps

BASE = Path(__file__).resolve().parent
SRC_DIR = BASE / "assets" / "cats" / "src"
OUT_DIR = BASE / "assets" / "cats"

ART_H = 430          # 版面上猫的高度占位，改这个要同步改 render.py 的 ART_H

# 姿态 -> (原图文件名, 顶部额外裁掉的比例)
# crop_top 不是给所有图用的：只有"望雨"那张是竖向窗框构图，猫被框挤在中间显得小，
# 把窗框上沿切出画面之后，窗户看起来像"延伸出画面"，猫也大了，比完整画框自然。
POSES = {
    "cat_morning_430.png": ("Hand_drawn_ink_line_art_illust_2026-11-04T13-00-36.png", 0.0),
    "cat_work_430.png":    ("Hand_drawn_ink_line_art_illust_2026-11-04T13-02-29.png", 0.0),
    "cat_lunch_430.png":   ("Hand_drawn_ink_line_art_illust_2026-11-04T13-01-05.png", 0.0),
    "cat_sleep_430.png":   ("Hand_drawn_ink_line_art_illust_2026-11-04T13-01-21.png", 0.0),
    "cat_rainy_430.png":   ("Hand_drawn_ink_line_art_illust_2026-11-04T13-04-45.png", 0.23),
}


def trim_white(im: Image.Image, thresh: int = 238) -> Image.Image:
    """裁掉四周纯白, 留一点呼吸边

    阈值必须压到 238 以下: AI 生成的图在纯白区域布满 240~249 的淡噪点,
    用 246 会把整张画布当成内容, 等于没裁, 猫在缩略图里只剩中间一小撮。
    """
    g = im.convert("L")
    mask = g.point(lambda p: 255 if p < thresh else 0)
    box = mask.getbbox()
    if not box:
        return im
    pad = 6
    l, t, r, b = box
    return im.crop((max(0, l - pad), max(0, t - pad),
                    min(im.width, r + pad), min(im.height, b + pad)))


def prep(src: Path, out: Path, height: int = ART_H, crop_top: float = 0.0) -> Image.Image:
    im = trim_white(Image.open(src).convert("RGB"))

    if crop_top > 0:
        # 先按比例切顶，再缩到目标高度。两步顺序不能反:
        # 先缩后切会把图放大一次再裁，线条多受一次重采样。
        c = int(im.height * crop_top)
        im = im.crop((0, c, im.width, im.height))

    w = round(im.width * height / im.height)
    im = im.resize((w, height), Image.LANCZOS)
    g = ImageOps.autocontrast(im.convert("L"), cutoff=0.5)
    # 轻微加深线条, 抵消缩小造成的发灰
    g = g.point(lambda p: max(0, int((p - 20) * 1.18)))
    out.parent.mkdir(parents=True, exist_ok=True)
    g.save(out)
    print(f"{out.name}: {g.size[0]}x{g.size[1]}  <- {src.name}"
          + (f"  (裁顶 {crop_top:.0%})" if crop_top else ""))
    return g


def build_all() -> None:
    missing = [s for s, _ in POSES.values() if not (SRC_DIR / s).exists()]
    if missing:
        raise SystemExit(f"原图缺失，先放回 {SRC_DIR}:\n  " + "\n  ".join(missing))
    for out_name, (src_name, crop_top) in POSES.items():
        prep(SRC_DIR / src_name, OUT_DIR / out_name, ART_H, crop_top)


if __name__ == "__main__":
    build_all()
