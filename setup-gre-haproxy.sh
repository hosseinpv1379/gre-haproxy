#!/bin/bash
#
# GRE tunnel + HAProxy — multiple IRAN → one KHAREJ
# به یاد جان‌فداهای میهن
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CONFIG_FILE="/etc/gre-haproxy.conf"
RCLOCAL="/etc/rc.local"
GRE_MARKER_START="# gre-haproxy tunnels start"
GRE_MARKER_END="# gre-haproxy tunnels end"
TUNNEL_IFACE_IRAN="gre-haproxy"
TUNNEL_IFACE_KHAREJ_PREFIX="gre-haproxy"

tunnel_iran_ip() { echo "10.10.$((10 * $1)).1"; }
tunnel_kharej_ip() { echo "10.10.$((10 * $1)).2"; }
tunnel_cidr() { echo "10.10.$((10 * $1)).1/30"; }
tunnel_kharej_cidr() { echo "10.10.$((10 * $1)).2/30"; }

detect_my_ip() {
    local ip=""
    if command -v ip &>/dev/null; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1)
    fi
    if [ -z "$ip" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s --max-time 3 4.icanhazip.com 2>/dev/null || true)
    fi
    echo "$ip"
}

# Detect likely role from existing interfaces (hint only)
detect_role_hint() {
    if ip link show "${TUNNEL_IFACE_KHAREJ_PREFIX}1" &>/dev/null; then echo "kharej"; return; fi
    if ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then echo "iran"; return; fi
    echo ""
}

print_panel() {
    echo ""
    echo -e "  ${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}   ${BOLD}${GREEN}GRE Tunnel + HAProxy${NC}   ${DIM}— multi-IRAN to one KHAREJ${NC}           ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}   ${DIM}In memory of the martyrs of the homeland${NC}                    ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}   ${DIM}(be yad-e janfaday-e mihan)${NC}                                 ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

if [ "$EUID" -ne 0 ]; then
    print_panel
    echo -e "  ${RED}This script must be run as root.${NC}"
    echo -e "  ${YELLOW}Run: ${NC}sudo bash $0"
    echo ""
    exit 1
fi

MY_IP=$(detect_my_ip)
ROLE_HINT=$(detect_role_hint)

print_panel

if [ -n "$MY_IP" ]; then
    echo -e "  ${DIM}This server IP:${NC} ${CYAN}${MY_IP}${NC}"
    if [ -n "$ROLE_HINT" ]; then
        [ "$ROLE_HINT" = "kharej" ] && echo -e "  ${DIM}Current role:${NC} ${GREEN}KHAREJ${NC} — tunnels active"
        [ "$ROLE_HINT" = "iran" ]   && echo -e "  ${DIM}Current role:${NC} ${GREEN}IRAN${NC} — tunnel active"
    fi
    echo ""
fi

echo -e "  ${BOLD}Menu:${NC}"
echo -e "  ${CYAN}  ┌─ Setup ────────────────────────────────────${NC}"
echo -e "  ${CYAN}  │${NC}  ${GREEN}1${NC}) IRAN      — Setup tunnel on this server"
echo -e "  ${CYAN}  │${NC}  ${GREEN}2${NC}) KHAREJ   — Add one IRAN server"
echo -e "  ${CYAN}  ├─ Manage ───────────────────────────────────${NC}"
echo -e "  ${CYAN}  │${NC}  ${YELLOW}3${NC}) Remove   — Remove tunnels / HAProxy"
echo -e "  ${CYAN}  │${NC}  ${YELLOW}4${NC}) Status  — Show tunnel and HAProxy status"
echo -e "  ${CYAN}  │${NC}  ${YELLOW}5${NC}) iperf3   — Bandwidth test (IRAN → KHAREJ)"
echo -e "  ${CYAN}  │${NC}  ${YELLOW}6${NC}) HAProxy  — Add port forwarding (IRAN only)"
echo -e "  ${CYAN}  └──────────────────────────────────────────${NC}"
echo ""
read -p "  Choice (1-6): " side_choice

case "$side_choice" in
    1) SIDE="iran";;
    2) SIDE="kharej";;
    3) SIDE="remove";;
    4) SIDE="status";;
    5) SIDE="iperf";;
    6) SIDE="haproxy";;
    *)
        echo -e "  ${RED}Invalid choice.${NC}"
        exit 1
        ;;
