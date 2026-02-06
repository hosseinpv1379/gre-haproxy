#!/bin/bash
#
# GRE tunnel + HAProxy - multiple IRAN -> one KHAREJ
# In memory of the martyrs of the homeland.
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
    echo -e "  ${CYAN}║${NC}   ${BOLD}${GREEN}GRE Tunnel + HAProxy${NC}   ${DIM}multi-IRAN -> one KHAREJ${NC}              ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}   ${DIM}be yad jan fadayan mihan${NC}                 ${CYAN}║${NC}"
    echo -e "  ${CYAN}║${NC}                                                                  ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

if [ "$EUID" -ne 0 ]; then
    print_panel
    echo -e "  ${RED}Run as root (sudo).${NC}"
    echo -e "  ${YELLOW}Usage: ${NC}sudo bash $0"
    echo ""
    exit 1
fi

MY_IP=$(detect_my_ip)
ROLE_HINT=$(detect_role_hint)

print_panel

if [ -n "$MY_IP" ]; then
    echo -e "  ${DIM}This server IP:${NC} ${CYAN}${MY_IP}${NC}"
    if [ -n "$ROLE_HINT" ]; then
        [ "$ROLE_HINT" = "kharej" ] && echo -e "  ${DIM}Current role:${NC} ${GREEN}KHAREJ${NC} - tunnels active"
        [ "$ROLE_HINT" = "iran" ]   && echo -e "  ${DIM}Current role:${NC} ${GREEN}IRAN${NC} - tunnel active"
    fi
    echo ""
fi

echo -e "  ${BOLD}Menu:${NC}"
echo -e "  ${CYAN}  +-- Setup ------------------------------------${NC}"
echo -e "  ${CYAN}  |${NC}  ${GREEN}1${NC}) IRAN      - Setup tunnel on this server"
echo -e "  ${CYAN}  |${NC}  ${GREEN}2${NC}) KHAREJ   - Add one IRAN server"
echo -e "  ${CYAN}  +-- Manage -----------------------------------${NC}"
echo -e "  ${CYAN}  |${NC}  ${YELLOW}3${NC}) Remove   - Remove tunnels / HAProxy"
echo -e "  ${CYAN}  |${NC}  ${YELLOW}4${NC}) Status   - Show tunnel and HAProxy status"
echo -e "  ${CYAN}  |${NC}  ${YELLOW}5${NC}) iperf3   - Bandwidth test (IRAN -> KHAREJ)"
echo -e "  ${CYAN}  |${NC}  ${YELLOW}6${NC}) HAProxy  - Add port forwarding (IRAN only)"
echo -e "  ${CYAN}  |${NC}  ${YELLOW}7${NC}) GOST    - Port forwarding TCP (IRAN only)"
echo -e "  ${CYAN}  |${NC}  ${YELLOW}8${NC}) Reverse - GOST reverse tunnel (outside -> Iran)"
echo -e "  ${CYAN}  +---------------------------------------------${NC}"
echo ""
read -p "  Choice (1-8): " side_choice

case "$side_choice" in
    1) SIDE="iran";;
    2) SIDE="kharej";;
    3) SIDE="remove";;
    4) SIDE="status";;
    5) SIDE="iperf";;
    6) SIDE="haproxy";;
    7) SIDE="gost";;
    8) SIDE="gost-reverse";;
    *)
        echo -e "  ${RED}Invalid choice.${NC}"
        exit 1
        ;;
esac

echo ""

