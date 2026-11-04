# -*- coding: utf-8 -*-
"""
Kindle 信息看板 · 渲染脚本
--------------------------------------------------
输出: 1072 x 1448 单色 PNG (Kindle Paperwhite 4 原生分辨率)
原理: 云端/GitHub Actions 生成图片 -> Kindle 越狱后 curl 拉取 -> fbink 全屏刷新

设计约束:
  1. E Ink 只有灰度, 依靠字号与留白建立层次, 不用颜色区分信息
  2. 猫咪姿态由天气驱动, 夜间改为睡姿
  3. 所有字号在 6 寸 300ppi 屏上实际观看距离 50cm 仍可读
"""
from __future__ import annotations

import json
import math
import urllib.request
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# ---------- 基础参数 ----------
BASE = Path(__file__).resolve().parent
OUT = BASE / "output" / "dashboard.png"
DATA = BASE / "data" / "schedule.json"
# ---------- 猫插画 ----------
# 同一只猫的四个姿态, 由 pick_cat_mood() 按天气和时段挑一张。
# 任何一张缺失都会自动退回 draw_cat() 的矢量简笔画, 脚本不会因为少图就崩。
CAT_ARTS = {
    "morning": BASE / "assets" / "cats" / "cat_morning_430.png",   # 7-10 点  刚睡醒
    "work":    BASE / "assets" / "cats" / "cat_work_430.png",      # 白天     敲电脑
    "lunch":   BASE / "assets" / "cats" / "cat_lunch_430.png",     # 11-14 点 扒鱼吃饭
    "rainy":   BASE / "assets" / "cats" / "cat_rainy_430.png",     # 白天下雨 望着窗外发愁
    "sleep":   BASE / "assets" / "cats" / "cat_sleep_430.png",     # 夜里 蜷成一团
}

# 只要天在下雨下雪打雷, 就不管几点一律蜷着
PRECIP_CODES = {51, 53, 55, 61, 63, 65, 66, 67, 71, 73, 75, 77,
                80, 81, 82, 85, 86, 95, 96, 99}


def pick_cat_mood(now: datetime, code: int | None) -> str:
    """猫的姿态：夜里一律睡，白天先看天气再看时段"""
    h = now.hour
    if h >= 22 or h < 7:
        return "sleep"          # 深夜不折腾, 下雨也睡
    if code in PRECIP_CODES:
        return "rainy"          # 白天下雨下雪: 趴在窗台望着外面发愁
    if 11 <= h < 14:
        return "lunch"
    if h < 10:
        return "morning"
    return "work"


# 插画缺失时, 用矢量简笔画顶上对应的姿态
_VEC_FALLBACK = {"morning": "stretch", "work": "arch", "lunch": "arch",
                 "rainy": "curl", "sleep": "curl"}

W, H = 1072, 1448
M = 56                      # 页边距
INK, GRAY, LIGHT = 0, 90, 165
BLUSH = 228                 # 腮红用的极浅灰, Carta 屏能出这个层次

def _pick_font(cands: list[str], what: str) -> str:
    """按顺序找第一个可用的字体文件: 本地 Windows 用雅黑, GitHub Actions 用思源/Noto

    注意用 is_file() 而不是 exists(): Path("") 等于 Path("."), exists() 会返回 True,
    于是把目录当成字体文件丢给 truetype, 报一个完全看不懂的错。
    """
    for c in cands:
        if c and Path(c).is_file():
            return c
    raise FileNotFoundError(f"找不到{what}字体, 候选: {cands}")


def _fc_match(*families: str) -> str:
    """用 fontconfig 兜底找字体, 挡住不同发行版的安装路径差异"""
    import subprocess
    for fam in families:
        try:
            r = subprocess.run(["fc-match", "-f", "%{file}", fam],
                               capture_output=True, timeout=5)
            out = r.stdout.decode().strip()
            if out and Path(out).is_file():
                return out
        except Exception:
            pass
    return ""


F_BOLD = _pick_font([
    str(BASE / "assets/fonts/NotoSansSC-Bold.otf"),
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc",
    "C:/Windows/Fonts/msyhbd.ttc",
    _fc_match("Noto Sans CJK SC:bold", "Noto Sans SC:bold"),
], "粗体")

F_REG = _pick_font([
    str(BASE / "assets/fonts/NotoSansSC-Regular.otf"),
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "C:/Windows/Fonts/msyh.ttc",
    _fc_match("Noto Sans CJK SC", "Noto Sans SC"),
], "常规")

