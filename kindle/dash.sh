#!/bin/sh
# Kindle 看板控制脚本
#
#   dash.sh on      进入看板模式：停掉系统界面 + 拉图 + 全屏显示 + 启动刷新循环
#   dash.sh update  只拉图并刷新（手动用）
#   dash.sh off     退出看板模式，停刷新循环 + 恢复原生系统界面
#   dash.sh test    检查环境（fbink / curl / 网络 / 图片地址）
#   dash.sh loop    内部用：常驻刷新循环，由 on 启动、off 结束
#
# 放在 /mnt/us/kindle-dash/kindle/dash.sh，需与 config.sh 同目录
#
# 为什么用常驻循环而不是 cron：
#   1. kindle 的 crond 重启后不保证自己起来，看板会在某次重启后悄悄停更
#   2. 加 cron 要 mntroot rw 把根分区挂成可写，写到一半断电有变砖风险
#   循环只碰 /mnt/us 用户分区，生命周期跟看板模式完全一致，安全得多。

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/config.sh"

mkdir -p "$DASH_DIR"

log() {
    echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$DASH_LOG"
    # 日志防爆：超过上限就只留最后 100 行
    if [ "$(wc -l < "$DASH_LOG" 2>/dev/null || echo 0)" -gt "$LOG_MAX_LINES" ]; then
        tail -n 100 "$DASH_LOG" > "$DASH_LOG.tmp" && mv "$DASH_LOG.tmp" "$DASH_LOG"
    fi
}

# ---------- 下载 ----------
# 关键：校验 PNG 魔数。断网或地址写错时 curl 可能抓到一堆 HTML 错误页，
# 直接喂给 fbink 会让屏幕变成一块白板，而且看不出是哪里错了。
fetch() {
    for url in "$DASH_URL" "$DASH_URL_FALLBACK"; do
        [ -z "$url" ] && continue

        # 加时间戳破 CDN 缓存：raw.githubusercontent.com 对同一 URL 会缓存几分钟，
        # 不加的话可能云端早就更新了，设备还在反复拿同一张旧图。
        if [ "$DASH_CACHE_BUST" = "1" ]; then
            case "$url" in
                *\?*) real="$url&t=$(date +%s)" ;;
                *)    real="$url?t=$(date +%s)" ;;
            esac
        else
            real="$url"
        fi

        if curl -sfL --max-time 90 --retry 2 --retry-delay 3 -o "$DASH_IMG.tmp" "$real"; then
            if [ "$(head -c 8 "$DASH_IMG.tmp" | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a" ]; then
                mv "$DASH_IMG.tmp" "$DASH_IMG"
                log "下载成功 ${url%%\?*}"
                return 0
            fi
            log "内容不是 PNG，丢弃：$url"
        else
            log "下载失败：$url"
        fi
    done
    rm -f "$DASH_IMG.tmp"
    return 1
}

# ---------- 显示 ----------
# -f 走 GC16 全刷：每 30 分钟闪一下不碍事，换来的是不会有残影一层层叠上去。
# 想减少闪烁就把 -f 去掉，但记得每天至少全刷一次清残影。
show() {
    if [ ! -f "$DASH_IMG" ]; then
        log "没有可用图片，跳过刷新"
        return 1
    fi
    if [ -z "$FBINK" ]; then
        log "找不到 fbink，无法显示"
        return 1
    fi
    "$FBINK" -q -g "file=$DASH_IMG,halign=CENTER,valign=CENTER,w=$SCREEN_W,h=$SCREEN_H" -f
    log "已刷新屏幕"
}

# ---------- 系统界面开关 ----------
# 新固件（5.16+）把整个显示栈（lxinit/framework/pillow/blanket）收进了一个
# 叫 x 的 upstart 任务，停 framework 单个进程压不住它，屏保还会自己冒出来。
# 老固件没有 x，退回 init.d + 单独停 pillow/blanket。
stop_ui() {
    if initctl status x >/dev/null 2>&1; then
        initctl stop x >/dev/null 2>&1
        return 0
    fi
    [ -x "$FRAMEWORK_INIT" ] && "$FRAMEWORK_INIT" stop >/dev/null 2>&1
    initctl stop pillow  >/dev/null 2>&1
    initctl stop blanket >/dev/null 2>&1
    return 0
}

