#!/bin/sh
# 打一个能直接喂给 Kindle 的程序包
#
#   sh tools/make-package.sh
#
# 产物在 dist/：
#   kindle-dash.tar.gz        设备端程序（解压到 /mnt/us/kindle-dash/）
#   KindleDash-Install.sh     安装用的 scriptlet（放进 documents/）
#
# 打包前会校验行尾：Kindle 的 sh 读不了 CRLF，带 \r 的脚本会报
# "not found" —— 症状是点了书毫无反应，极难排查。

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== 检查行尾 =="
BAD=0
for f in kindle/*.sh documents/*.sh tools/*.sh; do
    [ -f "$f" ] || continue
    if python -c "import sys;sys.exit(0 if b'\r\n' in open(sys.argv[1],'rb').read() else 1)" "$f"; then
        echo "[CRLF] $f"
        BAD=1
    fi
done
if [ "$BAD" = "1" ]; then
    echo "有文件是 CRLF，先修掉再打包。"
    exit 1
fi
echo "[好] 全是 LF"

echo "== 语法检查 =="
for f in kindle/*.sh documents/*.sh; do
    [ -f "$f" ] || continue
    sh -n "$f" || { echo "[语法错误] $f"; exit 1; }
done
echo "[好] 语法没问题"

echo "== 打包 =="
rm -rf dist
mkdir -p dist
tar czf dist/kindle-dash.tar.gz kindle extensions
cp documents/KindleDash-Install.sh dist/

echo ""
ls -lh dist/
echo ""
echo "程序包：$(wc -c < dist/kindle-dash.tar.gz) 字节"