esac

echo ""

# ----- REMOVE -----
if [ "$SIDE" = "remove" ]; then
    echo -e "  ${CYAN}┌─ حذف تونل / HAProxy ─────────────────────${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}1${NC}) ایران  — حذف تونل این سرور + اختیاری HAProxy"
    echo -e "  ${CYAN}│${NC}  ${GREEN}2${NC}) خارج   — حذف همه تونل‌های gre-haproxy1,2,..."
    echo -e "  ${CYAN}└──────────────────────────────────────────${NC}"
    read -p "  کدام؟ (1 یا 2): " remove_side

    if [ "$remove_side" = "2" ]; then
        for i in $(seq 1 32); do
            iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${i}"
            if ip link show "$iface" &>/dev/null; then
                echo -e "  ${YELLOW}در حال حذف ${iface}...${NC}"
                ip link set "$iface" down 2>/dev/null || true
                ip tunnel del "$iface" 2>/dev/null || true
                echo -e "  ${GREEN}✓${NC} $iface حذف شد."
            fi
        done
        [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE" && echo -e "  ${GREEN}✓${NC} فایل پیکربندی حذف شد."
    else
        if ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
            echo -e "  ${YELLOW}در حال حذف $TUNNEL_IFACE_IRAN...${NC}"
            ip link set "$TUNNEL_IFACE_IRAN" down 2>/dev/null || true
            ip tunnel del "$TUNNEL_IFACE_IRAN" 2>/dev/null || true
            echo -e "  ${GREEN}✓${NC} تونل ایران حذف شد."
        else
            echo -e "  ${YELLOW}اینترفیس $TUNNEL_IFACE_IRAN یافت نشد.${NC}"
        fi
        read -p "  HAProxy هم حذف/بازگردانی شود؟ (y/n): " remove_haproxy
        if [[ "$remove_haproxy" =~ ^[yY] ]]; then
            systemctl stop haproxy 2>/dev/null || true
            systemctl disable haproxy 2>/dev/null || true
            if [ -f /etc/haproxy/haproxy.cfg.bak ]; then
                cp /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
                echo -e "  ${GREEN}✓${NC} پیکربندی HAProxy از backup بازگردانی شد."
            else
                cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    maxconn 10000
    daemon

defaults
    mode tcp
    timeout connect 5000
    timeout client 50000
    timeout server 50000
EOF
                echo -e "  ${GREEN}✓${NC} پیکربندی HAProxy خالی شد."
            fi
            echo -e "  ${GREEN}✓${NC} HAProxy متوقف و غیرفعال شد."
        fi
    fi

    if [ -f "$RCLOCAL" ] && grep -q "$GRE_MARKER_START" "$RCLOCAL" 2>/dev/null; then
        sed -i "/$GRE_MARKER_START/,/$GRE_MARKER_END/d" "$RCLOCAL"
        sed -i '/^$/N;/^\n$/d' "$RCLOCAL" 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} دستورات تونل از rc.local حذف شد."
    fi

    echo ""
    echo -e "  ${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}║${NC}  ${BOLD}حذف با موفقیت انجام شد.${NC}                    ${GREEN}║${NC}"
    echo -e "  ${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
fi

