#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TREE="$(CDPATH= cd -- "$PROJECT_DIR/.." && pwd)"
CHECK_ONLY=0
RUN_DEFCONFIG=1

usage() {
	cat <<'EOF'
Usage: integrate.sh [--tree DIR] [--check] [--no-defconfig]

  --tree DIR       ImmortalWrt/OpenWrt source root (default: project parent)
  --check          Verify package copies, overlays and config without writing
  --no-defconfig   Sync and merge .config without running make defconfig
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--tree)
			[ "$#" -ge 2 ] || { usage >&2; exit 2; }
			TREE="$2"
			shift 2
			;;
		--check)
			CHECK_ONLY=1
			shift
			;;
		--no-defconfig)
			RUN_DEFCONFIG=0
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

TREE="$(CDPATH= cd -- "$TREE" && pwd)"
THEME_SRC="$PROJECT_DIR/theme/luci-theme-gwrt"
THEME_DST="$TREE/package/gwrt-theme/luci-theme-gwrt"
NESTED_DST="$THEME_DST/luci-theme-gwrt"
OVERLAY_SRC="$PROJECT_DIR/overlays"
OVERLAY_LIST="$PROJECT_DIR/manifest/overlay-files.txt"
CONFIG_FRAGMENT="$PROJECT_DIR/manifest/config.fragment"

fail() {
	echo "gwrt-theme: $*" >&2
	exit 1
}

[ -f "$TREE/rules.mk" ] || fail "$TREE is not an OpenWrt source root"
[ -f "$TREE/feeds/luci/luci.mk" ] || fail "feeds/luci/luci.mk is missing"
[ -f "$THEME_SRC/Makefile" ] || fail "canonical theme source is missing"
[ -d "$THEME_SRC/htdocs" ] || fail "canonical htdocs directory is missing"
[ -d "$THEME_SRC/root" ] || fail "canonical root directory is missing"
[ -f "$CONFIG_FRAGMENT" ] || fail "config fragment is missing"
[ -f "$OVERLAY_LIST" ] || fail "overlay manifest is missing"

check_copy() {
	cmp -s "$THEME_SRC/Makefile" "$1/Makefile" || return 1
	diff -qr "$THEME_SRC/htdocs" "$1/htdocs" >/dev/null || return 1
	diff -qr "$THEME_SRC/root" "$1/root" >/dev/null || return 1
}

check_overlays() {
	while IFS= read -r rel || [ -n "$rel" ]; do
		case "$rel" in ''|'#'*) continue ;; esac
		cmp -s "$OVERLAY_SRC/$rel" "$TREE/$rel" || return 1
	done < "$OVERLAY_LIST"
}

check_config() {
	[ -f "$TREE/.config" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in ''|'#'*) continue ;; esac
		grep -Fqx "$line" "$TREE/.config" || return 1
	done < "$CONFIG_FRAGMENT"
}

check_legacy_dashboard() {
	! grep -Eq 'injectDashboard|buildDashboardHTML|__gwrtDashboard' \
		"$THEME_SRC/htdocs/luci-static/gwrt/resources/gwrt.js"
}

check_source_residue() {
	! find "$THEME_SRC" -type f \( \
		-name '*.bak' -o -name '*.bak-*' -o -name '*.bak-src' -o \
		-name '*.orig' -o -name '*.old' -o -name '*~' \
	\) -print -quit | grep -q .
}

check_legacy_dashboard || fail "obsolete dashboard injector is present in canonical source"
check_source_residue || fail "backup or editor residue is present in canonical source"

if [ "$CHECK_ONLY" -eq 1 ]; then
	check_copy "$THEME_DST" || fail "flat theme package differs from canonical source"
	check_copy "$NESTED_DST" || fail "nested theme package differs from canonical source"
	check_overlays || fail "one or more compatibility overlays differ"
	check_config || fail ".config does not contain the required theme fragment"
	echo "gwrt-theme: source copies, overlays and config are synchronized"
	exit 0
fi

case "$THEME_DST" in
	"$TREE"/package/gwrt-theme/luci-theme-gwrt) ;;
	*) fail "refusing unsafe theme destination: $THEME_DST" ;;
esac

mkdir -p "$THEME_DST" "$NESTED_DST"

for dst in "$THEME_DST" "$NESTED_DST"; do
	rm -rf "$dst/htdocs" "$dst/root"
	mkdir -p "$dst/htdocs" "$dst/root"
	cp -a "$THEME_SRC/htdocs/." "$dst/htdocs/"
	cp -a "$THEME_SRC/root/." "$dst/root/"
	cp "$THEME_SRC/Makefile" "$dst/Makefile"
done

while IFS= read -r rel || [ -n "$rel" ]; do
	case "$rel" in ''|'#'*) continue ;; esac
	[ -f "$OVERLAY_SRC/$rel" ] || fail "missing overlay: $rel"
	mkdir -p "$(dirname -- "$TREE/$rel")"
	cp "$OVERLAY_SRC/$rel" "$TREE/$rel"
done < "$OVERLAY_LIST"

[ -f "$TREE/.config" ] || fail "$TREE/.config is missing; select a hardware profile first"
[ -x "$TREE/scripts/kconfig.pl" ] || fail "scripts/kconfig.pl is unavailable"

tmp="$TREE/.config.gwrt-theme.$$"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
"$TREE/scripts/kconfig.pl" + "$TREE/.config" "$CONFIG_FRAGMENT" > "$tmp"
mv "$tmp" "$TREE/.config"
trap - EXIT HUP INT TERM

if [ "$RUN_DEFCONFIG" -eq 1 ]; then
	make -C "$TREE" defconfig
fi

check_copy "$THEME_DST" || fail "flat theme verification failed after sync"
check_copy "$NESTED_DST" || fail "nested theme verification failed after sync"
check_overlays || fail "overlay verification failed after sync"
check_config || fail "required config values were not retained"

echo "gwrt-theme: integration complete"
