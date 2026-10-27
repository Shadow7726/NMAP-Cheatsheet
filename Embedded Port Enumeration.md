# 🔌 IoT / Embedded Port Enumeration Playbook — End to End

![Scope](https://img.shields.io/badge/scope-per--port%20enumeration-orange)
![Targets](https://img.shields.io/badge/targets-IoT%20%7C%20embedded%20%7C%20ICS-green)
![Companion](https://img.shields.io/badge/companion-nmap--embedded--cheatsheet-blue)

> A port-by-port assessment guide for authorized embedded-device testing. For each service you're
> likely to meet on IoT gear: **what it is → how to scan it → version detection → NSE scripts →
> direct interaction → what to look for → next step.** Companion to the Nmap embedded cheatsheet.

---

> [!CAUTION]
> Authorized testing only. Many of these probes (especially UDP, SNMP, and script scans) can
> destabilise fragile embedded stacks. Default to `-T2`, scope ports tightly, and watch the
> device while you work.

---

## 📑 Contents

**Baseline** · [Methodology](#-methodology-every-device) · [Quick port map](#-quick-iot-port-map)

**TCP services** · [21 FTP](#-21tcp--ftp) · [22 SSH](#-22tcp--ssh) · [23 Telnet](#-23tcp--telnet) · [80 HTTP](#-80tcp--http) · [443 HTTPS](#-443tcp--https) · [554 RTSP](#-554tcp--rtsp-cameras) · [1883 MQTT](#-1883tcp--mqtt) · [8080/8443 Alt-web](#-80808443tcp--alternate-web)

**UDP services** · [69 TFTP](#-69udp--tftp) · [123 NTP](#-123udp--ntp) · [161 SNMP](#-161udp--snmp) · [1900 SSDP/UPnP](#-1900udp--ssdp--upnp) · [5353 mDNS](#-5353udp--mdns) · [5683 CoAP](#-5683udp--coap)

**Industrial** · [502 Modbus](#-502tcp--modbus) · [102 S7](#-102tcp--siemens-s7) · [47808 BACnet](#-47808udp--bacnet)

**Close-out** · [Verify from inside the device](#-verify-from-inside-the-device) · [Per-service review matrix](#-per-service-review-matrix)

---

## 🧭 Methodology (every device)

Run this before diving into individual ports — it tells you *which* of the sections below you need.

```bash
# 1. Full TCP sweep — find everything, gently
sudo nmap -sS -p- -T2 -Pn --reason --open -oN all_tcp.txt <target>

# 2. Targeted UDP sweep — IoT lives here (always pair -sU with -sV)
sudo nmap -sU -sV --top-ports 50 -T2 -Pn --reason --open -oN all_udp.txt <target>

# 3. Version + default scripts on whatever stages 1-2 found
sudo nmap -sV -sC -T2 -Pn -p <open_ports> -oN service_enum.txt <target>
```

> [!NOTE]
> `--reason` tells you *why* a port is `open`/`closed`/`filtered` (e.g. `syn-ack` vs `no-response`).
> On embedded targets `filtered` usually means a firewall or a silent stack — not necessarily a
> missing service. Confirm with a direct client (curl/snmpwalk/etc.) before concluding anything.

---

## 🗺️ Quick IoT port map

| Port | Proto | Service | Jump |
|---|---|---|---|
| 21 | TCP | FTP | [↓](#-21tcp--ftp) |
| 22 | TCP | SSH | [↓](#-22tcp--ssh) |
| 23 | TCP | Telnet | [↓](#-23tcp--telnet) |
| 69 | UDP | TFTP | [↓](#-69udp--tftp) |
| 80 | TCP | HTTP | [↓](#-80tcp--http) |
| 102 | TCP | Siemens S7 | [↓](#-102tcp--siemens-s7) |
| 123 | UDP | NTP | [↓](#-123udp--ntp) |
| 161 | UDP | SNMP | [↓](#-161udp--snmp) |
| 443 | TCP | HTTPS | [↓](#-443tcp--https) |
| 502 | TCP | Modbus | [↓](#-502tcp--modbus) |
| 554 | TCP | RTSP | [↓](#-554tcp--rtsp-cameras) |
| 1883 | TCP | MQTT | [↓](#-1883tcp--mqtt) |
| 1900 | UDP | SSDP/UPnP | [↓](#-1900udp--ssdp--upnp) |
| 5353 | UDP | mDNS | [↓](#-5353udp--mdns) |
| 5683 | UDP | CoAP | [↓](#-5683udp--coap) |
| 8080/8443 | TCP | Alt web | [↓](#-80808443tcp--alternate-web) |
| 47808 | UDP | BACnet | [↓](#-47808udp--bacnet) |

---

## 🟢 21/tcp — FTP

**What it is:** File transfer, extremely common on cameras, routers, and NAS-style IoT for
firmware/config. Frequently allows **anonymous** access on cheap devices.

```bash
# Version + default scripts
sudo nmap -Pn -sV -p21 -sC <target>

# Anonymous login + banner
sudo nmap -Pn -p21 --script ftp-anon,ftp-syst <target>

# Direct interaction
ftp <target>            # try user: anonymous, pass: anything
curl ftp://<target>/ --user anonymous:anonymous
```

**Look for:** anonymous read/write, writable firmware directories, cleartext creds (it's
unencrypted), vendor-default accounts, FTP bounce (`ftp-bounce` script).

---

## 🟢 22/tcp — SSH

**What it is:** The management shell on most embedded Linux. Weak/default creds and old crypto
are the usual findings.

```bash
# Algorithms + auth methods + host key
sudo nmap -Pn -p22 --script ssh2-enum-algos,ssh-auth-methods,ssh-hostkey <target>

# Version
sudo nmap -Pn -sV -p22 <target>

# Direct — see the banner and offered auth
ssh -vv <target>
nc <target> 22         # grab raw banner
```

**Look for:** outdated OpenSSH/Dropbear versions, weak KEX/ciphers (CBC, diffie-hellman-group1),
`password` auth enabled, root login permitted, reused host keys across a device fleet (fingerprint
tells you it's the same firmware image).

> [!TIP]
> Dropbear banners (e.g. `SSH-2.0-dropbear_2019.78`) immediately flag an embedded box and often
> pin the firmware era.

---

## 🟢 23/tcp — Telnet

**What it is:** Cleartext legacy shell, still rampant on budget IoT. If it's open, it's usually
the fastest way in.

```bash
sudo nmap -Pn -sV -p23 --script telnet-encryption,telnet-ntlm-info,banner <target>

# Direct
telnet <target>
nc <target> 23
```

**Look for:** no encryption (by definition), default creds (`admin/admin`, `root/root`,
vendor pairs), Busybox shell, hardcoded backdoor accounts. Telnet open on IoT is itself a finding.

---

## 🟢 80/tcp — HTTP

**What it is:** The device web UI — usually the richest attack surface on IoT.

```bash
# Identity + methods + headers
sudo nmap -Pn -p80 --script http-title,http-headers,http-methods,http-server-header <target>

# Paths, admin pages, firmware endpoints
sudo nmap -Pn -p80 --script http-enum <target>

# Security posture + default creds + favicon fingerprint
sudo nmap -Pn -p80 --script http-security-headers,http-default-accounts,http-favicon <target>

# Direct
curl -v http://<target>/
curl -s http://<target>/ -I            # headers only
whatweb http://<target>/               # if installed — great for appliances
```

**Look for:** model/firmware in the title or `Server:` header, exposed `/cgi-bin/`, config
download endpoints, auth realm naming the vendor, missing auth on admin pages, default logins,
command-injection-prone CGI (common on routers/cameras).

---

## 🟢 443/tcp — HTTPS

**What it is:** The TLS-wrapped management UI. The certificate alone often leaks identity.

```bash
# Cert + cipher posture
sudo nmap -Pn -p443 --script ssl-cert,ssl-enum-ciphers,tls-alpn,ssl-date <target>

# Then run the same http-* scripts over TLS
sudo nmap -Pn -sV -p443 --script "http-title,http-headers,http-enum" <target>

# Direct
echo | openssl s_client -connect <target>:443 2>/dev/null | openssl x509 -noout -text
curl -vk https://<target>/
```

**Look for:** self-signed certs with vendor CN/SAN, long-lived or fleet-shared certs,
SSLv3/TLS1.0, weak ciphers, expired certs, hostname/serial leakage in the cert, `ssl-date` clock
skew (hints at device uptime/time source).

---

## 🟢 554/tcp — RTSP (cameras)

**What it is:** Real-time streaming on IP cameras. Often unauthenticated or default-credentialed.

```bash
sudo nmap -Pn -p554 --script rtsp-methods,rtsp-url-brute <target>

# Direct — enumerate stream paths
curl -v rtsp://<target>:554/
# ffplay rtsp://<target>:554/<path>   # view a discovered stream (authorized only)
```

**Look for:** `DESCRIBE` without auth, guessable stream URLs (`/live`, `/h264`, `/stream1`),
default camera creds, ONVIF endpoints on 80/8080 alongside.

---

## 🟢 1883/tcp — MQTT

**What it is:** Pub/sub telemetry bus for sensors and hubs. Frequently **anonymous** and world-
readable.

```bash
sudo nmap -Pn -p1883 --script mqtt-subscribe <target>

# Direct — dump all topics
mosquitto_sub -h <target> -t '#' -v           # '#' = every topic
mosquitto_sub -h <target> -t '$SYS/#' -v      # broker internals
```

**Look for:** anonymous subscribe/publish, sensitive data on topics, writable control topics
(you can actuate devices), broker version via `$SYS/broker/version`.

---

## 🟢 8080/8443/tcp — Alternate web

**What it is:** Secondary/admin web, proxies, ONVIF, debug consoles, dev servers. Treat exactly
like 80/443 but don't assume it's filtered just because the first scan said so.

```bash
# Confirm state with a trace — 'filtered' is not 'closed'
sudo nmap -Pn -sS -p8080,8443 --reason --packet-trace <target>

# If open, full web enum
sudo nmap -Pn -sV -p8080,8443 --script "http-* and not (brute or dos)" <target>

# Direct — a timeout does NOT prove absence
curl -v --connect-timeout 5 http://<target>:8080/
curl -vk --connect-timeout 5 https://<target>:8443/
```

> [!NOTE]
> `filtered` on 8080 means Nmap got no response — a firewall rule, rate-limit, or silent service.
> If you have SSH to the box, confirm from inside with `ss -lntup` (see close-out section).

---

## 🔵 69/udp — TFTP

**What it is:** No-auth file transfer for firmware/config. If present, you may be able to pull or
push firmware with zero credentials.

```bash
sudo nmap -sU -p69 --script tftp-enum <target>

# Direct — try known config/firmware names
tftp <target>
  > get config.bin
  > get firmware.bin
```

**Look for:** readable config/firmware, writable uploads (firmware replacement), predictable
filenames from the vendor's boot process.

---

## 🔵 123/udp — NTP

**What it is:** Time sync. Mostly an info-leak / amplification concern on IoT.

```bash
sudo nmap -sU -p123 --script ntp-info,ntp-monlist <target>

# Direct
ntpq -c rv <target>
```

**Look for:** `monlist` enabled (info leak + DDoS amplification), version disclosure, internal
peer addresses revealing network topology.

---

## 🔵 161/udp — SNMP

**What it is:** The single most valuable IoT UDP service. With a known community string (often
`public`) it dumps interfaces, processes, software, routes — a full device profile.

```bash
# Nmap enumeration
sudo nmap -sU -p161 --script \
  snmp-info,snmp-sysdescr,snmp-interfaces,snmp-netstat,snmp-processes,snmp-win32-software \
  <target>

# Brute the community string first if 'public' fails
sudo nmap -sU -p161 --script snmp-brute <target>

# Direct — walk the whole tree
snmpwalk -v2c -c public <target>
snmpwalk -v2c -c public <target> 1.3.6.1.2.1.1   # system group (sysDescr etc.)
```

**Look for:** writable community (`private` → you can *change* config), full `sysDescr` (model,
firmware, kernel), interface/ARP tables, running processes, installed software — effectively
internal recon without a shell.

> [!WARNING]
> SNMP writes (`snmpset`) can reconfigure or reboot a device. Read-only (`snmpwalk`) first; never
> write to production gear without explicit sign-off.

---

## 🔵 1900/udp — SSDP / UPnP

**What it is:** Device discovery. The description XML names the make, model, and services.

```bash
sudo nmap -sU -p1900 --script upnp-info <target>

# Direct — send an M-SEARCH and read the LOCATION URL, then fetch the XML
curl "http://<target>:<port>/<description>.xml"   # URL comes from upnp-info output
```

**Look for:** model/firmware in the description, exposed control URLs (SOAP actions), WANIPConn
port-mapping (router pivot), known UPnP CVEs for the stack (miniupnpd, etc.).

---

## 🔵 5353/udp — mDNS

**What it is:** Bonjour/Avahi service advertisement. Leaks hostnames and service inventory for
free.

```bash
sudo nmap -sU -p5353 --script dns-service-discovery <target>

# Direct
avahi-browse -a -t          # browse all services on the segment
dig @<target> -p 5353 _services._dns-sd._udp.local ptr
```

**Look for:** device hostname, advertised services (`_http._tcp`, `_ipp._tcp` printers,
`_raop._tcp` audio), software versions in TXT records.

---

## 🔵 5683/udp — CoAP

**What it is:** Lightweight REST for constrained sensors. Resource discovery is unauthenticated by
default.

```bash
sudo nmap -sU -p5683 --script coap-resources <target>

# Direct (coap-client from libcoap)
coap-client -m get coap://<target>/.well-known/core
```

**Look for:** the `/.well-known/core` resource list, writable resources (actuation), no DTLS
(cleartext), observable resources leaking sensor data.

---

## 🏭 502/tcp — Modbus

**What it is:** The flagship ICS protocol (PLCs/RTUs). **No authentication by design.**

```bash
sudo nmap -p502 --script modbus-discover <target>
```

**Look for:** unit/slave IDs, device identification strings, readable coils/registers. Reads are
generally safe; **writes alter a physical process — never on live plant.**

> [!CAUTION]
> ICS is the most fragile and highest-consequence class. Read-only discovery, `-T2` or slower,
> maintenance window, and sign-off before anything active.

---

## 🏭 102/tcp — Siemens S7

**What it is:** Siemens S7 PLC comms (S7-300/400/1200/1500).

```bash
sudo nmap -p102 --script s7-info <target>
```

**Look for:** module type, serial, firmware, plant/rack identification — all read-only and
valuable for asset inventory and CVE matching.

---

## 🏭 47808/udp — BACnet

**What it is:** Building automation (HVAC, lighting, access).

```bash
sudo nmap -sU -p47808 --script bacnet-info <target>
```

**Look for:** vendor/model/firmware, device instance number, object list — maps the building
controller without touching control points.

---

## 🔎 Verify from inside the device

Once you have SSH/Telnet access, **compare what's externally reachable against what's actually
listening.** The gap is where the interesting findings live (services bound to localhost, firewall
rules hiding ports, debug daemons).

```bash
# Listening TCP + UDP sockets with owning process
sudo ss -lntup
netstat -lntup            # fallback on busybox/older systems

# Running processes
ps aux
ps -w                     # busybox variant

# Firewall rules
sudo iptables -S
sudo nft list ruleset

# What's actually bound where (confirms the '8080 filtered' question)
cat /proc/net/tcp /proc/net/udp     # raw, when tools are stripped out
```

**Cross-reference:** a port that scanned `filtered` but shows `LISTEN` in `ss` means a firewall is
in front of it. A process listening on `0.0.0.0` that *didn't* appear in your scan means your scan
missed it (retry with `--reason`, slower timing, or correct interface).

---

## 📋 Per-service review matrix

| Area | What to examine |
|---|---|
| **SSH (22)** | Version, KEX/cipher strength, auth methods, root-login policy, fleet-shared host keys |
| **Telnet (23)** | Present at all (finding), default creds, backdoor accounts |
| **FTP/TFTP (21/69)** | Anonymous access, writable firmware/config, cleartext creds |
| **Web (80/443/8080)** | Server/firmware banner, exposed endpoints, methods, default logins, CGI injection, TLS posture |
| **RTSP (554)** | Unauthenticated streams, default camera creds, guessable URLs |
| **SNMP (161)** | Community strings, read vs write, full device profile leak |
| **MQTT (1883)** | Anonymous sub/pub, sensitive topics, writable control topics |
| **UPnP/mDNS (1900/5353)** | Model/firmware leak, control URLs, service inventory |
| **CoAP (5683)** | Resource list, writable resources, missing DTLS |
| **ICS (502/102/47808)** | Device ID, firmware, exposure of control protocol to the network at all |
| **Port exposure** | Externally reachable vs internally listening (`ss` diff) |
| **Firmware** | Embedded creds, outdated libs, debug services, config files |

---

> [!TIP]
> **Recommended flow:** run the [methodology](#-methodology-every-device) sweep → for each open
> port, jump to its section and run the scan + direct-interaction commands → verify findings from
> inside the device → fill in the [review matrix](#-per-service-review-matrix) as your report
> skeleton.

*Reference material for authorized security assessment and network administration only.*