# ----- STATUS -----
if [ "$SIDE" = "status" ]; then
    echo ""
    echo -e "  ${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}              ${GREEN}وضعیت تونل و سرویس‌ها${NC}                          ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Detect side: KHAREJ has gre-haproxy1 ; IRAN has gre-haproxy only
    if ip link show "${TUNNEL_IFACE_KHAREJ_PREFIX}1" &>/dev/null; then
        echo -e "  ${YELLOW}▶ نقش${NC}        ${GREEN}خارج (KHAREJ)${NC} — تجمیع چند تونل ایران"
        echo ""
        if [ -f "$CONFIG_FILE" ]; then
            KHAREJ_IP=$(sed -n '1p' "$CONFIG_FILE")
            N_IRAN=$(sed -n '2p' "$CONFIG_FILE")
            N_IRAN=$((N_IRAN + 0))
            echo -e "  ${YELLOW}▶ این سرور${NC}    ${CYAN}$KHAREJ_IP${NC}"
            echo -e "  ${YELLOW}▶ تونل‌ها${NC}      $N_IRAN سرور ایران متصل"
            echo ""
            echo -e "  ${CYAN}┌──────────────────┬─────────────────────┬─────────────────┬────────┐${NC}"
            echo -e "  ${CYAN}│${NC} Interface        ${CYAN}│${NC} IRAN (public)      ${CYAN}│${NC} Tunnel peer     ${CYAN}│${NC} Ping   ${CYAN}│${NC}"
            echo -e "  ${CYAN}├──────────────────┼─────────────────────┼─────────────────┼────────┤${NC}"
            for i in $(seq 1 "$N_IRAN"); do
                line=$((2 + i))
                iran_ip=$(sed -n "${line}p" "$CONFIG_FILE")
                iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${i}"
                peer_ip=$(tunnel_iran_ip "$i")
                if ip link show "$iface" &>/dev/null; then
                    ping -c 1 -W 2 "$peer_ip" &>/dev/null && pstat="${GREEN}  ✓ OK${NC}" || pstat="${RED}  ✗ FAIL${NC}"
                    printf "  ${CYAN}│${NC} %-16s ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-15s ${CYAN}│${NC} %b ${CYAN}│${NC}\n" "$iface" "$iran_ip" "$peer_ip" "$pstat"
                else
                    pstat="${RED}down${NC}"
                    printf "  ${CYAN}│${NC} %-16s ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-15s ${CYAN}│${NC} %b ${CYAN}│${NC}\n" "$iface" "$iran_ip" "—" "$pstat"
                fi
            done
            echo -e "  ${CYAN}└──────────────────┴─────────────────────┴─────────────────┴────────┘${NC}"
        else
            echo -e "  ${YELLOW}▶ پیکربندی${NC}   ${YELLOW}فایل $CONFIG_FILE نیست${NC} — اینترفیس‌های تونل:"
            for i in $(seq 1 32); do
                iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${i}"
                if ip link show "$iface" &>/dev/null; then
                    addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[0-9.]+/[0-9]+' || echo "—")
                    echo -e "                   ${GREEN}$iface${NC}  $addr"
                fi
            done
        fi
    elif ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
        our_cidr=$(ip -4 addr show "$TUNNEL_IFACE_IRAN" 2>/dev/null | grep -oP 'inet \K[0-9.]+/[0-9]+')
        backend_ip=$(echo "$our_cidr" | cut -d'/' -f1 | sed 's/\.[0-9]*$/.2/')
        echo -e "  ${YELLOW}▶ نقش${NC}        ${GREEN}ایران (IRAN)${NC} — یک تونل به خارج"
        echo ""
        echo -e "  ${YELLOW}▶ اینترفیس${NC}    ${CYAN}$TUNNEL_IFACE_IRAN${NC}"
        echo -e "  ${YELLOW}▶ طرف ایران${NC}    ${CYAN}${our_cidr:-—}${NC}"
        echo -e "  ${YELLOW}▶ طرف خارج${NC}     ${CYAN}${backend_ip}${NC}"
        echo ""
        if ping -c 2 -W 2 "$backend_ip" &>/dev/null; then
            echo -e "  ${YELLOW}▶ اتصال${NC}       ${GREEN}✓ قابل دسترس${NC} — تونل برقرار است"
        else
            echo -e "  ${YELLOW}▶ اتصال${NC}       ${RED}✗ غیرقابل دسترس${NC} — تونل یا سرور خارج را بررسی کنید"
        fi
    else
        echo -e "  ${YELLOW}▶ نقش${NC}      تونلی روی این سرور یافت نشد."
        echo -e "                 ابتدا از منو گزینه ۱ یا ۲ را اجرا کنید."
    fi

    echo ""
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    if systemctl is-active haproxy &>/dev/null; then
        echo -e "  ${CYAN}│${NC} ${YELLOW}HAProxy${NC}   ${GREEN}● در حال اجرا${NC}                                        ${CYAN}│${NC}"
    else
        echo -e "  ${CYAN}│${NC} ${YELLOW}HAProxy${NC}   ${YELLOW}○ متوقف${NC} (یا نصب نشده)                                ${CYAN}│${NC}"
    fi
    if [ -f "$RCLOCAL" ] && grep -q "$GRE_MARKER_START" "$RCLOCAL" 2>/dev/null; then
        echo -e "  ${CYAN}│${NC} ${YELLOW}بوت${NC}       ${GREEN}● تونل در rc.local${NC} (بعد از ریبوت برقرار می‌شود)   ${CYAN}│${NC}"
    else
        echo -e "  ${CYAN}│${NC} ${YELLOW}بوت${NC}       ${YELLOW}○ rc.local تنظیم نشده${NC} — tunnels won’t restore on boot ${CYAN}│${NC}"
    fi
    echo -e "  ${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${GREEN}✓ گزارش وضعیت آماده است.${NC}"
    echo ""
    exit 0
