#!/bin/sh
# 卸载钩子。KPM 自己会删包目录，这里只收拾我们自己铺出去的东西。
#
# 注意：升级时这个钩子会带 upgrade 参数执行，
# 那种情况下不要删 /mnt/us/kindle-dash —— 紧接着 install.sh 会覆盖它。

sh /mnt/us/kindle-dash/kindle/dash.sh off >/dev/null 2>&1

rm -f "/mnt/us/documents/Kindle 看板 启动.sh" 2>/dev/null
rm -f "/mnt/us/documents/Kindle 看板 退出.sh" 2>/dev/null
rm -f "/mnt/us/documents/Kindle 看板 自检.sh" 2>/dev/null

[ "$1" = "upgrade" ] && exit 0

rm -rf /mnt/us/kindle-dash 2>/dev/null
exit 0
