#!/usr/bin/env bash
# Kindle 端脚本的本地测试
#
#   bash tests/test_kindle.sh
#
# 为什么要有这个：这些脚本最终要在 Kindle 上跑，而那里没法调试。
# 一旦 fetch 逻辑写错，表现不是报错，而是屏幕一片白、日志里什么都看不出来。
# 所以在电脑上先用桩程序（fbink / curl / framework / sleep）把每条分支跑一遍，
# 确认 .active 标志位、PNG 魔数校验、失败保留旧图这些行为都对。
#
# 测试不会碰真实的 /mnt/us、/etc，全部在临时目录里进行。

set -u

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
# 刻意用 /tmp 下的固定位置，而不是 mktemp 的返回值：
# Git Bash 里 mktemp 可能回一个 C://Users//... 的 Windows 路径，
# 反斜杠进到 sh 的重定向里会被当转义符，整条链路都跑不通。
TMP="/tmp/kindle-dash-test.$$"
rm -rf "$TMP" 2>/dev/null
mkdir -p "$TMP"
SB="$TMP/sandbox"          # 沙箱：假装是 Kindle 的 /mnt/us/kindle-dash
STUB="$TMP/stub"           # 桩程序住的地方

PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ---------------- 断言 ----------------
ok()   { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1（期望 $3，实际 $2）"; fi; }
nz()   { if [ -n "$(cat "$2" 2>/dev/null)" ]; then ok "$1"; else bad "$1（$2 为空）"; fi; }
z()    { if [ ! -s "$2" ]; then ok "$1"; else bad "$1（$2 不该有内容）"; fi; }
isfile() { if [ -f "$2" ]; then ok "$1"; else bad "$1（$2 不存在）"; fi; }
nofile() { if [ ! -f "$2" ]; then ok "$1"; else bad "$1（$2 不该存在）"; fi; }
png()  { # 文件头必须是 PNG
    local m
    m="$(head -c 8 "$2" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    eq "$1" "$m" "89504e470d0a1a0a"
}

# ---------------- 搭环境 ----------------
setup_stubs() {
    mkdir -p "$STUB"
    # fbink：记录每次调用，-i 时假装回报尺寸
    cat > "$STUB/fbink" <<'EOF'
#!/bin/sh
echo "fbink $*" >> "$STUB_DIR/fbink.log"
case " $* " in *" -i "*) echo "dimensions: 1072x1448";; esac
exit 0
EOF
    # curl：行为由 $STUB_DIR/curl_mode 决定，方便模拟断网和错误页
    cat > "$STUB/curl" <<'EOF'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *)  url="$1"; shift ;;
    esac
done
echo "$url" >> "$STUB_DIR/curl.log"
mode=$(cat "$STUB_DIR/curl_mode" 2>/dev/null || echo good)
case "$mode" in
    good) cp "$STUB_DIR/good.png" "$out" ;;
    html) printf '<!DOCTYPE html><html><body>404: Not Found</body></html>\n' > "$out" ;;
    fail) exit 22 ;;
    primary_fail)
        case "$url" in
            *primary*) exit 22 ;;
            *) cp "$STUB_DIR/good.png" "$out" ;;
        esac ;;