# ----- REMOVE -----
if [ "$SIDE" = "remove" ]; then
    echo -e "  ${CYAN}+-- Remove tunnel / HAProxy ----------------${NC}"
    echo -e "  ${CYAN}|${NC}  ${GREEN}1${NC}) IRAN   - Remove tunnel on this server + optional HAProxy"
    echo -e "  ${CYAN}|${NC}  ${GREEN}2${NC}) KHAREJ - Remove all gre-haproxy1,2,... tunnels"
    echo -e "  ${CYAN}+-------------------------------------------${NC}"
    read -p "  Which? (1 or 2): " remove_side

    if [ "$remove_side" = "2" ]; then
        for i in $(seq 1 32); do
            iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${i}"
            if ip link show "$iface" &>/dev/null; then
                echo -e "  ${YELLOW}Removing ${iface}...${NC}"
                ip link set "$iface" down 2>/dev/null || true
                ip tunnel del "$iface" 2>/dev/null || true
                echo -e "  ${GREEN}Done.${NC} $iface removed."
            fi
        done
        [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE" && echo -e "  ${GREEN}Done.${NC} Config file removed."
        read -p "  Also remove GOST reverse tunnel server (gost-reverse-tunnel)? (y/n): " remove_reverse_k
        if [[ "$remove_reverse_k" =~ ^[yY] ]]; then
            systemctl stop gost-reverse-tunnel 2>/dev/null || true
            systemctl disable gost-reverse-tunnel 2>/dev/null || true
            rm -f /etc/systemd/system/gost-reverse-tunnel.service
            systemctl daemon-reload 2>/dev/null || true
            rm -rf /etc/gost-reverse-tunnel
            echo -e "  ${GREEN}Done.${NC} GOST reverse tunnel removed."
        fi
    else
        if ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
            echo -e "  ${YELLOW}Removing $TUNNEL_IFACE_IRAN...${NC}"
            ip link set "$TUNNEL_IFACE_IRAN" down 2>/dev/null || true
            ip tunnel del "$TUNNEL_IFACE_IRAN" 2>/dev/null || true
            echo -e "  ${GREEN}Done.${NC} IRAN tunnel removed."
        else
            echo -e "  ${YELLOW}Interface $TUNNEL_IFACE_IRAN not found.${NC}"
        fi
        read -p "  Also remove/restore HAProxy config? (y/n): " remove_haproxy
        if [[ "$remove_haproxy" =~ ^[yY] ]]; then
            systemctl stop haproxy 2>/dev/null || true
            systemctl disable haproxy 2>/dev/null || true
            if [ -f /etc/haproxy/haproxy.cfg.bak ]; then
                cp /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
                echo -e "  ${GREEN}Done.${NC} HAProxy config restored from backup."
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
                echo -e "  ${GREEN}Done.${NC} HAProxy config cleared."
            fi
            echo -e "  ${GREEN}Done.${NC} HAProxy stopped and disabled."
        fi
        read -p "  Also remove GOST port forwarding (gost-gre)? (y/n): " remove_gost
        if [[ "$remove_gost" =~ ^[yY] ]]; then
            systemctl stop gost-gre 2>/dev/null || true
            systemctl disable gost-gre 2>/dev/null || true
            rm -f /etc/systemd/system/gost-gre.service
            systemctl daemon-reload 2>/dev/null || true
            rm -rf /etc/gost-gre
            echo -e "  ${GREEN}Done.${NC} GOST service, config and local certs removed."
        fi
        read -p "  Also remove GOST reverse tunnel (gost-reverse-tunnel)? (y/n): " remove_reverse
        if [[ "$remove_reverse" =~ ^[yY] ]]; then
            systemctl stop gost-reverse-tunnel 2>/dev/null || true
            systemctl disable gost-reverse-tunnel 2>/dev/null || true
            rm -f /etc/systemd/system/gost-reverse-tunnel.service
            systemctl daemon-reload 2>/dev/null || true
            rm -rf /etc/gost-reverse-tunnel
            echo -e "  ${GREEN}Done.${NC} GOST reverse tunnel removed."
        fi
    fi

    if [ -f "$RCLOCAL" ] && grep -q "$GRE_MARKER_START" "$RCLOCAL" 2>/dev/null; then
        sed -i "/$GRE_MARKER_START/,/$GRE_MARKER_END/d" "$RCLOCAL"
        sed -i '/^$/N;/^\n$/d' "$RCLOCAL" 2>/dev/null || true
        echo -e "  ${GREEN}Done.${NC} Tunnel commands removed from rc.local."
    fi

    echo ""
    echo -e "  ${GREEN}Remove completed.${NC}"
    echo ""
    exit 0
fi

# ----- STATUS -----
if [ "$SIDE" = "status" ]; then
    echo ""
    echo -e "  ${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}              ${GREEN}Tunnel and services status${NC}                     ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if ip link show "${TUNNEL_IFACE_KHAREJ_PREFIX}1" &>/dev/null; then
        echo -e "  ${YELLOW}>> Role${NC}       ${GREEN}KHAREJ${NC} - aggregating multiple IRAN tunnels"
        echo ""
        if [ -f "$CONFIG_FILE" ]; then
            KHAREJ_IP=$(sed -n '1p' "$CONFIG_FILE")
            N_IRAN=$(sed -n '2p' "$CONFIG_FILE")
            N_IRAN=$((N_IRAN + 0))
            echo -e "  ${YELLOW}>> This server${NC} ${CYAN}$KHAREJ_IP${NC}"
            echo -e "  ${YELLOW}>> Tunnels${NC}     $N_IRAN IRAN server(s) connected"
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
            echo -e "  ${YELLOW}>> Config${NC}    ${YELLOW}No $CONFIG_FILE${NC} - tunnel interfaces:"
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
        echo -e "  ${YELLOW}>> Role${NC}       ${GREEN}IRAN${NC} - single tunnel to KHAREJ"
        echo ""
        echo -e "  ${YELLOW}>> Interface${NC}  ${CYAN}$TUNNEL_IFACE_IRAN${NC}"
        echo -e "  ${YELLOW}>> This side${NC}   ${CYAN}${our_cidr:-—}${NC}"
        echo -e "  ${YELLOW}>> KHAREJ side${NC} ${CYAN}${backend_ip}${NC}"
        echo ""
        if ping -c 2 -W 2 "$backend_ip" &>/dev/null; then
            echo -e "  ${YELLOW}>> Reachable${NC}  ${GREEN}Yes${NC} - tunnel is up"
        else
            echo -e "  ${YELLOW}>> Reachable${NC}  ${RED}No${NC} - check tunnel or KHAREJ server"
        fi
    else
        echo -e "  ${YELLOW}>> Role${NC}     No gre-haproxy tunnel on this server."
        echo -e "                Run option 1 or 2 first."
    fi

    echo ""
    echo -e "  ${CYAN}+-------------------------------------------------------------+${NC}"
    if systemctl is-active haproxy &>/dev/null; then
        echo -e "  ${CYAN}|${NC} ${YELLOW}HAProxy${NC}   ${GREEN}Running${NC}                                        ${CYAN}|${NC}"
    else
        echo -e "  ${CYAN}|${NC} ${YELLOW}HAProxy${NC}   ${YELLOW}Not running${NC} (or not installed)                    ${CYAN}|${NC}"
    fi
    if systemctl is-active gost-gre &>/dev/null 2>/dev/null; then
        echo -e "  ${CYAN}|${NC} ${YELLOW}GOST${NC}      ${GREEN}Running${NC} (TCP port forwarding)                      ${CYAN}|${NC}"
    else
        echo -e "  ${CYAN}|${NC} ${YELLOW}GOST${NC}      ${YELLOW}Not running${NC} (or not configured)                   ${CYAN}|${NC}"
    fi
    if systemctl is-active gost-reverse-tunnel &>/dev/null 2>/dev/null; then
        echo -e "  ${CYAN}|${NC} ${YELLOW}Reverse${NC}   ${GREEN}Running${NC} (GOST reverse tunnel)                       ${CYAN}|${NC}"
    else
        echo -e "  ${CYAN}|${NC} ${YELLOW}Reverse${NC}   ${YELLOW}Not running${NC} (or not configured)                   ${CYAN}|${NC}"
    fi
    if [ -f "$RCLOCAL" ] && grep -q "$GRE_MARKER_START" "$RCLOCAL" 2>/dev/null; then
        echo -e "  ${CYAN}|${NC} ${YELLOW}Boot${NC}      ${GREEN}Tunnels in rc.local${NC} (will restore after reboot)  ${CYAN}|${NC}"
    else
        echo -e "  ${CYAN}|${NC} ${YELLOW}Boot${NC}      ${YELLOW}rc.local not configured${NC} - tunnels wont restore on boot   ${CYAN}|${NC}"
    fi
    echo -e "  ${CYAN}+-------------------------------------------------------------+${NC}"
    echo ""
    echo -e "  ${GREEN}Status complete.${NC}"
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
        echo -e "  ${YELLOW}Bandwidth test IRAN -> KHAREJ (target: ${CYAN}$TARGET${NC})"
        echo -e "  ${DIM}${IPERF_STREAMS} streams, ${IPERF_DURATION}s. Run iperf3 server on KHAREJ first (option 5 -> Start server).${NC}"
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
            echo -e "  ${RED}iperf3 failed. Start iperf3 server on KHAREJ (option 5).${NC}"
            [ -s "$tmpjson_err" ] && cat "$tmpjson_err"
        fi
        exit 0
    fi

    if ip link show "${TUNNEL_IFACE_KHAREJ_PREFIX}1" &>/dev/null; then
        echo -e "  ${CYAN}Start iperf3 server on this KHAREJ so IRAN can run the bandwidth test.${NC}"
        read -p "  Run server for 90 seconds? (y/n): " run_srv
        if [[ "$run_srv" =~ ^[yY] ]]; then
            echo -e "  ${GREEN}iperf3 server listening on port 5201. From IRAN run option 5 within 90s.${NC}"
            echo ""
            timeout 90 iperf3 -s -1 2>/dev/null || timeout 90 iperf3 -s
            echo -e "  ${GREEN}Server stopped.${NC}"
        fi
        exit 0
    fi

    echo -e "  ${YELLOW}No tunnel found. Run this option on KHAREJ or IRAN with tunnel up.${NC}"
    exit 1
fi

# ----- HAProxy: add or manage port forwarding (IRAN only) -----
if [ "$SIDE" = "haproxy" ]; then
    if ! ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
        echo -e "  ${YELLOW}HAProxy port forwarding is for IRAN servers. This server has no gre-haproxy tunnel.${NC}"
        echo -e "  Run option 1 (IRAN) first, then option 6."
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
    echo -e "  ${CYAN}║${NC}        ${GREEN}HAProxy - Port forwarding (IRAN -> KHAREJ)${NC}                ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}>> Backend (tunnel)${NC} ${CYAN}$BACKEND_IP${NC}"
    if [ -f "$CFG" ]; then
        existing=$(grep -oP 'bind 0\.0\.0\.0:\K[0-9]+' "$CFG" 2>/dev/null | sort -u)
        if [ -n "$existing" ]; then
            echo -e "  ${YELLOW}>> Current ports${NC}  ${CYAN}$(echo $existing | tr '\n' ' ')${NC}"
        fi
    fi
    echo ""
    echo -e "  Format: ${CYAN}listen_port=backend_port${NC} (comma separated)"
    echo -e "  Example: ${CYAN}443=9321,80=8080,2070=2070${NC}"
    echo ""
    read -p "  New port(s) to add: " PORTS_INPUT

    if [ -z "$PORTS_INPUT" ]; then
        echo -e "  ${YELLOW}No input. Nothing changed.${NC}"
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
                echo -e "  ${YELLOW}Port ${LPORT} already in config, skipped.${NC}"
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
            echo -e "  ${GREEN}HAProxy reloaded. $added port(s) added.${NC}"
        else
            echo -e "  ${RED}HAProxy config error. Restored from backup.${NC}"
            [ -f /etc/haproxy/haproxy.cfg.bak ] && cp /etc/haproxy/haproxy.cfg.bak "$CFG"
        fi
    fi
    echo ""
    exit 0
fi

# ----- GOST: TCP port forwarding (IRAN only) -----
GOST_BIN="/usr/local/bin/gost"
GOST_DIR="/etc/gost-gre"
GOST_CONF="$GOST_DIR/config"
GOST_PORTS="$GOST_DIR/ports"
if [ "$SIDE" = "gost" ]; then
    if ! ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
        echo -e "  ${YELLOW}GOST port forwarding is for IRAN servers. This server has no gre-haproxy tunnel.${NC}"
        echo -e "  Run option 1 (IRAN) first, then option 7."
        exit 1
    fi
    our_cidr=$(ip -4 addr show "$TUNNEL_IFACE_IRAN" 2>/dev/null | grep -oP 'inet \K[0-9.]+/[0-9]+')
    BACKEND_IP=$(echo "$our_cidr" | cut -d'/' -f1 | sed 's/\.[0-9]*$/.2/')

    # Install GOST if missing
    if ! command -v gost &>/dev/null && [ ! -x "$GOST_BIN" ]; then
        echo -e "  ${YELLOW}Installing GOST (GO Simple Tunnel)...${NC}"
        GOST_VER="3.2.6"
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64|amd64) GOST_ARCH="amd64";;
            aarch64|arm64) GOST_ARCH="arm64";;
            armv7l|armhf) GOST_ARCH="armv7";;
            i386|i686) GOST_ARCH="386";;
            *) GOST_ARCH="amd64";;
        esac
        GURL="https://github.com/go-gost/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_linux_${GOST_ARCH}.tar.gz"
        tmpdir=$(mktemp -d)
        trap "rm -rf $tmpdir" EXIT
        if ! curl -sSLf -o "$tmpdir/gost.tar.gz" "$GURL" 2>/dev/null; then
            echo -e "  ${RED}Download failed. Try manually: wget $GURL${NC}"
            exit 1
        fi
        tar -xzf "$tmpdir/gost.tar.gz" -C "$tmpdir"
        mkdir -p /usr/local/bin
        if [ -f "$tmpdir/gost" ]; then
            cp -f "$tmpdir/gost" "$GOST_BIN"
        else
            find "$tmpdir" -maxdepth 2 -type f -name gost -exec cp -f {} "$GOST_BIN" \;
        fi
        chmod +x "$GOST_BIN"
        if [ ! -x "$GOST_BIN" ]; then
            echo -e "  ${RED}GOST install failed.${NC}"
            exit 1
        fi
        echo -e "  ${GREEN}GOST installed.${NC}"
    fi
    GOST_CMD="$GOST_BIN"
    [ -x "$GOST_BIN" ] && GOST_CMD="$GOST_BIN"

    echo ""
    echo -e "  ${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${GREEN}GOST - Port forwarding (TCP)${NC}  IRAN -> KHAREJ                   ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}>> Backend (tunnel)${NC} ${CYAN}$BACKEND_IP${NC}"
    GOST_MODE="tcp"

    # Load existing ports if re-running
    existing_ports=""
    [ -f "$GOST_PORTS" ] && existing_ports=$(tr '\n' ',' < "$GOST_PORTS" | sed 's/,$//')
    [ -f "$GOST_CONF" ] && . "$GOST_CONF" 2>/dev/null
    if [ -n "$existing_ports" ]; then
        echo -e "  ${YELLOW}>> Current GOST ports${NC}  ${CYAN}$existing_ports${NC}"
    fi
    echo ""
    echo -e "  Format: ${CYAN}listen_port=backend_port${NC} (comma separated)"
    echo -e "  Example: ${CYAN}443=9321,80=8080,2070=2070${NC}"
    echo ""
    read -p "  New port(s) to add: " PORTS_INPUT

    if [ -z "$PORTS_INPUT" ]; then
        echo -e "  ${YELLOW}No input. Nothing changed.${NC}"
        exit 0
    fi

    # Append new ports to list (avoid duplicates)
    for pair in $(echo "$PORTS_INPUT" | tr ',' '\n'); do
        pair=$(echo "$pair" | tr -d ' ')
        [[ "$pair" =~ ^([0-9]+)=([0-9]+)$ ]] || continue
        LPORT="${BASH_REMATCH[1]}"
        BPORT="${BASH_REMATCH[2]}"
        if [ -f "$GOST_PORTS" ] && grep -qx "${LPORT}=${BPORT}" "$GOST_PORTS" 2>/dev/null; then
            echo -e "  ${YELLOW}Port ${LPORT}=${BPORT} already in config, skipped.${NC}"
            continue
        fi
        mkdir -p "$GOST_DIR"
        echo "${LPORT}=${BPORT}" >> "$GOST_PORTS"
        echo -e "  ${GREEN}✓${NC} Port ${CYAN}${LPORT}${NC} → $BACKEND_IP:${BPORT} (${GOST_MODE})"
    done

    # Save mode and backend for service
    mkdir -p "$GOST_DIR"
    echo "GOST_MODE=$GOST_MODE" > "$GOST_CONF"
    echo "BACKEND_IP=$BACKEND_IP" >> "$GOST_CONF"

    # Build gost -L arguments from ports file (TCP only)
    GOST_L_ARGS=()
    while IFS='=' read -r LPORT BPORT; do
        [ -z "$LPORT" ] && continue
        GOST_L_ARGS+=("tcp://:${LPORT}/${BACKEND_IP}:${BPORT}")
    done < "$GOST_PORTS" 2>/dev/null

    if [ ${#GOST_L_ARGS[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}No valid ports in config.${NC}"
        exit 0
    fi

    # Build ExecStart: one "-L URL" per port
    EXEC_START="$GOST_CMD"
    for url in "${GOST_L_ARGS[@]}"; do
        EXEC_START="$EXEC_START -L $url"
    done

    # Systemd unit
    cat > /etc/systemd/system/gost-gre.service << EOF
[Unit]
Description=GOST TCP port forwarding (gre-haproxy)
After=network.target

[Service]
Type=simple
ExecStart=$EXEC_START
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable gost-gre
    systemctl restart gost-gre
    sleep 1
    if systemctl is-active gost-gre &>/dev/null; then
        echo ""
        echo -e "  ${GREEN}GOST is running. Port forwarding active (TCP).${NC}"
    else
        echo -e "  ${RED}GOST failed to start. Check: journalctl -u gost-gre -n 30${NC}"
    fi
    echo ""
    exit 0
fi

# ----- GOST Reverse Tunnel (outside -> Iran): Server on KHAREJ, Client on IRAN -----
GOST_REVERSE_DIR="/etc/gost-reverse-tunnel"
GOST_REVERSE_CONF="$GOST_REVERSE_DIR/config"
if [ "$SIDE" = "gost-reverse" ]; then
    GOST_BIN="/usr/local/bin/gost"
    if ! command -v gost &>/dev/null && [ ! -x "$GOST_BIN" ]; then
        echo -e "  ${YELLOW}Installing GOST...${NC}"
        GOST_VER="3.2.6"
        ARCH=$(uname -m)
        case "$ARCH" in x86_64|amd64) GOST_ARCH="amd64";; aarch64|arm64) GOST_ARCH="arm64";; armv7l|armhf) GOST_ARCH="armv7";; i386|i686) GOST_ARCH="386";; *) GOST_ARCH="amd64";; esac
        GURL="https://github.com/go-gost/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_linux_${GOST_ARCH}.tar.gz"
        tmpdir=$(mktemp -d)
        trap "rm -rf $tmpdir" EXIT
        if ! curl -sSLf -o "$tmpdir/gost.tar.gz" "$GURL" 2>/dev/null; then
            echo -e "  ${RED}Download failed. Try: wget $GURL${NC}"
            exit 1
        fi
        tar -xzf "$tmpdir/gost.tar.gz" -C "$tmpdir"
        mkdir -p /usr/local/bin
        if [ -f "$tmpdir/gost" ]; then cp -f "$tmpdir/gost" "$GOST_BIN"; else find "$tmpdir" -maxdepth 2 -type f -name gost -exec cp -f {} "$GOST_BIN" \;; fi
        chmod +x "$GOST_BIN"
        [ ! -x "$GOST_BIN" ] && echo -e "  ${RED}GOST install failed.${NC}" && exit 1
        echo -e "  ${GREEN}GOST installed.${NC}"
    fi
    [ -x "$GOST_BIN" ] || { echo -e "  ${RED}GOST not found at $GOST_BIN${NC}"; exit 1; }

    echo ""
    echo -e "  ${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}   ${GREEN}GOST Reverse Tunnel${NC}  (outside <-> Iran)                        ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}  |${NC}  ${GREEN}1${NC}) Server - run where visitors connect (entrypoint)"
    echo -e "  ${CYAN}  |${NC}  ${GREEN}2${NC}) Client - run where the local service (e.g. V2Ray) is"
    echo -e "  ${CYAN}  |${NC}  ${DIM}  For \"V2Ray on Germany, address Iran\": run 1 on IRAN, 2 on KHAREJ (see README).${NC}"
    echo -e "  ${CYAN}  +------------------------------------------------------------------${NC}"
    read -p "  Server or Client? (1 or 2): " rev_side

    if [ "$rev_side" = "1" ]; then
        # ---- Server (KHAREJ) ----
        echo ""
        echo -e "  ${YELLOW}>> Server = entrypoint. Visitors connect here; traffic is sent to the Client.${NC}"
        read -p "  Entrypoint port (public, e.g. 80) [80]: " EPORT
        EPORT=${EPORT:-80}
        read -p "  Tunnel service port (e.g. 8443) [8443]: " TPORT
        TPORT=${TPORT:-8443}
        read -p "  Hostname for this tunnel (e.g. iran.example.com): " REV_HOST
        REV_HOST=$(echo "$REV_HOST" | tr -d ' ')
        [ -z "$REV_HOST" ] && REV_HOST="reverse.local"
        read -p "  Tunnel ID (UUID, or press Enter to generate): " TUNNEL_ID
        if [ -z "$TUNNEL_ID" ]; then
            TUNNEL_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "4d21094e-b74c-4916-86c1-d9fa36ea677b")
        fi
        mkdir -p "$GOST_REVERSE_DIR"
        echo "ROLE=server" > "$GOST_REVERSE_CONF"
        echo "ENTRYPOINT_PORT=$EPORT" >> "$GOST_REVERSE_CONF"
        echo "TUNNEL_PORT=$TPORT" >> "$GOST_REVERSE_CONF"
        echo "HOSTNAME=$REV_HOST" >> "$GOST_REVERSE_CONF"
        echo "TUNNEL_ID=$TUNNEL_ID" >> "$GOST_REVERSE_CONF"
        # gost -L "tunnel://:8443?entrypoint=:80&tunnel=hostname:UUID"
        REV_CMD="$GOST_BIN -L \"tunnel://:${TPORT}?entrypoint=:${EPORT}&tunnel=${REV_HOST}:${TUNNEL_ID}\""
        cat > /etc/systemd/system/gost-reverse-tunnel.service << EOF
