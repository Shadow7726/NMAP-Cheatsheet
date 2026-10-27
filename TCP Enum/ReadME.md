# 🛰️ IoT / Embedded Nmap Enumeration Toolkit

![Nmap](https://img.shields.io/badge/requires-nmap%207.9x+-blue?logo=nmap&logoColor=white)
![Shell](https://img.shields.io/badge/shell-bash-121011?logo=gnubash&logoColor=white)
![Scope](https://img.shields.io/badge/scope-IoT%20%7C%20embedded%20%7C%20ICS%2FSCADA-orange)
![Output](https://img.shields.io/badge/output-live%20progress%20%2B%20MD%20report-green)
![Use](https://img.shields.io/badge/use-authorized%20testing%20only-red)

A small, practical toolkit for enumerating **fragile embedded / IoT / ICS targets** with Nmap —
built around the reality that these devices can be *crashed* by an aggressive scan, not just
detected. It pairs automated scan scripts with field references so you can go from a cold IP to a
finished report without hammering the device.

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
| **`fastscan.sh`** | Script | Quick two-stage scan (fast port sweep → deep scan of open ports only) |
| **`nmap-embedded-cheatsheet.md`** | Reference | Advanced Nmap flag/technique cheatsheet for embedded gear |
| **`iot-port-playbook.md`** | Reference | Per-port enumeration playbook (scan → NSE → direct client → what to look for) |
| **`README.md`** | Docs | This file |

The two scripts and two references are designed to work together:
**cheatsheet** (concepts) → **playbook** (per-port procedure) → **fastscan.sh** (quick triage) →
**tcp-enum.sh** (full automated run + report).

---

## ✨ Features

- **Live terminal progress** — real Nmap percentage and ETA (`--stats-every`), a `[step/total] %`
  tracker, and per-stage timers.
- **Auto-generated Markdown report** — scan metadata, open-ports table, per-service findings, and
  recommended next steps, written to `REPORT.md` at the end of the run.
- **Three safety profiles** — `fast`, `safe`, `ics` — so timing matches how fragile the target is.
- **Service-aware deep enumeration** — detects which ports are open and runs the matching NSE
  scripts for FTP, SSH, Telnet, HTTP(S), RTSP, MQTT, alt-web, Modbus and Siemens S7.
- **Two-stage speed model** — heavy version/script detection runs only against open ports, never
  the full 65535-port range.
- **Interrupt-safe** — Ctrl-C still produces a report from whatever completed.
- **Robust defaults** — dependency and privilege checks, TTY-aware colour, and `--send-ip` to
  dodge the raw-Ethernet/ARP failure common on USB-gadget and virtual interfaces.

---

## 🔧 Requirements

- **Nmap 7.9x or newer** (required)
- **Bash** 4+ and standard GNU userland (`grep`, `awk`, `sed`, `paste`)
- **Root / sudo** — SYN (`-sS`) and OS (`-O`) scans need raw-socket privileges
- *Optional:* `figlet` or `toilet` for large ASCII banner headers; `mosquitto_sub` for direct
  MQTT inspection; `glow` for pretty-printing the report in the terminal

Install on Debian / Kali / Ubuntu:

```bash
sudo apt update
sudo apt install -y nmap figlet          # figlet is optional (nicer banners)
```

---

## 🚀 Quick start

```bash
# Make the scripts executable
chmod +x tcp-enum.sh fastscan.sh

# Full TCP assessment with a generated report (replace with your scope)
sudo ./tcp-enum.sh 192.0.2.10

# Gentle profile for fragile IoT / unknown stacks
sudo ./tcp-enum.sh 192.0.2.10 safe

# Quick two-stage triage scan
sudo ./fastscan.sh 198.51.100.25
```

> [!NOTE]
> Addresses shown throughout this README are **RFC 5737 documentation ranges**
> (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) — placeholders only. Substitute the real
> address(es) you are authorized to test.

---

## 🎛️ Scan profiles

Both scripts accept the same three profiles as an optional second argument (default: `fast`).

| Profile | Timing | Use on |
|---|---|---|
| `fast` | `-T4 --min-rate 1000` | Robust hosts / embedded Linux |
| `safe` | `-T2 --max-rate 300` | Fragile IoT / unknown stacks |
| `ics` | `-T2 --scan-delay 100ms --max-rate 100` | PLCs / SCADA / medical — gentlest |

> [!WARNING]
> `fast` is for hardware you know can take it. On a brittle stack it causes false `filtered`
> results or hangs — drop to `safe`, or `ics` for industrial controllers. Never exceed `safe`
> timing on a PLC.

---

## 📂 Output & the report

Each run of `tcp-enum.sh` creates a timestamped directory:

```
tcpenum_<target>_<YYYYMMDD_HHMMSS>/
├── 00_full_session.log      # everything printed during the run
├── 01_all_tcp.txt / .gnmap  # full-range sweep results
├── 02_identify.{nmap,xml,gnmap}   # version / OS / default-script pass
├── ssh_22.txt, http_80.txt, …     # per-service NSE output
└── REPORT.md                # ← the consolidated report
```

**`REPORT.md`** contains:

- **Scan metadata** — target, profile, timing, start time, total duration, Nmap version, status
- **Executive summary** — count and list of open ports
- **Open ports & services** — a table parsed from the identify stage (port / state / service / version)
- **Per-service findings** — the port line plus NSE script output for each enumerated service
- **Recommended next steps**

Render it with any Markdown viewer, or in the terminal:

```bash
glow tcpenum_192.0.2.10_*/REPORT.md      # if glow is installed
```

---

## 🧭 How `tcp-enum.sh` works

1. **Stage 1 — Sweep.** Full 65535-port SYN scan to find every open TCP port (live progress shown).
2. **Stage 2 — Identify.** `-sV -sC -O` version/script/OS detection run **only** against the open
   ports from Stage 1.
3. **Stage 3 — Deep.** For each known service that's open, the matching NSE block runs
   (SSH algos & host key, HTTP enum & default creds, TLS posture, RTSP streams, MQTT topics, Modbus/S7
   read-only discovery, etc.).
4. **Report.** Findings are parsed and written to `REPORT.md`.

`fastscan.sh` is the lightweight cousin: Stage 1 + a single deep pass on the open ports, no
per-service breakout and no report — ideal for quick triage.

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

Confirm the route and interface first:

```bash
ip route get <target>
ip -br addr
```
</details>

<details>
<summary><b>A port shows <code>filtered</code> — is the service there or not?</b></summary>

`filtered` means Nmap got no response (firewall, rate-limit, or a silent stack) — it is **not**
the same as `closed`. Confirm with a direct client, e.g. for a web port:

```bash
curl -v --connect-timeout 5 http://<target>:8080/
```

A timeout still doesn't prove absence. If you have shell access, diff external reachability against
what's actually listening: `ss -lntup`.
</details>

<details>
<summary><b>SYN/OS scan fails or returns nothing without sudo</b></summary>

`-sS` and `-O` need raw-socket privileges. Run with `sudo`, or use an unprivileged connect scan:

```bash
nmap -sT -p- -T2 -Pn <target>
```
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
