#!/bin/sh
# GWRT Theme — 一键安装配套插件
#
# 用法（在路由器上执行）:
#   wget -O- https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release/install-plugins.sh | sh
#   或本地: sh install-plugins.sh
#
# 覆盖：apk (ImmortalWrt 24.10+/OpenWrt main) 与 opkg (老版本) 两种包管理器。
# 插件包本体位于本脚本同目录的 plugins/ 下；也可用 -u <url> 指定远程仓库根地址。

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE_BASE="https://raw.githubusercontent.com/rothdren-lion/gwrt-theme/main/release"

usage() {
	cat <<'EOF'
用法: sh install-plugins.sh [-u <release仓库URL>] [-h]

  -u <url>   release 目录的远程地址（默认 GitHub raw）
  -h         显示帮助

可安装的插件（缺失时主题会自动降级，不影响主题本体）:
  luci-app-oaf        应用过滤（App Filter）— 仪表盘「活跃 App」依赖
  kmod-oaf            OAF 内核模块 — 需按机型从固件源获取
  bandix-plus         流量统计 — 仪表盘「网速/连接排行」依赖
  luci-app-bandix-plus
  coremark            CPU 跑分 — 仪表盘「点击运行 CoreMark」依赖
  ttyd / luci-app-ttyd  Web 终端
  appfilter           应用特征库
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-u) REMOTE_BASE="$2"; shift 2 ;;
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

# ── 架构探测（决定是否安装二进制插件）────────────────────────
detect_arch() {
	apk --print-arch 2>/dev/null || opkg print-architecture 2>/dev/null || echo unknown
}
ARCH="$(detect_arch)"
log "系统架构：$ARCH"

# ── 依赖插件清单 ────────────────────────────────────────────
# 必需（仪表盘核心数据依赖）: oaf / bandix-plus
# 可选: coremark / ttyd / openclash
REQUIRED_PLUGINS="luci-app-oaf luci-i18n-oaf-zh-cn bandix-plus luci-app-bandix-plus luci-i18n-bandix-plus-zh-cn appfilter"
OPTIONAL_PLUGINS="luci-app-ttyd luci-i18n-ttyd-zh-cn"
# 架构相关（仅 aarch64 有现成构建）
ARCH_PLUGINS="ttyd coremark"

# ── 拉取辅助 ────────────────────────────────────────────────
fetch_pkg() {
	# $1=包名前缀  $2=子目录（"" 或 "aarch64/"）
	local name="$1" sub="${2:-}"
	local local_file="${BASE_DIR}/plugins/${sub}${name}"
	local url="${REMOTE_BASE}/plugins/${sub}"
	# 精确版本文件需要先查清单
	return 0
}

install_from_dir() {
	local dir="$1" prefix="$2"
	[ -d "$dir" ] || return 0
	local f
	for f in "$dir"/${prefix}-*.apk "$dir"/${prefix}-*.ipk; do
		[ -f "$f" ] || continue
		install_one "$f"
	done
}

install_one() {
	local f="$1"
	local bn
	bn="$(basename "$f")"
	case "$PM" in
		apk)  apk add --allow-untrusted "$f" >/dev/null 2>&1 && log "已安装 $bn" || log "跳过（失败）$bn" ;;
		opkg) opkg install "$f" >/dev/null 2>&1 && log "已安装 $bn" || log "跳过（失败）$bn" ;;
	esac
}

download_pkg() {
	# 从远程仓库拉一个包（需要 manifest 里给出精确文件名）
	local name="$1" sub="${2:-}"
	local fname="$3"
	local out="/tmp/gwrt-pkg-$fname"
	if [ -f "${BASE_DIR}/plugins/${sub}${fname}" ]; then
		cp "${BASE_DIR}/plugins/${sub}${fname}" "$out"
		return 0
	fi
	curl -fsSL -o "$out" "${REMOTE_BASE}/plugins/${sub}${fname}" 2>/dev/null || {
		log "下载失败: $fname"
		return 1
	}
	echo "$out"
}

# ── 主流程 ──────────────────────────────────────────────────
log "安装必需插件…"
for p in $REQUIRED_PLUGINS; do
	install_from_dir "${BASE_DIR}/plugins" "$p"
done

log "安装可选插件…"
for p in $OPTIONAL_PLUGINS; do
	install_from_dir "${BASE_DIR}/plugins" "$p"
done

if [ "$ARCH" = "aarch64_cortex-a53" ]; then
	log "检测到 aarch64，安装架构相关插件（ttyd / coremark）…"
	for p in $ARCH_PLUGINS; do
		install_from_dir "${BASE_DIR}/plugins/aarch64" "$p"
	done
else
	log "架构 $ARCH 暂无预编译的 ttyd/coremark，请从对应固件源安装："
	log "  opkg install ttyd coremark   # 或   apk add ttyd coremark"
fi

# ── 主题收尾：刷新 LuCI 缓存并重启相关服务 ──────────────────
log "刷新 LuCI 缓存…"
rm -f /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache/ 2>/dev/null || true

if [ -f /etc/init.d/gwrt-clients ]; then
	/etc/init.d/gwrt-clients restart 2>/dev/null || true
fi
if [ -f /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd reload 2>/dev/null || true
fi
if [ -f /etc/init.d/dnsmasq ]; then
	/etc/init.d/dnsmasq reload 2>/dev/null || true
fi

log "完成。刷新浏览器（Ctrl+F5）即可看到完整仪表盘。"
