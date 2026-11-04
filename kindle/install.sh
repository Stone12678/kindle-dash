#!/bin/sh
# 一键安装（在 Kindle 上执行，或从 KUAL 菜单点「① 安装 / 更新」）
#
#   sh /mnt/us/kindle-dash/kindle/install.sh
#
# 会做三件事：检查依赖、装 KUAL 菜单、给脚本加执行权限。
# 装完用 KUAL 打开「Kindle 看板」→「开启看板」。
#
# 注意：本脚本只动 /mnt/us 用户分区，不碰系统分区。
# 早期版本会 mntroot rw 往 /etc/crontab/root 写定时任务，现在改成
# dash.sh 自己维护刷新循环——系统分区挂成可写时断电有变砖风险，不值得。

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/config.sh"

LOG="$DASH_DIR/install.log"
mkdir -p "$DASH_DIR"

# 输出同时写进日志，因为从 KUAL 点进来时看不到终端
say() {
    echo "$*"
    echo "$*" >> "$LOG"
}

: > "$LOG"
say "== Kindle 看板安装 =="
say "项目目录：$ROOT"
say ""

# ---------- 1. 依赖检查 ----------
MISS=0
if [ -z "$FBINK" ]; then
    say "[缺] fbink —— 搜索框里试：;kpm install fbink"
    MISS=1
fi
if ! command -v curl >/dev/null 2>&1; then
    say "[缺] curl —— 越狱系统一般自带"
    MISS=1
fi
if [ "$MISS" = "1" ]; then
    say ""
    say "补齐依赖后再点一次安装。"
    exit 1
fi

say "[有] fbink: $FBINK"
say "[有] curl : $(command -v curl)"

# ---------- 2. 配置检查 ----------
case "$DASH_URL" in
    *USER*|*REPO*)
        say ""
        say "[!] config.sh 里的 DASH_URL 还是占位符，请先改成自己的仓库地址："
        say "    $HERE/config.sh"
        exit 1
        ;;
esac
say "[有] DASH_URL = $DASH_URL"

# ---------- 3. 装 KUAL 菜单 ----------
EXT="$KUAL_EXT_DIR"
mkdir -p "$EXT"
cp "$ROOT/extensions/kindle-dash/config.xml" "$EXT/" 2>/dev/null
cp "$ROOT/extensions/kindle-dash/menu.json"  "$EXT/" 2>/dev/null

# 如果项目没放在 /mnt/us/kindle-dash，菜单里的路径要跟着改
UB="$(echo "$ROOT" | sed 's/\/$//')"
if [ "$UB" != "/mnt/us/kindle-dash" ]; then
    say "[!] 项目不在 /mnt/us/kindle-dash，正在修正菜单路径…"
    sed -i "s|/mnt/us/kindle-dash|$UB|g" "$EXT/menu.json"
fi
say "[装] KUAL 菜单 -> $EXT"

# ---------- 4. 执行权限 ----------
# FAT32 上拷过来的文件没有 x 位，必须显式加，否则 KUAL 点了没反应
chmod +x "$HERE/dash.sh" 2>/dev/null
say "[装] 执行权限已设置"

# ---------- 5. 备份旧图，避免首次打开白屏 ----------
if [ -f "$ROOT/../dashboard.png" ]; then
    cp "$ROOT/../dashboard.png" "$DASH_IMG" 2>/dev/null
fi

say ""
say "装好了。"
say "接下来：KUAL -> Kindle 看板 -> 开启看板。"
say "屏幕变成看板就说明通了；没有变化就去看 $DASH_LOG"
