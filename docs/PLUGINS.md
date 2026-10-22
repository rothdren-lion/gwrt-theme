# 配套插件清单与功能依赖说明

GWRT 主题的核心（仪表盘、主题样式、菜单、设备指纹、EQoS 面板）**全部包含在主题包内**，
不依赖任何第三方插件即可运行。本文档说明各插件的用途、缺失时的降级行为，以及
「单独装主题包（ipk/apk）」与「集成进固件编译」的差异。

## 1. 插件清单

> **本仓库不分发任何第三方插件二进制包**。以下插件请自行从你所用固件的 package 源
> 获取，或从上游项目页下载对应架构的安装包。

### 1.1 流量统计（仪表盘「网速-EQoS」「连接数」「连接排行」）

| 包名 | 作用 | 缺失后果 | 上游 |
|---|---|---|---|
| `bandix-plus` | 流量统计守护进程 | 网速卡片无实时速率、连接排行空白 | <https://github.com/timsaya/bandix-plus> |
| `luci-app-bandix-plus` | 上述的 LuCI 界面 | 同上 | 同上 |
| `luci-i18n-bandix-plus-zh-cn` | 中文翻译 | 界面英文 | 同上 |

获取方式：
- 固件源已包含 → `apk add bandix-plus luci-app-bandix-plus` / `opkg install bandix-plus luci-app-bandix-plus`
- 固件源没有 → 从上游 Releases 下载对应架构的包，本地 `apk add --allow-untrusted <包文件>`

### 1.2 CPU 跑分（仪表盘「点击运行 CoreMark」）

| 包名 | 作用 | 缺失后果 | 上游 |
|---|---|---|---|
| `coremark` | 跑分程序 | 无跑分按钮 | <https://github.com/eembc/coremark> |

获取方式：固件源（`coremark`，Apache-2.0）；`coremark` 为 aarch64 预编译，
其他架构需自行编译。**注意**：`coremark` 会在路由器上跑满 CPU，建议仅在需要时手动触发。

### 1.3 Web 终端（概览网格「Terminal」图标）

| 包名 | 作用 | 缺失后果 | 上游 |
|---|---|---|---|
| `ttyd` | 终端服务端 | 无 Terminal 图标 | <https://github.com/tsl0922/ttyd> (MIT) |
| `luci-app-ttyd` | LuCI 界面 | 同上 | <https://github.com/openwrt/luci> |
| `luci-i18n-ttyd-zh-cn` | 中文翻译 | 界面英文 | 同上 |

获取方式：固件源（`luci-app-ttyd` + `ttyd`）。`ttyd` 为 aarch64 预编译。

### 1.4 应用过滤（仪表盘「活跃 App」）

| 包名 | 作用 | 缺失后果 | 上游 |
|---|---|---|---|
| `appfilter` | 应用特征库 + 用户界面 | 「活跃 App」为空 | <https://github.com/iveco/luci-app-appfilter> |
| `luci-app-oaf` | OpenAppFilter 的 LuCI 界面 | 同上 | <https://github.com/destan19/OpenAppFilter> |
| `kmod-oaf` | OAF 内核模块 | 前两者无法安装（依赖不满足） | 同上 |

获取方式：**只能从你所用固件的 package 源获取**。
> ⚠️ `kmod-oaf` 是内核模块，必须与目标机型的内核版本严格匹配，**不可跨架构/跨版本复制**。
> 本仓库不提供该插件，也不提供任何第三方应用特征数据库。

### 1.5 其他（概览网格图标，可选）

| 包名 | 作用 | 缺失后果 | 上游 |
|---|---|---|---|
| `luci-app-openclash` | 科学上网 | 无「科学上网」图标 | <https://github.com/vernesong/OpenClash> |

## 2. 一键安装助手

`release/install-plugins.sh` 只做一件事：**尝试从你设备当前已配置的固件源**安装上表插件；
源里没有的，会打印出上游项目地址与本地安装命令。

```sh
# 尝试安装
wget -O- https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/install-plugins.sh | sh

# 只看清单与上游地址，不安装
wget -O- https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/install-plugins.sh | sh -s -- -n
```

脚本自动探测 `apk` / `opkg`，装完会清 LuCI 缓存并 reload rpcd。

