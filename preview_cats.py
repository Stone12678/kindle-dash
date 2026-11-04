# -*- coding: utf-8 -*-
"""猫咪姿态图鉴: 验证天气联动与奶油猫造型"""
from pathlib import Path

from PIL import Image, ImageDraw

from render import F, F_BOLD, F_REG, GRAY, INK, draw_cat, draw_weather_icon

W, H = 1072, 900
OUT = Path(__file__).resolve().parent / "output" / "cat_poses.png"

POSES = [
    ("stretch", 0, "晴", "四肢舒展, 整个摊开", "身体拉长贴地, 前爪往前伸, 尾巴向后铺开"),
    ("arch", 3, "阴 · 多云", "伸懒腰", "前身压低, 屁股翘起, 尾巴竖在天上"),
    ("curl", 61, "雨 · 雪", "蜷缩起来", "团成一团, 爪子收在身前, 尾巴绕到脚边"),
    ("sleep", -1, "夜间", "睡着", "22 点后不看天气, 一律睡姿"),
]

img = Image.new("L", (W, H), 255)
d = ImageDraw.Draw(img)

CELL_W, CELL_H = W // 2, H // 2
for i, (mood, code, sky, name, desc) in enumerate(POSES):
    col, row = i % 2, i // 2
    cx = col * CELL_W + CELL_W // 2
    base = row * CELL_H

    draw_weather_icon(d, cx=cx, cy=base + 70, s=26, code=code)
    d.text((cx, base + 128), sky, font=F(F_BOLD, 24), fill=GRAY, anchor="ms")

    draw_cat(d, cx=cx, cy=base + 268, s=72, mood=mood)

    d.text((cx, base + 350), name, font=F(F_BOLD, 36), fill=INK, anchor="ms")
    d.text((cx, base + 392), desc, font=F(F_REG, 23), fill=GRAY, anchor="ms")

d.line([(0, CELL_H), (W, CELL_H)], fill=205, width=2)
d.line([(CELL_W, 0), (CELL_W, H)], fill=205, width=2)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
print(f"已生成: {OUT}")