_font_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}


def F(path: str, size: int) -> ImageFont.FreeTypeFont:
    key = (path, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(path, size)
    return _font_cache[key]


def text(d, xy, s, size, fill=INK, bold=False, anchor="ls"):
    """在 (x, y) 基线处绘制文字, anchor 默认左对齐 + 基线对齐"""
    d.text(xy, s, font=F(F_BOLD if bold else F_REG, size), fill=fill, anchor=anchor)


def rule(d, y, x1=M, x2=W - M, width=2, fill=LIGHT):
    d.line([(x1, y), (x2, y)], fill=fill, width=width)


def wrap(s: str, size: int, max_w: int, bold: bool = False) -> list[str]:
    """按像素宽度逐字折行, 中文没有空格可断, 只能一个字一个字量"""
    if not s:
        return []
    f = F(F_BOLD if bold else F_REG, size)
    lines, cur = [], ""
    for ch in s:
        if f.getlength(cur + ch) <= max_w or not cur:
            cur += ch
        else:
            lines.append(cur)
            cur = ch
    if cur:
        lines.append(cur)
    return lines


def fit_title(s: str, max_w: int, max_lines: int = 2) -> tuple[int, list[str]]:
    """在不超过 max_lines 行的前提下取最大字号, 保证长书名不会溢出到猫身上"""
    last = ([s], 24)
    for size in (42, 38, 34, 30, 26):
        ls = wrap(s, size, max_w, bold=True)
        if len(ls) <= max_lines:
            return size, ls
        last = (ls, size)
    return last[1], last[0][:max_lines]


# ---------- 天气数据 ----------
WEATHER_TXT = {
    0: "晴", 1: "少云", 2: "多云", 3: "阴",
    45: "雾", 48: "雾凇",
    51: "小毛雨", 53: "毛毛雨", 55: "浓毛雨",
    61: "小雨", 63: "中雨", 65: "大雨",
    66: "冻雨", 67: "强冻雨",
    71: "小雪", 73: "中雪", 75: "大雪", 77: "霰",
    80: "阵雨", 81: "强阵雨", 82: "暴雨",
    85: "阵雪", 86: "强阵雪",
    95: "雷阵雨", 96: "雷雨冰雹", 99: "强雷雨",
}
WEEKDAY = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


def fetch_weather() -> dict:
    """Open-Meteo 免费接口, 无需 API Key。平湖独山港坐标"""
    url = (
        "https://api.open-meteo.com/v1/forecast"
        "?latitude=30.68&longitude=121.02"
        "&current=temperature_2m,relative_humidity_2m,weather_code"
        "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        "&timezone=Asia%2FShanghai&forecast_days=6"
    )
    try:
        with urllib.request.urlopen(url, timeout=8) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        print(f"[warn] 天气获取失败: {e}")
        return {}


# ---------- 天气图标 ----------
def _bez(p0, p1, p2, p3, n=26):
    """三次贝塞尔采样点, 用来画自然的尾巴曲线 (Pillow 没有曲线原语)"""
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        pts.append((
            u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1],
        ))
    return pts


def _cloud(d, cx, cy, s, fill=INK, lw=4):
    """云: 实心剪影。隆起要够高、底座要够窄, 否则看着像一块砖"""
    d.rounded_rectangle([cx - s * 0.78, cy + s * 0.08, cx + s * 0.78, cy + s * 0.42],
                        radius=int(s * 0.16), fill=fill)
    d.ellipse([cx - s * 0.80, cy - s * 0.28, cx - s * 0.12, cy + s * 0.32], fill=fill)
    d.ellipse([cx - s * 0.34, cy - s * 0.62, cx + s * 0.34, cy + s * 0.24], fill=fill)
    d.ellipse([cx + s * 0.06, cy - s * 0.22, cx + s * 0.74, cy + s * 0.34], fill=fill)