fi

# ----- iperf3 test: 10 connections IRAN (client) → KHAREJ (server) -----
if [ "$SIDE" = "iperf" ]; then
    IPERF_DURATION=10
    IPERF_STREAMS=10
    if ! command -v iperf3 &>/dev/null; then
        echo -e "${YELLOW}Installing iperf3...${NC}"
        apt-get update -qq 2>/dev/null; apt-get install -y iperf3 2>/dev/null || true
        if ! command -v iperf3 &>/dev/null; then
            echo -e "${YELLOW}Retrying after full package list update...${NC}"
            apt-get update
            apt-get install -y iperf3
        fi
        if ! command -v iperf3 &>/dev/null; then
            echo -e "${RED}Could not install iperf3. Try manually: apt-get update && apt-get install -y iperf3${NC}"
            exit 1
        fi
        echo -e "${GREEN}iperf3 installed.${NC}"
    fi

    # IRAN = client: run iperf3 -c toward KHAREJ tunnel IP (our backend = 10.10.x.2)
    if ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
        our_cidr=$(ip -4 addr show "$TUNNEL_IFACE_IRAN" 2>/dev/null | grep -oP 'inet \K[0-9.]+/[0-9]+')
        if [ -z "$our_cidr" ]; then
            echo -e "${RED}Could not get tunnel IP on $TUNNEL_IFACE_IRAN.${NC}"
            exit 1
        fi
        TARGET=$(echo "$our_cidr" | cut -d'/' -f1 | sed 's/\.[0-9]*$/.2/')
        echo ""
        echo -e "  ${YELLOW}تست پهنای باند ایران → خارج (مقصد: ${CYAN}$TARGET${NC})"
        echo -e "  ${DIM}${IPERF_STREAMS} اتصال، ${IPERF_DURATION} ثانیه. روی سرور خارج باید سرور iperf3 بالا باشد (گزینه ۵ → Start server).${NC}"
        echo ""

        tmpjson=$(mktemp)
        tmpjson_err="${tmpjson}.err"
        trap 'rm -f "$tmpjson" "$tmpjson_err" 2>/dev/null' EXIT
        if iperf3 -c "$TARGET" -P "$IPERF_STREAMS" -t "$IPERF_DURATION" -J 2>"$tmpjson_err" >"$tmpjson"; then
            # sum_received = what KHAREJ (server) received = what IRAN (client) sent = IRAN→KHAREJ bandwidth
            bps=""
            if command -v jq &>/dev/null; then
                bps=$(jq -r '.end.sum_received.bits_per_second // empty' "$tmpjson" 2>/dev/null)
            fi
            if [ -z "$bps" ] || [ "$bps" = "null" ]; then
                bps=$(grep -oP '"bits_per_second":\s*\K[0-9.e+-]+' "$tmpjson" 2>/dev/null | tail -1)
            fi
            if [ -z "$bps" ]; then
                bps=$(sed -n 's/.*"bits_per_second":[[:space:]]*\([0-9.e+-]*\).*/\1/p' "$tmpjson" | tail -1)
            fi
            if [ -n "$bps" ] && [ "$bps" != "null" ]; then
                gbps=$(awk "BEGIN { printf \"%.2f\", $bps/1e9 }")
                mbs=$(awk "BEGIN { printf \"%.2f\", $bps/8/1e6 }")
                echo ""
                echo -e "  ${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
                echo -e "  ${GREEN}║${NC}     ${CYAN}iperf3${NC}  •  ${IPERF_STREAMS} connections  •  ${IPERF_DURATION}s  •  IRAN → KHAREJ       ${GREEN}║${NC}"
                echo -e "  ${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
                echo -e "  ${GREEN}║${NC}                                                                ${GREEN}║${NC}"
                echo -e "  ${GREEN}║${NC}     ${YELLOW}Bandwidth${NC}   ${CYAN}${gbps}${NC} Gbit/s                                    ${GREEN}║${NC}"
                echo -e "  ${GREEN}║${NC}     ${YELLOW}Throughput${NC}  ${CYAN}${mbs}${NC} MB/s                                      ${GREEN}║${NC}"
                echo -e "  ${GREEN}║${NC}                                                                ${GREEN}║${NC}"
                echo -e "  ${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
                echo ""
            else
                echo -e "${YELLOW}Raw iperf3 output:${NC}"
                iperf3 -c "$TARGET" -P "$IPERF_STREAMS" -t "$IPERF_DURATION" 2>/dev/null || true
            fi
        else
            echo -e "  ${RED}iperf3 ناموفق. روی سرور خارج سرور iperf3 را با گزینه ۵ روشن کنید.${NC}"
            [ -s "$tmpjson_err" ] && cat "$tmpjson_err"
        fi
        exit 0
    fi

    if ip link show "${TUNNEL_IFACE_KHAREJ_PREFIX}1" &>/dev/null; then
        echo -e "  ${CYAN}شروع سرور iperf3 روی این خارج — ایران می‌تواند تست پهنای باند بزند.${NC}"
        read -p "  سرور ۹۰ ثانیه بالا بیاید؟ (y/n): " run_srv
        if [[ "$run_srv" =~ ^[yY] ]]; then
            echo -e "  ${GREEN}سرور iperf3 در حال اجرا (پورت 5201). ظرف ۹۰ ثانیه از ایران گزینه ۵ را بزنید.${NC}"
            echo ""
            timeout 90 iperf3 -s -1 2>/dev/null || timeout 90 iperf3 -s
            echo -e "  ${GREEN}سرور متوقف شد.${NC}"
        fi
        exit 0
    fi

    echo -e "  ${YELLOW}تونلی یافت نشد. این گزینه را روی سرور خارج یا ایران (با تونل فعال) اجرا کنید.${NC}"
    exit 1
