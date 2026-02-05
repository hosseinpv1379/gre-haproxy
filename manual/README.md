# GRE Tunnel + HAProxy Setup (Multi-IRAN / One KHAREJ)

Interactive script to set up **multiple IRAN servers** connecting to **one KHAREJ server** over GRE tunnels, with **HAProxy port forwarding** on each IRAN. Each tunnel uses its own subnet so there are no network conflicts.

## Topology

```
  IRAN #1 (gre1)  ----\
                        \
  IRAN #2 (gre1)  -------+----  KHAREJ (gre1, gre2, gre3, ...)
                        /
  IRAN #3 (gre1)  ----/
```

- **KHAREJ**: One server with multiple GRE interfaces (`gre1`, `gre2`, `gre3`, ...). Each `greN` goes to one IRAN and uses a dedicated /30 subnet.
- **IRAN**: Each IRAN server has a single `gre1` to KHAREJ and uses one /30 subnet. No overlap between IRANs.

## Subnets (no conflicts)

| IRAN index | Subnet        | IRAN side   | KHAREJ side  | KHAREJ iface |
|------------|---------------|-------------|--------------|--------------|
| 1          | 10.10.10.0/30 | 10.10.10.1  | 10.10.10.2   | gre1         |
| 2          | 10.10.20.0/30 | 10.10.20.1  | 10.10.20.2   | gre2         |
| 3          | 10.10.30.0/30 | 10.10.30.1  | 10.10.30.2   | gre3         |
| ...        | 10.10.(10*i).0/30 | .1     | .2           | gre(i)       |

So you can run many IRANs against one KHAREJ without route or address clashes.

## What the script does

- Detects and shows this server’s public IP and asks whether to use it.
- **KHAREJ**: Asks how many IRAN servers (N), then asks each IRAN’s public IP. Creates `gre1`..`greN` with the subnets above and writes all tunnel bring-up commands to `rc.local`. Saves state to `/etc/vortexl2-gre.conf`.
- **IRAN**: Asks “IRAN index” (1, 2, 3, ...) so it uses the correct subnet. Creates one `gre1` to KHAREJ, adds bring-up to `rc.local`. Then (optional) asks for HAProxy ports and configures HAProxy to forward to the KHAREJ side of this tunnel (e.g. 10.10.20.2 for IRAN #2).

## Requirements

- Linux with `ip` (iproute2)
- Root (run with `sudo`)
- HAProxy: script can install it via `apt` (Debian/Ubuntu)

## Usage

### 1. On KHAREJ (once)

```bash
chmod +x setup-gre-haproxy.sh
sudo ./setup-gre-haproxy.sh
```

- Choose **2) KHAREJ**.
- Confirm or set KHAREJ public IP.
- Enter **number of IRAN servers** (e.g. 3).
- Enter **public IP of IRAN #1, #2, #3** (in order).

The script creates `gre1`, `gre2`, `gre3` and writes all of them to `rc.local`.

### 2. On each IRAN server

Run the script once per IRAN:

```bash
sudo ./setup-gre-haproxy.sh
```

- Choose **1) IRAN**.
- Enter **IRAN index**: 1 for first Iran, 2 for second, etc. (must match the order you used on KHAREJ).
- Confirm or set this IRAN’s public IP.
- Enter KHAREJ public IP.
- Optionally enter HAProxy ports (e.g. `443=9321,80=8080`).

Each IRAN gets one `gre1` and its own subnet; HAProxy on that IRAN forwards to the corresponding KHAREJ IP (e.g. 10.10.20.2 for index 2).

## Port format (IRAN side)

Comma-separated:

```text
listen_port=backend_port
```

Example: `443=9321,80=8080,2070=2070`  
Backend is always the KHAREJ side of that IRAN’s tunnel (e.g. 10.10.20.2 for IRAN #2).

## Files

| File | Description |
|------|-------------|
| `setup-gre-haproxy.sh` | Main script (multi-IRAN, one KHAREJ) |
| `port-forward-haproxy.txt` | Manual HAProxy reference |
| `/etc/vortexl2-gre.conf` | KHAREJ: saved list of IRAN IPs (used if you extend the script later) |

## rc.local and boot

Tunnel commands are written between markers in `/etc/rc.local`. If `rc.local` does not run on boot:

```bash
sudo systemctl enable rc-local
# or
sudo systemctl enable rc.local
```

## Checks after setup

- **KHAREJ**: `ip addr show | grep gre` (see gre1, gre2, …). Ping from IRAN: `ping 10.10.10.2` (or .20.2, .30.2 for IRAN 2, 3).
- **IRAN**: `ip addr show gre1`, `ping 10.10.x.2` (x = 10, 20, 30 for index 1, 2, 3).
- **HAProxy (each IRAN)**: `systemctl status haproxy`, `ss -tlnp | grep haproxy`.

## HAProxy config

- Config: `/etc/haproxy/haproxy.cfg`
- Backup: `/etc/haproxy/haproxy.cfg.bak`

To change ports, edit the config then:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy
```

## Summary

- **Multiple IRAN, one KHAREJ**: supported; each IRAN has its own GRE and /30.
- **No network conflicts**: separate subnets (10.10.10.0/30, 10.10.20.0/30, …) and separate GRE interfaces on KHAREJ.
- **Index alignment**: IRAN index on each Iran server must match the order of IRAN IPs entered on KHAREJ (1 = first, 2 = second, …).
