# Release 目录说明

本目录提供**开箱即用**的预编译产物，让用户无需搭建固件编译环境也能装上主题。

```
release/
├── packages/                    # 主题包本体（已实测安装验证）
│   ├── luci-theme-gwrt-1.0-r110.apk
│   └── luci-theme-gwrt-1.0-r110.apk.sha256
├── plugins/                     # 配套插件（架构无关）
│   ├── appfilter-*.apk
│   ├── bandix-plus-*.apk
│   ├── luci-app-bandix-plus-*.apk
│   ├── luci-app-oaf-*.apk
│   ├── luci-app-ttyd-*.apk
│   └── luci-i18n-*.apk
├── plugins/aarch64/             # 架构相关二进制（ttyd / coremark）
│   ├── coremark-*.apk
│   └── ttyd-*.apk
├── plugins/optional/            # 大体积可选插件
│   └── luci-app-openclash-*.apk
└── install-plugins.sh           # 一键安装配套插件
```

## 一键装主题 + 插件（路由器上执行）

```sh
# 1. 装主题
wget -O /tmp/luci-theme-gwrt.apk \
  https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/packages/luci-theme-gwrt-1.0-r110.apk
apk add --allow-untrusted /tmp/luci-theme-gwrt.apk

# 2. 装配套插件
wget -O- https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/install-plugins.sh | sh

# 3. 清缓存 + 重载
rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload
/etc/init.d/gwrt-clients restart 2>/dev/null
```

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

## 校验

```sh
sha256sum -c luci-theme-gwrt-1.0-r110.apk.sha256
```

## 兼容性

| 项目 | 说明 |
|---|---|
| 包格式 | `.apk`（apk-tools 3.x）—— 适用于 ImmortalWrt 24.10+ / OpenWrt main |
| 老版本 OpenWrt（opkg） | 本目录未提供 `.ipk`；请自行用 `scripts/integrate.sh` 集成编译，或从对应固件源获取 |
| 架构 | 主题包为 `noarch`（纯 ucode/JS/CSS），**任意架构通用** |
| 依赖 | `luci-base` |
| 已验证 | JDCloud 雅典娜 AX6600（RE-CS-02，aarch64_cortex-a53，ImmortalWrt 6.18.52） |

> 主题包不含 OTA（固件在线升级）功能，升级固件请走各固件自身的 OTA 通道。
