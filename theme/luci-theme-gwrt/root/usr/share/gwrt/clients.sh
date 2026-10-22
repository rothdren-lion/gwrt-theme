#!/bin/sh
# GWRT clients tracker — 持久化接入设备状态
#
# 用法:
#   clients.sh scan        # 扫一次 ARP+assoclist, 更新内存状态 + 必要时 flush JSON
#   clients.sh daemon      # 后台循环扫描 (init.d 用)
#   clients.sh cleanup-daily  # 凌晨 0:00 cron 调用, 清离线条目
#   clients.sh dump        # 输出当前 JSON (供前端 ubus 调用 / 调试)
#
# 数据存档: /etc/gwrt/clients.json
# 内存运行档: /tmp/gwrt-clients.json (高频更新避免伤 flash)
#
# JSON 格式:
# {
#   "updated": 1782480000,
#   "clients": [
#     {"mac":"aa:bb..","ip":"192.168.10.5","host":"phone","via":"wifi5g",
#      "online":true,"first_seen":1782470000,"last_seen":1782480000,"signal":-42}
#   ]
# }

. /lib/functions.sh 2>/dev/null

PERSIST=/etc/gwrt/clients.json
RUNTIME=/tmp/gwrt-clients.json
WWWLINK=/www/gwrt-clients.json   # uhttpd 暴露给前端 fetch
PERSIST_DIR=/etc/gwrt
FLUSH_INTERVAL=300   # 5min flush to flash
SCAN_INTERVAL=30     # 30s scan tick

mkdir -p "$PERSIST_DIR"

# 把 RUNTIME 不存在/损坏时从 PERSIST 恢复 (重启场景)
ensure_runtime() {
	if [ ! -s "$RUNTIME" ] || ! jsonfilter -i "$RUNTIME" -e '@.updated' >/dev/null 2>&1; then
		if [ -s "$PERSIST" ] && jsonfilter -i "$PERSIST" -e '@.updated' >/dev/null 2>&1; then
			cp "$PERSIST" "$RUNTIME"
		else
			echo '{"updated":0,"clients":[]}' > "$RUNTIME"
		fi
	fi
}