fi

# ----- HAProxy: add or manage port forwarding (IRAN only) -----
if [ "$SIDE" = "haproxy" ]; then
    if ! ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
        echo -e "  ${YELLOW}فوروارد پورت HAProxy فقط روی سرور ایران است. روی این سرور تونل gre-haproxy نیست.${NC}"
        echo -e "  ابتدا گزینه ۱ (ایران) را اجرا کنید، بعد گزینه ۶."
        exit 1
    fi
    our_cidr=$(ip -4 addr show "$TUNNEL_IFACE_IRAN" 2>/dev/null | grep -oP 'inet \K[0-9.]+/[0-9]+')
    BACKEND_IP=$(echo "$our_cidr" | cut -d'/' -f1 | sed 's/\.[0-9]*$/.2/')
    CFG="/etc/haproxy/haproxy.cfg"

    if ! command -v haproxy &>/dev/null; then
        echo -e "${YELLOW}Installing HAProxy...${NC}"
        apt-get update -qq && apt-get install -y haproxy
    fi

    echo ""
    echo -e "  ${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}        ${GREEN}HAProxy — فوروارد پورت (ایران → خارج)${NC}                ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}▶ Backend (طرف تونل)${NC}  ${CYAN}$BACKEND_IP${NC}"
    if [ -f "$CFG" ]; then
        existing=$(grep -oP 'bind 0\.0\.0\.0:\K[0-9]+' "$CFG" 2>/dev/null | sort -u)
        if [ -n "$existing" ]; then
            echo -e "  ${YELLOW}▶ پورت‌های فعلی${NC}    ${CYAN}$(echo $existing | tr '\n' ' ')${NC}"
        fi
    fi
    echo ""
    echo -e "  فرمت: ${CYAN}پورت_گوش دادن=پورت_مقصد${NC} (با کاما جدا کنید)"
    echo -e "  مثال: ${CYAN}443=9321,80=8080,2070=2070${NC}"
    echo ""
    read -p "  پورت(های) جدید برای افزودن: " PORTS_INPUT

    if [ -z "$PORTS_INPUT" ]; then
        echo -e "  ${YELLOW}ورودی نبود. تغییری اعمال نشد.${NC}"
        exit 0
    fi

    need_full_config=0
    if [ ! -f "$CFG" ] || ! grep -q "frontend fe_\|backend tunnel_" "$CFG" 2>/dev/null; then
        need_full_config=1
    fi

    [ -f "$CFG" ] && cp "$CFG" /etc/haproxy/haproxy.cfg.bak

    if [ "$need_full_config" -eq 1 ]; then
        cat > "$CFG" << 'CFGHEAD'
