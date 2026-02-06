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

---

## Step-by-step guide: GRE Tunnel + HAProxy setup

This guide walks you through setting up a GRE tunnel between an **IRAN server** and a **KHAREJ server**, testing bandwidth, and configuring HAProxy for port forwarding.

### Step 1: Run the script on both servers

On both servers, download and run the script:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/hosseinpv1379/gre-haproxy/main/setup-gre-haproxy.sh)
```

Or if you have the script locally:

```bash
sudo bash setup-gre-haproxy.sh
```

---

### Step 2: Setup tunnel on IRAN server

1. On the **IRAN server**, run the script and choose **1** (IRAN).
2. Answer the prompts:
   - **IRAN index:** Enter `1` if this is your first IRAN server, `2` for the second, etc. This must match the order you add servers on KHAREJ.
   - **IRAN server IP:** Confirm or enter the public IP of this IRAN server.
   - **KHAREJ server IP:** Enter the public IP of your KHAREJ (outside) server.
3. The script creates the GRE tunnel interface (`gre-haproxy`) and configures it.
4. You should see: `IRAN tunnel ready. Test: ping BACKEND_IP`

**Verify:** The tunnel interface should be up: `ip link show gre-haproxy`

---

### Step 3: Setup tunnel on KHAREJ server

1. On the **KHAREJ server**, run the script and choose **2** (KHAREJ).
2. Answer the prompts:
   - **KHAREJ server IP:** Confirm or enter the public IP of this KHAREJ server.
   - **New IRAN server IP:** Enter the **same IRAN server public IP** you used in Step 2.
3. The script creates the GRE tunnel interface (`gre-haproxy1` for the first IRAN, `gre-haproxy2` for the second, etc.) and configures it.
4. You should see: `KHAREJ ready. On the IRAN server run this script, option 1 (IRAN), index 1. Backend IP for that IRAN: 10.10.x.2`

**Verify:** The tunnel interface should be up: `ip link show gre-haproxy1` (or `gre-haproxy2`, etc.)

---

### Step 4: Test tunnel connectivity

From the **IRAN server**, ping the backend IP shown in Step 3:

```bash
ping 10.10.x.2
```

If you get replies, the tunnel is working.

---

### Step 5: Bandwidth test (iperf3)

Before configuring HAProxy, test the tunnel bandwidth to ensure it meets your needs.

#### 5.1: Start iperf3 server on KHAREJ

1. On the **KHAREJ server**, run the script and choose **5** (iperf3).
2. When prompted: **"Run server for 90 seconds? (y/n)"**, type **`y`** and press Enter.
3. The iperf3 server starts listening on port 5201 for 90 seconds.

#### 5.2: Run bandwidth test from IRAN

1. On the **IRAN server**, run the script and choose **5** (iperf3).
2. The script automatically runs the bandwidth test using multiple streams (default: 10 connections) for a duration (default: 30 seconds).
3. You will see output showing:
   - **Bandwidth:** Upload speed from IRAN to KHAREJ
   - **Transfer:** Total data transferred
   - **Retr:** Retransmissions (should be low for a stable connection)

**Note:** Make sure to run Step 5.1 (server on KHAREJ) **before** Step 5.2 (test from IRAN), and complete Step 5.2 within the 90-second window.

---

### Step 6: Configure HAProxy port forwarding (if bandwidth is good)

If the bandwidth test shows acceptable performance, proceed to configure HAProxy for port forwarding.

1. On the **IRAN server**, run the script and choose **6** (HAProxy).
2. The script installs HAProxy if not already installed.
3. When prompted for ports, enter them in the format: **`LOCAL_PORT=REMOTE_PORT`**

   **Examples:**
   - `443=443` — Forward port 443 on IRAN to port 443 on KHAREJ
   - `8080=80` — Forward port 8080 on IRAN to port 80 on KHAREJ
   - `2222=22` — Forward port 2222 on IRAN to port 22 (SSH) on KHAREJ
   - `443=443,8080=80,2222=22` — Multiple ports separated by commas

4. The script configures HAProxy and restarts the service.
5. HAProxy listens on the specified ports on the IRAN server and forwards traffic through the GRE tunnel to the corresponding ports on the KHAREJ server.

**Verify:** Check HAProxy status: `systemctl status haproxy` (should be active). Test forwarding: from IRAN, `curl http://127.0.0.1:8080` (if you forwarded 8080→80) should reach the service on KHAREJ port 80.

