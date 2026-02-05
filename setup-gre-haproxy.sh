#!/bin/bash
#
# GRE tunnel + HAProxy setup: multiple IRAN servers -> one KHAREJ server.
# Each IRAN gets its own GRE interface and /30 subnet to avoid conflicts.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="/etc/gre-haproxy.conf"
RCLOCAL="/etc/rc.local"
GRE_MARKER_START="# gre-haproxy tunnels start"
GRE_MARKER_END="# gre-haproxy tunnels end"
TUNNEL_IFACE_IRAN="gre-haproxy"
TUNNEL_IFACE_KHAREJ_PREFIX="gre-haproxy"

# Subnet for tunnel index i: 10.10.(10*i).0/30 -> Iran .1, Kharej .2
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

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  GRE tunnel + HAProxy (multi-IRAN / one KHAREJ)${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run as root (sudo).${NC}"
    exit 1
fi

MY_IP=$(detect_my_ip)
if [ -n "$MY_IP" ]; then
    echo -e "${GREEN}This server IP (detected): ${CYAN}${MY_IP}${NC}"
    echo ""
fi

echo -e "${YELLOW}Select action:${NC}"
echo "  1) IRAN - Setup (this server is one of the Iran servers)"
echo "  2) KHAREJ - Setup (this server is the single Kharej server)"
echo "  3) Remove - Remove GRE tunnel(s) and HAProxy from this server"
echo "  4) Status - Show tunnel and HAProxy status"
echo "  5) iperf3 test - Bandwidth test (10 connections, IRAN→KHAREJ)"
read -p "Choice (1, 2, 3, 4 or 5): " side_choice

case "$side_choice" in
    1) SIDE="iran";;
    2) SIDE="kharej";;
    3) SIDE="remove";;
    4) SIDE="status";;
    5) SIDE="iperf";;
    *)
        echo -e "${RED}Invalid choice.${NC}"
        exit 1
        ;;
esac

echo ""