start_ui() {
    if initctl status x >/dev/null 2>&1; then
        initctl start x >/dev/null 2>&1
        return 0
    fi
    [ -x "$FRAMEWORK_INIT" ] && "$FRAMEWORK_INIT" start >/dev/null 2>&1
    return 0
}

# ---------- 刷新循环（进程管理） ----------
stop_keeper() {
    if [ -f "$KEEPER_PID" ]; then
        kill "$(cat "$KEEPER_PID")" 2>/dev/null
        rm -f "$KEEPER_PID"
    fi
    # 兜底：进程号文件丢了也要清干净，否则开一次看板就多一个后台循环在跑
    for p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
        if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "dash.sh loop"; then
            kill "$p" 2>/dev/null
        fi
    done
}

start_keeper() {
    stop_keeper
    nohup sh "$HERE/dash.sh" loop >/dev/null 2>&1 &
    echo "$!" > "$KEEPER_PID"
    log "刷新循环已启动，每 ${REFRESH_SEC} 秒一次"
}

# ---------- 环境检查 ----------
case "$1" in
    on)
        # 从书架上的 scriptlet 点「启动」时，这个进程是 framework 拉起来的，
        # 直接停系统界面会把它自己一起收走（内核 cgroup 层面）。
        # 所以这里只落标记、甩出一个脱离终端的进程，自己立刻返回，
        # 8 秒后那个进程再去停界面——那时 scriptlet 早就退干净了。
        touch "$DASH_DIR/.active"
        log "收到启动指令，8 秒后接管屏幕"
        setsid sh "$HERE/dash.sh" boot </dev/null >/dev/null 2>&1 &
        ;;

    boot)
        # 真正干活的分支。两个来源：上面 fork 出来的，或者开机时 upstart 拉起的。
        sleep 8
        [ -f "$DASH_DIR/.active" ] || exit 0
        lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1
        stop_ui
        sleep 3
        log "进入看板模式"
        if fetch; then show; fi
        start_keeper
        ;;

    peek)
        # 只画一屏，不动系统界面。第一次验证链路用：屏幕闪一下看板，
        # 几秒后会被状态栏重绘盖回去。这一步最安全，不会把自己搞掉。
        lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1
        if fetch; then
            show && echo "画好了。几秒后会被系统界面盖回，属正常。"
        else
            echo "拉图失败，看 $DASH_LOG"
            exit 1
        fi
        ;;

    loop)
        # 常驻循环。判断 .active 而不是单纯 while true：
        # 用户点「退出看板」后，最迟一个周期内自己退出，不会留孤儿进程。
        while [ -f "$DASH_DIR/.active" ]; do
            sleep "$REFRESH_SEC"
            [ -f "$DASH_DIR/.active" ] || break
            if fetch; then
                show
            else
                # 下载失败保留上一次的图，不清屏——宁可显示旧数据也不要白屏
                log "本次刷新失败，保留原图"
            fi
        done
        rm -f "$KEEPER_PID"
        ;;

    update)
        # 手动刷新。没在看板模式就不动屏幕，否则你正在看书时会被顶掉
        if [ ! -f "$DASH_DIR/.active" ]; then
            exit 0
        fi
        if fetch; then
            show
        else
            log "本次刷新失败，保留原图"
            exit 1
        fi
        ;;

    off)
        rm -f "$DASH_DIR/.active"
        stop_keeper
        start_ui
        lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
        log "退出看板模式"
        ;;

    test)
        echo "== 环境检查 =="
        if [ -z "$FBINK" ]; then
            echo "[缺] fbink —— 搜索框里试 ;kpm install fbink"
            exit 1
        fi
        if ! command -v curl >/dev/null 2>&1; then
            echo "[缺] curl"
            exit 1
        fi
        echo "fbink: $FBINK"
        echo "curl : $(command -v curl)"
        echo "uid  : $(id -u 2>/dev/null) / $(id 2>/dev/null | cut -d' ' -f1)"
        echo
        echo "== 网络与图片地址 =="
        if fetch; then
            echo "图片已下载：$DASH_IMG"
            "$FBINK" -q -i -g "file=$DASH_IMG" 2>&1 | head -1
        else
            echo "下载失败，检查 config.sh 里的 DASH_URL"
            exit 1
        fi
        echo
        echo "== 试刷一次 =="
        show && echo "屏幕上应该已经显示看板了"
        ;;

    *)
        echo "用法: dash.sh on|off|update|peek|test"
        exit 1
        ;;
esac
