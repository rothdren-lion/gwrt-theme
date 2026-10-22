# Release 目录说明

本目录只提供**主题包本体**（本项目自己的产物）与一个插件安装助手脚本。

> **本仓库不分发任何第三方插件二进制包**，避免再分发第三方作品。
> 需要哪些插件、去哪下、怎么装 —— 见下方「配套插件」与 [`../docs/PLUGINS.md`](../docs/PLUGINS.md)。

```
release/
├── packages/                    # 主题包本体（已真机实测验证）
│   ├── luci-theme-gwrt-1.0-r111.apk
│   └── luci-theme-gwrt-1.0-r111.apk.sha256
├── install-plugins.sh           # 插件安装助手（从你设备已配置的固件源装）
└── README.md
```

## 安装主题

### 方式 A：路由器上直接装（推荐，无需编译环境）

```sh
# 1. 下载主题包
wget -O /tmp/luci-theme-gwrt.apk \
  https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/packages/luci-theme-gwrt-1.0-r111.apk

# 2. 安装（老版本 opkg 系统用 opkg install /tmp/luci-theme-gwrt.apk）
apk add --allow-untrusted /tmp/luci-theme-gwrt.apk

# 3. 清缓存 + 重载
rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload
/etc/init.d/gwrt-clients restart 2>/dev/null
```

### 方式 B：编译进固件

见仓库根目录 `README.md` 的「使用」章节（`scripts/integrate.sh`）。

## ⚠️ 装完必查：uci-defaults 是否执行

**首次安装**会正常执行包内 `/etc/uci-defaults/*`；但**同版本重装（apk Replacing）不会执行**，
脚本会残留在 `/etc/uci-defaults/`，导致仪表盘入口模板不被创建、页面显示不出仪表盘。

```sh
# 检查
ls /etc/uci-defaults/ | grep gwrt

# 若有残留，手动补跑关键三个
sh /etc/uci-defaults/33_gwrt-dashboard   # 仪表盘入口（最重要）
sh /etc/uci-defaults/37_gwrt-dhcp-fp     # DHCP 设备指纹
sh /etc/uci-defaults/36_gwrt-clients-init # 设备守护
```

> 安装时若报 `trying to overwrite ... owned by ...`（如 `samba4-server` 占用同名 hotplug 文件），
> 加 `--force-overwrite` 即可，不影响功能。

## 配套插件

主题**不强制依赖**任何插件，缺失时对应卡片自动降级。请按需自行获取：

| 插件 | 用途 | 缺失后果 | 获取方式 |
|---|---|---|---|
| `bandix-plus`<br>`luci-app-bandix-plus` | 流量统计 | 「网速-EQoS」卡片无速率、连接排行空白 | 固件源；或 <https://github.com/timsaya/bandix-plus> |
| `coremark` | CPU 跑分 | 无「点击运行 CoreMark」按钮 | 固件源（`coremark`）；上游 <https://github.com/eembc/coremark> |
| `ttyd`<br>`luci-app-ttyd` | Web 终端 | 概览网格无「Terminal」图标 | 固件源；上游 <https://github.com/tsl0922/ttyd> / <https://github.com/openwrt/luci> |
| `appfilter`<br>`luci-app-oaf`<br>`kmod-oaf` | 应用过滤 | 「活跃 App」为空 | 固件源；`kmod-oaf` 为内核模块，**必须匹配目标机型内核版本** |

一键尝试安装（只从**你设备已配置的固件源**取，源里没有会打印上游地址）：

```sh
wget -O- https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/install-plugins.sh | sh

# 只看清单不安装
wget -O- https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/install-plugins.sh | sh -s -- -n
```

固件源里没有的插件，请自行下载**对应架构**的包后本地安装：

```sh
apk add --allow-untrusted <包文件>     # apk
opkg install <包文件>                   # opkg
```

## 校验

```sh
sha256sum -c luci-theme-gwrt-1.0-r111.apk.sha256
```

## 兼容性

| 项目 | 说明 |
|---|---|
| 包格式 | `.apk`（apk-tools 3.x）—— 适用于 ImmortalWrt 24.10+ / OpenWrt main |
| 老版本 OpenWrt（opkg） | 本目录未提供 `.ipk`；请用 `scripts/integrate.sh` 集成编译，或从对应固件源获取 |
| 架构 | 主题包为 `noarch`（纯 ucode/JS/CSS），**任意架构通用** |
| 依赖 | `luci-base` |
| 已验证 | JDCloud 雅典娜 AX6600（RE-CS-02，aarch64_cortex-a53，ImmortalWrt 6.18.52） |

> 主题包不含 OTA（固件在线升级）功能，升级固件请走各固件自身的 OTA 通道。
>
> 本仓库**不含任何第三方应用特征数据库**（如 OpenAppFilter 的 `feature.bin`），
> 也不含被改写并强制覆盖的第三方 LuCI 视图。应用过滤相关能力由主题通过标准
> ubus 接口可选探测，需该功能请自行从你所用固件的 package 源安装。
