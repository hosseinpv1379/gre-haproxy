# GRE Tunnel + HAProxy

Set up **multiple IRAN servers** → **one KHAREJ server** over GRE tunnels with HAProxy port forwarding. Tunnel interface names: `gre-haproxy` (on each IRAN), `gre-haproxy1`, `gre-haproxy2`, … (on KHAREJ).

## Quick run (one-liner)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/hosseinpv1379/gre-haproxy/main/setup-gre-haproxy.sh)
```

- On **KHAREJ**: choose 2, then enter the **new IRAN server public IP** (each run adds one tunnel; first run = first IRAN, next runs = add more).
- On **each IRAN**: choose 1, enter IRAN index (1, 2, … — must match the order added on KHAREJ), then optionally HAProxy ports.
- **Remove**: choose 3 to remove GRE tunnel(s) and optionally HAProxy from this server (then choose IRAN or KHAREJ).

## Script and docs

| Link | Description |
|------|-------------|
| [setup-gre-haproxy.sh](https://github.com/hosseinpv1379/gre-haproxy/blob/main/setup-gre-haproxy.sh) | Main setup script |
| [Raw script (direct run)](https://raw.githubusercontent.com/hosseinpv1379/gre-haproxy/main/setup-gre-haproxy.sh) | Direct download URL |
| [Extended guide](manual/README.md) | Subnets, usage, troubleshooting |

## Requirements

- Linux, root (sudo)
- `apt` for HAProxy install (Debian/Ubuntu)

## GOST in this script (TCP only)

Option **7 (GOST)** in the script is **TCP** port forwarding only (IRAN → KHAREJ). No TLS/WSS/HTTP2.

## GOST Reverse Tunnel – connection from outside to Iran

To have **traffic from outside (e.g. Germany) reach Iran**, use GOST **Reverse Proxy Tunnel**. It runs **on both sides**: the **client on Iran** connects out to the **server on Germany**; visitors that hit Germany are sent through the tunnel to Iran.

**Flow:** Visitor → **Germany (tunnel server)** → tunnel (held by Iran client) → **Iran (tunnel client)** → local service in Iran.

- **Server (e.g. Germany):** Listens on a public entry (e.g. :80), has tunnel IDs (and optional hostname rules). Sends incoming traffic through the tunnel to the client.
- **Client (e.g. Iran):** Connects out to the server and keeps the tunnel open; forwards tunneled traffic to a local address.

**Example:**

1. **On Germany (server):**
   ```bash
   gost -L "tunnel://:8443?entrypoint=:80&tunnel=iran.example.com:4d21094e-b74c-4916-86c1-d9fa36ea677b"
   ```
2. **On Iran (client):**
   ```bash
   gost -L rtcp://:0/127.0.0.1:80 -F "tunnel://GERMANY_IP:8443?tunnel.id=4d21094e-b74c-4916-86c1-d9fa36ea677b"
   ```

Visitor requests to Germany (e.g. http://iran.example.com) are sent through the tunnel to Iran and forwarded to 127.0.0.1:80. Full docs: [GOST – Reverse Proxy Tunnel](https://gost.run/en/tutorials/reverse-proxy-tunnel/).

## Author

GitHub: [hosseinpv1379](https://github.com/hosseinpv1379)