# ----- REMOVE: tear down GRE and HAProxy -----
if [ "$SIDE" = "remove" ]; then
    echo -e "${YELLOW}Remove as which side?${NC}"
    echo "  1) IRAN (remove gre-haproxy tunnel + HAProxy)"
    echo "  2) KHAREJ (remove all gre-haproxy1, gre-haproxy2, ... tunnels)"
    read -p "Choice (1 or 2): " remove_side

    if [ "$remove_side" = "2" ]; then
        # KHAREJ: remove all gre-haproxyN interfaces
        for i in $(seq 1 32); do
            iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${i}"
            if ip link show "$iface" &>/dev/null; then
                echo -e "${YELLOW}Removing $iface...${NC}"
                ip link set "$iface" down 2>/dev/null || true
                ip tunnel del "$iface" 2>/dev/null || true
                echo -e "${GREEN}Removed $iface${NC}"
            fi
        done
        [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE" && echo -e "${GREEN}Removed $CONFIG_FILE${NC}"
    else
        # IRAN: remove gre-haproxy interface
        if ip link show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
            echo -e "${YELLOW}Removing $TUNNEL_IFACE_IRAN...${NC}"
            ip link set "$TUNNEL_IFACE_IRAN" down 2>/dev/null || true
            ip tunnel del "$TUNNEL_IFACE_IRAN" 2>/dev/null || true
            echo -e "${GREEN}Removed $TUNNEL_IFACE_IRAN${NC}"
        else
            echo -e "${YELLOW}Interface $TUNNEL_IFACE_IRAN not found.${NC}"
        fi

        # HAProxy: stop service and restore or clear config
        read -p "Also remove HAProxy config and stop HAProxy? (y/n): " remove_haproxy
        if [[ "$remove_haproxy" =~ ^[yY] ]]; then
            systemctl stop haproxy 2>/dev/null || true
            systemctl disable haproxy 2>/dev/null || true
            if [ -f /etc/haproxy/haproxy.cfg.bak ]; then
                cp /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
                echo -e "${GREEN}Restored HAProxy config from backup.${NC}"
            else
                # Minimal valid config so haproxy can start if needed later
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
                echo -e "${GREEN}HAProxy config cleared (minimal).${NC}"
            fi
            echo -e "${GREEN}HAProxy stopped and disabled.${NC}"
        fi
    fi

    # Remove our block from rc.local (both IRAN and KHAREJ)
    if [ -f "$RCLOCAL" ] && grep -q "$GRE_MARKER_START" "$RCLOCAL" 2>/dev/null; then
        sed -i "/$GRE_MARKER_START/,/$GRE_MARKER_END/d" "$RCLOCAL"
        sed -i '/^$/N;/^\n$/d' "$RCLOCAL" 2>/dev/null || true
        echo -e "${GREEN}Removed tunnel commands from $RCLOCAL${NC}"
    fi

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Remove done.${NC}"
    echo -e "${GREEN}============================================${NC}"
    exit 0
fi

# ----- STATUS: show tunnel and HAProxy status -----
if [ "$SIDE" = "status" ]; then
    echo ""
    echo -e "  ${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${CYAN}║${NC}                    ${GREEN}GRE Tunnel Status${NC}                         ${CYAN}║${NC}"
    echo -e "  ${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Detect side: KHAREJ has gre-haproxy1 ; IRAN has gre-haproxy only
    if ip link show "${TUNNEL_IFACE_KHAREJ_PREFIX}1" &>/dev/null; then
        echo -e "  ${YELLOW}▶ Role${NC}      ${GREEN}KHAREJ${NC} (this server aggregates multiple IRAN tunnels)"
        echo ""
        if [ -f "$CONFIG_FILE" ]; then
            KHAREJ_IP=$(sed -n '1p' "$CONFIG_FILE")
            N_IRAN=$(sed -n '2p' "$CONFIG_FILE")
            N_IRAN=$((N_IRAN + 0))
            echo -e "  ${YELLOW}▶ This server${NC}  ${CYAN}$KHAREJ_IP${NC}"
            echo -e "  ${YELLOW}▶ Tunnels${NC}      $N_IRAN IRAN server(s) connected"
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
            echo -e "  ${YELLOW}▶ Config${NC}     ${YELLOW}No $CONFIG_FILE${NC} — tunnel interfaces:"
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
        echo -e "  ${YELLOW}▶ Role${NC}      ${GREEN}IRAN${NC} (single tunnel to KHAREJ)"
        echo ""
        echo -e "  ${YELLOW}▶ Interface${NC}   ${CYAN}$TUNNEL_IFACE_IRAN${NC}"
        echo -e "  ${YELLOW}▶ This side${NC}    ${CYAN}${our_cidr:-—}${NC}  (this server)"
        echo -e "  ${YELLOW}▶ KHAREJ side${NC}  ${CYAN}${backend_ip}${NC}  (tunnel endpoint)"
        echo ""
        if ping -c 2 -W 2 "$backend_ip" &>/dev/null; then
            echo -e "  ${YELLOW}▶ Connectivity${NC} ${GREEN}✓ Reachable${NC} — tunnel is up"
        else
            echo -e "  ${YELLOW}▶ Connectivity${NC} ${RED}✗ Unreachable${NC} — check tunnel or KHAREJ"
        fi
    else
        echo -e "  ${YELLOW}▶ Role${NC}      No gre-haproxy tunnel on this server."
        echo -e "                 Run setup (option 1 or 2) first."
    fi

    echo ""
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    if systemctl is-active haproxy &>/dev/null; then
        echo -e "  ${CYAN}│${NC} ${YELLOW}HAProxy${NC}   ${GREEN}● Running${NC}                                              ${CYAN}│${NC}"
    else
        echo -e "  ${CYAN}│${NC} ${YELLOW}HAProxy${NC}   ${YELLOW}○ Not running${NC} (or not installed)                         ${CYAN}│${NC}"
    fi
    if [ -f "$RCLOCAL" ] && grep -q "$GRE_MARKER_START" "$RCLOCAL" 2>/dev/null; then
        echo -e "  ${CYAN}│${NC} ${YELLOW}Boot${NC}      ${GREEN}● Tunnels in rc.local${NC} (will restore after reboot)     ${CYAN}│${NC}"
    else
        echo -e "  ${CYAN}│${NC} ${YELLOW}Boot${NC}      ${YELLOW}○ rc.local not configured${NC} — tunnels won’t restore on boot ${CYAN}│${NC}"
    fi
    echo -e "  ${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
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
        echo -e "${YELLOW}Testing IRAN → KHAREJ (this machine = client, KHAREJ = server at ${CYAN}$TARGET${NC})"
        echo -e "${YELLOW}${IPERF_STREAMS} streams, ${IPERF_DURATION}s. Ensure iperf3 server is running on KHAREJ (run this script on KHAREJ → 5 → Start server).${NC}"
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
            echo -e "${RED}iperf3 failed. Is iperf3 server running on KHAREJ? (run this script on KHAREJ → 5 → Start server)${NC}"
            [ -s "$tmpjson_err" ] && cat "$tmpjson_err"
        fi
        exit 0
    fi

    # KHAREJ = server: start iperf3 -s so IRAN can connect and test
    if ip link show "${TUNNEL_IFACE_KHAREJ_PREFIX}1" &>/dev/null; then
        echo -e "${CYAN}Start iperf3 server on this KHAREJ so IRAN can run the bandwidth test (IRAN = client).${NC}"
        read -p "Run server for 90 seconds? (y/n): " run_srv
        if [[ "$run_srv" =~ ^[yY] ]]; then
            echo -e "${GREEN}Starting iperf3 server (listening on 0.0.0.0:5201). Run test from IRAN within 90s (option 5).${NC}"
            echo ""
            timeout 90 iperf3 -s -1 2>/dev/null || timeout 90 iperf3 -s
            echo -e "${GREEN}Server stopped.${NC}"
        fi
        exit 0
    fi

    echo -e "${YELLOW}No tunnel found. Run on KHAREJ or IRAN with tunnel already set up.${NC}"
    exit 1
fi

# ----- KHAREJ: add one IRAN tunnel -----
if [ "$SIDE" = "kharej" ]; then
    read -p "Use ${MY_IP} as KHAREJ server IP? (y/n): " use_k
    if [[ "$use_k" =~ ^[yY] ]]; then
        KHAREJ_IP="$MY_IP"
    else
        read -p "Enter KHAREJ server public IP: " KHAREJ_IP
    fi

    IRAN_IPS=()
    N_IRAN=0
    if [ -f "$CONFIG_FILE" ]; then
        # Read existing: line1=KHAREJ_IP, line2=N, then N lines of IRAN IPs
        KHAREJ_IP=$(sed -n '1p' "$CONFIG_FILE")
        N_IRAN=$(sed -n '2p' "$CONFIG_FILE")
        N_IRAN=$((N_IRAN + 0))
        for i in $(seq 1 "$N_IRAN"); do
            line=$((2 + i))
            ip=$(sed -n "${line}p" "$CONFIG_FILE")
            [ -n "$ip" ] && IRAN_IPS+=("$ip")
        done
    fi

    echo -e "${YELLOW}Add new IRAN server. Enter public IP of the new IRAN server:${NC}"
    read -p "New IRAN server IP: " new_iran_ip
    if [ -z "$new_iran_ip" ]; then
        echo -e "${RED}IP required.${NC}"
        exit 1
    fi
    N_IRAN=$((N_IRAN + 1))
    IRAN_IPS+=("$new_iran_ip")

    # Create only the new tunnel (gre-haproxyN)
    iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${N_IRAN}"
    if ip link show "$iface" &>/dev/null; then
        echo -e "${YELLOW}Removing existing $iface...${NC}"
        ip link set "$iface" down 2>/dev/null || true
        ip tunnel del "$iface" 2>/dev/null || true
    fi
    kcidr=$(tunnel_kharej_cidr "$N_IRAN")
    echo -e "${GREEN}Creating $iface (IRAN #$N_IRAN: $new_iran_ip -> $kcidr)...${NC}"
    ip tunnel add "$iface" mode gre local "$KHAREJ_IP" remote "$new_iran_ip" ttl 255
    ip addr add "$kcidr" dev "$iface"
    ip link set "$iface" mtu 1436
    ip link set "$iface" up
    sysctl -w "net.ipv4.conf.$iface.rp_filter=0" 2>/dev/null || true
    echo -e "${GREEN}Added $iface. Tell this IRAN to use index $N_IRAN.${NC}"

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
    echo -e "${GREEN}Tunnel commands written to $RCLOCAL${NC}"
    echo ""
    echo -e "Tunnels: ${CYAN}ip addr show | grep $TUNNEL_IFACE_KHAREJ_PREFIX${NC}"
    echo -e "This IRAN must use index ${CYAN}$N_IRAN${NC} and backend IP $(tunnel_kharej_ip "$N_IRAN")"
    echo -e "If rc.local does not run on boot: ${CYAN}systemctl enable rc-local${NC}"
    exit 0
fi

# ----- IRAN: single tunnel, index 1..N -----
echo -e "${YELLOW}This IRAN server index (1=first, 2=second, ...). Must match KHAREJ setup.${NC}"
read -p "IRAN index (1, 2, 3, ...): " IRAN_INDEX
IRAN_INDEX=$((IRAN_INDEX + 0))
if [ "$IRAN_INDEX" -lt 1 ]; then
    echo -e "${RED}Index must be at least 1.${NC}"
    exit 1
fi

if [ -n "$MY_IP" ]; then
    read -p "Use ${MY_IP} as this IRAN server IP? (y/n): " use_iran
    if [[ "$use_iran" =~ ^[yY] ]]; then
        IRAN_IP="$MY_IP"
    else
        read -p "Enter this IRAN server public IP: " IRAN_IP
    fi
else
    read -p "Enter this IRAN server public IP: " IRAN_IP
fi
read -p "Enter KHAREJ server public IP: " KHAREJ_IP

if [ -z "$IRAN_IP" ] || [ -z "$KHAREJ_IP" ]; then
    echo -e "${RED}IRAN and KHAREJ IPs are required.${NC}"
    exit 1
fi

# This IRAN uses single tunnel interface gre-haproxy
if ip tunnel show "$TUNNEL_IFACE_IRAN" &>/dev/null; then
    echo -e "${YELLOW}Removing existing $TUNNEL_IFACE_IRAN...${NC}"
    ip link set "$TUNNEL_IFACE_IRAN" down 2>/dev/null || true
    ip tunnel del "$TUNNEL_IFACE_IRAN" 2>/dev/null || true
fi

MY_CIDR=$(tunnel_cidr "$IRAN_INDEX")
BACKEND_IP=$(tunnel_kharej_ip "$IRAN_INDEX")

echo ""
echo -e "${GREEN}Creating GRE tunnel (IRAN #$IRAN_INDEX -> $BACKEND_IP)...${NC}"
ip tunnel add "$TUNNEL_IFACE_IRAN" mode gre local "$IRAN_IP" remote "$KHAREJ_IP" ttl 255
ip addr add "$MY_CIDR" dev "$TUNNEL_IFACE_IRAN"
ip link set "$TUNNEL_IFACE_IRAN" mtu 1436
ip link set "$TUNNEL_IFACE_IRAN" up
sysctl -w "net.ipv4.conf.$TUNNEL_IFACE_IRAN.rp_filter=0" 2>/dev/null || true
echo -e "${GREEN}Tunnel created: this IRAN $MY_CIDR, backend (KHAREJ) $BACKEND_IP${NC}"
ip addr show "$TUNNEL_IFACE_IRAN"
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
echo -e "${GREEN}Commands added to $RCLOCAL${NC}"

# HAProxy on IRAN: forward to this tunnel's KHAREJ IP
echo ""
echo -e "${CYAN}--------------------------------------------${NC}"
echo -e "${YELLOW}HAProxy port forward (to KHAREJ $BACKEND_IP)${NC}"
echo -e "${YELLOW}Format: listen_port=backend_port (comma separated)${NC}"
echo -e "${YELLOW}Example: 443=9321,80=8080,2070=2070${NC}"
echo -e "${CYAN}--------------------------------------------${NC}"
read -p "Ports: " PORTS_INPUT

if [ -n "$PORTS_INPUT" ]; then
    if ! command -v haproxy &>/dev/null; then
        echo -e "${YELLOW}Installing HAProxy...${NC}"
        apt-get update -qq
        apt-get install -y haproxy
    fi

    [ -f /etc/haproxy/haproxy.cfg ] && cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak

    CFG="/etc/haproxy/haproxy.cfg"
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

    IFS=',' read -ra PAIRS <<< "$PORTS_INPUT"
    for pair in "${PAIRS[@]}"; do
        pair=$(echo "$pair" | tr -d ' ')
        if [[ "$pair" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            LPORT="${BASH_REMATCH[1]}"
            BPORT="${BASH_REMATCH[2]}"
            cat >> "$CFG" << EOF

backend tunnel_${LPORT}
    mode tcp
    server s1 ${BACKEND_IP}:${BPORT} check

frontend fe_${LPORT}
    mode tcp
    bind 0.0.0.0:${LPORT}
    default_backend tunnel_${LPORT}
EOF
            echo -e "  ${GREEN}Port ${LPORT} -> ${BACKEND_IP}:${BPORT}${NC}"
        fi
    done

    if haproxy -c -f "$CFG" 2>/dev/null; then
        systemctl enable haproxy 2>/dev/null || true
        systemctl restart haproxy 2>/dev/null || systemctl start haproxy
        echo -e "${GREEN}HAProxy started.${NC}"
    else
        echo -e "${RED}HAProxy config error. Check: haproxy -c -f $CFG${NC}"
    fi
else
    echo -e "${YELLOW}No ports entered. HAProxy not configured.${NC}"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Done.${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Tunnel: ${CYAN}ip addr show $TUNNEL_IFACE_IRAN${NC}"
echo -e "Test: ${CYAN}ping $BACKEND_IP${NC}"
echo -e "HAProxy: ${CYAN}systemctl status haproxy${NC}"
echo -e "If rc.local does not run on boot: ${CYAN}systemctl enable rc-local${NC}"
echo ""