global
    maxconn 10000
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /var/run/haproxy.sock mode 660 level admin
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5000
    timeout client  50000
    timeout server  50000

CFGHEAD
    fi

    added=0
    IFS=',' read -ra PAIRS <<< "$PORTS_INPUT"
    for pair in "${PAIRS[@]}"; do
        pair=$(echo "$pair" | tr -d ' ')
        if [[ "$pair" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            LPORT="${BASH_REMATCH[1]}"
            BPORT="${BASH_REMATCH[2]}"
            if [ -f "$CFG" ] && grep -q "frontend fe_${LPORT}\|bind 0.0.0.0:${LPORT}" "$CFG" 2>/dev/null; then
                echo -e "  ${YELLOW}پورت ${LPORT} از قبل وجود دارد، رد شد.${NC}"
                continue
            fi
            cat >> "$CFG" << EOF

backend tunnel_${LPORT}
    mode tcp
    server s1 ${BACKEND_IP}:${BPORT} check

frontend fe_${LPORT}
    mode tcp
    bind 0.0.0.0:${LPORT}
    default_backend tunnel_${LPORT}
EOF
            echo -e "  ${GREEN}✓${NC} Port ${CYAN}${LPORT}${NC} → ${BACKEND_IP}:${BPORT}"
            added=$((added + 1))
        fi
    done

    if [ "$added" -gt 0 ]; then
        if haproxy -c -f "$CFG" 2>/dev/null; then
            systemctl enable haproxy 2>/dev/null || true
            systemctl reload haproxy 2>/dev/null || systemctl restart haproxy 2>/dev/null || true
            echo ""
            echo -e "  ${GREEN}✓ HAProxy بارگذاری شد. $added پورت اضافه شد.${NC}"
        else
            echo -e "  ${RED}خطای پیکربندی HAProxy. از backup بازگردانی شد.${NC}"
            [ -f /etc/haproxy/haproxy.cfg.bak ] && cp /etc/haproxy/haproxy.cfg.bak "$CFG"
        fi
    fi
    echo ""
    exit 0
fi

# ----- KHAREJ: add one IRAN tunnel -----
if [ "$SIDE" = "kharej" ]; then
    echo -e "  ${CYAN}┌─ سرور خارج (KHAREJ) — اضافه کردن یک ایران ─${NC}"
    echo -e "  ${CYAN}└──────────────────────────────────────────${NC}"
    echo ""
    if [ -n "$MY_IP" ]; then
        read -p "  آی‌پی این سرور (خارج) = ${MY_IP} استفاده شود؟ (y/n): " use_k
        if [[ "$use_k" =~ ^[yY] ]]; then
            KHAREJ_IP="$MY_IP"
        else
            read -p "  آی‌پی عمومی سرور خارج را وارد کنید: " KHAREJ_IP
        fi
    else
        read -p "  آی‌پی عمومی سرور خارج را وارد کنید: " KHAREJ_IP
    fi

    IRAN_IPS=()
    N_IRAN=0
    if [ -f "$CONFIG_FILE" ]; then
        KHAREJ_IP=$(sed -n '1p' "$CONFIG_FILE")
        N_IRAN=$(sed -n '2p' "$CONFIG_FILE")
        N_IRAN=$((N_IRAN + 0))
        for i in $(seq 1 "$N_IRAN"); do
            line=$((2 + i))
            ip=$(sed -n "${line}p" "$CONFIG_FILE")
            [ -n "$ip" ] && IRAN_IPS+=("$ip")
        done
        echo -e "  ${DIM}تا الان $N_IRAN سرور ایران متصل است.${NC}"
        echo ""
    fi

    echo -e "  ${YELLOW}آی‌پی عمومی سرور ایران جدید را وارد کنید:${NC}"
    read -p "  IP: " new_iran_ip
    if [ -z "$new_iran_ip" ]; then
        echo -e "  ${RED}آی‌پی الزامی است.${NC}"
        exit 1
    fi
    N_IRAN=$((N_IRAN + 1))
    IRAN_IPS+=("$new_iran_ip")

    iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${N_IRAN}"
    if ip link show "$iface" &>/dev/null; then
        echo -e "  ${YELLOW}در حال جایگزینی $iface...${NC}"
        ip link set "$iface" down 2>/dev/null || true
        ip tunnel del "$iface" 2>/dev/null || true
    fi
    kcidr=$(tunnel_kharej_cidr "$N_IRAN")
    echo ""
    echo -e "  ${GREEN}در حال ایجاد تونل $iface (ایران #$N_IRAN)...${NC}"
    ip tunnel add "$iface" mode gre local "$KHAREJ_IP" remote "$new_iran_ip" ttl 255
    ip addr add "$kcidr" dev "$iface"
    ip link set "$iface" mtu 1436
    ip link set "$iface" up
    sysctl -w "net.ipv4.conf.$iface.rp_filter=0" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} تونل اضافه شد. روی سرور ایران گزینه ۱ را با ${CYAN}شماره $N_IRAN${NC} اجرا کنید."

    # Save config: KHAREJ_IP, N_IRAN, then all IRAN IPs
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "$KHAREJ_IP" > "$CONFIG_FILE"
    echo "$N_IRAN" >> "$CONFIG_FILE"
    for ip in "${IRAN_IPS[@]}"; do echo "$ip" >> "$CONFIG_FILE"; done

    # rc.local: full block for all N_IRAN tunnels
    if [ ! -f "$RCLOCAL" ]; then
        printf '%s\n' '#!/bin/bash' 'exit 0' > "$RCLOCAL"
        chmod +x "$RCLOCAL"
    fi
    if grep -q "$GRE_MARKER_START" "$RCLOCAL" 2>/dev/null; then
        sed -i "/$GRE_MARKER_START/,/$GRE_MARKER_END/d" "$RCLOCAL"
        sed -i '/^$/N;/^\n$/d' "$RCLOCAL" 2>/dev/null || true
    fi
    sed -i '/^exit 0$/d' "$RCLOCAL" 2>/dev/null || true
    {
        echo ""
        echo "$GRE_MARKER_START"
        for i in $(seq 1 "$N_IRAN"); do
            iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${i}"
            iran_ip="${IRAN_IPS[$((i-1))]}"
            kcidr=$(tunnel_kharej_cidr "$i")
            echo "ip tunnel add $iface mode gre local $KHAREJ_IP remote $iran_ip ttl 255"
            echo "ip addr add $kcidr dev $iface"
            echo "ip link set $iface mtu 1436"
            echo "ip link set $iface up"
            echo "sysctl -w net.ipv4.conf.$iface.rp_filter=0 2>/dev/null || true"
        done
        echo "$GRE_MARKER_END"
        echo ""
        echo "exit 0"
    } >> "$RCLOCAL"
    echo -e "  ${GREEN}✓${NC} دستورات تونل در $RCLOCAL ذخیره شد."
    echo ""
    echo -e "  ${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}║${NC}  ${BOLD}خارج آماده است.${NC} روی سرور ایران همین اسکریپت را بزنید،     ${GREEN}║${NC}"
    echo -e "  ${GREEN}║${NC}  گزینه ${CYAN}۱ (ایران)${NC} و شماره ایران را ${CYAN}$N_IRAN${NC} بگذارید.              ${GREEN}║${NC}"
    echo -e "  ${GREEN}║${NC}  آی‌پی backend آن ایران: ${CYAN}$(tunnel_kharej_ip "$N_IRAN")${NC}                    ${GREEN}║${NC}"
    echo -e "  ${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
fi

# ----- IRAN: single tunnel -----
echo -e "  ${CYAN}┌─ سرور ایران (IRAN) — نصب تونل ─────────────────${NC}"
echo -e "  ${CYAN}└──────────────────────────────────────────${NC}"
echo ""
echo -e "  ${YELLOW}شماره این سرور ایران (۱=اولین، ۲=دومین، ...). باید با ترتیب اضافه‌شدن روی خارج یکی باشد.${NC}"
read -p "  شماره ایران (1, 2, 3, ...): " IRAN_INDEX
IRAN_INDEX=$((IRAN_INDEX + 0))
if [ "$IRAN_INDEX" -lt 1 ]; then
    echo -e "  ${RED}شماره باید حداقل ۱ باشد.${NC}"
    exit 1
fi

if [ -n "$MY_IP" ]; then
    read -p "  آی‌پی این سرور = ${MY_IP} استفاده شود؟ (y/n): " use_iran
    if [[ "$use_iran" =~ ^[yY] ]]; then
        IRAN_IP="$MY_IP"
    else
        read -p "  آی‌پی عمومی این سرور ایران: " IRAN_IP
    fi
else
    read -p "  آی‌پی عمومی این سرور ایران: " IRAN_IP
fi
read -p "  آی‌پی عمومی سرور خارج: " KHAREJ_IP

if [ -z "$IRAN_IP" ] || [ -z "$KHAREJ_IP" ]; then
    echo -e "  ${RED}هر دو آی‌پی ایران و خارج لازم است.${NC}"
    exit 1
fi

if ip tunnel show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
    echo -e "  ${YELLOW}در حال جایگزینی تونل قبلی...${NC}"
    ip link set "$TUNNEL_IFACE_IRAN" down 2>/dev/null || true
    ip tunnel del "$TUNNEL_IFACE_IRAN" 2>/dev/null || true
fi

MY_CIDR=$(tunnel_cidr "$IRAN_INDEX")
BACKEND_IP=$(tunnel_kharej_ip "$IRAN_INDEX")

echo ""
echo -e "  ${GREEN}در حال ایجاد تونل GRE (ایران #$IRAN_INDEX → $BACKEND_IP)...${NC}"
ip tunnel add "$TUNNEL_IFACE_IRAN" mode gre local "$IRAN_IP" remote "$KHAREJ_IP" ttl 255
ip addr add "$MY_CIDR" dev "$TUNNEL_IFACE_IRAN"
ip link set "$TUNNEL_IFACE_IRAN" mtu 1436
ip link set "$TUNNEL_IFACE_IRAN" up
sysctl -w "net.ipv4.conf.$TUNNEL_IFACE_IRAN.rp_filter=0" 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} تونل ساخته شد. این سرور: ${CYAN}$MY_CIDR${NC}، طرف خارج: ${CYAN}$BACKEND_IP${NC}"
echo ""

