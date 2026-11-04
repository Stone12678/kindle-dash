#!/bin/sh
# KPM 安装钩子。KPM 解压后在包目录里执行，所以相对路径指的是包内文件。
#
# 它把程序铺到固定的用户目录 /mnt/us/kindle-dash，
# 再往 documents 里放三本小书——回书架点一下就能用，不需要终端。

DEST=/mnt/us/kindle-dash
DOCS=/mnt/us/documents

mkdir -p "$DEST/kindle" "$DOCS" 2>/dev/null

# 1. 铺开程序本体
cp -f ./kindle/config.sh "$DEST/kindle/" 2>/dev/null
cp -f ./kindle/dash.sh   "$DEST/kindle/" 2>/dev/null

# FAT32 上拷过来的文件没有 x 位，必须显式加，
# 否则 scriptlet 点下去只会安静地什么都不发生
chmod +x "$DEST"/kindle/*.sh 2>/dev/null

# 2. 记下 fbink 的位置
# SpiderCat 自带的 fbink 装在 libkh 下，不在 PATH 里，
# 这里探测一次写进缓存，dash.sh 启动时直接读，省得每次扫盘
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
[ -n "$FB" ] && echo "$FB" > "$DEST/.fbink"

# 3. 书架入口
# SH_Integration 把 documents 里的 .sh 索引成书，书名来自 # Name: 注释
mk() {
    cat > "$DOCS/$1" <<EOF
#!/bin/sh
# Name: $2
# Author: Stone
exec $3
EOF
}

mk "Kindle 看板 启动.sh" "看板 - 启动" "sh $DEST/kindle/dash.sh on"
mk "Kindle 看板 退出.sh" "看板 - 退出" "sh $DEST/kindle/dash.sh off"
mk "Kindle 看板 自检.sh" "看板 - 自检" "sh $DEST/kindle/dash.sh test"

exit 0
