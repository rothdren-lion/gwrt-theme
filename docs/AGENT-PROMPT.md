# GWRT Theme — Agent 一键接入提示词

> **用法**：把本文件整段内容（从「开始」到「结束」）直接粘进任意 AI Agent（Claude Code / Cursor / Codex / OpenCode / pi 等）的对话里，Agent 即可自动完成主题接入。

---

## ▶ 开始：把下面这段话原样交给你的 Agent

````text
请帮我把 GWRT LuCI 主题接入我的 OpenWrt / ImmortalWrt 设备。

【仓库】https://github.com/rothdren-lion/gwrt-theme
【主题版本】1.0-r110（Apache-2.0，开源版：已去除 OTA）
【支持平台】ImmortalWrt / OpenWrt，LuCI ucode 模板（24.10 及以后）

━━━ 第一步：判断接入方式 ━━━

先探测我的环境，再选路径：

A) 我有固件源码树（有 package/ 和 feeds/ 目录，.config 存在）
   → 走【方案 A：集成进固件编译】

B) 我只有一台运行中的路由器（能 SSH / LuCI 访问）
   → 走【方案 B：直接装到路由器】

C) 我只有主题包文件（.ipk / .apk），没有源码树
   → 走【方案 C：离线装包】

先执行探测，不要问我，直接用探测结果决定：
  - 检查当前目录是否有 package/ 与 feeds/luci/ → 是则方案 A
  - 否则检查能否 SSH 到路由器（ssh root@<ip>） → 是则方案 B
  - 否则询问用户要装到哪台设备 → 方案 B

━━━ 方案 A：集成进固件编译 ━━━

1. 克隆主题到源码树内（放在源码根目录的子目录里，避免被 package/ 扫描成重复包）：
   git clone https://github.com/rothdren-lion/gwrt-theme.git gwrt-theme

2. 执行集成脚本（同步主题源码到 package/gwrt-theme/luci-theme-gwrt，并合并配置片段）：
   ./gwrt-theme/scripts/integrate.sh --tree .
   验证不写入：./gwrt-theme/scripts/integrate.sh --tree . --check

3. 编译主题包（先只编主题，快速验证）：
   make package/luci-theme-gwrt/clean
   make package/luci-theme-gwrt/compile -j$(nproc)

4. 若需要整机固件，合并配置片段后 defconfig 再编译：
   ./gwrt-theme/scripts/build-with-theme.sh --tree . -j6
   （注意：该包装器不会切换硬件 profile，请先选好目标机型）

5. 验证产物存在：
   ls -la bin/packages/*/base/luci-theme-gwrt-*.apk
   或 bin/packages/*/luci/luci-theme-gwrt-*.ipk

━━━ 方案 B：直接装到运行中的路由器 ━━━

1. 确认路由器上 LuCI 主题目录与包管理器：
   ssh root@<router-ip> 'ls /usr/share/ucode/luci/template/themes/ 2>/dev/null; command -v apk || command -v opkg'

2. 把主题包传到路由器并安装（先备份现有主题）：
   ssh root@<ip> 'cp -a /usr/share/ucode/luci/template/themes/gwrt /tmp/gwrt-backup 2>/dev/null'
   scp luci-theme-gwrt-*.apk root@<ip>:/tmp/
   ssh root@<ip> 'apk add --allow-untrusted /tmp/luci-theme-gwrt-*.apk'
   （opkg 系统：scp *.ipk 后 opkg install /tmp/luci-theme-gwrt-*.ipk）

3. 安装配套插件（应用过滤 OAF / 流量统计 bandix-plus / 跑分 / Web 终端）：
   ssh root@<ip> 'wget -O- https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/install-plugins.sh | sh'
   或下载后本地执行：sh install-plugins.sh

4. 重启相关服务并清缓存：
   ssh root@<ip> 'rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache/; /etc/init.d/rpcd reload; /etc/init.d/gwrt-clients restart 2>/dev/null; /etc/init.d/dnsmasq reload 2>/dev/null'

5. 切换主题为 gwrt：
   ssh root@<ip> "uci set luci.main.mediaurlbase='/luci-static/gwrt'; uci set luci.themes.Gwrt='/luci-static/gwrt'; uci commit luci"

6. 验证：浏览器打开 http://<router-ip>/cgi-bin/luci/admin/status/overview
   应看到 GWRT 仪表盘（系统信息 / CPU·温度 / 运行存储 / 活跃 App / 连接设备 / 连接数 / 网速-EQoS / 日志报错 + 网口状态图 + 接入设备表 + 网络拓扑）
   若仍是原生界面 → 执行 ssh root@<ip> 'ls /etc/uci-defaults/' 检查 uci-defaults 是否已执行

