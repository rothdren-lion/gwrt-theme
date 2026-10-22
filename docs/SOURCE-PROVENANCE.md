# gwrt-theme-V3 源码来源说明

拉取时间：2026-09-27  ·  目标版本：**luci-theme-gwrt 1.0-r92**

## 三个来源合并

| 来源 | 提供内容 | 份额 |
|---|---|---|
| 路由器 `root@192.168.9.9`（运行时 r92，apk 清单 752 条） | 主体运行文件：css/js/fonts/img(600 app_icons+brands+containers)/ucode 模板/acl/clients.sh/libexec/hotplug/init.d/cgi-bin | 741 个（tar 拉取，排除 `*.bak.*`、`/etc/config/gwrt`、`luci.disabled` 运行时态） |
| 同机 **`/rom`**（固件 squashfs 原始副本） | 路由器上已被执行删除的 9 个 `etc/uci-defaults/*` + `etc/config/{gwrt,luci.disabled}` 默认值 | 11 个 |
| 本地 `~/gwrt-theme-project`（r82） | 构建骨架：`Makefile`(已改 `PKG_RELEASE:=92`)、`README.md`、`manifest/`、`scripts/`、`overlays/`、`VERSION`、`ax6600.conf.example` | 6 项 |

## 校验

- 包清单 750 条（排除 `.bak` 与 2 个运行时配置）**逐条比对：缺失 0**
- 与路由器 md5 抽验 6/6 一致（`cascade.css` `gwrt.js` `menu-i18n.js` `index_gwrt.ut` `acl json` `clients.sh`）
- 包体积 2.73 MB ≈ apk 数据库记录 `S:2728962`

## 已知处理

- `docs/not-in-r92-package/34_gwrt-gecoosac-apk`：r82 本地树里有、**r92 包清单没有**，已移出包树避免污染打包
- `/www/luci-static/gwrt/css/cascade.css.bak.*`、`index_gwrt.ut.bak.*`、`sysauth.ut.bak.*`：路由器上的编辑备份，未纳入
- `root/usr/share/gwrt/theme-version`：由 Makefile 的 `Build/Prepare` 在编译时生成 `$(PKG_VERSION)-r$(PKG_RELEASE)`，不随包分发

## 版本对照

| 位置 | 版本 | cascade.css md5 |
|---|---|---|
| 本目录（新） | r92 | `c3ac5407d00ccfb56e3659b2b06dd6e1`（= 9/24 部署版） |
| `~/gwrt-theme-project` | r82 | `36622ffd44277a6c08e26d1e5a68bcdd`（8/5，旧） |
| 磁盘恢复件 `~/gwrt-recovery/FINAL/theme-css` | 中间态 | `5bc533c8` / `6d2f2551` / `89d13725`（三版历史） |

---

## 与路由器 192.168.9.9 的一致性验证（2026-09-27 第二轮）

| 检查项 | 结果 |
|---|---|
| **[A] apk 包清单逐文件 md5** | **743 / 743 完全一致** |
| **[B] 主题自有命名空间文件在树内** | **729 / 729，缺失 0**（`/www/luci-static/gwrt/**`、`themes/gwrt/**`、`/usr/share/gwrt/**`、acl json） |
| **[C] 反向：树内多出的文件** | 仅 10 个 = 9 个 `etc/uci-defaults/*`（路由器执行后已删，取自 `/rom`）+ `Makefile`（构建元数据） |

### 第二轮补充的内容

- `img/plugin_icons/{easytier,passwall,podman,smartdns,wireguard}.png` 5 个：
  在路由器主题目录内，但**不属于任何 apk 包**（`grep -l` 全包无归属）→ 判定为随主题使用的图标，纳入源码树
- `etc/config/gwrt` 改用**路由器运行中实际值**（1241 B，含设备标注/OTA 通道）；
  `/rom` 出厂默认（248 B）存档于 `docs/router-state/etc-config-gwrt.rom-default`
- 路由器上的 4 个编辑备份存档于 `docs/router-backups/`（不进包树）：
  `cascade.css.bak.20260922` `cascade.css.bak.20260923` `sysauth.ut.bak.20260923` `index_gwrt.ut.bak.20260922`

### 结论

**源码树 = 当前 192.168.9.9 上运行的主题（r92）逐字节一致**，另含 9 个原始 uci-defaults 与 Makefile 使其可编译。

---

## 开源版 r110（2026-10-22）

本仓库发布的是 **r110**，基于构建树 `package/gwrt-theme/luci-theme-gwrt` 的 **r109** 制作，
相对 r109 做了三项面向公开发布的改动：

| 改动 | 说明 |
|---|---|
| **移除 OTA 功能** | 删除 `usr/libexec/gwrt-ota`、`etc/uci-defaults/32_gwrt-ota-github-hosts`；移除 `31_luci-theme-gwrt` 中的 OTA manifest 配置；剥离 `index_gwrt.ut` 中全部 OTA JS（约 7.7 KB）与仪表盘固件卡片上的升级按钮；移除 rpcd ACL 中的 `/usr/libexec/gwrt-ota` 条目；清理 `cascade.css` 中的 `.gwrt-ota-*` 样式；footer 链接由 `gwrt-ota` 仓库改指本仓库 |
| **脱敏 `etc/config/gwrt`** | 原文件含 9 条真实设备的 MAC 标注（Sony-TV / chuangmi_camera / Kinder5 / ESP32-BSM 等），公开发布版仅保留出厂默认段（usb_lan / theme / he），设备标注需由使用者自行配置 |
| **版本号 +1** | `PKG_RELEASE` 109 → 110，便于区分开源版与内部版 |

其余 770+ 文件与 r109 逐字节一致（含 r109 新增的 DNS 急救 `gwrt-dns-rescue`、
WiFi 首启配置 `38/39/40b`、swap 初始化 `40a`、挂载策略 `45` 等）。

配套插件包随仓库 `release/plugins/` 一并提供，详见 `docs/PLUGINS.md`。