## 3. 关键问题：单独编译 ipk/apk 安装，会功能缺失吗？

**结论：核心功能不会缺失，但有三个「需要手动补做」的点。**

### 3.1 为什么核心功能不会缺失

主题包 `luci-theme-gwrt` 自身包含了仪表盘所需的全部内容：

| 内容 | 位置 |
|---|---|
| 仪表盘入口模板（4400+ 行 ucode） | `root/usr/share/ucode/luci/template/admin_status/index_gwrt.ut` |
| 主题模板（header/footer/登录页） | `root/usr/share/ucode/luci/template/themes/gwrt/*.ut` |
| CSS / JS / 226 个 App 图标 / 41 品牌 OUI 库 | `root/www/luci-static/gwrt/` |
| 设备守护进程 | `root/usr/share/gwrt/clients.sh` + `root/etc/init.d/gwrt-clients` |
| DHCP 指纹钩子 | `root/usr/libexec/gwrt-dhcp-fp` + `root/etc/hotplug.d/dhcp/30-gwrt-dhcp-fp` |
| EQoS / LAN 别名 / WAN6 地址 / 跑分 执行器 | `root/usr/libexec/gwrt-*` |
| rpcd 权限 | `root/usr/share/rpcd/acl.d/luci-theme-gwrt.json` |

共 777 个文件（r109 实测 `.list` 行数），全部随包分发。

### 3.2 三个需要手动补做的点

**① `uci-defaults` 的执行时机**

`/etc/uci-defaults/*` 脚本在两种情况下行为不同：

| 安装方式 | uci-defaults 是否执行 | 说明 |
|---|---|---|
| 集成进固件编译（`sysupgrade` 刷机） | ✅ 首启动时执行 | `/etc/init.d/boot` 的 `uci_apply_defaults` 遍历执行后删除 |
| 单独 `apk add`（**首次安装**） | ✅ 安装时执行 | `default_postinst` 会 source 脚本并删除（见 `base-files/files/lib/functions.sh`） |
| 单独 `apk add`（**同版本重装 / Replacing**） | ⚠️ **不执行** | 实测：apk 走 Replacing 路径时不触发 `default_postinst` 的 uci-defaults 分支，脚本残留在 `/etc/uci-defaults/` |

apk 的 `post-install` 顺序是：`default_postinst`（执行 uci-defaults）→ 再追加
`postinst-pkg`（luci.mk 的默认 postinst 会 `rm -f /tmp/luci-indexcache.*` + `rpcd reload`）。

> **实测记录（2026-10-22，r110/r111 → 雅典娜 AX6600）**：
> 首次 `apk add` 正常执行 uci-defaults；随后同版本 `apk add`（Replacing）时
> `/etc/uci-defaults/` 中 19 个 GWRT 脚本全部残留未执行，
> 导致仪表盘入口模板（`admin_status/index.ut`）未被创建、DHCP 指纹钩子未启用。
> 手动 `sh /etc/uci-defaults/33_gwrt-dashboard` 等补跑后一切正常。
> **结论：升级/重装后若仪表盘不显示，先手动补跑 uci-defaults。**

但有一个坑：`default_postinst` 执行后会 **删除** uci-defaults 脚本。
若主题是「先装过一次、后来又升级了新版本」，新版本带的 uci-defaults 仍会执行（新的文件），
可若你曾手动 `rm` 过它们、或在 overlay 层面被清理，就需要手动补跑。

**② 仪表盘入口模板的替换**

`33_gwrt-dashboard` 做的事是把
`/usr/share/gwrt/admin_status-index.ut` 复制为
`/usr/share/ucode/luci/template/admin_status/index.ut`（LuCI 的 ucode dispatcher 入口）。

- 固件编译路径：脚本在首启动执行 → 替换成功 → 仪表盘生效
- 单独装包路径：脚本在安装时执行 → 同样替换成功

若仪表盘不显示，依次检查：

```sh
ls -l /usr/share/ucode/luci/template/admin_status/index.ut   # 是否存在
grep -c gwrt-dashboard /usr/share/ucode/luci/template/admin_status/index.ut
rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload
```

