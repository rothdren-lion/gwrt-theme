include $(TOPDIR)/rules.mk

LUCI_TITLE:=GWRT Theme
LUCI_DEPENDS:=+luci-base

PKG_NAME:=luci-theme-gwrt
PKG_VERSION:=1.0
PKG_RELEASE:=111

# GWRT 2026-10-18: modal diet - default 880x76vh, drop backdrop-filter jank,
# pause 3s dashboard polling while a plugin modal is open.

# GWRT 2026-10-04: disable css minify for this package.
# csstidy 1.3 (2005) cannot parse color-mix() in gwrtDevFlash keyframes and
# silently truncates the css at that point, dropping ~4.5KB of trailing rules
# (incl. the layer-3 modal convention). +10KB uncompressed is acceptable.
LUCI_MINIFY_CSS:=0
PKG_MAINTAINER:=GWRT
PKG_LICENSE:=Apache-2.0

define Build/Prepare/luci-theme-gwrt
	@if grep -Eq 'injectDashboard|buildDashboardHTML|__gwrtDashboard' \
		$(PKG_BUILD_DIR)/htdocs/luci-static/gwrt/resources/gwrt.js; then \
		echo "ERROR: obsolete GWRT dashboard injector is present" >&2; \
		exit 1; \
	fi
	@test ! -e $(PKG_BUILD_DIR)/root/usr/share/ucode/luci/template/admin_status/index.ut.bak-src || { \
		echo "ERROR: obsolete GWRT dashboard backup is present" >&2; \
		exit 1; \
	}
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/root/usr/share/gwrt
	printf '%s\n' '$(PKG_VERSION)-r$(PKG_RELEASE)' > \
		$(PKG_BUILD_DIR)/root/usr/share/gwrt/theme-version
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/htdocs/luci-static/resources
	$(CP) $(PKG_BUILD_DIR)/htdocs/luci-static/gwrt/resources/menu-gwrt.js \
		$(PKG_BUILD_DIR)/htdocs/luci-static/resources/menu-gwrt.js
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
