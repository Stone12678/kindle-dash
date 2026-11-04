#!/bin/sh
# Kindle 看板控制脚本
#
#   dash.sh on      进入看板模式：停掉系统界面 + 拉图 + 全屏显示
#   dash.sh update  只拉图并刷新（已在看板模式下，供 cron 定时调用）
#   dash.sh off     退出看板模式，恢复原生系统界面
#   dash.sh test    检查环境（fbink / curl / 网络 / 图片地址）
#
# 放在 /mnt/us/kindle-dash/kindle/dash.sh，需与 config.sh 同目录

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
    fbink -q -g "file=$DASH_IMG,halign=CENTER,valign=CENTER,w=$SCREEN_W,h=$SCREEN_H" -f
    log "已刷新屏幕"
}

# ---------- 环境检查 ----------
need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少 $1 —— $2"
        return 1
    fi
    return 0
}

case "$1" in
    on)
        # 顺序很重要：先阻止屏保（它依赖系统界面），再停界面
        lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1
        "$FRAMEWORK_INIT" stop
        sleep 2
        touch "$DASH_DIR/.active"
        log "进入看板模式"
        if fetch; then show; fi
        ;;

    update)
        # cron 每 30 分钟会调一次。没在看板模式就直接退出，
        # 否则你正在看书时屏幕会突然被看板顶掉
        if [ ! -f "$DASH_DIR/.active" ]; then
            exit 0
        fi
        if fetch; then
            show
        else
            # 下载失败保留上一次的图，不清屏——宁可显示旧数据也不要白屏
            log "本次刷新失败，保留原图"
            exit 1
        fi
        ;;

    off)
        rm -f "$DASH_DIR/.active"
        "$FRAMEWORK_INIT" start
        lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
        log "退出看板模式"
        ;;

    test)
        echo "== 环境检查 =="
        need fbink   "FBInk 没装，KUAL 里的 FBInk 扩展或 KPM 装一下" || exit 1
        need curl    "没有 curl" || exit 1
        echo "fbink: $(command -v fbink)"
        echo "curl : $(command -v curl)"
        echo
        echo "== 网络与图片地址 =="
        if fetch; then
            echo "图片已下载：$DASH_IMG"
            echo "尺寸：$(fbink -q -i -g "file=$DASH_IMG" 2>&1 | head -1)"
        else
            echo "下载失败，检查 config.sh 里的 DASH_URL"
            exit 1
        fi
        echo
        echo "== 试刷一次 =="
        show && echo "屏幕上应该已经显示看板了"
        ;;

    *)
        echo "用法: dash.sh on|update|off|test"
        exit 1
        ;;
esac