**③ 主题未注册 / 缓存未清**

单独装包时若 `luci.themes.Gwrt` 与 `luci.main.mediaurlbase` 没被设置，或 LuCI 模板缓存
没清，页面会显示原生 LuCI 而不是 GWRT 主题。修复：

```sh
uci set luci.main.mediaurlbase='/luci-static/gwrt'
uci set luci.themes.Gwrt='/luci-static/gwrt'
uci commit luci
rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload
```

### 3.3 固件编译路径独有的东西（单独装包拿不到）

| 项目 | 说明 |
|---|---|
| `30_gwrt-banner` SSH 登录横幅 | uci-defaults，单独装包**也会**执行 ✅ |
| `44_gwrt-hostname` 主机名设为 GWRT | 同上 ✅ |
| `40~43` 存储/aria2/samba/nfs 初始化 | 同上 ✅（但依赖对应插件已装） |
| `manifest/config.fragment` 功能包选择 | ❌ 单独装包不生效，需手工装对应插件（见第 1 节） |
| `scripts/integrate.sh` 双树同步 | ❌ 仅编译期使用 |
| 固件级 `/etc/config/luci.disabled` | ✅ 随包分发（`root/etc/config/luci.disabled`） |

### 3.4 一句话总结

> **主题包是自包含的，单独编译 ipk/apk 安装不会功能缺失** ——
> 仪表盘、主题样式、设备指纹、EQoS 面板全部可用（已在真机实测验证）。
> 唯一需要留意的是：① 配套插件（bandix-plus 等）要另外装，否则对应卡片降级；
> ② 装完清 LuCI 缓存 + reload rpcd；③ **重装/升级场景下 uci-defaults 不会自动执行**，
> 需手动补跑 `33_gwrt-dashboard`（仪表盘入口）、`37_gwrt-dhcp-fp`（设备指纹）、
> `36_gwrt-clients-init`（设备守护）三个关键脚本。

### 3.5 真机实测验证（2026-10-22）

在 **JDCloud 雅典娜 AX6600（RE-CS-02，ImmortalWrt 6.18.52 / apk）** 上实测：

| 检查项 | 结果 |
|---|---|
| `apk add` 安装 r111 | ✅ 成功（775 文件 / 3.0 MB） |
| 主题包文件完整性 | ✅ 9/9 关键路径就位 |
| 仪表盘渲染 | ✅ `.gwrt-dashboard` 存在，47 个网格图标、60 行设备表 |
| OTA 按钮 | ✅ 已移除（`gwrtOtaBtn` 不存在） |
| OTA 脚本 / ACL 条目 | ✅ 均已移除 |
| 固件版本显示 | ✅ `gwrt 260920-05` |
| 设备守护 `clients.sh` | ✅ 运行中 |
| 主题注册 | ✅ `luci.themes.Gwrt` + `luci.main.mediaurlbase` 已设 |
| 同版本重装 | ⚠️ uci-defaults 残留未执行 → 手动补跑后恢复 |

**实测也暴露了一个安装细节**：若目标设备已装 `samba4-server` 等包且占用同名
hotplug 文件，apk 会报 `trying to overwrite ... owned by ...`，需加
`--force-overwrite` 安装（不影响功能）。

## 4. 验证清单

安装后逐项确认：

```sh
# 1. 主题包已装
apk info -e luci-theme-gwrt && cat /usr/share/gwrt/theme-version

# 2. 主题已注册
uci get luci.themes.Gwrt && uci get luci.main.mediaurlbase

# 3. 仪表盘入口已替换
grep -c gwrt /usr/share/ucode/luci/template/admin_status/index.ut

# 4. 设备守护在跑
pgrep -f clients.sh && /etc/init.d/gwrt-clients status

# 5. DHCP 指纹钩子已启用
uci get dhcp.@dnsmasq[0].dhcpscript    # 期望 /usr/libexec/gwrt-dhcp-fp

# 6. 配套插件
apk info -e bandix-plus luci-app-bandix-plus coremark 2>/dev/null
```

浏览器打开 `http://<router-ip>/cgi-bin/luci/admin/status/overview`，
应看到完整的 GWRT 仪表盘（对照 `docs/screenshots/`）。