# 当前活跃 MAC 集合 = ARP REACHABLE/DELAY/STALE + WiFi assoclist
#
# ⚠️ 本固件没有 iwinfo CLI（只装了 libiwinfo + rpcd-mod-iwinfo），
# 所以 WiFi 必须走 ubus：
#   ubus call iwinfo info      '{"device":"phy0-ap0"}'   → frequency / mode
#   ubus call iwinfo assoclist '{"device":"phy0-ap0"}'   → results[].mac / signal
# 旧实现用 `iwinfo "$phy" info|assoclist`，命令不存在导致 WiFi 段静默全失败，
# 无线客户端只能被 ARP 分支兜底标成 wired —— 这就是 via 列看不到 WiFi 的根因。
collect_active() {
	# ARP-based: REACHABLE/DELAY/STALE 都算 (PROBE/FAILED 排除)
	ip neigh show 2>/dev/null | awk '
		/lladdr/ && /(REACHABLE|DELAY|STALE)/ && !/FAILED/ {
			ip=$1; mac=""; for(i=1;i<=NF;i++) if($i=="lladdr") mac=$(i+1)
			if (mac && ip !~ /^(fe80|ff)/) print tolower(mac)"|"ip"|wired"
		}'

	# WiFi: 遍历 hostapd interface（经 ubus，不依赖 iwinfo CLI）
	for phy in $(ubus list 'hostapd.*' 2>/dev/null | cut -d. -f2); do
		[ -z "$phy" ] && continue

		# 频段判定：用 frequency(MHz) 换算，比解析 iwinfo 文案更可靠
		# 5G 再细分：5150-5350=5.2G(5gl)，5470-5895=5.8G(5gh)
		info=$(ubus call iwinfo info "{\"device\":\"$phy\"}" 2>/dev/null)
		freq=$(printf '%s' "$info" | jsonfilter -e '@.frequency' 2>/dev/null)
		case "$freq" in ''|*[!0-9]*) freq=0 ;; esac
		if   [ "$freq" -ge 5925 ] 2>/dev/null; then tag="wifi6g"
		elif [ "$freq" -ge 5470 ] 2>/dev/null; then tag="wifi5gh"
		elif [ "$freq" -ge 4900 ] 2>/dev/null; then tag="wifi5gl"
		elif [ "$freq" -ge 2400 ] 2>/dev/null; then tag="wifi24g"
		else
			tag="wifi"
			# 频率取不到时退回接口名约定 (双 5G 设备 re-cs-02: phy0=5.2G, phy2/3=5.8G)
			case "$phy" in *phy2*|*phy3*) tag="wifi5gh" ;; esac
		fi

		ubus call iwinfo assoclist "{\"device\":\"$phy\"}" 2>/dev/null | awk -v t="$tag" '
			# 注意：ubus JSON 里 "mac" 与 "signal" 分处两行，不能在同一行内取值，
			# 否则 signal 永远为空。用下标数组按条目配对，END 再输出。
			$1 == "\"mac\":"    { v=$2; gsub(/[",]/, "", v); n++; mac[n]=tolower(v) }
			$1 == "\"signal\":" { v=$2; gsub(/[",]/, "", v); sig[n]=v }
			END {
				for (i = 1; i <= n; i++)
					if (mac[i] ~ /^[0-9a-f][0-9a-f](:[0-9a-f][0-9a-f]){5}$/)
						# 必须保持 4 段 mac|ip|via|sig（ip 用 - 占位），
						# 合并阶段按 mac|ip|via|sig 解析，缺一段会整体错位
						print mac[i]"|-|"t"|"sig[i]
			}'
	done
}

# === WAN 信息采集 (ISP 检测 / 光猫 / 上级路由) ===
collect_wan_info() {
	local def_route gateway iface wan_ip wan_type is_private gw_reachable
	local isp="未知" is_combo="false"
	def_route=$(ip route show default 2>/dev/null)
	gateway=$(echo "$def_route" | awk '/default via/{print $3}')
	iface=$(echo "$def_route" | awk '/dev/{print $5}')
	wan_ip=""; wan_type="none"; is_private="false"; gw_reachable="false"

	if [ -n "$iface" ]; then
		case "$iface" in
			pppoe-*) wan_type="pppoe" ;;
			*)       wan_type="dhcp"  ;;
		esac
		wan_ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)

		case "$wan_ip" in
			10.*|172.1[6-9]*|172.2[0-9]*|172.3[0-1]*|192.168.*)
				is_private="true"
				wan_type="dhcp"
				;;
		esac

		ping -c 1 -W 1 "$gateway" >/dev/null 2>&1 && gw_reachable="true"

		# ── ISP 检测 ──
		# 1) PPPoE AC name (AC 名常含 ISP 标识)
		if [ "$wan_type" = "pppoe" ]; then
			local ac_name
			ac_name=$(cat /proc/net/pppoe 2>/dev/null | head -1 | awk '{print $1}')
			case "$ac_name" in
				*CT*|*CHINANET*|*CHINATELECOM*) isp="电信" ;;
				*CU*|*UNICOM*|*CNC*)            isp="联通" ;;
				*CM*|*CMCC*|*CHINAMOBILE*)      isp="移动" ;;
			esac
		fi

		# 2) DNS 服务器 IP 匹配
		if [ "$isp" = "未知" ]; then
			local dns_servers
			dns_servers=$(awk '/^nameserver/{print $2}' /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null | tr '\n' ' ')
			for dns in $dns_servers; do
				case "$dns" in
					114.114.*|180.76.*|1.2.4.*|210.22.*|218.*) isp="电信"; break ;;
					123.123.*|124.124.*|210.21.*)               isp="联通"; break ;;
					211.136.*|221.130.*|120.196.*|211.137.*)    isp="移动"; break ;;
				esac
			done
		fi

		# 3) 网关 IP 范围兜底
		if [ "$isp" = "未知" ] && [ -n "$gateway" ]; then
			local gw_octet
			gw_octet=$(echo "$gateway" | cut -d. -f1)
			case "$gw_octet" in
				61|116|180|183|218|219|222) isp="电信" ;;
				60|124|210)                 isp="联通" ;;
				111|112|117|211|223)        isp="移动" ;;
			esac
		fi

		# 猫路由一体: 私有 IP 或 PPPoE 猫路由合一场景
		[ "$is_private" = "true" ] && is_combo="true"
	fi

	# ── 桥接成员 (物理 LAN 口 + WiFi radio) ──
	local bridge_members="[]"
	local br_json
	br_json=$(ubus call network.device status '{"name":"br-lan"}' 2>/dev/null)
	if [ -n "$br_json" ]; then
		bridge_members=$(echo "$br_json" | jsonfilter -e '@["bridge-members"]' 2>/dev/null)
		[ -z "$bridge_members" ] && bridge_members="[]"
	fi

	printf '{"type":"%s","ip":"%s","gateway":"%s","gateway_reachable":%s,"is_private":%s,"isp":"%s","is_combo":%s,"bridge_members":%s}' \
		"$wan_type" "${wan_ip:-}" "${gateway:-}" "$gw_reachable" "$is_private" "$isp" "$is_combo" "$bridge_members"
}

