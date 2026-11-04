# Kindle 看板 · Paperwhite 4

把闲置的 Kindle 变成一块电子墨水信息屏：大时钟、天气预警、未来 6 天、在读进度，配一只趴在电脑前的猫。

```
GitHub Actions（每 30 分钟）
        │  用 Pillow 渲染 1072×1448 灰度 PNG
        ▼
   render 分支 (dashboard.png)
        │  Kindle 用 curl 拉取
        ▼
   fbink 全屏刷新 → 屏幕更新
```

**为什么要绕到 GitHub**：Kindle 自己跑不动渲染（PW4 只有 1GHz 单核 + 512MB 内存），而且拿不到天气数据。让云端算好、设备只负责显示，是这套方案最省事的地方。

---

## 一、先让云端跑通（不用碰 Kindle）

### 1. 建仓库并推上去

在 GitHub 上新建一个仓库，然后在本目录执行。用 `gh` 命令行可以一条命令搞定（会顺便建库、推代码）：

```bash
gh auth login                                  # 浏览器授权一次
gh repo create kindle-dash --public --source=. --push
```

不想用 `gh` 就在网页上建空仓库，然后：

```bash
git remote add origin https://github.com/你的用户名/你的仓库名.git
git push -u origin main
```

本地仓库已经 `git init` 并提交好了，不需要再初始化。

> **仓库建议公开**：私有仓库的 `raw` 地址不支持直链拉取，Kindle 端得改成 GitHub API 加令牌，多一层配置、令牌还会一年过期。如果书单不方便公开，把 `data/schedule.json` 里的书名换成代号（默认已是「技术资料 A」）比上私有方案划算。

### 2. 开启 Actions 写权限

仓库 → **Settings → Actions → General → Workflow permissions** → 选 **Read and write permissions** → Save。

不开这一步，工作流渲染完推不上去。

### 3. 手动跑一次

仓库 → **Actions → 渲染 Kindle 看板 → Run workflow**。

跑完会多出一个 `render` 分支，里面只有一张 `dashboard.png`。打开这个地址确认能访问：

```
https://raw.githubusercontent.com/你的用户名/你的仓库名/render/dashboard.png
```

> `render` 分支每次都是**强制覆盖**，永远只有一个提交。不这么做的话一天 48 张图累积下来，仓库很快就几十 GB。

### 4. 之后再也不用管

工作流已经配好每 30 分钟自动跑。注意两点：

- **GitHub 的 cron 是 UTC 时间**，`*/30` 每半小时一次，跟时区无关，不用换算
- **仓库连续 60 天没有任何提交，GitHub 会自动停掉定时任务**。偶尔在网页上手动 Run 一次，或者改一下 `data/schedule.json` 提交上去，就能续上

---

## 二、越狱（一次性，约 15 分钟）

PW4 固件 5.18.1 走 **SpiderCat**。这是社区方法，**不保证零风险**，动手前把书和笔记备份出来。

1. 连上 WiFi，全程别断网（这方法要在线）
2. 把存储塞到只剩 100MB 以内，删掉根目录所有 `.bin` —— 防越狱途中被 OTA 覆盖
3. 打开 Kindle 浏览器 → `kindlemodding.org/spidercat/` → 下载那个特制 azw3
4. 回书库点开这本"书"，等提示越狱成功（它会自动屏蔽 OTA）
5. 装包管理器：搜索框输入 `;kpm install koreader`

顺带说一句，越狱后 `;kpm install koreader` 装的 KOReader，看 epub 和漫画比原生好很多，算是附赠收益。

---

## 三、部署 Kindle 端

把整个项目目录拷到 Kindle 的 `/mnt/us/kindle-dash/`（USB 连电脑拖过去即可），然后：

### 1. 改配置

编辑 `/mnt/us/kindle-dash/kindle/config.sh`，把 `DASH_URL` 换成你自己的地址：

```sh
DASH_URL="https://raw.githubusercontent.com/你的用户名/你的仓库名/render/dashboard.png"
```

### 2. 安装

在 Kindle 上开 KUAL → 打开终端（KUAL 的 Term 扩展，或 SSH），执行：

```sh
sh /mnt/us/kindle-dash/kindle/install.sh
```

它会装好 KUAL 菜单和每 30 分钟的定时任务。

### 3. 自检再开机

KUAL → **Kindle 看板 → 环境自检**。它会依次检查 fbink、网络、图片能否下载、能不能刷屏。全通过再点「开启看板」。

### 4. 退出

KUAL → **Kindle 看板 → 退出看板**，回到原生书架。

> 看板模式会 `stop` 掉系统界面（否则原生 UI 会盖住图片），所以退出务必走菜单，别直接拔线。

---

## 四、日常怎么改

| 想改什么 | 动哪里 |
|---|---|
| 在读的书名 / 章节 / 进度 | `data/schedule.json` 里的 `_reading` |
| 版式、字号、配色深浅 | `render.py`，所有坐标都在 `render()` 里 |
| 换猫的图 / 加新姿态 | PNG 放进 `assets/cats/`，改 `CAT_ARTS` 字典和 `pick_cat_mood()` 的时段规则 |
| 换成别的机型 | `kindle/config.sh` 里的 `SCREEN_W/SCREEN_H`；PW4 之外要重新调版式 |