# rc.local for this Iran (single tunnel)
if [ ! -f "$RCLOCAL" ]; then
    printf '%s\n' '#!/bin/bash' 'exit 0' > "$RCLOCAL"
    chmod +x "$RCLOCAL"
fi
if grep -q "$GRE_MARKER_START" "$RCLOCAL" 2>/dev/null; then
    sed -i "/$GRE_MARKER_START/,/$GRE_MARKER_END/d" "$RCLOCAL"
    sed -i '/^$/N;/^\n$/d' "$RCLOCAL" 2>/dev/null || true
fi
sed -i '/^exit 0$/d' "$RCLOCAL" 2>/dev/null || true
{
    echo ""
    echo "$GRE_MARKER_START"
    echo "ip tunnel add $TUNNEL_IFACE_IRAN mode gre local $IRAN_IP remote $KHAREJ_IP ttl 255"
    echo "ip addr add $MY_CIDR dev $TUNNEL_IFACE_IRAN"
    echo "ip link set $TUNNEL_IFACE_IRAN mtu 1436"
    echo "ip link set $TUNNEL_IFACE_IRAN up"
    echo "sysctl -w net.ipv4.conf.$TUNNEL_IFACE_IRAN.rp_filter=0 2>/dev/null || true"
    echo "$GRE_MARKER_END"
    echo ""
    echo "exit 0"
} >> "$RCLOCAL"
echo -e "  ${GREEN}✓${NC} دستورات تونل در rc.local ذخیره شد (بعد از ریبوت اجرا می‌شود)."
echo ""
echo -e "  ${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${GREEN}║${NC}  ${BOLD}تونل ایران آماده است.${NC}                                    ${GREEN}║${NC}"
echo -e "  ${GREEN}║${NC}  تست: ${CYAN}ping $BACKEND_IP${NC}                                   ${GREEN}║${NC}"
echo -e "  ${GREEN}║${NC}  برای فوروارد پورت، دوباره اسکریپت را بزنید و گزینه ${CYAN}۶${NC} (HAProxy).  ${GREEN}║${NC}"
echo -e "  ${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
