#!/usr/bin/env bash
#
# fastscan.sh — two-stage Nmap scan (fast port sweep → targeted deep scan)
# Optimised for embedded / IoT targets. Authorized testing only.
#
# Usage:
#   ./fastscan.sh <target> [profile]
#
# Profiles:
#   fast    (default) -T4 --min-rate 1000   robust hosts / embedded Linux
#   safe              -T2 --max-retries 2    fragile IoT / unknown stacks
#   ics               -T2 --scan-delay 100ms PLCs / SCADA — gentlest
#
# Examples:
#   ./fastscan.sh 192.168.7.2
#   ./fastscan.sh 192.168.7.2 safe
#   sudo ./fastscan.sh 10.0.0.5 ics
#
set -euo pipefail

# ---- args ----------------------------------------------------------------
TARGET="${1:-}"
PROFILE="${2:-fast}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <target> [fast|safe|ics]" >&2
    exit 1
fi

# ---- timing per profile --------------------------------------------------
case "$PROFILE" in
    fast) TIMING="-T4 --min-rate 1000 --max-retries 2" ;;
    safe) TIMING="-T2 --max-retries 2 --max-rate 300" ;;
    ics)  TIMING="-T2 --scan-delay 100ms --max-retries 1 --max-rate 100" ;;
    *)    echo "Unknown profile: $PROFILE (use fast|safe|ics)" >&2; exit 1 ;;
esac

# ---- raw-socket note -----------------------------------------------------
# -sS needs root. --send-ip avoids the broken eth_send/ARP path seen on
# USB-gadget and virtual interfaces (errno 22). Drop --send-ip if you are
# L2-adjacent on a normal Ethernet NIC and want ARP-based speed.
COMMON="-n -Pn --open --send-ip"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="scan_${TARGET//[^0-9A-Za-z]/_}_${STAMP}"

echo "[*] Target : $TARGET"
echo "[*] Profile: $PROFILE  ($TIMING)"
echo "[*] Output : ${OUT}_*"
echo

# ---- stage 1: fast full-range port sweep ---------------------------------
echo "[1/2] Fast port sweep (all 65535 TCP ports)..."
sudo nmap -sS -p- $TIMING $COMMON -oG "${OUT}_stage1.gnmap" "$TARGET" >/dev/null

PORTS="$(grep -oP '\d+/open' "${OUT}_stage1.gnmap" 2>/dev/null \
         | cut -d/ -f1 | sort -un | paste -sd, || true)"

if [[ -z "$PORTS" ]]; then
    echo "[!] No open TCP ports found. Host may be down, filtered, or UDP-only."
    echo "    Try UDP:  sudo nmap -sU -sV --top-ports 50 $TIMING $COMMON $TARGET"
    exit 0
fi
echo "[+] Open ports: $PORTS"
echo

# ---- stage 2: deep scan on open ports only -------------------------------
echo "[2/2] Deep scan (version + default scripts + OS) on open ports..."
sudo nmap -sV -sC -O --osscan-guess $TIMING $COMMON \
     -p "$PORTS" -oA "${OUT}_stage2" "$TARGET"

echo
echo "[*] Done. Results saved as ${OUT}_stage2.{nmap,xml,gnmap}"
