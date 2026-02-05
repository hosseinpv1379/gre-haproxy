# GRE Tunnel + HAProxy

Set up **multiple IRAN servers** → **one KHAREJ server** over GRE tunnels with HAProxy port forwarding. Tunnel interface names: `gre-haproxy` (on each IRAN), `gre-haproxy1`, `gre-haproxy2`, … (on KHAREJ).

## Quick run (one-liner)

```bash
sudo bash <(curl -sSL https://raw.githubusercontent.com/hosseinpv1379/gre-haproxy/main/setup-gre-haproxy.sh)
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

## Author

GitHub: [hosseinpv1379](https://github.com/hosseinpv1379)
