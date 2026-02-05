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

echo -e "${YELLOW}Select server side:${NC}"
echo "  1) IRAN (this server is one of the Iran servers)"
echo "  2) KHAREJ (this server is the single Kharej server)"
read -p "Choice (1 or 2): " side_choice

case "$side_choice" in
    1) SIDE="iran";;
    2) SIDE="kharej";;
    *)
        echo -e "${RED}Invalid choice.${NC}"
        exit 1
        ;;
esac

echo ""

# ----- KHAREJ: multiple IRAN tunnels -----
if [ "$SIDE" = "kharej" ]; then
    read -p "Use ${MY_IP} as KHAREJ server IP? (y/n): " use_k
    if [[ "$use_k" =~ ^[yY] ]]; then
        KHAREJ_IP="$MY_IP"
    else
        read -p "Enter KHAREJ server public IP: " KHAREJ_IP
    fi

    echo -e "${YELLOW}How many IRAN servers will connect to this KHAREJ? (1, 2, 3, ...)${NC}"
    read -p "Number of IRAN servers: " N_IRAN
    N_IRAN=$((N_IRAN + 0))
    if [ "$N_IRAN" -lt 1 ]; then
        echo -e "${RED}Enter at least 1.${NC}"
        exit 1
    fi

    IRAN_IPS=()
    for i in $(seq 1 "$N_IRAN"); do
        read -p "Public IP of IRAN server #$i: " ip
        IRAN_IPS+=("$ip")
    done

    # Remove existing GRE interfaces used by us (gre-haproxy1, gre-haproxy2, ...)
    for i in $(seq 1 "$N_IRAN"); do
        iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${i}"
        if ip link show "$iface" &>/dev/null; then
            echo -e "${YELLOW}Removing existing $iface...${NC}"
            ip link set "$iface" down 2>/dev/null || true
            ip tunnel del "$iface" 2>/dev/null || true
        fi
    done

    echo ""
    echo -e "${GREEN}Creating $N_IRAN GRE tunnel(s) on KHAREJ...${NC}"
    for i in $(seq 1 "$N_IRAN"); do
        iface="${TUNNEL_IFACE_KHAREJ_PREFIX}${i}"
        iran_ip="${IRAN_IPS[$((i-1))]}"
        kcidr=$(tunnel_kharej_cidr "$i")
        ip tunnel add "$iface" mode gre local "$KHAREJ_IP" remote "$iran_ip" ttl 255
        ip addr add "$kcidr" dev "$iface"
        ip link set "$iface" mtu 1436
        ip link set "$iface" up
        echo -e "  ${GREEN}$iface: local $KHAREJ_IP remote $iran_ip -> $kcidr${NC}"
    done

    # Save state for possible "add tunnel" later
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "$KHAREJ_IP" > "$CONFIG_FILE"
    echo "$N_IRAN" >> "$CONFIG_FILE"
    for ip in "${IRAN_IPS[@]}"; do echo "$ip" >> "$CONFIG_FILE"; done

    # rc.local: ensure file exists, then replace our block
    if [ ! -f "$RCLOCAL" ]; then
        printf '%s\n' '#!/bin/bash' 'exit 0' > "$RCLOCAL"
        chmod +x "$RCLOCAL"
    fi
    # Remove old block
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
        done
        echo "$GRE_MARKER_END"
        echo ""
        echo "exit 0"
    } >> "$RCLOCAL"
    echo -e "${GREEN}Tunnel commands written to $RCLOCAL${NC}"
    echo ""
    echo -e "Tunnels: ${CYAN}ip addr show | grep $TUNNEL_IFACE_KHAREJ_PREFIX${NC}"
    echo -e "From each IRAN #i: ${CYAN}ping $(tunnel_kharej_ip 1)${NC} (or .20.2, .30.2, ...)"
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
