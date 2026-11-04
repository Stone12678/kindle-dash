#!/usr/bin/env python3
"""把看板打成一个 KPM 包（.kpkg），并生成仓库索引 kpm.json。

KPM 包本质是个 tar.gz，里面必须有 manifest.json，可选三个钩子：

    install.sh    包解压后执行，工作目录就是包目录
    launch.sh     从启动器拉起时执行（scriptlet 里 kpm launch 会调它）
    uninstall.sh  卸载时执行

KPM 官方文档明确鼓励在 install.sh 里往 /mnt/us/documents 放 scriptlet，
所以这里走“装完就在书架上多一本书”的路子，用户不需要终端。

    python tools/make-kpm.py
"""

import json
import os
import shutil
import tarfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build", "kpm", "kindle-dash")
DIST = os.path.join(ROOT, "dist")

ID = "kindle-dash"
NAME = "Kindle Dash"
AUTHOR = "Stone"
VERSION = [1, 0, 0]
PLATFORM = "kindlehf"
DESC = "把闲置 Kindle 变成电子墨水信息看板：大时钟、天气预警、未来 6 天、在读进度，配一只猫。"
KPkg_NAME = f"{ID}_{'.'.join(map(str, VERSION))}_{PLATFORM}.kpkg"

# 仓库地址：CDN 在国内比 raw 快得多，KPM 自己用 curl 拉，不看 MIME 类型
BASE = "https://cdn.jsdelivr.net/gh/Stone12678/kindle-dash@main"

MANIFEST = {
    "manifest_version": 2,
    "id": ID,
    "name": NAME,
    "author": AUTHOR,
    "description": DESC,
    "version": VERSION,
    "dependencies": [],
    "supported_platforms": [PLATFORM],
}

INSTALL = r"""#!/bin/sh
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
"""

LAUNCH = r"""#!/bin/sh
# 从启动器拉起时走这里（scriptlet 里 kpm launch kindle-dash 会调它）
exec sh /mnt/us/kindle-dash/kindle/dash.sh on
"""

UNINSTALL = r"""#!/bin/sh
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
"""


def main():
    if os.path.isdir(BUILD):
        shutil.rmtree(BUILD)
    os.makedirs(BUILD)
    os.makedirs(DIST, exist_ok=True)

    with open(os.path.join(BUILD, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(MANIFEST, f, indent=2, ensure_ascii=False)

    for name, body in (
        ("install.sh", INSTALL),
        ("launch.sh", LAUNCH),
        ("uninstall.sh", UNINSTALL),
    ):
        p = os.path.join(BUILD, name)
        # newline="\n" 必须显式指定：Windows 默认写 CRLF，
        # 而 Kindle 的 sh 读到 \r 会报 "not found"，症状是点了书毫无反应
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
        os.chmod(p, 0o755)

    shutil.copytree(os.path.join(ROOT, "kindle"), os.path.join(BUILD, "kindle"))

    out = os.path.join(DIST, KPkg_NAME)

    def norm(ti):
        # tar 里统一 755，避免 Windows 上的权限位漏进包里
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = "root"
        ti.mode = 0o755 if ti.isdir() or ti.name.endswith(".sh") else 0o644
        ti.mtime = int(time.time())
        return ti

    with tarfile.open(out, "w:gz", compresslevel=5) as t:
        for item in sorted(os.listdir(BUILD)):
            t.add(os.path.join(BUILD, item), arcname=item, filter=norm)

    repo = {
        "manifest_version": 2,
        "id": "stone-kindle-dash",
        "name": "Kindle Dash",
        "description": "Kindle 看板相关包。",
        "packages": {
            ID: {
                "name": NAME,
                "author": AUTHOR,
                "description": DESC,
                "artifacts": [
                    {
                        "url": f"{BASE}/dist/{KPkg_NAME}",
                        "version": VERSION,
                        "dependencies": [],
                        "supported_platforms": [PLATFORM],
                    }
                ],
            }
        },
    }
    repo_path = os.path.join(ROOT, "kpm.json")
    with open(repo_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(repo, f, indent=2, ensure_ascii=False)

    print(f"包  : {out}  ({os.path.getsize(out)} 字节)")
    print(f"索引: {repo_path}")
    print(f"安装: ;kpm add-repo {BASE}/kpm.json")
    print(f"      ;kpm install {ID}")


if __name__ == "__main__":
    main()