[Unit]
Description=GOST reverse tunnel server (outside)
After=network.target

[Service]
Type=simple
ExecStart=$GOST_BIN -L "tunnel://:${TPORT}?entrypoint=:${EPORT}&tunnel=${REV_HOST}:${TUNNEL_ID}"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable gost-reverse-tunnel
        systemctl restart gost-reverse-tunnel
        sleep 1
        echo ""
        echo -e "  ${GREEN}Reverse tunnel server is running.${NC}"
        echo -e "  ${DIM}On the other server (Client) run this script, option 8, then choose 2 (Client) and use:${NC}"
        echo -e "  ${CYAN}Tunnel ID: ${TUNNEL_ID}${NC}"
        echo -e "  ${DIM}Server address: THIS_MACHINE_IP:${TPORT}  (this machine = tunnel server)${NC}"
        echo ""
        exit 0
    fi

    if [ "$rev_side" = "2" ]; then
        # ---- Client (IRAN) ----
        echo ""
        echo -e "  ${YELLOW}>> Client connects to the tunnel Server and forwards traffic to local service (e.g. V2Ray).${NC}"
        read -p "  Server address (tunnel server IP or domain:port, e.g. 1.2.3.4:8443): " REV_SERVER
        REV_SERVER=$(echo "$REV_SERVER" | tr -d ' ')
        [ -z "$REV_SERVER" ] && { echo -e "  ${RED}Server address required.${NC}"; exit 1; }
        read -p "  Tunnel ID (must match server): " TUNNEL_ID
        TUNNEL_ID=$(echo "$TUNNEL_ID" | tr -d ' ')
        [ -z "$TUNNEL_ID" ] && { echo -e "  ${RED}Tunnel ID required.${NC}"; exit 1; }
        read -p "  Local target (e.g. 127.0.0.1:80 or 192.168.1.1:443) [127.0.0.1:80]: " LOCAL_TARGET
        LOCAL_TARGET=${LOCAL_TARGET:-127.0.0.1:80}
        mkdir -p "$GOST_REVERSE_DIR"
        echo "ROLE=client" > "$GOST_REVERSE_CONF"
        echo "SERVER=$REV_SERVER" >> "$GOST_REVERSE_CONF"
        echo "TUNNEL_ID=$TUNNEL_ID" >> "$GOST_REVERSE_CONF"
        echo "LOCAL_TARGET=$LOCAL_TARGET" >> "$GOST_REVERSE_CONF"
        # gost -L rtcp://:0/127.0.0.1:80 -F "tunnel://SERVER:8443?tunnel.id=UUID"
        cat > /etc/systemd/system/gost-reverse-tunnel.service << EOF
