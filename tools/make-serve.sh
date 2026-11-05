#!/bin/sh
# 生成"局域网分发目录" dist/serve，给电脑上那个 python -m http.server 用
#
#   sh tools/make-serve.sh            # 默认 192.168.31.110:8765
#   sh tools/make-serve.sh 192.168.1.20:8765
#
# 为什么要单独出一份：设备上那些境外 CDN 全被墙了（jsDelivr 被 RST、
# github.io 挂住），只有局域网是通得最稳的。所以这里把安装脚本和程序包里
# 的地址全部改写成电脑的内网地址，Kindle 只要 wget 得到就能装。

set -e

IP="${1:-192.168.31.110:8765}"
BASE="http://$IP"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVE="$ROOT/dist/serve"

echo "分发地址：$BASE"

# 1. 程序包：把里面的图片地址改成局域网
#    （否则装完了设备还是去拉被墙的地址，屏幕上永远出不来图）
rm -rf "$ROOT/build/serve"
mkdir -p "$ROOT/build/serve" "$SERVE"
tar xzf "$ROOT/dist/kindle-dash.tar.gz" -C "$ROOT/build/serve"
sed -i "s#^DASH_URL=.*#DASH_URL=\"$BASE/dashboard.png\"#; s#^DASH_URL_FALLBACK=.*#DASH_URL_FALLBACK=\"\"#; s#^DASH_EXTRA_URLS=.*#DASH_EXTRA_URLS=\"\"#" \
    "$ROOT/build/serve/kindle/config.sh"
tar czf "$SERVE/kindle-dash.tar.gz" -C "$ROOT/build/serve" .
rm -rf "$ROOT/build/serve"

# 2. 安装脚本：把程序包地址改成本机
sed "s#^PKG_URL=.*#PKG_URL=\"$BASE/kindle-dash.tar.gz\"#; s#^PKG2_URL=.*#PKG2_URL=\"\"#" \
    "$ROOT/documents/KindleDash-Install.sh" > "$SERVE/k"

echo
echo "目录：$SERVE"
ls -lh "$SERVE"
echo
echo "在 Kindle 的 kTerm 里："
echo "  wget $IP/k"
echo "  sh k"