---

### Step 7: Check status

At any time, run the script and choose **4** (Status) on either server to see:
- Tunnel interface status
- Tunnel IP addresses
- Connectivity (ping) to the other side
- HAProxy status (if configured)
- GOST reverse tunnel status (if configured)

---

### Summary

After completing these steps:

- ✅ GRE tunnel is established between IRAN and KHAREJ
- ✅ Bandwidth has been tested
- ✅ HAProxy is configured for port forwarding (if bandwidth was acceptable)
- ✅ Services on KHAREJ are accessible through the IRAN server’s public IP on the forwarded ports

**Traffic flow:** Client → IRAN (public IP, forwarded port) → GRE tunnel → KHAREJ (target port)

---

## GOST in this script (TCP only)

Option **7 (GOST)** in the script is **TCP** port forwarding only (IRAN → KHAREJ). No TLS/WSS/HTTP2.

## GOST Reverse Tunnel – full guide (zero to hero)

Traffic direction: **from outside (e.g. Germany) into Iran**. The **client runs on Iran** and connects out to the **server on the outside**; visitors that connect to the outside server are sent through the tunnel to Iran.

**Flow:** Visitor → **Outside server (KHAREJ)** → tunnel (kept open by Iran client) → **Iran (client)** → local service in Iran.

---

### Prerequisites

- Two servers: one **outside** (e.g. Germany, KHAREJ) with a public IP; one **inside** (Iran) that can reach the outside server.
- Root (sudo) on both.
- The script is the same on both; you run it and choose **Server** on the outside machine and **Client** on the Iran machine.

---

### Step 1: Run the script on both servers

On both the **outside server** and the **Iran server**:

```bash
sudo bash setup-gre-haproxy.sh
```

Or one-liner:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/hosseinpv1379/gre-haproxy/main/setup-gre-haproxy.sh)
```

Choose **8** (Reverse – GOST reverse tunnel).

---

### Step 2: On the OUTSIDE server (e.g. Germany / KHAREJ)

1. In the script choose **8**, then **1** (Server).
2. Enter:
   - **Entrypoint port:** public port where visitors will connect (e.g. **80** for HTTP). Must be open in the firewall.
   - **Tunnel service port:** internal port for the tunnel (e.g. **8443**). Must be open for the Iran server’s IP (or 0.0.0.0) in the firewall.
   - **Hostname:** hostname that visitors will use (e.g. `iran.example.com`). DNS for this hostname must point to **this outside server’s IP**.
   - **Tunnel ID:** press Enter to auto-generate a UUID, or paste a UUID you want to reuse. You will need this **exact value** on the Iran side.
3. The script installs GOST if needed, creates the systemd service `gost-reverse-tunnel`, and starts it.
4. At the end it prints something like:
   - **Tunnel ID:** `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
   - **Server address:** `THIS_SERVER_IP:8443`
5. **Write down** the Tunnel ID and the server address (e.g. `1.2.3.4:8443`). You will use them on the Iran server.

**Check:** On the outside server, ports 80 (entrypoint) and 8443 (tunnel) must be open in the firewall (e.g. `ufw allow 80,8443/tcp` then `ufw reload`).

---

### Step 3: On the IRAN server (client)