[Unit]
Description=GOST reverse tunnel client (Iran)
After=network.target

[Service]
Type=simple
ExecStart=$GOST_BIN -L rtcp://:0/${LOCAL_TARGET} -F "tunnel://${REV_SERVER}?tunnel.id=${TUNNEL_ID}"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable gost-reverse-tunnel
        systemctl restart gost-reverse-tunnel
        sleep 1
        echo ""
        if systemctl is-active gost-reverse-tunnel &>/dev/null; then
            echo -e "  ${GREEN}Reverse tunnel client is running. Traffic from outside -> server -> this host -> ${LOCAL_TARGET}${NC}"
        else
            echo -e "  ${RED}Failed to start. Check: journalctl -u gost-reverse-tunnel -n 30${NC}"
        fi
        echo ""
        exit 0
    fi

    echo -e "  ${RED}Invalid. Choose 1 (Server) or 2 (Client).${NC}"
    exit 1
fi

# ----- KHAREJ: add one IRAN tunnel -----
if [ "$SIDE" = "kharej" ]; then
    echo -e "  ${CYAN}+-- KHAREJ - Add one IRAN server -----------------${NC}"
    echo ""
    if [ -n "$MY_IP" ]; then
        read -p "  Use ${MY_IP} as KHAREJ server IP? (y/n): " use_k
        if [[ "$use_k" =~ ^[yY] ]]; then
            KHAREJ_IP="$MY_IP"
        else
            read -p "  Enter KHAREJ server public IP: " KHAREJ_IP
        fi
    else
        read -p "  Enter KHAREJ server public IP: " KHAREJ_IP
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
        echo -e "  ${DIM}$N_IRAN IRAN server(s) already connected.${NC}"
        echo ""
    fi

    echo -e "  ${YELLOW}Enter public IP of the new IRAN server:${NC}"
    read -p "  IP: " new_iran_ip
    if [ -z "$new_iran_ip" ]; then
        echo -e "  ${RED}IP is required.${NC}"
        exit 1
    fi
    N_IRAN=$((N_IRAN + 1))
    IRAN_IPS+=("$new_iran_ip")

    iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${N_IRAN}"
    if ip link show "$iface" &>/dev/null; then
        echo -e "  ${YELLOW}Replacing existing $iface...${NC}"
        ip link set "$iface" down 2>/dev/null || true
        ip tunnel del "$iface" 2>/dev/null || true
    fi
    kcidr=$(tunnel_kharej_cidr "$N_IRAN")
    echo ""
    echo -e "  ${GREEN}Creating tunnel $iface (IRAN #$N_IRAN)...${NC}"
    ip tunnel add "$iface" mode gre local "$KHAREJ_IP" remote "$new_iran_ip" ttl 255
    ip addr add "$kcidr" dev "$iface"
    ip link set "$iface" mtu 1436
    ip link set "$iface" up
    sysctl -w "net.ipv4.conf.$iface.rp_filter=0" 2>/dev/null || true
    echo -e "  ${GREEN}Done.${NC} On the IRAN server run option 1 with index ${CYAN}$N_IRAN${NC}."

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
    echo -e "  ${GREEN}Tunnel commands saved to $RCLOCAL.${NC}"
    echo ""
    echo -e "  ${GREEN}KHAREJ ready. On the IRAN server run this script, option 1 (IRAN), index $N_IRAN.${NC}"
    echo -e "  Backend IP for that IRAN: ${CYAN}$(tunnel_kharej_ip "$N_IRAN")${NC}"
    echo ""
    exit 0
