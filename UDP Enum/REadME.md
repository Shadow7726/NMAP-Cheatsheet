# 🛰️ IoT / Embedded Nmap Enumeration Toolkit

![Nmap](https://img.shields.io/badge/requires-nmap%207.9x+-blue?logo=nmap&logoColor=white)
![Shell](https://img.shields.io/badge/shell-bash-121011?logo=gnubash&logoColor=white)
![Scope](https://img.shields.io/badge/scope-IoT%20%7C%20embedded%20%7C%20ICS%2FSCADA-orange)
![Output](https://img.shields.io/badge/output-live%20progress%20%2B%20MD%20report-green)
![Use](https://img.shields.io/badge/use-authorized%20testing%20only-red)

A small, practical toolkit for enumerating **fragile embedded / IoT / ICS targets** with Nmap —
built around the reality that these devices can be *crashed* by an aggressive scan, not just
detected. It pairs automated scan scripts (TCP **and** UDP) with field references so you can go
from a cold IP to a finished report without hammering the device.

---

> [!CAUTION]
> **Authorized testing only.** Use these tools solely against systems you own or have explicit,
> written permission to assess. Unauthorized scanning is illegal in most jurisdictions, and
> embedded TCP/IP stacks can **reboot or hang** under load. The defaults here are deliberately
> gentle — keep them that way on anything you don't fully control.

---

## 📦 What's in the box

| File | Type | Purpose |
|---|---|---|
| **`tcp-enum.sh`** | Script | Full TCP assessment: sweep → identify → per-service NSE → **auto report** |
| **`udp-enum.sh`** | Script | Full UDP assessment with **interactive scope/profile menus** → per-service NSE → **auto report** |
| **`fastscan.sh`** | Script | Quick two-stage scan (fast port sweep → deep scan of open ports only) |
| **`nmap-embedded-cheatsheet.md`** | Reference | Advanced Nmap flag/technique cheatsheet for embedded gear |
| **`iot-port-playbook.md`** | Reference | Per-port enumeration playbook (scan → NSE → direct client → what to look for) |
| **`README.md`** | Docs | This file |

The scripts and references are designed to work together:
**cheatsheet** (concepts) → **playbook** (per-port procedure) → **fastscan.sh** (quick triage) →
**tcp-enum.sh** / **udp-enum.sh** (full automated runs + reports).

---

## ✨ Features

- **Live terminal progress** — real Nmap percentage and ETA (`--stats-every`), a `[step/total] %`
  tracker, and per-stage timers.
- **Auto-generated Markdown report** — scan metadata, open-ports table, per-service findings, and
  recommended next steps, written to `REPORT.md` at the end of the run.
- **Interactive menus (UDP)** — pick the **scan scope** (known IoT ports / top 100 / top 200 / all
  / custom / fast) and the **timing profile**, each with an on-screen description. Pass arguments to
  skip the menus for automation.
- **Three safety profiles** — `fast`, `safe`, `ics` — so timing matches how fragile the target is.
- **Service-aware deep enumeration** — detects which ports are open and runs the matching NSE
  scripts for each service (SSH, HTTP/S, RTSP, MQTT, Modbus, S7 on TCP; SNMP, TFTP, SSDP, mDNS,
  CoAP, BACnet, EtherNet/IP and more on UDP).
- **Two-stage speed model** — heavy version/script detection runs only against open ports.
- **Read-only by default** — no brute force, no writes; SNMP/ICS enumeration is discovery-only.
- **Interrupt-safe** — Ctrl-C still produces a report from whatever completed.
- **Robust defaults** — dependency and privilege checks, TTY-aware colour, and `--send-ip` to
  dodge the raw-Ethernet/ARP failure common on USB-gadget and virtual interfaces.

---

## 🔧 Requirements

- **Nmap 7.9x or newer** (required)
- **Bash** 4+ and standard GNU userland (`grep`, `awk`, `sed`, `paste`)
- **Root / sudo** — SYN (`-sS`), UDP (`-sU`) and OS (`-O`) scans need raw-socket privileges
- *Optional:* `figlet` or `toilet` for large ASCII banner headers; `mosquitto_sub` for direct
  MQTT inspection; `snmpwalk` (net-snmp) for direct SNMP; `glow` to pretty-print the report

Install on Debian / Kali / Ubuntu:

```bash
sudo apt update
sudo apt install -y nmap figlet          # figlet is optional (nicer banners)
```

---

## 🚀 Quick start

```bash
# Make the scripts executable
chmod +x tcp-enum.sh udp-enum.sh fastscan.sh

# Full TCP assessment with a generated report (replace with your scope)
sudo ./tcp-enum.sh 192.0.2.10

# Full UDP assessment — prompts you for scope and profile
sudo ./udp-enum.sh 192.0.2.10

# Quick two-stage triage scan
sudo ./fastscan.sh 198.51.100.25
```

> [!NOTE]
> Addresses shown throughout this README are **RFC 5737 documentation ranges**
> (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) — placeholders only. Substitute the real
> address(es) you are authorized to test.

---

## 🎛️ Scan profiles

All scripts accept the same three timing profiles (default: `fast`, except the UDP menu defaults to
`safe`).

| Profile | Timing | Use on |
|---|---|---|
| `fast` | `-T4` (TCP adds `--min-rate 1000`) | Robust hosts / embedded Linux |
| `safe` | `-T2` + rate cap | Fragile IoT / unknown stacks |
| `ics` | `-T2 --scan-delay 100ms` + low rate | PLCs / SCADA / medical — gentlest |

> [!WARNING]
> `fast` is for hardware you know can take it. On a brittle stack it causes false `filtered`
> results or hangs — drop to `safe`, or `ics` for industrial controllers. Never exceed `safe`
> timing on a PLC.

---

## 🧰 `tcp-enum.sh`

```bash
sudo ./tcp-enum.sh <target> [profile]       # profile: fast | safe | ics
```

1. **Stage 1 — Sweep.** Full 65535-port SYN scan to find every open TCP port (live progress).
2. **Stage 2 — Identify.** `-sV -sC -O` version/script/OS detection run **only** against the open
   ports from Stage 1.
3. **Stage 3 — Deep.** For each known service that's open, the matching NSE block runs (SSH algos &
   host key, HTTP enum & default-cred check, TLS posture, RTSP streams, MQTT topics, Modbus/S7
   read-only discovery).
4. **Report.** Findings parsed into `REPORT.md`.

---

## 🧰 `udp-enum.sh` (interactive)

```bash
sudo ./udp-enum.sh [target] [profile] [scope] [custom_ports]
```

Run it with **no arguments** and it walks you through two menus. Anything you *do* pass on the
command line is used as-is and that menu is skipped (useful for scripting/cron).

### Scan-scope menu

| # | Option | Description |
|---|---|---|
| 1 | **Known IoT ports** | Curated ~22 UDP ports (SNMP, TFTP, SSDP, mDNS, CoAP, BACnet, EtherNet/IP…). Fast & targeted. *Recommended.* |
| 2 | **Top 100 UDP** | Nmap's 100 most common UDP ports. Broader, slower. |
| 3 | **Top 200 UDP** | Nmap's 200 most common UDP ports. Wider net, slower still. |
| 4 | **All 65535 UDP** | Every UDP port. Very slow (hours) — asks for confirmation. |
| 5 | **Custom ports** | You type a port / list / range, e.g. `161,1900,5353` or `1-1000` (validated). |
| 6 | **Fast discovery** | Known ports, discovery only (no `-sV` in stage 1); detail recovered in stage 2. |

### Timing-profile menu

`fast` / `safe` (default, recommended) / `ics` — each described on screen.

### Argument order (to skip the menus)

```bash
sudo ./udp-enum.sh 192.0.2.10 safe known            # profile + scope given
sudo ./udp-enum.sh 198.51.100.25 ics custom 47808,44818
```

> [!NOTE]
> UDP scanning is **slow and lossy** by nature — this tool always uses `-sV` (except in fast
> discovery) so results are definitive rather than the uninformative `open|filtered`. A clean
> result is **not** proof a service is absent.

---

## ⚡ `fastscan.sh`

```bash
sudo ./fastscan.sh <target> [profile]
```

The lightweight cousin: a fast full-range TCP sweep, then a single deep pass (`-sV -sC -O`) on the
open ports — no per-service breakout and no report. Ideal for quick triage.

---

## 📂 Output & the report

Each run of `tcp-enum.sh` / `udp-enum.sh` creates a timestamped directory:

```
tcpenum_<target>_<YYYYMMDD_HHMMSS>/     # (udpenum_… for the UDP tool)
├── 00_full_session.log        # everything printed during the run
├── 01_all_tcp.txt / .gnmap    # stage-1 sweep (01_udp.* for UDP)
├── 02_identify.{nmap,xml,gnmap}   # version / OS / default-script pass
├── ssh_22.txt, http_80.txt …  # per-service NSE output (snmp_161.txt … for UDP)
└── REPORT.md                  # ← the consolidated report
```

**`REPORT.md`** contains: scan metadata (target, profile, scope, timing, start, duration, Nmap
version, status) · executive summary (open-port count + list) · an open-ports table parsed from the
identify stage (port / state / service / version) · per-service findings (port line + NSE output) ·
recommended next steps.

Render it with any Markdown viewer, or in the terminal:

```bash
glow tcpenum_192.0.2.10_*/REPORT.md      # if glow is installed
```

---

## 🩺 Troubleshooting

<details>
<summary><b><code>eth_send … errno=22: Invalid argument</code> / "0 hosts up"</b></summary>

Nmap couldn't inject a raw Ethernet frame on the chosen interface (common on USB-gadget,
`tun`/`ppp`/VPN, or VM/WSL virtual NICs). The scripts already pass **`--send-ip`** to route at the
raw-IP layer and sidestep this. If running Nmap manually:

```bash
sudo nmap -sS -p- -T2 -Pn --send-ip <target>
```

Confirm the route and interface first: `ip route get <target>` and `ip -br addr`.
</details>

<details>
<summary><b>A port shows <code>filtered</code> — is the service there or not?</b></summary>

`filtered` means Nmap got no response (firewall, rate-limit, or a silent stack) — not the same as
`closed`. Confirm with a direct client, e.g. `curl -v --connect-timeout 5 http://<target>:8080/`.
If you have shell access, diff external reachability against what's listening: `ss -lntup`.
</details>

<details>
<summary><b>UDP scan finds nothing / everything is <code>open|filtered</code></b></summary>

UDP is lossy and silent ports look identical to open ones without a payload probe. `udp-enum.sh`
uses `-sV` to force definitive answers. If a scan comes back empty, widen the scope (re-run and pick
Top 200 or All) and use the `safe` profile so responses aren't dropped by aggressive timing.
</details>

<details>
<summary><b>SYN/UDP/OS scan fails or returns nothing without sudo</b></summary>

`-sS`, `-sU` and `-O` need raw-socket privileges. Run with `sudo`, or for TCP use an unprivileged
connect scan: `nmap -sT -p- -T2 -Pn <target>`.
</details>

<details>
<summary><b>Banners aren't "big"</b></summary>

Large ASCII banner headers use `figlet`/`toilet` when present. Without them you still get the bold
boxed fallback headers. Install with `sudo apt install figlet`.
</details>

---

## 📚 Reference docs

- **`nmap-embedded-cheatsheet.md`** — host discovery, every TCP/UDP scan type, timing for fragile
  devices, NSE categories, ICS/IoT protocols, evasion, output formats, and full recon workflows.
- **`iot-port-playbook.md`** — a per-port procedure (FTP, SSH, Telnet, HTTP/S, RTSP, MQTT, TFTP,
  NTP, SNMP, SSDP/UPnP, mDNS, CoAP, Modbus, S7, BACnet): what it is → how to scan → NSE scripts →
  direct client → what to look for → next step.

---

## ⚖️ Legal & responsible use

This toolkit is intended for **security professionals, network administrators, and researchers**
operating within the bounds of the law and with explicit authorization. You are responsible for
ensuring you have permission to scan any target. The authors and contributors assume no liability
for misuse or for any damage to scanned systems.

---

*Reference material and tooling for authorized security assessment and network administration only.*