1. In the script choose **8**, then **2** (Client).
2. Enter:
   - **Server address:** the outside server’s **IP or domain** and the **tunnel port** (e.g. `1.2.3.4:8443` or `germany.example.com:8443`). This must be reachable from Iran.
   - **Tunnel ID:** the **same UUID** you got on the outside server (copy-paste).
   - **Local target:** where to forward traffic inside Iran (e.g. `127.0.0.1:80` for a local web server, or `192.168.1.10:443` for a device on the LAN).
3. The script creates the systemd service `gost-reverse-tunnel` and starts it.

**Check:** `sudo systemctl status gost-reverse-tunnel` should show **active (running)**. If it fails, run `journalctl -u gost-reverse-tunnel -n 50` and fix (e.g. wrong server address or firewall on the outside server).

---

### Step 4: DNS and visitor access

1. Point the **hostname** you chose (e.g. `iran.example.com`) in DNS to the **outside server’s public IP** (A record).
2. After DNS has propagated, a **visitor** opening `http://iran.example.com` in a browser will:
   - Connect to the outside server on port 80.
   - The outside server (GOST tunnel server) sends the request through the tunnel to the Iran client.
   - The Iran client forwards it to the **local target** (e.g. `127.0.0.1:80`).
   - The response goes back the same way.

So the visitor sees the service that is running on the **Iran** side (local target), even though they connected to the outside server.

