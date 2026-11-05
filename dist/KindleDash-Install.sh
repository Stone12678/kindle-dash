#!/bin/sh
# Name: Kindle 看板 安装
# Author: Stone

# ============================================================
# Kindle 看板 —— 无线安装（scriptlet）
#
# 用法：把这个文件放进 Kindle 的 documents 文件夹，
#       在书架上点开它，就会以 root 身份自动安装。
#
# 它做四件事：
#   1. 从 GitHub Releases 下载程序包
#   2. 解压到 /mnt/us/kindle-dash
#   3. 探测 fbink 等依赖
#   4. 在 documents 里生成「启动 / 退出 / 自检」三个小书
#
# 只写 /mnt/us 用户分区，不碰系统分区。
# ============================================================

# 程序包和本脚本放在同一台服务器上（GitHub Pages），
# 只要能下到本脚本，就一定能下到程序包。
# jsDelivr 在 Kindle 的网络里会被 reset，别再用。
PKG_URL="https://stone12678.github.io/kindle-dash/kindle-dash.tar.gz"
PKG2_URL="https://raw.githubusercontent.com/Stone12678/kindle-dash/main/dist/kindle-dash.tar.gz"

DEST="/mnt/us/kindle-dash"
DOCS="/mnt/us/documents"
LOG="$DEST/install.log"
TMP="/tmp/kindle-dash.tar.gz"

mkdir -p "$DEST" "$DOCS" 2>/dev/null
: > "$LOG" 2>/dev/null

# stdout 会被 SH_Integration 转给 fbink 显示在屏幕上，
# 同时留一份到文件，屏幕看不全的时候还能回来看
say() {
    echo "$*" >> "$LOG" 2>/dev/null
    echo "$*"
}

say "== Kindle 看板 安装 =="
say ""

# ---------- 1. 权限 ----------
say "uid: $(id -u 2>/dev/null) / $(id 2>/dev/null | cut -d' ' -f1)"
if [ "$(id -u 2>/dev/null)" != "0" ]; then
    say "[!] 不是 root，先打开 SpiderCat 那本书"
    say "    再回来点这本"
    exit 1
fi

# ---------- 2. 下载工具 ----------
DL=""
if command -v curl >/dev/null 2>&1; then
    DL="curl"
elif command -v wget >/dev/null 2>&1; then
    DL="wget"
else
    say "[!] 既没有 curl 也没有 wget，没法下载"
    exit 1
fi
say "[有] $DL"

get() {
    # $1 = url  $2 = 输出文件
    if [ "$DL" = "curl" ]; then
        curl -sfL --max-time 150 --retry 2 --retry-delay 2 -o "$2" "$1"
    else
        wget -q -T 150 -O "$2" "$1"
    fi
}

# ---------- 3. 下载程序包 ----------
say ""
say "下载程序包…"
OK=0
for u in "$PKG_URL" "$PKG2_URL"; do
    [ -z "$u" ] && continue
    if get "$u" "$TMP"; then
        # 校验 gzip 魔数 1f 8b，防止把 HTML 错误页当程序包
        if [ "$(head -c 2 "$TMP" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "1f8b" ]; then
            OK=1
            say "[好] 已下载 $(wc -c < "$TMP" 2>/dev/null) 字节"
            break
        fi
        say "[!] 内容不是压缩包"
    else
        say "[!] 下载失败"
    fi
done

if [ "$OK" != "1" ]; then
    say ""
    say "全部地址都失败，检查 Wi-Fi"
    exit 1
fi

# ---------- 4. 解压 ----------
say "解压…"
rm -rf "$DEST/kindle" "$DEST/extensions" 2>/dev/null
if ! tar xzf "$TMP" -C "$DEST" 2>>"$LOG"; then
    say "[!] 解压失败，见 install.log"
    exit 1
fi
rm -f "$TMP"
chmod +x "$DEST"/kindle/*.sh 2>/dev/null
say "[好] 解压到 $DEST"

# ---------- 5. 依赖探测 ----------
say ""
say "检查依赖…"

# fbink：SpiderCat 自带，装在 libkh 里，通常不在 PATH 上
FB=""
for c in "$(command -v fbink 2>/dev/null)" \
         /mnt/us/libkh/bin/fbink \
         /var/local/kmc/libkh/bin/fbink \
         /mnt/us/koreader/fbink \
         /mnt/us/extensions/fbink/bin/fbink; do
    if [ -n "$c" ] && [ -x "$c" ]; then FB="$c"; break; fi
done
if [ -z "$FB" ]; then
    FB="$(find /mnt/us /var/local -maxdepth 6 -name fbink -type f 2>/dev/null | head -n 1)"
fi
if [ -n "$FB" ]; then
    echo "$FB" > "$DEST/.fbink"
    say "[好] fbink: $FB"
else
    say "[缺] fbink —— 搜索框里试 ;kpm install fbink"
fi

# curl 也要记下来，dash.sh 拉图用
command -v curl >/dev/null 2>&1 && say "[好] curl: $(command -v curl)"

# ---------- 6. 生成三个控制用 scriptlet ----------
say ""
say "生成控制菜单…"

mk_scriptlet() {
    # $1 文件名  $2 显示名  $3 实际命令
    cat > "$DOCS/$1" <<EOF
#!/bin/sh
# Name: $2
# Author: Stone
exec $3
EOF
}

mk_scriptlet "Kindle 看板 启动.sh" "看板 - 启动" "sh $DEST/kindle/dash.sh on"
mk_scriptlet "Kindle 看板 退出.sh" "看板 - 退出" "sh $DEST/kindle/dash.sh off"
mk_scriptlet "Kindle 看板 自检.sh" "看板 - 自检" "sh $DEST/kindle/dash.sh test"

say "[好] 已在书架上生成 3 本小书"

# ---------- 7. 收尾 ----------
say ""
say "安装完成。"
say "回书架（点左上角返回），"
say "找『看板 - 启动』点开。"