fi

# ----- IRAN: single tunnel -----
echo -e "  ${CYAN}+-- IRAN - Setup tunnel on this server -----------${NC}"
echo ""
echo -e "  ${YELLOW}This IRAN server index (1=first, 2=second, ...). Must match order added on KHAREJ.${NC}"
read -p "  IRAN index (1, 2, 3, ...): " IRAN_INDEX
IRAN_INDEX=$((IRAN_INDEX + 0))
if [ "$IRAN_INDEX" -lt 1 ]; then
    echo -e "  ${RED}Index must be at least 1.${NC}"
    exit 1
fi

if [ -n "$MY_IP" ]; then
    read -p "  Use ${MY_IP} as this IRAN server IP? (y/n): " use_iran
    if [[ "$use_iran" =~ ^[yY] ]]; then
        IRAN_IP="$MY_IP"
    else
        read -p "  Enter this IRAN server public IP: " IRAN_IP
    fi
else
    read -p "  Enter this IRAN server public IP: " IRAN_IP
fi
read -p "  Enter KHAREJ server public IP: " KHAREJ_IP

if [ -z "$IRAN_IP" ] || [ -z "$KHAREJ_IP" ]; then
    echo -e "  ${RED}Both IRAN and KHAREJ IPs are required.${NC}"
    exit 1