# === 端口指纹（后台异步探测，结果缓存到 /tmp/gwrt-portfp.list: mac|os） ===
# 用途：DHCP option 指纹拿不到时，用设备开放端口推断系统（如 fnOS 的 5666/5667）。
# 设计：探测在后台跑（每个 MAC 只探一次并缓存），不阻塞 30s 扫描节拍。
probe_ports_async() {
	local active="$1"
	local cache=/tmp/gwrt-portfp.list out=/tmp/gwrt-portfp.lock
	[ -f "$cache" ] || : > "$cache"
	[ -f "$out" ] && return 0   # 上一轮模拟探完再说
	: > "$out"
	(
		n=0
		printf '%s\n' "$active" | while IFS='|' read -r mac ip via sig; do
			[ -n "$mac" ] || continue
			[ -n "$ip" ] && [ "$ip" != "-" ] || continue
			grep -q "^$mac|" "$cache" 2>/dev/null && continue
			n=$((n+1)); [ "$n" -gt 6 ] && break
			os=""
			if nc -z -w 1 "$ip" 5666 2>/dev/null || nc -z -w 1 "$ip" 5667 2>/dev/null; then
				os=fnos                       # fnOS Web UI
			else
				# SSH banner 在认证前明文返回，无需密码，可直接读出发行版
				banner=$(nc -w 2 "$ip" 22 </dev/null 2>/dev/null | head -c 160)
				lb=$(printf '%s' "$banner" | tr 'A-Z' 'a-z')
				case "$lb" in
					*ubuntu*) os=ubuntu ;;
					*ssh-*)   os=linux  ;;
				esac
			fi
			printf '%s|%s\n' "$mac" "$os" >> "$cache"
		done
		rm -f "$out"
	) >/dev/null 2>&1 &
}

