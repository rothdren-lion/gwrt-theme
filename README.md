# GWRT Theme (luci-theme-gwrt)

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-ImmortalWrt%20%2F%20OpenWrt-informational)](https://openwrt.org)

一个为 **ImmortalWrt / OpenWrt (LuCI, ucode 模板)** 设计的现代 LuCI 主题，内置信息密集型仪表盘、应用图标识别、设备品牌指纹、EQoS 限速面板与固件 OTA 更新。

> 当前版本：`1.0-r92`（见 `VERSION`，由 `Makefile` 在编译期写入 `theme-version`）

---

## ✨ 特性

- **现代深/浅色双主题**：登录页与全站界面均支持一键切换，样式基于 CSS 变量（`cascade.css`）
- **仪表盘首页**（`admin_status/index_gwrt.ut`）：系统信息、CPU/温度、内存存储、活跃 App、连接设备、连接数、网口状态图、NTP 同步、CoreMark 跑分等聚合展示
- **应用图标识别**：内置 226 张 App 图标 + emoji 回退链（PNG → emoji → 分类 emoji → 📦），配合 OAF 应用过滤展示每个 App 的流量
- **设备品牌识别**：
  - `oui-vendors.json`：41 个品牌 / 8637 条 OUI 前缀
  - `clients.sh` 常驻守护 + `gwrt-dhcp-fp`（dnsmasq dhcp-script，option 60/55/61）采集设备指纹
- **EQoS 智能限速**：首页直接管理总上行/下行与单设备限速
- **OTA 固件更新**：对接 GitHub Releases 的 OTA manifest（`gwrt-ota`），支持型号/目标/通道校验
- **状态菜单图标化**：路由、防火墙、日志、进程、信道分析、实时图表等以图标形式并入概览网格
- **中英双语菜单 i18n**（`menu-i18n.js`）
- **DHCP 租约默认展开**、双端口双主题（80/443 端口可映射不同主题）等细节优化

## 📦 目录结构

```
.
├── theme/luci-theme-gwrt/     # 主题包源码（唯一编辑入口）
│   ├── htdocs/luci-static/gwrt/   # CSS / JS / 图标 / i18n
│   ├── root/usr/share/ucode/...   # ucode 模板（header / sysauth / 仪表盘）
│   ├── root/etc/uci-defaults/     # 首刷初始化脚本（30~44 号）
│   ├── root/etc/config/gwrt       # 默认配置（OTA 通道等）
│   └── Makefile                   # OpenWrt 包 Makefile（Apache-2.0）
├── overlays/                  # 配套补丁：OAF 应用过滤逐 App 勾选修复
├── manifest/config.fragment   # 固件侧主题相关功能包配置片段
├── scripts/integrate.sh       # 将主题源码同步进固件树并合并配置
├── scripts/build-with-theme.sh# 一键集成 + 编译
├── docs/SOURCE-PROVENANCE.md  # 源码来源与一致性校验说明
└── feature-db/feature.bin     # OAF 应用特征库
```

## 🚀 使用

### 集成到固件源码树

在 ImmortalWrt/OpenWrt 源码根目录执行：

```sh
# 集成（将 theme/luci-theme-gwrt 同步到 package/gwrt-theme/，合并 config.fragment）
./gwrt-theme/scripts/integrate.sh --tree .

# 只校验不写入
./gwrt-theme/scripts/integrate.sh --tree . --check

# 集成并编译（示例：6 线程）
taskset -c 0-5 ./gwrt-theme/scripts/build-with-theme.sh --tree . -j6
```

> 包装器不会切换硬件 profile，请先选好目标机型配置。

### 单独编译主题包

```sh
make package/luci-theme-gwrt/{clean,compile} -j$(nproc)
```

### 关键 uci-defaults

| 脚本 | 作用 |
|---|---|
| `30_gwrt-banner` | 用 `/etc/openwrt_release` + DTS model 生成 SSH 登录横幅，对齐首页固件版本卡片 |
| `31_luci-theme-gwrt` | 主题默认项与 OTA manifest 清理 |
| `36_gwrt-clients-init` | 启动 `gwrt-clients` 设备守护进程 |
| `37_gwrt-dhcp-fp` | 启用 dnsmasq 指纹钩子 |
| `44_gwrt-hostname` | 出厂主机名设为 `GWRT`（保留用户自定义） |

## 🔧 开发约定

- **只编辑 `theme/luci-theme-gwrt/`**，不要改固件树里生成的 `package/gwrt-theme/luci-theme-gwrt/` 副本；改完运行 `integrate.sh` 并用 `--check` 验证
- `clients.sh` 更新部署后需重启守护进程：`/etc/init.d/gwrt-clients restart`
- `Makefile` 的 `Build/Prepare` 会拒绝遗留的 dashboard injector 与备份文件，保证包内干净

## 📄 源码来源

`docs/SOURCE-PROVENANCE.md` 记录了本源码树的三个合并来源（运行中路由器拉取 + squashfs /rom 原始副本 + 本地构建骨架）以及与路由器运行版本的逐文件 md5 一致性验证结果。

## 📜 许可证

[Apache-2.0](LICENSE)（与上游 LuCI 保持一致）