**Note:** The public entrypoint only supports HTTP and TLS (SNI). For plain TCP (e.g. SSH), you need a **private tunnel** and a visitor that runs GOST; see [GOST docs](https://gost.run/en/tutorials/reverse-proxy-tunnel/).

---

### Step 5: Start on boot and status

- Both Server and Client are run as systemd services named **gost-reverse-tunnel**, and are **enabled** by the script, so they start on boot.
- To see status in the main script: run the script, choose **4** (Status). A line **Reverse – Running** or **Not running** shows the state of `gost-reverse-tunnel` on that machine.

---

### Step 6: Remove the reverse tunnel

- **On the Iran server:** Run the script → **3** (Remove) → **1** (IRAN). When asked “Also remove GOST reverse tunnel (gost-reverse-tunnel)?”, answer **y**.
- **On the outside server:** Run the script → **3** (Remove) → **2** (KHAREJ). When asked “Also remove GOST reverse tunnel server?”, answer **y**.

Config and service files under `/etc/gost-reverse-tunnel/` and `gost-reverse-tunnel.service` are removed.

---

### Use case: V2Ray on Germany, config address = Iran (users connect to Iran, traffic goes to Germany)

You have **V2Ray installed on the Germany server**, but you want the **config address to be Iran** so that users connect to Iran and traffic is sent through the reverse tunnel to Germany (where V2Ray runs). That is exactly what the reverse tunnel does when you put the **Server on Iran** and the **Client on Germany**.

**Flow:** User (with V2Ray config) → connects to **Iran** (tunnel server) → tunnel → **Germany** (tunnel client) → **V2Ray** on Germany.

So in the script you choose **Server** on the **Iran** machine and **Client** on the **Germany** machine (opposite of “outside = server, Iran = client” in the generic guide above).

#### Step-by-step for this setup

**1. On the IRAN server (tunnel server – users connect here)**

- Run the script → choose **8** (Reverse) → choose **1** (Server).
- **Entrypoint port:** the port users will use in their V2Ray config (e.g. **443** or **10085**). Open this port in the Iran server firewall.
- **Tunnel service port:** e.g. **8443**. Open it for the Germany server’s IP (or 0.0.0.0).
- **Hostname:** a domain that points to the **Iran server’s IP** (e.g. `proxy.iransite.com`). Users can use either this hostname or the Iran server IP in their config.
- **Tunnel ID:** press Enter to generate, or type your own UUID. **Copy this Tunnel ID** and the line **Server address: IRAN_IP:8443** (or the tunnel port you chose).

**2. On the GERMANY server (tunnel client – V2Ray runs here)**

- Run the script → choose **8** (Reverse) → choose **2** (Client).
- **Server address:** **Iran server IP** and the tunnel port (e.g. `IRAN_IP:8443`). Germany must be able to reach this (Iran firewall must allow Germany IP on the tunnel port).
- **Tunnel ID:** paste the **same UUID** you got on the Iran server.
- **Local target:** the address and port where **V2Ray** listens on Germany (e.g. `127.0.0.1:10085` or `127.0.0.1:443`). Check your V2Ray config for the inbound port.

**3. Give users the V2Ray config**

- **Address:** Iran server **IP** or the **hostname** you set (e.g. `proxy.iransite.com`).
- **Port:** the **entrypoint port** you set on Iran (e.g. 443 or 10085).
- Rest of the config (UUID, alterId, etc.) is from your V2Ray as usual.

So the “server” in the user’s config is **Iran**; the reverse tunnel carries the traffic to **Germany** where V2Ray is actually running.

**4. Firewall summary**

| Where   | Port to open        | For whom        |
|---------|---------------------|------------------|
| Iran    | Entrypoint (e.g. 443) | Users (0.0.0.0) |
| Iran    | Tunnel port (e.g. 8443) | Germany server IP |
| Germany | No need to open for users | — (users never connect to Germany directly) |

**5. Check**

- On Germany: `systemctl status gost-reverse-tunnel` → active. V2Ray listening on the port you used as local target.
- User: set config to Iran address + entrypoint port; connect. Traffic path: User → Iran → tunnel → Germany → V2Ray.

---

### Manual commands (without the script)

If you prefer to run GOST by hand:

**Server (outside), one tunnel:**

```bash
gost -L "tunnel://:8443?entrypoint=:80&tunnel=iran.example.com:YOUR-UUID-HERE"
```

**Client (Iran):**

```bash
gost -L rtcp://:0/127.0.0.1:80 -F "tunnel://OUTSIDE_SERVER_IP:8443?tunnel.id=YOUR-UUID-HERE"
```

Use the same UUID on both sides. Replace `127.0.0.1:80` with your desired local target.

---

### Tunnel stability (if the tunnel drops suddenly)

The script configures the GOST reverse tunnel service with:

- **Restart=always** and **RestartSec=15** so that if the process exits (e.g. connection closed), systemd restarts it.
- **StartLimitIntervalSec=300** and **StartLimitBurst=5** to avoid endless restart loops if something is wrong.
- **tunnel.weight=255** on the client so the server prefers this client’s connection.

To reduce random disconnects:

1. **Use the tunnel server’s IP** (not a domain) as the client’s “Server address” when possible, to avoid DNS or resolution issues.
2. **Firewall / NAT:** Long-lived TCP between Iran and Germany can be dropped by middleboxes (NAT timeout, stateful firewall). If the tunnel port is only used by the other server, allow that and avoid aggressive “idle timeout” rules on that connection.
3. **Check logs:** `journalctl -u gost-reverse-tunnel -f` on both sides to see disconnects or errors.

---

### Troubleshooting

| Problem | What to check |
|--------|----------------|
| Client does not connect | Firewall on the outside server: allow the **tunnel port** (e.g. 8443) from the Iran server’s IP (or 0.0.0.0). Client logs: `journalctl -u gost-reverse-tunnel -f`. |
| Visitor gets connection refused | Firewall on the outside server: allow the **entrypoint port** (e.g. 80). DNS: hostname must point to the outside server’s IP. |
| Visitor connects but no response | On Iran, check that the **local target** (e.g. 127.0.0.1:80) is listening and responds. Test locally on the Iran server: `curl http://127.0.0.1:80`. |
| Tunnel ID mismatch | Tunnel ID on the client must be **exactly** the same as on the server (copy-paste the UUID). |
| Tunnel drops often | Prefer **IP** for client “Server address”; check firewall/NAT idle timeout; see “Tunnel stability” above. |

Official docs: [GOST – Reverse Proxy Tunnel](https://gost.run/en/tutorials/reverse-proxy-tunnel/).

## Author

GitHub: [hosseinpv1379](https://github.com/hosseinpv1379)
