#!/bin/sh
# 一键安装（在 Kindle 上执行）
#
#   sh /mnt/us/kindle-dash/kindle/install.sh
#
# 会做三件事：装 KUAL 菜单、加 30 分钟定时任务、检查依赖。
# 装完记得先改 knile/config.sh 里的 DASH_URL，再用 KUAL 打开「Kindle 看板」。

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/config.sh"

echo "== Kindle 看板安装 =="
echo "项目目录：$ROOT"
echo

# ---------- 1. 依赖检查 ----------
MISS=0
if ! command -v fbink >/dev/null 2>&1; then
    echo "[缺] fbink —— 先用 KUAL 的 FBInk 扩展，或 KPM 装 FBInk"
    MISS=1
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "[缺] curl —— 越狱系统一般自带，没有就用 wget 版脚本"
    MISS=1
fi
[ "$MISS" = "1" ] && echo && echo "补齐依赖后再跑一次本脚本。" && exit 1

echo "[有] fbink: $(command -v fbink)"
echo "[有] curl : $(command -v curl)"

# ---------- 2. 配置检查 ----------
case "$DASH_URL" in
    *USER*|*REPO*)
        echo
        echo "[!] config.sh 里的 DASH_URL 还是占位符，请先改成你自己的仓库地址："
        echo "    $HERE/config.sh"
        exit 1
        ;;
esac
echo "[有] DASH_URL = $DASH_URL"

# ---------- 3. 装 KUAL 菜单 ----------
EXT="$KUAL_EXT_DIR"
mkdir -p "$EXT"
cp "$ROOT/extensions/kindle-dash/config.xml" "$EXT/" 2>/dev/null
cp "$ROOT/extensions/kindle-dash/menu.json"  "$EXT/" 2>/dev/null

# 如果项目没放在 /mnt/us/kindle-dash，菜单里的路径要跟着改
UB="$(echo "$ROOT" | sed 's/\/$//')"
if [ "$UB" != "/mnt/us/kindle-dash" ]; then
    echo "[!] 项目不在 /mnt/us/kindle-dash，正在修正菜单路径…"
    sed -i "s|/mnt/us/kindle-dash|$UB|g" "$EXT/menu.json"
fi
echo "[装] KUAL 菜单 -> $EXT"

# ---------- 4. 定时任务 ----------
LINE="*/30 * * * * $ROOT/kindle/dash.sh update"
if [ -f "$CRON_FILE" ] && grep -qF "$ROOT/kindle/dash.sh" "$CRON_FILE"; then
    echo "[有] 定时任务已存在，跳过"
else
    mntroot rw 2>/dev/null
    mkdir -p "$(dirname "$CRON_FILE")"
    echo "$LINE" >> "$CRON_FILE"
    mntroot ro 2>/dev/null
    killall crond 2>/dev/null
    /etc/init.d/cron restart 2>/dev/null || crond 2>/dev/null
    echo "[装] 每 30 分钟自动刷新（仅在看板模式下生效）"
fi

chmod +x "$HERE/dash.sh"

echo
echo "装好了。"
echo "接下来：打开 KUAL -> Kindle 看板 -> 环境自检，通过后再点「开启看板」。"