def draw_weather_icon(d, cx: int, cy: int, s: int, code: int | None):
    """s = 图标半径基准。E Ink 上图块比线条更醒目, 云用实心"""
    lw = max(3, s // 10)
    if code is None:
        return

    if code == -1:
        # 月亮: 两个圆做差集, 画成弯月
        d.ellipse([cx - s * 0.62, cy - s * 0.62, cx + s * 0.52, cy + s * 0.52], fill=INK)
        d.ellipse([cx - s * 0.20, cy - s * 0.78, cx + s * 0.76, cy + s * 0.30], fill=255)
        return

    if code in (0, 1):
        # 太阳: 空心圆 + 八道射线
        r = s * 0.40
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK, width=lw, fill=255)
        for i in range(8):
            a = math.pi * i / 4
            d.line([(cx + math.cos(a) * s * 0.58, cy + math.sin(a) * s * 0.58),
                    (cx + math.cos(a) * s * 0.94, cy + math.sin(a) * s * 0.94)],
                   fill=INK, width=lw)
        return

    if code in (45, 48):
        # 雾: 三条粗细不一的横线
        for i, wd in enumerate((1.0, 0.86, 0.62)):
            y = cy - s * 0.22 + i * s * 0.26
            d.line([(cx - s * wd, y), (cx + s * wd, y)], fill=INK, width=max(3, lw + 1))
        return

    # 云系: 多云偏浅, 阴与降水偏深
    _cloud(d, cx, cy - s * 0.12, s, fill=115 if code == 2 else INK)

    if code in (61, 63, 65, 51, 53, 55, 66, 67, 80, 81, 82):
        # 雨: 三道斜线
        for i, dx in enumerate((-0.42, 0.0, 0.42)):
            x = cx + s * dx
            d.line([(x + s * 0.08, cy + s * 0.56), (x - s * 0.04, cy + s * 0.86)],
                   fill=INK, width=max(3, lw))
    elif code in (71, 73, 75, 77, 85, 86):
        # 雪: 三个实心小方点
        for dx in (-0.42, 0.0, 0.42):
            x = cx + s * dx
            d.ellipse([x - s * 0.07, cy + s * 0.58, x + s * 0.07, cy + s * 0.72], fill=INK)
    elif code in (95, 96, 99):
        # 雷: 折线闪电
        d.polygon([(cx + s * 0.10, cy + s * 0.44), (cx - s * 0.16, cy + s * 0.78),
                   (cx + s * 0.02, cy + s * 0.78), (cx - s * 0.10, cy + s * 1.02),
                   (cx + s * 0.26, cy + s * 0.66), (cx + s * 0.06, cy + s * 0.66)], fill=INK)


