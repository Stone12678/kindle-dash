# Kindle 端配置 —— 只需要改这一个文件
# 把这个文件拷到 Kindle 的 /mnt/us/kindle-dash/kindle/ 目录下

# 图片地址。仓库建好后确认这一行和你的实际仓库一致
DASH_URL="https://raw.githubusercontent.com/Stone12678/kindle-dash/render/dashboard.png"

# 备用地址。国内直连 raw.githubusercontent.com 有时会超时，
# 主地址失败后会依次尝试这里（填 Cloudflare Worker 反代或 Gitee 镜像，没有就留空）
DASH_URL_FALLBACK=""

# 在图片地址后面加时间戳（?t=1234567890）绕过 CDN 缓存
# raw.githubusercontent.com 走的是 CDN，同一个 URL 会被缓存几分钟；
# 关掉的话可能出现"云端已经更新了，设备还在显示上一张"。开着没有任何代价。
DASH_CACHE_BUST=1

# 图片落盘位置和日志
DASH_DIR="/mnt/us/kindle-dash"
DASH_IMG="$DASH_DIR/current.png"
DASH_LOG="$DASH_DIR/dash.log"

# 看板模式下多久换一次图（秒）。1800 = 30 分钟
# 云端每 30 分钟重新渲染一次，这里跟着对齐就行；调小只会更耗电，不会更及时
REFRESH_SEC=1800
KEEPER_PID="$DASH_DIR/.keeper.pid"

# KUAL 菜单装到哪里
KUAL_EXT_DIR="/mnt/us/extensions/kindle-dash"

# 屏幕分辨率。PW4 是 1072x1448，别的机型请对应改：
#   PW1/PW2 = 758x1024    PW3 = 1072x1448    PW5 = 1236x1648
#   Kindle 8/10 = 600x800  Kindle 11 = 1072x1448
SCREEN_W=1072
SCREEN_H=1448

# 日志超过这个行数就自动截断，防止塞满存储
LOG_MAX_LINES=200

# ---- 系统路径 ----
# 本来该写死在脚本里，但抽成变量有两个好处：
# 一是不同的固件版本路径有差异，出问题时改这里就行，不用翻脚本；
# 二是可以指到空壳桩程序上，在电脑上把整套流程跑一遍再碰真机。
FRAMEWORK_INIT="/etc/init.d/framework"    # 原生系统界面（看板模式下要停掉它）

# ---- fbink ----
# SpiderCat 越狱自带 fbink，但装在 libkh 目录下，不在 PATH 里，
# 所以不能只靠命令名去找。安装脚本会探测一次写进 .fbink 缓存，
# 这里优先读缓存，读不到再现场找一遍。
FBINK="${FBINK:-}"
if [ -z "$FBINK" ] && [ -f "$DASH_DIR/.fbink" ]; then
    FBINK="$(cat "$DASH_DIR/.fbink" 2>/dev/null)"
fi
if [ -z "$FBINK" ] || [ ! -x "$FBINK" ]; then
    FBINK=""
    for c in "$(command -v fbink 2>/dev/null)" \
             /mnt/us/libkh/bin/fbink \
             /var/local/kmc/libkh/bin/fbink \
             /mnt/us/koreader/fbink \
             /mnt/us/extensions/fbink/bin/fbink; do
        if [ -n "$c" ] && [ -x "$c" ]; then FBINK="$c"; break; fi
    done
fi