fi

if ip tunnel show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
    echo -e "  ${YELLOW}Replacing existing tunnel...${NC}"
    ip link set "$TUNNEL_IFACE_IRAN" down 2>/dev/null || true
    ip tunnel del "$TUNNEL_IFACE_IRAN" 2>/dev/null || true
fi

MY_CIDR=$(tunnel_cidr "$IRAN_INDEX")
BACKEND_IP=$(tunnel_kharej_ip "$IRAN_INDEX")

echo ""
echo -e "  ${GREEN}Creating GRE tunnel (IRAN #$IRAN_INDEX -> $BACKEND_IP)...${NC}"
ip tunnel add "$TUNNEL_IFACE_IRAN" mode gre local "$IRAN_IP" remote "$KHAREJ_IP" ttl 255
ip addr add "$MY_CIDR" dev "$TUNNEL_IFACE_IRAN"
ip link set "$TUNNEL_IFACE_IRAN" mtu 1436
ip link set "$TUNNEL_IFACE_IRAN" up
sysctl -w "net.ipv4.conf.$TUNNEL_IFACE_IRAN.rp_filter=0" 2>/dev/null || true
echo -e "  ${GREEN}Done.${NC} This server: ${CYAN}$MY_CIDR${NC}, KHAREJ side: ${CYAN}$BACKEND_IP${NC}"
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
echo -e "  ${GREEN}Tunnel commands saved to rc.local (run at boot).${NC}"
echo ""
echo -e "  ${GREEN}IRAN tunnel ready. Test: ping $BACKEND_IP${NC}"
echo -e "  To add port forwarding, run this script again and choose option 6 (HAProxy)."
echo ""