改完提交，等下一次 Actions 跑完（或手动 Run），Kindle 半小时内自动跟上。

### 改完先跑一遍自测

动过 `kindle/` 下的脚本，**先在本机跑测试再提交**：

```bash
bash tests/test_kindle.sh
```

39 项检查，覆盖 `on / update / off / test` 四条分支，用桩程序替掉 fbink、curl、系统界面，在临时目录里模拟整台设备。重点验证这几件事：

- 没开看板模式时，定时任务静默退出，不抢屏
- 断网时**保留上一张图**，不刷白屏
- 下载到 HTML 错误页时能识别出来（校验 PNG 魔数），不往屏幕上糊
- 主地址挂了自动切备用地址
- 重复安装不会把定时任务追加两遍
- 所有 shell 脚本是 LF 行尾

之所以要在本机测：这些脚本跑在 Kindle 上，出了错的表现不是报错，而是屏幕一片白、日志里什么都看不出来。推送后 GitHub 也会自动跑一遍这个测试。

### 猫怎么换

同一只黑白奶牛猫，四个姿态，按时间和天气自动切：

| 姿态 | 出现条件 | 文件 |
|---|---|---|
| 刚睡醒（揉眼抱杯子） | 7:00–10:00 | `cat_morning_430.png` |
| 敲电脑（有点嫌弃） | 10:00–11:00、14:00–22:00 | `cat_work_430.png` |
| 扒鱼吃饭 | 11:00–14:00 | `cat_lunch_430.png` |
| 望着窗外下雨发愁 | 白天下雨 / 下雪 / 打雷 | `cat_rainy_430.png` |
| 蜷成一团睡 | 22:00–7:00 | `cat_sleep_430.png` |

优先级是**夜里 > 天气 > 时段**：22 点后一律睡（下雨也睡），白天遇到降水就去看雨，其余按时段走。规则全在 `pick_cat_mood()` 里。

五张图必须是**同一画风**：浓墨笔触、灰阶淡阴影、纯白背景。新加图时用现成的图做参考图走图生图，比纯文字描述更容易保持一致。

`cat_rainy_430.png` 是个特例——窗户是竖向构图，猫被窗框挤在中间显小，所以裁掉了窗框上沿再放大。这样窗户反而成了"延伸出画面"的效果，比完整的画框自然。

**阅读进度目前是手填的**。自动读取需要从 Kindle 的 `cc.db` 取数再上报到仓库，要在这台设备上存一个 GitHub 令牌，链路长一环、风险也多一分，所以一期先不做。

---

## 五、会遇到的坑

**国内拉 raw.githubusercontent.com 很慢甚至超时**
这是最可能卡住的地方。两个办法：① 在 `config.sh` 里把 `DASH_URL_FALLBACK` 填成 Cloudflare Worker 反代地址，脚本会依次重试；② 把图片同步到 Gitee 或自己的图床。**别指望 GitHub 的 raw 在国内像访问百度一样稳定。**

**屏幕每 30 分钟闪一下**
`dash.sh` 里 `fbink ... -f` 的 `-f` 是 GC16 全刷，闪一下的代价换来没有残影累积。嫌烦可以去掉 `-f`，但那样每几小时得手动全刷一次，否则字会糊成一片灰。

**必须一直插着 USB**
PW4 电池撑不住半小时一刷，看板模式基本等于常电设备。

**天气拉不到**
`render.py` 用的是 Open-Meteo，免费、不用注册 key。挂了的话脚本不会崩，只是图上没有天气数据。坐标在 `fetch_weather()` 里，默认是平湖独山港 `30.68N / 121.02E`。

**中文变成方框**
Actions 环境必须装 `fonts-noto-cjk`，工作流里已经装好了。本地 Windows 走的是微软雅黑，`render.py` 会自动按顺序找字体。

**拷到 Kindle 上跑不起来，报 `/bin/sh: not found` 或语法错**
十有八九是行尾符变成了 CRLF。Windows 上的编辑器和 Git 默认都会转换，而 `sh` 会把 `\r` 当成命令的一部分。仓库里有 `.gitattributes` 强制 LF，`tests/test_kindle.sh` 每次也会检查这一项——如果测试报行尾问题，说明文件在提交前被某个编辑器改过了。

---

## 文件说明

```
render.py              主渲染脚本，输出 1072×1448 灰度 PNG
prep_cat.py            从原图重建全部猫插画（裁白边、缩放、加深线条）
preview_cats.py        生成矢量猫姿态图鉴（插画缺失时的兜底样式）
data/schedule.json     「在读」区块的数据，书名建议用代号
assets/cats/           五张猫插画（5 个姿态），缺图时自动退回矢量简笔画
assets/cats/src/       AI 原始生成图，prep_cat.py 从这里重建
kindle/config.sh       设备端配置（地址、分辨率、系统路径）
kindle/dash.sh         控制脚本 on / update / off / test
kindle/install.sh      一键安装
extensions/kindle-dash KUAL 菜单
tests/test_kindle.sh   Kindle 端脚本的本地测试（39 项）
.github/workflows/     定时渲染 + 脚本自测
.gitattributes         强制 LF 行尾，防止 CRLF 让 Kindle 跑不起来
```