# ---------- 奶油猫 ----------
def _face(d, hx, hy, hr, lw, eyes="open"):
    """奶油猫的圆脸: 耳朵先画让头发盖住根部, 豆豆眼 + 小腮红"""
    # 耳朵
    d.polygon([(hx - hr * 0.80, hy - hr * 0.44), (hx - hr * 0.94, hy - hr * 1.30),
               (hx - hr * 0.10, hy - hr * 0.94)], fill=255, outline=INK, width=lw)
    d.polygon([(hx + hr * 0.12, hy - hr * 0.94), (hx + hr * 0.96, hy - hr * 1.22),
               (hx + hr * 0.80, hy - hr * 0.36)], fill=255, outline=INK, width=lw)
    # 脸
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=255, outline=INK, width=lw)
    # 腮红
    for sx in (-0.62, 0.62):
        d.ellipse([hx + hr * sx - hr * 0.17, hy + hr * 0.14,
                   hx + hr * sx + hr * 0.17, hy + hr * 0.36], fill=BLUSH)
    # 眼睛
    if eyes in ("closed", "happy"):
        for ex in (-0.38, 0.38):
            d.arc([hx + hr * ex - hr * 0.16, hy - hr * 0.22,
                   hx + hr * ex + hr * 0.16, hy + hr * 0.04],
                  200, 340, fill=INK, width=lw)
    else:
        for ex in (-0.38, 0.38):
            d.ellipse([hx + hr * ex - hr * 0.14, hy - hr * 0.24,
                       hx + hr * ex + hr * 0.14, hy + hr * 0.04], fill=INK)
    # 鼻子
    d.polygon([(hx - hr * 0.07, hy + hr * 0.20), (hx + hr * 0.07, hy + hr * 0.20),
               (hx, hy + hr * 0.31)], fill=INK)
    # 胡须
    for k in (-1, 1):
        for dy in (0.15, 0.27):
            d.line([(hx + k * hr * 0.52, hy + hr * dy),
                    (hx + k * hr * 1.30, hy + hr * (dy - 0.06))],
                   fill=INK, width=max(2, lw // 2))


def draw_cat(d: ImageDraw.ImageDraw, cx: int, cy: int, s: int, mood: str = "curl"):
    """
    奶油猫。s = 身体半宽。
    mood: stretch(晴·四肢舒展) / arch(阴·伸懒腰) / curl(雨·蜷缩) / sleep(夜)

    画法要点:
      - 头画在身体之后, 靠白色填充压住身体轮廓, 视觉上才是"头在前面"
      - 尾巴一律从身体边缘起笔再用贝塞尔连出去, 否则会变成一根漂在空中的线
      - 奶油猫的脸要大, 头身比接近 1:2 才显憨
    """
    lw = max(4, s // 19)
    hr = s * 0.50

    if mood in ("curl", "sleep"):
        d.ellipse([cx - s * 0.94, cy - s * 0.46, cx + s * 0.80, cy + s * 0.46],
                  fill=255, outline=INK, width=lw)
        _face(d, cx + s * 0.52, cy - s * 0.18, hr, lw, eyes="closed")
        d.line(_bez((cx - s * 0.94, cy + s * 0.32), (cx - s * 1.16, cy + s * 0.54),
                    (cx - s * 0.78, cy + s * 0.62), (cx - s * 0.48, cy + s * 0.44)),
               fill=INK, width=lw, joint="curve")
        return

    if mood == "stretch":
        d.ellipse([cx - s * 0.84, cy - s * 0.18, cx + s * 0.78, cy + s * 0.38],
                  fill=255, outline=INK, width=lw)
        _face(d, cx - s * 0.70, cy - s * 0.46, hr, lw, eyes="happy")
        for dy in (0.14, 0.30):
            d.line([(cx - s * 0.84, cy + s * dy), (cx - s * 1.16, cy + s * (dy + 0.10))],
                   fill=INK, width=lw)
        d.line(_bez((cx + s * 0.66, cy + s * 0.10), (cx + s * 0.98, cy + s * 0.02),
                    (cx + s * 1.22, cy + s * 0.20), (cx + s * 1.36, cy + s * 0.44)),
               fill=INK, width=lw, joint="curve")
        return

    # arch: 伸懒腰 —— 前身压低, 屁股翘起, 尾巴竖在天上
    d.ellipse([cx - s * 0.66, cy - s * 0.40, cx + s * 0.62, cy + s * 0.36],
              fill=255, outline=INK, width=lw)
    _face(d, cx - s * 0.74, cy - s * 0.04, hr * 0.94, lw, eyes="closed")
    d.line([(cx - s * 0.92, cy + s * 0.34), (cx - s * 1.34, cy + s * 0.48)],
           fill=INK, width=lw)
    d.line(_bez((cx + s * 0.58, cy + s * 0.06), (cx + s * 0.98, cy - s * 0.40),
                (cx + s * 0.88, cy - s * 0.78), (cx + s * 0.54, cy - s * 0.88)),
           fill=INK, width=lw, joint="curve")


def weather_mood(code: int | None) -> tuple[str, str]:
    """天气 -> 猫咪姿态 + 问候语"""
    if code in (0, 1):
        return "stretch", "天晴, 事也顺"
    if code in (2, 3, 45, 48):
        return "arch", "不紧不慢, 正合适"
    if code in (95, 96, 99):
        return "curl", "打雷了, 屋里待着"
    return "curl", "外面在下雨, 稳着来"


# ---------- 主渲染 ----------
def render(now: datetime | None = None) -> Path:
    now = now or datetime.now()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(img)

    wx = fetch_weather()
    cur = wx.get("current", {})
    daily = wx.get("daily", {})
    code = cur.get("weather_code")
    code = int(code) if code is not None else None

    # ===== 顶部: 时间 =====
    text(d, (M, 200), now.strftime("%H:%M"), 168, bold=True)

    # 天气: 图标 + 大字号温度 + 文字
    draw_weather_icon(d, cx=752, cy=146, s=40, code=code)
    if cur:
        text(d, (W - M, 182), f"{cur.get('temperature_2m', '--')}°", 70, bold=True, anchor="rs")
        text(d, (W - M, 228), WEATHER_TXT.get(code, ""), 32, GRAY, anchor="rs")

    # 日期行
    text(d, (M, 258), f"{now.month}月{now.day}日  {WEEKDAY[now.weekday()]}", 46, bold=True)
    week = now.isocalendar()[1]
    doy = now.timetuple().tm_yday
    text(d, (M, 300), f"{now.year} 年 · 第 {week} 周 · 第 {doy} 天", 27, GRAY)
    if cur:
        text(d, (W - M, 300), f"湿度 {cur.get('relative_humidity_2m', '--')}%", 27, GRAY, anchor="rs")

    rule(d, 332, width=3, fill=INK)

    # ===== 主体: 大猫 + 在读 =====
    try:
        sched = json.loads(DATA.read_text(encoding="utf-8"))
    except Exception:
        sched = {}
    rd = dict(sched.get("_reading", {})) if isinstance(sched, dict) else {}
    # Kindle 端上报的实时数据优先 (由 kindle/report_progress.sh 写入)
    reading_file = BASE / "data" / "reading.json"
    if reading_file.exists():
        try:
            rd.update(json.loads(reading_file.read_text(encoding="utf-8")))
        except Exception as e:
            print(f"[warn] reading.json 解析失败: {e}")

    text(d, (M, 384), "在读", 36, bold=True)
    text(d, (W - M, 384), "封面与进度来自 Kindle 本地", 24, LIGHT, anchor="rs")

    # ===== 猫: 版面主角, 居中横向大图 =====
    # 位图缺失时退回矢量简笔画, 保证脚本不会挂
    ART_H = 430
    art_y = 406
    mood = pick_cat_mood(now, code)
    art = CAT_ARTS.get(mood)
    if art and art.exists():
        pic = Image.open(art)
        if pic.height != ART_H:      # 换一张比例的图也不会变形
            pic = pic.resize((round(pic.width * ART_H / pic.height), ART_H), Image.LANCZOS)
        img.paste(pic, ((W - pic.width) // 2, art_y))
    else:
        print(f"[warn] 缺少 {mood} 姿态的插画, 用矢量简笔画兜底")
        draw_cat(d, cx=W // 2, cy=art_y + 300, s=150, mood=_VEC_FALLBACK[mood])

    rule(d, 886)

    # ===== 在读: 书名 + 进度, 横排铺满 =====
    tsize, tlines = fit_title(rd.get("title", "尚未读取到在读图书"), W - 2 * M - 200, 1)
    pct = int(rd.get("progress", 0))
    bar_h = 26

    y = 934
    text(d, (M, y), tlines[0], tsize, bold=True)
    text(d, (W - M, y), f"{pct}%", 68, bold=True, anchor="rs")

    meta = rd.get("meta", "")
    if meta:
        text(d, (M, y + 40), meta, 24, GRAY)

    bar_y = y + 76
    d.rectangle([M, bar_y, W - M, bar_y + bar_h], outline=INK, width=2)
    filled = int((W - 2 * M - 8) * pct / 100)
    if filled > 0:
        d.rectangle([M + 4, bar_y + 4, M + 4 + filled, bar_y + bar_h - 4], fill=INK)

    status = rd.get("status", "")
    if status:
        text(d, (M, bar_y + bar_h + 40), status, 23, GRAY)

    # ===== 未来 6 天 =====
    if daily.get("time"):
        rule(d, 1128, fill=LIGHT)
        text(d, (M, 1180), "未来 6 天", 34, bold=True)
        col_w = (W - 2 * M) // 6
        for i in range(min(6, len(daily["time"]))):
            cd = datetime.strptime(daily["time"][i], "%Y-%m-%d")
            colx = M + col_w * i
            label = "今天" if i == 0 else WEEKDAY[cd.weekday()]
            text(d, (colx, 1236), label, 26, GRAY)
            dcode = int(daily["weather_code"][i])
            draw_weather_icon(d, cx=colx + 19, cy=1288, s=19, code=dcode)
            text(d, (colx + 48, 1298), f"{round(daily['temperature_2m_max'][i])}°", 34, bold=True)
            text(d, (colx, 1338), WEATHER_TXT.get(dcode, "-"), 24, GRAY)

    # ===== 底部: 一句问候 =====
    if 22 <= now.hour or now.hour < 7:
        greet = "该休息了, 明天再说"
    else:
        greet = weather_mood(code)[1]
    text(d, (M, 1396), greet, 34, bold=True)
    text(d, (W - M, 1394), "每 30 分钟自动刷新", 22, LIGHT, anchor="rs")

    img.save(OUT)
    print(f"已生成: {OUT}  ({img.size[0]}x{img.size[1]})  天气码={code}")
    return OUT


if __name__ == "__main__":
    render()