━━━ 方案 C：离线装包 ━━━

1. 若手上只有主题 .apk/.ipk：
   scp *.apk root@<ip>:/tmp/ && ssh root@<ip> 'apk add --allow-untrusted /tmp/*.apk'
   若报 "trying to overwrite ... owned by ..."（如 samba4-server 占用同名 hotplug 文件），
   加 --force-overwrite 重装即可，不影响功能。

2. **关键：安装后必须检查 uci-defaults 是否被执行**
   apk 首次安装会执行包内 /etc/uci-defaults/* 脚本；但**同版本重装（Replacing）
   不会执行**，脚本会残留在 /etc/uci-defaults/。
   检查：ssh root@<ip> 'ls /etc/uci-defaults/ | grep gwrt'
   若有残留 → 手动补跑关键三个（其余可选）：
     ssh root@<ip> 'sh /etc/uci-defaults/33_gwrt-dashboard'   # 替换 admin_status 入口模板（最重要）
     ssh root@<ip> 'sh /etc/uci-defaults/37_gwrt-dhcp-fp'     # 启用 DHCP 指纹钩子
     ssh root@<ip> 'sh /etc/uci-defaults/36_gwrt-clients-init' # 启用设备守护

3. 无论哪种方案，装完都要：
     ssh root@<ip> 'rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache/; /etc/init.d/rpcd reload'
   否则页面仍是旧模板 / 原生 LuCI。

2. 配套插件同样从 release/plugins/ 取，按架构选择：
   - 架构无关：release/plugins/*.apk
   - aarch64 二进制：release/plugins/aarch64/{ttyd,coremark}.apk
   - kmod-oaf 必须按机型从固件源获取，不可跨架构

━━━ 通用注意事项 ━━━

- 本仓库已去除 OTA（固件在线升级）相关功能，不含任何 OTA manifest 配置。
- 主题**不强制依赖**配套插件：缺 OAF 则「活跃 App」为空，缺 bandix-plus 则网速卡片回退，缺 coremark 则无跑分按钮。主题本体始终可独立安装。
- 装完必须清理 LuCI 缓存（/tmp/luci-indexcache.*、/tmp/luci-modulecache/）并 reload rpcd，否则页面仍是旧模板。
- 主题会替换 /usr/share/ucode/luci/template/admin_status/index.ut（原文件备份为 index.ut.bak-src）。这是仪表盘的入口，替换失败会导致仪表盘不显示。
- 开发时：只改仓库里的 theme/luci-theme-gwrt/，改完跑 integrate.sh 同步到固件树；不要直接改固件树里 package/gwrt-theme/ 的副本。

━━━ 交付要求 ━━━

完成后向我汇报：
1. 采用了哪个方案（A/B/C）以及依据
2. 实际执行的命令清单
3. 主题安装位置与版本（主题包内 /usr/share/gwrt/theme-version）
4. 哪些配套插件装成功、哪些未装及原因（如架构不匹配）
5. 验证结果：仪表盘是否正常显示（截图或描述卡片内容）
6. 若某步失败：失败原因 + 建议的下一步
````

## ▶ 结束

---

## 附：Agent 常见追问速查

| 追问 | 回答 |
|---|---|
| 主题需要哪些插件？ | OAF（应用过滤）、bandix-plus（流量统计）、coremark（跑分）、ttyd（Web 终端）。**全部可选**，缺失只降级不报错 |
| `kmod-oaf` 从哪来？ | 必须与目标机型/内核版本匹配，从该机型固件的 package 源获取，不可跨架构复制 |
| 装完仪表盘还是原生 LuCI？ | 清 `/tmp/luci-indexcache.*` + `/tmp/luci-modulecache/` 并 `reload rpcd`；再检查 `admin_status/index.ut` 是否已被替换 |
| 会覆盖我的原生 LuCI 吗？ | 只覆盖 `admin_status/index.ut`（备份为 `index.ut.bak-src`）和注册 `luci.themes.Gwrt`，其余页面样式跟随主题 |
| 支持哪些机型？ | 主题本体与平台无关（纯 ucode/JS/CSS），不限定机型；二进制插件 `ttyd`/`coremark` 目前只提供 aarch64 构建 |
| 怎么升级主题？ | 重新安装新版本主题包即可；`uci-defaults` 只在首次执行，`33_gwrt-dashboard` 等需要手动重跑（见方案 C） |
| 怎么恢复原生 LuCI？ | `cp /usr/share/ucode/luci/template/admin_status/index.ut.bak-src .../index.ut`，并 `uci delete luci.themes.Gwrt; uci commit luci`，重启 rpcd |
