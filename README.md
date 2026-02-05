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

## Manual certificate for GOST (TLS/WSS/HTTP2)

GOST expects the certificate and key in a fixed path. If you get the certificate yourself (e.g. when port 80 is blocked or you use DNS challenge), put the files where the script expects them:

| File   | Path (on IRAN server)   |
|--------|-------------------------|
| Certificate (full chain) | `/etc/gost-gre/cert.pem` |
| Private key              | `/etc/gost-gre/key.pem`  |

### 1) Create the directory

```bash
sudo mkdir -p /etc/gost-gre
```

### 2) Get the certificate (choose one method)

**Option A – Certbot with DNS challenge** (works when port 80 is blocked):

```bash
sudo certbot certonly --manual --preferred-challenges dns -d YOUR_DOMAIN
```

Add the TXT record Certbot shows to your DNS, then press Enter. After success, copy the cert and key into GOST paths:

```bash
sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem /etc/gost-gre/cert.pem
sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem /etc/gost-gre/key.pem
sudo chmod 600 /etc/gost-gre/key.pem
```

**Option B – Certbot standalone** (if port 80 is free):

```bash
sudo systemctl stop gost-gre haproxy 2>/dev/null
sudo certbot certonly --standalone -d YOUR_DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem /etc/gost-gre/cert.pem
sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem /etc/gost-gre/key.pem
sudo chmod 600 /etc/gost-gre/key.pem
sudo systemctl start haproxy 2>/dev/null
```

**Option C – Certificate from elsewhere**

Copy your full-chain certificate to `/etc/gost-gre/cert.pem` and the private key to `/etc/gost-gre/key.pem`, then:

```bash
sudo chmod 644 /etc/gost-gre/cert.pem
sudo chmod 600 /etc/gost-gre/key.pem
```

### 3) Run the script and use the existing cert

Run the setup script → choose **7 (GOST)** → choose TLS/WSS/HTTP2. When asked **“Use existing certificate in /etc/gost-gre? (y/n)”** answer **y**. Then add your port(s). The script will use the cert and key in `/etc/gost-gre/` and (re)start the GOST service.

## Author

GitHub: [hosseinpv1379](https://github.com/hosseinpv1379)
