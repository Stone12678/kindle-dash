# Kindle 端配置 —— 只需要改这一个文件
# 把这个文件拷到 Kindle 的 /mnt/us/kindle-dash/kindle/ 目录下

# 图片地址。会按顺序试，第一个给出真 PNG 的就用，并记进 .lasturl
#
# 为什么要排这么多：国内到境外 CDN 很不稳定，实测 jsDelivr 被 RST、
# github.io 会挂住不返回。所以按"实测能通"的优先级排：
#   1. 局域网：电脑上跑 python -m http.server 8765，最稳，但电脑得开着
#   2. gh-proxy 镜像：GitHub 的反代，国内一般能过
#   3. 官方 raw：时通时不通
#   4. GitHub Pages：国内经常挂住，排最后
DASH_URL="http://192.168.31.110:8765/dashboard.png"

DASH_URL_FALLBACK="https://gh-proxy.com/https://raw.githubusercontent.com/Stone12678/kindle-dash/render/dashboard.png"

DASH_EXTRA_URLS="https://raw.githubusercontent.com/Stone12678/kindle-dash/render/dashboard.png https://stone12678.github.io/kindle-dash/dashboard.png"

# 连不上就赶紧换下一个，别把整个刷新周期耗在一个被墙的地址上
CONNECT_TIMEOUT=8
FETCH_TIMEOUT=30

# 每隔几秒看一眼电源键状态（按一下就退出看板）
POLL_SEC=3

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

# ---- 时钟 ----
# 云端图故意不画时间（GitHub 免费版的定时任务实测 4~7 小时才跑一次，
# 印在图上的时间会停住），改由设备自己往空白处叠一行时间，每分钟刷一次。
# 位置必须和 render.py 里留白的位置对齐，改版式时两边一起改。
CLOCK_ON=1                 # 设 0 关掉设备时钟
CLOCK_PX=140               # 矢量字体的像素高度
CLOCK_TOP=56               # 文字顶边 y
CLOCK_LEFT=56              # 文字左边 x
CLOCK_CLEAR="top=44,left=44,width=560,height=164"   # 每帧先刷白这块再写字
# 内置点阵字体的退路：-S 放大倍数，CLOCK_IBM_X/Y 是像素微调
CLOCK_SCALE=10
CLOCK_IBM_X=56
CLOCK_IBM_Y=48

# 时钟字体候选。Kindle 原生自带的 Caecilia 数字很好看，优先用它；
# 装了 KOReader 的话还能用它的 Noto。都不存在就退回内置点阵字。
CLOCK_FONTS="/usr/java/lib/fonts/Caecilia_LT_75_Bold.ttf
/usr/java/lib/fonts/Caecilia_LT_65_Medium.ttf
/usr/java/lib/fonts/Caecilia_LT_67_Cond_Medium.ttf
/mnt/us/koreader/fonts/noto/NotoSans-Bold.ttf
/mnt/us/koreader/fonts/noto/NotoSans-Regular.ttf
/mnt/us/system/fonts/STHeiti_Medium.ttf"

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