# === scan 模式: 扫描一次,更新 RUNTIME ===
do_scan() {
	ensure_runtime

	local now=$(date +%s)
	local active_list active_macs wan_info
	active_list=$(collect_active)
	wan_info=$(collect_wan_info)
	active_macs=$(echo "$active_list" | awk -F'|' '{print $1}' | sort -u)

	# 读当前已知 clients
	local existing_json
	existing_json=$(cat "$RUNTIME" 2>/dev/null)
	[ -z "$existing_json" ] && existing_json='{"updated":0,"clients":[]}'

	# 加载 DHCP leases (从 /tmp/dhcp.leases)
	local dhcp_data=""
	[ -r /tmp/dhcp.leases ] && dhcp_data=$(awk '{print tolower($2)"|"$3"|"$4}' /tmp/dhcp.leases)

	# DHCP 指纹 (option 60/55, dnsmasq dhcp-script 写入): mac|os|vendor|options
	local fp_data=""
	[ -r /tmp/gwrt-dhcp-fp.list ] && fp_data=$(cat /tmp/gwrt-dhcp-fp.list)

	# 端口指纹（fnOS 5666/5667）：异步探测 + 缓存，只补 DHCP 未识别的
	probe_ports_async "$active_list"
	local portfp_data=""
	[ -r /tmp/gwrt-portfp.list ] && portfp_data=$(cat /tmp/gwrt-portfp.list)
	local fp_clean fp_combined
	fp_clean=$(printf '%s\n' "$fp_data" | grep -v '|unknown|')
	# 端口在前、DHCP 在后：同 MAC 时 DHCP 覆盖端口推断
	fp_combined=$(printf '%s\n%s\n' "$portfp_data" "$fp_clean")

	# ── 桥端口映射 (mac → 物理端口名) ──
	local bridge_port_data=""
	if command -v brctl >/dev/null 2>&1 && [ -d /sys/class/net/br-lan/brif ]; then
		# 端口编号(hex)→ decimal → 接口名 (用 shell 转换)
		local pmap_dec=""
		for f in /sys/class/net/br-lan/brif/*; do
			local iface=$(basename "$f")
			local pn=$(cat "$f/port_no" 2>/dev/null)
			[ -n "$pn" ] && pn_dec=$((pn)) 2>/dev/null && pmap_dec="${pmap_dec}${pn_dec}|${iface}\n"
		done
		bridge_port_data=$(brctl showmacs br-lan 2>/dev/null | awk -v pm="$pmap_dec" '
			BEGIN {
				n = split(pm, plines, /\n/)
				for (i = 1; i <= n; i++) {
					split(plines[i], a, "|")
					if (a[1]) pmap[a[1]] = a[2]
				}
			}
			/^[[:space:]]*[0-9]+[[:space:]]/ && !/yes/ {
				mac = tolower($2); port_no = $1 + 0  # 强转 numeric
				if (pmap[port_no]) print mac"|"pmap[port_no]
			}')
	fi

	# 用 awk 做合并 (省得调 jsonfilter 上百次)
	local merged
	merged=$(awk -v now="$now" -v existing="$existing_json" -v active="$active_list" -v dhcp="$dhcp_data" -v fp="$fp_combined" -v wan_json="$wan_info" -v port_data="$bridge_port_data" '
	BEGIN {
		# 解析 existing JSON (粗暴 regex, 适配我们已知格式)
		n = split(existing, eline, /\{"mac":"/)
		for (i = 2; i <= n; i++) {
			s = eline[i]
			mac = ""; host = ""; first = 0; last = 0; off_at = 0
			if (match(s, /^[^"]+/))                 { mac = substr(s, RSTART, RLENGTH) }
			if (match(s, /"host":"[^"]*"/))         { host = substr(s, RSTART+8, RLENGTH-9) }
			if (match(s, /"first_seen":[0-9]+/))    { first = substr(s, RSTART+13, RLENGTH-13)+0 }
			if (match(s, /"last_seen":[0-9]+/))     { last = substr(s, RSTART+12, RLENGTH-12)+0 }
			if (match(s, /"offline_at":[0-9]+/))    { off_at = substr(s, RSTART+13, RLENGTH-13)+0 }
			if (mac) {
				e_first[mac] = first
				e_last[mac]  = last
				e_off[mac]   = off_at
				e_host[mac]  = host
			}
		}

		# DHCP leases (ip + hostname 补全)
		n = split(dhcp, dline, "\n")
		for (i = 1; i <= n; i++) {
			split(dline[i], a, "|")
			if (a[1]) {
				d_ip[a[1]]   = a[2]
				d_host[a[1]] = a[3]
			}
		}

		# 解析 active
		n = split(active, aline, "\n")
		for (i = 1; i <= n; i++) {
			split(aline[i], a, "|")
			if (a[1]) {
				active_mac[a[1]] = 1
				if (a[2] != "-" && a[2] != "") a_ip[a[1]]  = a[2]
				a_via[a[1]] = a[3]
				a_sig[a[1]] = a[4]
				all_macs[a[1]] = 1
			}
		}
		# 解析桥端口数据 (mac → 物理端口名)
		n = split(port_data, pdline, "\n")
		for (i = 1; i <= n; i++) {
			split(pdline[i], a, "|")
			if (a[1]) port_of[a[1]] = a[2]
		}
		# 解析 DHCP 指纹 (mac → 系统特性)
		n = split(fp, fline, "\n")
		for (i = 1; i <= n; i++) {
			split(fline[i], fa, "|")
			if (fa[1]) f_os[fa[1]] = fa[2]
		}
		# 把 existing 里的 MAC 也加进 all_macs (保留离线设备)
		for (m in e_first) all_macs[m] = 1
		for (m in d_ip)    all_macs[m] = 1

		# 输出 JSON
		printf("{\"updated\":%d,\"wan\":%s,\"clients\":[", now, wan_json)
		first_entry = 1
		for (m in all_macs) {
			online = (m in active_mac) ? 1 : 0
			ip   = (m in a_ip)   ? a_ip[m]   : (m in d_ip ? d_ip[m] : "")
			via  = (m in a_via)  ? a_via[m]  : ""
			sig  = (m in a_sig)  ? a_sig[m]  : ""
			host = (m in d_host) ? d_host[m] : e_host[m]
			# 重连时重置 first_seen = now, 显示本次连接时长
			was_offline = (m in e_off) && e_off[m] > 0
			if (online && was_offline) {
				f = now
			} else {
				f = (m in e_first && e_first[m] > 0) ? e_first[m] : now
			}
			# online 模式: 持续更新 last_seen, 清空 offline_at
			# offline 模式: 保留 e_last, 首次掉线记录 offline_at
			if (online) {
				l = now
				off = 0
			} else {
				l = (m in e_last && e_last[m] > 0) ? e_last[m] : now
				off = (m in e_off && e_off[m] > 0) ? e_off[m] : now
			}
			if (!first_entry) printf(",")
			first_entry = 0
			# JSON 转义 host 里的特殊字符 (简化, 通常只有字母数字)
			gsub(/[\\"]/, "", host)
			port = (m in port_of) ? port_of[m] : ""
			printf("{\"mac\":\"%s\",\"ip\":\"%s\",\"host\":\"%s\",\"via\":\"%s\",\"port\":\"%s\",\"online\":%s,\"first_seen\":%d,\"last_seen\":%d,\"offline_at\":%d,\"signal\":\"%s\",\"os\":\"%s\"}",
				m, ip, host, via, port, (online ? "true" : "false"), f, l, off, sig, f_os[m])
		}
		printf("]}\n")
	}')

	# 写 RUNTIME
	echo "$merged" > "$RUNTIME.new"
	mv "$RUNTIME.new" "$RUNTIME"

	# 暴露给 uhttpd 让前端 fetch (/gwrt-clients.json)
	[ -L "$WWWLINK" ] || ln -sf "$RUNTIME" "$WWWLINK" 2>/dev/null
}

# === flush 模式: 把 RUNTIME 写到 PERSIST (5分钟一次,有 diff 才写) ===
do_flush() {
	[ ! -s "$RUNTIME" ] && return
	# 用 mtime 判断: 上次 flush 时间记录在 /tmp/gwrt-clients.flushed
	local last_flush=0
	[ -r /tmp/gwrt-clients.flushed ] && last_flush=$(cat /tmp/gwrt-clients.flushed)
	local now=$(date +%s)
	local gap=$((now - last_flush))
	[ "$gap" -lt "$FLUSH_INTERVAL" ] && return

	# diff 检测: 用 sha256 比较 clients 段
	local rsum psum
	rsum=$(sha256sum "$RUNTIME"  2>/dev/null | awk '{print $1}')
	psum=$(sha256sum "$PERSIST"  2>/dev/null | awk '{print $1}')
	if [ "$rsum" != "$psum" ]; then
		cp "$RUNTIME" "$PERSIST"
		echo "$now" > /tmp/gwrt-clients.flushed
	fi
}

# === cleanup-daily: 每天 0:00 cron 调用,清离线条目 ===
do_cleanup_daily() {
	ensure_runtime
	local now=$(date +%s)
	# 只保留 online=true 的条目, 全部 reset first_seen=now
	local cleaned
	cleaned=$(cat "$RUNTIME" | awk -v now="$now" '
		BEGIN { kept = 0 }
		{
			n = split($0, eline, /\{"mac":"/)
			printf("{\"updated\":%d,\"clients\":[", now)
			for (i = 2; i <= n; i++) {
				s = eline[i]
				if (s ~ /"online":true/) {
					# 重置 first_seen = now
					gsub(/"first_seen":[0-9]+/, "\"first_seen\":" now, s)
					gsub(/}.*/, "}", s)
					if (kept > 0) printf(",")
					printf("{\"mac\":\"%s", s)
					kept++
				}
			}
			printf("]}\n")
		}')
	echo "$cleaned" > "$RUNTIME.new"
	mv "$RUNTIME.new" "$RUNTIME"
	cp "$RUNTIME" "$PERSIST"
	echo $(date +%s) > /tmp/gwrt-clients.flushed

	# 顺手清内存缓存
	sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
}

# === dump: 输出当前 JSON ===
do_dump() {
	ensure_runtime
	cat "$RUNTIME"
}

# === daemon: 后台循环 ===
do_daemon() {
	# 启动时从 PERSIST 恢复
	ensure_runtime
	while :; do
		do_scan
		do_flush
		sleep "$SCAN_INTERVAL"
	done
}

case "$1" in
	scan)           do_scan ;;
	flush)          do_flush ;;
	cleanup-daily)  do_cleanup_daily ;;
	dump)           do_dump ;;
	daemon)         do_daemon ;;
	*)
		echo "Usage: $0 {scan|flush|cleanup-daily|dump|daemon}" >&2
		exit 1
		;;
esac
