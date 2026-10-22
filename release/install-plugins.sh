#!/bin/sh
# GWRT Theme — 配套插件安装助手
#
# 用法（在路由器上执行）:
#   wget -O- https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/install-plugins.sh | sh
#   或本地: sh install-plugins.sh
#
# 说明:
#   本仓库**不分发任何第三方插件二进制包**（避免再分发第三方作品）。
#   本脚本只做一件事：尝试从**你设备当前已配置的固件源**里安装所需插件。
#   源里没有的插件，会打印出上游项目地址与获取方法，请自行下载对应架构的包。
#
# 覆盖 apk (ImmortalWrt 24.10+ / OpenWrt main) 与 opkg (老版本) 两种包管理器。

set -e

usage() {
	cat <<'EOF'
用法: sh install-plugins.sh [-n] [-h]

  -n         只列出插件与获取方式，不执行安装
  -h         显示帮助

插件清单（全部可选，缺失时主题自动降级，不影响主题本体）:
  bandix-plus + luci-app-bandix-plus   流量统计  → 仪表盘「网速/连接排行」
  coremark                             CPU 跑分   → 仪表盘「点击运行 CoreMark」
  ttyd + luci-app-ttyd                 Web 终端   → 概览网格「Terminal」

  appfilter / luci-app-oaf / kmod-oaf  应用过滤  → 仪表盘「活跃 App」
      ↑ 需自行从固件源获取；内核模块必须与目标机型内核版本匹配，不可跨架构
EOF
}

DRY_RUN=0
while [ "$#" -gt 0 ]; do
	case "$1" in
		-n|--dry-run) DRY_RUN=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "未知参数: $1"; usage; exit 1 ;;
	esac
done

log() { echo "[gwrt] $*"; }

# ── 包管理器探测 ────────────────────────────────────────────
if command -v apk >/dev/null 2>&1; then
	PM=apk
elif command -v opkg >/dev/null 2>&1; then
	PM=opkg
else
	log "错误：未找到 apk / opkg，无法安装插件"
	exit 1
fi
log "包管理器：$PM"

# ── 插件元数据 ──────────────────────────────────────────────
# 用法: "包名|用途|上游地址"
PLUGINS="
bandix-plus|流量统计守护（仪表盘网速/连接排行）|https://github.com/timsaya/bandix-plus
luci-app-bandix-plus|bandix-plus 的 LuCI 界面|https://github.com/timsaya/bandix-plus
coremark|CPU 跑分（仪表盘点击运行 CoreMark）|https://github.com/eembc/coremark
ttyd|Web 终端服务端|https://github.com/tsl0922/ttyd
luci-app-ttyd|Web 终端的 LuCI 界面|https://github.com/openwrt/luci
luci-i18n-ttyd-zh-cn|Web 终端中文包|https://github.com/openwrt/luci
luci-i18n-bandix-plus-zh-cn|bandix-plus 中文包|https://github.com/timsaya/bandix-plus
"

print_upstream_hint() {
	log "  ↳ 上游: $2"
	log "     若你的固件源没有该包，请自行下载对应架构的安装包后："
	log "     $PM add --allow-untrusted <包文件>   # apk"
	log "     opkg install <包文件>                 # opkg"
}

if [ "$DRY_RUN" -eq 1 ]; then
	echo "插件清单（不执行安装）:"
	echo "$PLUGINS" | while IFS='|' read -r name use url; do
		[ -n "$name" ] || continue
		printf '  %-26s %s\n' "$name" "$use"
		printf '  %-26s 上游: %s\n' "" "$url"
	done
	exit 0
fi

# ── 安装 ────────────────────────────────────────────────────
INSTALLED=0
MISSING=0

echo "$PLUGINS" | while IFS='|' read -r name use url; do
	[ -n "$name" ] || continue
	if $PM info -e "$name" >/dev/null 2>&1; then
		log "已安装，跳过: $name"
		continue
	fi
	log "安装: $name  ($use)"
	if $PM add "$name" >/dev/null 2>&1 || $PM install "$name" >/dev/null 2>&1; then
		log "  ✅ 成功"
	else
		log "  ⚠️ 固件源中没有该包，需自行下载安装"
		print_upstream_hint "$name" "$url"
	fi
done

# ── 收尾 ────────────────────────────────────────────────────
log "刷新 LuCI 缓存…"
rm -f /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache/ 2>/dev/null || true

[ -f /etc/init.d/gwrt-clients ] && /etc/init.d/gwrt-clients restart 2>/dev/null
[ -f /etc/init.d/rpcd ] && /etc/init.d/rpcd reload 2>/dev/null
[ -f /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq reload 2>/dev/null

log "完成。刷新浏览器（Ctrl+F5）即可看到完整仪表盘。"
log "提示：'活跃 App' 卡片需要应用过滤插件（appfilter / luci-app-oaf / kmod-oaf），"
log "      仓库不提供该类插件，请自行从固件源获取（内核模块须匹配机型内核版本）。"