esac
exit 0
EOF
    printf '#!/bin/sh\necho "framework $*" >> "$STUB_DIR/framework.log"\n' > "$STUB/framework"
    printf '#!/bin/sh\nexit 0\n' > "$STUB/lipc-set-prop"
    printf '#!/bin/sh\nexit 0\n' > "$STUB/mntroot"
    printf '#!/bin/sh\nexit 0\n' > "$STUB/killall"
    printf '#!/bin/sh\nexit 0\n' > "$STUB/crond"
    # sleep 也桩掉：dash.sh 的 on 分支里有 sleep 2，不然每个用例都多等 2 秒
    printf '#!/bin/sh\nexit 0\n' > "$STUB/sleep"
    chmod +x "$STUB"/*

    PNG_OUT="$STUB/good.png" python -c "import os; from PIL import Image; Image.new('L',(1072,1448),255).save(os.environ['PNG_OUT'])"
}

# 每次用例前重置沙箱，用指定的 URL 生成 config.sh
reset_sandbox() {
    local url="${1:-https://example.com/render/dashboard.png}"
    local fallback="${2:-}"
    local bust="${3:-1}"
    rm -rf "$SB"
    mkdir -p "$SB/kindle" "$SB/downloads" "$SB/kual" "$SB/etc"
    cp "$PROJ/kindle/dash.sh"   "$SB/kindle/dash.sh"
    cp "$PROJ/kindle/install.sh" "$SB/kindle/install.sh"
    mkdir -p "$SB/extensions/kindle-dash"
    cp "$PROJ/extensions/kindle-dash/"* "$SB/extensions/kindle-dash/" 2>/dev/null

    cat > "$SB/kindle/config.sh" <<EOF
DASH_URL="$url"
DASH_URL_FALLBACK="$fallback"
DASH_CACHE_BUST="$bust"
DASH_DIR="$SB/dash"
DASH_IMG="\$DASH_DIR/current.png"
DASH_LOG="\$DASH_DIR/dash.log"
KUAL_EXT_DIR="$SB/kual"
SCREEN_W=1072
SCREEN_H=1448
LOG_MAX_LINES=200
FRAMEWORK_INIT="$STUB/framework"
CRON_FILE="$SB/etc/crontab"
EOF
    rm -f "$STUB"/*.log
    echo good > "$STUB/curl_mode"
}

# 调 dash.sh，返回退出码
run_dash() {
    ( cd "$SB" && STUB_DIR="$STUB" PATH="$STUB:$PATH" sh "$SB/kindle/dash.sh" "$@" ) >"$TMP/out" 2>&1
    echo $?
}
fbcalls() {
    if [ -f "$STUB/fbink.log" ]; then wc -l < "$STUB/fbink.log" | tr -d ' '; else echo 0; fi
}

# ================================================================
echo
echo "== 0. 行尾符必须是 LF =="
# 这条放在最前面：CRLF 的 shell 脚本拷到 Kindle 上，/bin/sh 会报
# "/bin/sh: not found" 或莫名其妙的语法错误，人根本想不到是行尾的问题。
# Windows 上的编辑器和 Git 都可能悄悄改成 CRLF，所以每次都查一遍。
# 用 python 读字节来判断：shell 里对 \r 的处理各版本不一致，
# 有时候明明有 CR 却匹配不到，这条检查就白做了。
bad_eol=$(PROJ_DIR="$PROJ" python -c '
import os, pathlib
root = pathlib.Path(os.environ["PROJ_DIR"])
hits = []
for sub in ("kindle", "tests"):
    for f in sorted((root / sub).glob("*.sh")):
        if b"\r\n" in f.read_bytes():
            hits.append(f.name)
print(" ".join(hits))
' 2>/dev/null)
if [ -z "$bad_eol" ]; then
    ok "shell 脚本均为 LF 行尾"
else
    bad "这些文件含 CRLF，拷到 Kindle 会跑不起来：$bad_eol"
fi

echo
echo "== 1. 没开看板模式时，定时任务不许抢屏 =="
setup_stubs; reset_sandbox
code=$(run_dash update)
eq "update 在非看板模式下返回 0（静默退出）" "$code" "0"
eq "没有调用 fbink" "$(fbcalls)" "0"
nofile "没有生成 .active" "$SB/dash/.active"

echo
echo "== 2. 开启看板：停系统界面 + 下载 + 刷新 =="
code=$(run_dash on)
eq "on 返回 0" "$code" "0"
nz "停掉了原生系统界面" "$STUB/framework.log"
isfile "生成了 .active 标志" "$SB/dash/.active"
isfile "图片已落盘" "$SB/dash/current.png"
png "落盘的文件是真 PNG" "$SB/dash/current.png"
eq "调用了一次 fbink" "$(fbcalls)" "1"
nz "fbink 用了全刷参数 -f" "$STUB/fbink.log"
if grep -q 'halign=CENTER' "$STUB/fbink.log"; then ok "按居中方式铺满屏幕"; else bad "缺少 halign 参数"; fi

echo
echo "== 3. 看板模式下的定时刷新 =="
echo good > "$STUB/curl_mode"
code=$(run_dash update)
eq "update 返回 0" "$code" "0"
eq "又刷了一次屏" "$(fbcalls)" "2"

echo
echo "== 4. 断网时不能把屏幕刷白 =="
echo fail > "$STUB/curl_mode"
cp "$SB/dash/current.png" "$TMP/keep.png"
code=$(run_dash update)
eq "下载失败时返回非 0" "$code" "1"
eq "没有调用 fbink（不刷白屏）" "$(fbcalls)" "2"
if cmp -s "$SB/dash/current.png" "$TMP/keep.png"; then
    ok "旧图被保留下来"
else
    bad "旧图被覆盖或删除了"
fi
nofile "没留下 .tmp 残留文件" "$SB/dash/current.png.tmp"

echo
echo "== 5. 拿到 HTML 错误页时要识别出来 =="
echo html > "$STUB/curl_mode"
code=$(run_dash update)
eq "HTML 不当作图片，返回非 0" "$code" "1"
eq "依然没有刷屏" "$(fbcalls)" "2"
png "current.png 还是上一张完好的 PNG" "$SB/dash/current.png"
if grep -q "内容不是 PNG" "$SB/dash/dash.log"; then ok "日志里说清了原因"; else bad "日志没记录原因"; fi

echo
echo "== 6. 主地址挂了要自动换备用地址 =="
reset_sandbox "https://primary.example.com/d.png" "https://backup.example.com/d.png"
echo primary_fail > "$STUB/curl_mode"
code=$(run_dash on)
eq "切到备用地址后成功" "$code" "0"
if [ "$(grep -c 'example.com' "$STUB/curl.log")" = "2" ]; then
    ok "先试了主地址、再试备用地址"
else
    bad "没有依次尝试两个地址（curl 调用 $(grep -c 'example.com' "$STUB/curl.log") 次）"
fi
png "最终拿到的是有效 PNG" "$SB/dash/current.png"

echo
echo "== 7. 退出看板要恢复原生界面 =="
code=$(run_dash off)
eq "off 返回 0" "$code" "0"
nofile ".active 已清除" "$SB/dash/.active"
if grep -q "framework start" "$STUB/framework.log"; then ok "重新启动了系统界面"; else bad "没有恢复系统界面"; fi

echo
echo "== 8. 环境自检命令 =="
reset_sandbox
out=$( cd "$SB" && STUB_DIR="$STUB" PATH="$STUB:$PATH" sh "$SB/kindle/dash.sh" test 2>&1 )
if echo "$out" | grep -q "环境检查"; then ok "test 跑起来了"; else bad "test 没有输出检查结果"; fi
if echo "$out" | grep -q "fbink:"; then ok "报告了 fbink 路径"; else bad "没有报告 fbink"; fi
if echo "$out" | grep -q "1072x1448"; then ok "报告了图片尺寸"; else bad "没有报告尺寸"; fi

echo
echo "== 9. 安装脚本：URL 还是占位符时要拦住 =="
reset_sandbox "https://raw.githubusercontent.com/USER/REPO/render/dashboard.png" ""
code=$( cd "$SB" && STUB_DIR="$STUB" PATH="$STUB:$PATH" sh "$SB/kindle/install.sh" >"$TMP/inst1" 2>&1; echo $? )
eq "占位符 URL 直接拒绝安装" "$code" "1"
if grep -q "占位符" "$TMP/inst1"; then ok "给出了明确提示"; else bad "提示不清楚"; fi

echo
echo "== 10. 安装脚本：正常安装 =="
reset_sandbox "https://example.com/d.png"
code=$( cd "$SB" && STUB_DIR="$STUB" PATH="$STUB:$PATH" sh "$SB/kindle/install.sh" >"$TMP/inst2" 2>&1; echo $? )
eq "安装成功" "$code" "0"
isfile "KUAL 菜单已就位" "$SB/kual/menu.json"
grep -q "dash.sh update" "$SB/etc/crontab" && ok "写了定时任务" || bad "没写定时任务"
eq "定时任务行数为 1" "$(grep -c 'dash.sh update' "$SB/etc/crontab")" "1"

# 再跑一次不能重复追加
code=$( cd "$SB" && STUB_DIR="$STUB" PATH="$STUB:$PATH" sh "$SB/kindle/install.sh" >"$TMP/inst3" 2>&1; echo $? )
eq "重复安装不报错" "$code" "0"
eq "定时任务没有重复追加" "$(grep -c 'dash.sh update' "$SB/etc/crontab")" "1"

echo
echo "== 11. 破 CDN 缓存的开关 =="
reset_sandbox "https://example.com/d.png" "" 1
run_dash on >/dev/null
if grep -q '?t=' "$STUB/curl.log"; then
    ok "开启后地址带上了时间戳，绕过 CDN 缓存"
else
    bad "开启开关但地址没有时间戳（$(head -1 "$STUB/curl.log")）"
fi

reset_sandbox "https://example.com/d.png" "" 0
run_dash on >/dev/null
if grep -q '?t=' "$STUB/curl.log"; then
    bad "关掉开关后不该再加时间戳"
else
    ok "关掉后恢复成原始地址"
fi

# 备用地址本身带查询参数时，要接 & 而不是再补一个 ?
reset_sandbox "https://example.com/d.png?raw=1" "" 1
run_dash on >/dev/null
if grep -q 'raw=1&t=' "$STUB/curl.log"; then
    ok "原地址已有参数时正确用 & 追加"
else
    bad "已有查询参数时拼接错了（$(head -1 "$STUB/curl.log")）"
fi

# ================================================================
echo
printf '通过 %d 项，失败 %d 项\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
