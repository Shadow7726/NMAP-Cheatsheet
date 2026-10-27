#!/usr/bin/env bash
###############################################################################
#  tcp-enum.sh  —  Professional TCP enumeration suite for IoT / embedded devices
#
#  • Full-range sweep → targeted identify → per-service deep NSE enumeration
#  • Live progress in the terminal (nmap percentage + ETA, stage timers)
#  • Auto-generated Markdown report at the end of the scan
#  • Interrupt-safe: Ctrl-C still produces a report from whatever completed
#
#  Authorized testing only. Use solely against systems you own or are
#  explicitly permitted to assess.
#
#  Usage:    ./tcp-enum.sh <target> [profile]
#  Profile:  fast (default) | safe | ics
#
#  Examples (RFC 5737 documentation addresses — replace with your scope):
#      sudo ./tcp-enum.sh 192.0.2.10
#      sudo ./tcp-enum.sh 192.0.2.10 safe
#      sudo ./tcp-enum.sh 198.51.100.25 ics
###############################################################################
set -uo pipefail

# ===========================================================================
#  Presentation helpers  (bold / bright colour so commands stand out large)
# ===========================================================================
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
    CYAN=$'\e[96m'; YELLOW=$'\e[93m'; GREEN=$'\e[92m'; RED=$'\e[91m'
    BLUE=$'\e[94m'; MAGENTA=$'\e[95m'; WHITE=$'\e[97m'; BGBLUE=$'\e[44m'
else
    BOLD=''; DIM=''; RESET=''; CYAN=''; YELLOW=''; GREEN=''; RED=''
    BLUE=''; MAGENTA=''; WHITE=''; BGBLUE=''
fi

banner() {
    if command -v figlet >/dev/null 2>&1; then
        echo; printf '%s' "${BOLD}${CYAN}"; figlet -w 120 "$1" 2>/dev/null; printf '%s\n' "${RESET}"
    elif command -v toilet >/dev/null 2>&1; then
        echo; toilet -f standard "$1" 2>/dev/null; echo
    else
        echo
        echo "${BOLD}${BGBLUE}${WHITE}  ============================================================  ${RESET}"
        echo "${BOLD}${BGBLUE}${WHITE}   >>>  $1  <<<   ${RESET}"
        echo "${BOLD}${BGBLUE}${WHITE}  ============================================================  ${RESET}"
        echo
    fi
}

section() { echo; echo "${BOLD}${GREEN}#### $1 ####${RESET}"; echo; }
info()    { echo "${BOLD}${BLUE}[*]${RESET} $1"; }
ok()      { echo "${BOLD}${GREEN}[+]${RESET} $1"; }
warn()    { echo "${BOLD}${YELLOW}[!]${RESET} $1"; }
err()     { echo "${BOLD}${RED}[x]${RESET} $1" >&2; }

# ---------------------------------------------------------------------------
#  Progress bookkeeping — a visible [step/total] tracker across the whole run
# ---------------------------------------------------------------------------
STEP=0
TOTAL=2            # stages 1 and 2 are always run; stage-3 steps added later
step_header() {    # $1 = title
    STEP=$((STEP + 1))
    local pct=$(( STEP * 100 / (TOTAL > 0 ? TOTAL : 1) ))
    echo
    echo "${BOLD}${MAGENTA}┌──────────────────────────────────────────────────────────────────────┐${RESET}"
    printf "${BOLD}${MAGENTA}│  PROGRESS  [%2d/%-2d]  %3d%%   %-40s│${RESET}\n" "$STEP" "$TOTAL" "$pct" "$1"
    echo "${BOLD}${MAGENTA}└──────────────────────────────────────────────────────────────────────┘${RESET}"
}

# ---------------------------------------------------------------------------
#  run() — print the command LARGE+BOLD, stream it live (tee), time it
#  nmap gets -v --stats-every so the terminal shows % complete and ETA live.
# ---------------------------------------------------------------------------
run() {
    local cmd="$*"
    echo
    echo "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
    echo "${BOLD}${YELLOW}║  RUNNING COMMAND                                                       ║${RESET}"
    echo "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
    echo "${BOLD}${CYAN}  \$ ${WHITE}${cmd}${RESET}"
    echo "${BOLD}${YELLOW}────────────────────────────────────────────────────────────────────────${RESET}"
    local t0 t1
    t0=$(date +%s)
    # Stream to terminal AND append to the master log.
    eval "$cmd" 2>&1 | tee -a "$LOGFILE"
    t1=$(date +%s)
    echo "${DIM}    ↳ completed in $((t1 - t0))s${RESET}"
    echo
}

# ===========================================================================
#  Argument parsing
# ===========================================================================
TARGET="${1:-}"
PROFILE="${2:-fast}"

if [[ -z "$TARGET" ]]; then
    echo "${RED}Usage: $0 <target> [fast|safe|ics]${RESET}" >&2
    echo "  e.g. sudo $0 192.0.2.10 safe" >&2
    exit 1
fi

case "$PROFILE" in
    fast) TIMING="-T4 --min-rate 1000 --max-retries 2"          ; PROFILE_DESC="aggressive (robust hosts / embedded Linux)" ;;
    safe) TIMING="-T2 --max-retries 2 --max-rate 300"           ; PROFILE_DESC="polite (fragile IoT / unknown stacks)" ;;
    ics)  TIMING="-T2 --scan-delay 100ms --max-retries 1 --max-rate 100" ; PROFILE_DESC="gentlest (PLCs / SCADA)" ;;
    *)    err "Unknown profile: $PROFILE (use fast | safe | ics)"; exit 1 ;;
esac

# ===========================================================================
#  Pre-flight checks
# ===========================================================================
command -v nmap >/dev/null 2>&1 || { err "nmap is not installed. Install it and retry."; exit 1; }

# Only prepend sudo when not already root (keeps output clean when run as root).
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
if [[ -n "$SUDO" ]]; then
    warn "Not running as root — SYN/OS scans need privileges; commands use 'sudo'."
fi

NMAP_VER="$(nmap --version 2>/dev/null | head -1)"

# --send-ip routes at raw-IP layer, avoiding the eth_send/ARP errno-22 failure
# seen on USB-gadget and virtual interfaces. Drop it if L2-adjacent on Ethernet.
COMMON="-n -Pn --open --reason --send-ip -v --stats-every 15s"

STAMP="$(date +%Y%m%d_%H%M%S)"
SAFE_TGT="${TARGET//[^0-9A-Za-z._-]/_}"
OUTDIR="tcpenum_${SAFE_TGT}_${STAMP}"
mkdir -p "$OUTDIR"
LOGFILE="$OUTDIR/00_full_session.log"
REPORT="$OUTDIR/REPORT.md"
: > "$LOGFILE"

SCAN_START_EPOCH=$(date +%s)
SCAN_START_HUMAN="$(date '+%Y-%m-%d %H:%M:%S %Z')"
PORTS=""

# ===========================================================================
#  Interrupt / exit handling — always try to leave a report behind
# ===========================================================================
INTERRUPTED=0
on_interrupt() { echo; warn "Interrupted — finalising report from completed stages…"; INTERRUPTED=1; }
trap on_interrupt INT TERM

# ---------------------------------------------------------------------------
#  Report generator (invoked at the end, and on interrupt via finish())
# ---------------------------------------------------------------------------
build_report() {
    local end_epoch dur_min dur_sec
    end_epoch=$(date +%s)
    dur_sec=$(( end_epoch - SCAN_START_EPOCH ))
    dur_min=$(( dur_sec / 60 )); dur_sec=$(( dur_sec % 60 ))

    {
        echo "# TCP Enumeration Report"
        echo
        echo "> Automated assessment output — **authorized testing only**."
        echo
        echo "## Scan metadata"
        echo
        echo "| Field | Value |"
        echo "|---|---|"
        echo "| Target | \`$TARGET\` |"
        echo "| Profile | $PROFILE — $PROFILE_DESC |"
        echo "| Timing options | \`$TIMING\` |"
        echo "| Started | $SCAN_START_HUMAN |"
        echo "| Duration | ${dur_min}m ${dur_sec}s |"
        echo "| Nmap | ${NMAP_VER:-unknown} |"
        echo "| Status | $([[ $INTERRUPTED -eq 1 ]] && echo 'INTERRUPTED (partial)' || echo 'completed') |"
        echo

        echo "## Executive summary"
        echo
        if [[ -n "$PORTS" ]]; then
            local n; n=$(awk -F',' '{print NF}' <<<"$PORTS")
            echo "- **$n open TCP port(s)** discovered: \`$PORTS\`"
        else
            echo "- **No open TCP ports** were discovered (host down, fully filtered, or UDP-only)."
        fi
        echo "- Full session log: \`00_full_session.log\`"
        echo "- Per-service outputs saved alongside this report."
        echo

        # ---- Open ports table (parsed from the identify stage) ----
        echo "## Open ports & services"
        echo
        if [[ -f "$OUTDIR/02_identify.nmap" ]]; then
            echo "| Port | State | Service | Version |"
            echo "|---|---|---|---|"
            awk '/^[0-9]+\/tcp/ {
                port=$1; state=$2; svc=$3;
                ver="";
                for (i=4;i<=NF;i++) ver=ver $i " ";
                gsub(/\|/,"\\|",ver);
                if (ver=="") ver="—";
                printf "| %s | %s | %s | %s |\n", port, state, svc, ver;
            }' "$OUTDIR/02_identify.nmap"
        else
            echo "_Identify stage did not complete._"
        fi
        echo

        # ---- Per-service findings ----
        echo "## Per-service findings"
        echo
        local f svc_label
        for f in "$OUTDIR"/ftp_*.txt "$OUTDIR"/ssh_*.txt "$OUTDIR"/telnet_*.txt \
                 "$OUTDIR"/http_*.txt "$OUTDIR"/https_*.txt "$OUTDIR"/rtsp_*.txt \
                 "$OUTDIR"/mqtt_*.txt "$OUTDIR"/altweb_*.txt "$OUTDIR"/modbus_*.txt \
                 "$OUTDIR"/s7_*.txt; do
            [[ -f "$f" ]] || continue
            svc_label="$(basename "$f" .txt)"
            echo "### $svc_label"
            echo
            echo '```'
            # Port line + NSE script output lines only — keep the report tight.
            grep -E '^[0-9]+/tcp|^\|' "$f" 2>/dev/null || echo "(no script output captured)"
            echo '```'
            echo
        done

        echo "## Recommended next steps"
        echo
        echo "1. Review each open service against the per-service review matrix in the IoT port playbook."
        echo "2. Where you have shell access, diff externally-reachable ports against internally listening sockets (\`ss -lntup\`)."
        echo "3. Validate any notable finding with a second scan before reporting — embedded stacks give flaky results."
        echo
        echo "---"
        echo "_Generated by tcp-enum.sh on $(date '+%Y-%m-%d %H:%M:%S %Z'). For authorized security assessment only._"
    } > "$REPORT"
}

finish() {
    banner "REPORT"
    build_report
    ok "Report written: ${WHITE}$OUTDIR/REPORT.md${RESET}"
    echo "${BOLD}Artifacts in $OUTDIR/:${RESET}"
    ls -1 "$OUTDIR/" | sed "s/^/    /"
    echo
    echo "${BOLD}${BLUE}Tip:${RESET} render the report with any Markdown viewer, or ${DIM}glow $OUTDIR/REPORT.md${RESET}"
    [[ $INTERRUPTED -eq 1 ]] && exit 130 || exit 0
}

# ===========================================================================
#  Header
# ===========================================================================
banner "TCP ENUM"
echo "${BOLD}Target  : ${WHITE}$TARGET${RESET}"
echo "${BOLD}Profile : ${WHITE}$PROFILE${RESET}  ${DIM}($PROFILE_DESC)${RESET}"
echo "${BOLD}Timing  : ${WHITE}$TIMING${RESET}"
echo "${BOLD}Output  : ${WHITE}$OUTDIR/${RESET}"
echo "${BOLD}Started : ${WHITE}$SCAN_START_HUMAN${RESET}"

# ===========================================================================
#  STAGE 1 — Full-range TCP sweep (live progress)
# ===========================================================================
banner "STAGE 1 SWEEP"
step_header "Full 65535-port TCP sweep"
run "$SUDO nmap -sS -p- $TIMING $COMMON -oN $OUTDIR/01_all_tcp.txt -oG $OUTDIR/01_all_tcp.gnmap $TARGET"

PORTS="$(grep -oP '\d+/open' "$OUTDIR/01_all_tcp.gnmap" 2>/dev/null \
         | cut -d/ -f1 | sort -un | paste -sd, || true)"

[[ $INTERRUPTED -eq 1 ]] && finish

if [[ -z "$PORTS" ]]; then
    warn "No open TCP ports found. Host may be down, filtered, or UDP-only."
    echo "    ${DIM}Try UDP:  $SUDO nmap -sU -sV --top-ports 50 $TIMING -n -Pn --open $TARGET${RESET}"
    finish
fi
ok "Open TCP ports: ${WHITE}$PORTS${RESET}"

has() { [[ ",$PORTS," == *",$1,"* ]]; }

# ---- Pre-compute total steps so the progress tracker is accurate ----------
EXTRA=0
for p in 21 22 23 80 443 554 1883 8080 8443 502 102; do has "$p" && EXTRA=$((EXTRA+1)); done
TOTAL=$(( 2 + EXTRA ))

# ===========================================================================
#  STAGE 2 — Identify (version + default scripts + OS) on open ports only
# ===========================================================================
banner "STAGE 2 IDENTIFY"
step_header "Service / version / OS identification"
run "$SUDO nmap -sV -sC -O --osscan-guess $TIMING $COMMON -p $PORTS -oA $OUTDIR/02_identify $TARGET"
[[ $INTERRUPTED -eq 1 ]] && finish

# ===========================================================================
#  STAGE 3 — Per-service deep enumeration
# ===========================================================================
banner "STAGE 3 DEEP"

if has 21; then
    step_header "FTP (21) deep enumeration"
    section "FTP (21) — anonymous access, banner, writable dirs"
    run "$SUDO nmap -Pn -sV -p21 $COMMON --script ftp-anon,ftp-syst,ftp-bounce -oN $OUTDIR/ftp_21.txt $TARGET"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

if has 22; then
    step_header "SSH (22) deep enumeration"
    section "SSH (22) — algorithms, auth methods, host key"
    run "$SUDO nmap -Pn -sV -p22 $COMMON --script ssh2-enum-algos,ssh-auth-methods,ssh-hostkey -oN $OUTDIR/ssh_22.txt $TARGET"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

if has 23; then
    step_header "Telnet (23) deep enumeration"
    section "TELNET (23) — encryption, banner (open telnet = finding)"
    run "$SUDO nmap -Pn -sV -p23 $COMMON --script telnet-encryption,telnet-ntlm-info,banner -oN $OUTDIR/telnet_23.txt $TARGET"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

if has 80; then
    step_header "HTTP (80) deep enumeration"
    section "HTTP (80) — identity, paths, default creds, security headers"
    run "$SUDO nmap -Pn -p80 $COMMON --script http-title,http-headers,http-methods,http-server-header,http-enum,http-security-headers,http-default-accounts,http-favicon -oN $OUTDIR/http_80.txt $TARGET"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

if has 443; then
    step_header "HTTPS (443) deep enumeration"
    section "HTTPS (443) — TLS posture + web enumeration over TLS"
    run "$SUDO nmap -Pn -sV -p443 $COMMON --script ssl-cert,ssl-enum-ciphers,tls-alpn,ssl-date,http-title,http-headers,http-enum -oN $OUTDIR/https_443.txt $TARGET"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

if has 554; then
    step_header "RTSP (554) deep enumeration"
    section "RTSP (554) — camera streams, methods, URL brute"
    run "$SUDO nmap -Pn -p554 $COMMON --script rtsp-methods,rtsp-url-brute -oN $OUTDIR/rtsp_554.txt $TARGET"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

if has 1883; then
    step_header "MQTT (1883) deep enumeration"
    section "MQTT (1883) — anonymous subscribe, topic dump"
    run "$SUDO nmap -Pn -p1883 $COMMON --script mqtt-subscribe -oN $OUTDIR/mqtt_1883.txt $TARGET"
    command -v mosquitto_sub >/dev/null 2>&1 && \
        echo "${BOLD}${BLUE}[hint]${RESET} Direct dump: ${WHITE}mosquitto_sub -h $TARGET -t '#' -v${RESET}"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

for ap in 8080 8443; do
    if has "$ap"; then
        step_header "Alt-web ($ap) deep enumeration"
        section "ALT-WEB ($ap) — proxy / admin / ONVIF / dev console"
        run "$SUDO nmap -Pn -sV -p$ap $COMMON --script \"http-title,http-headers,http-methods,http-enum,ssl-cert\" -oN $OUTDIR/altweb_${ap}.txt $TARGET"
        [[ $INTERRUPTED -eq 1 ]] && finish
    fi
done

if has 502; then
    step_header "Modbus (502) deep enumeration"
    section "MODBUS (502) — ICS device discovery (READ-ONLY)"
    warn "ICS target — read-only discovery only. No writes on live plant."
    run "$SUDO nmap -Pn -p502 $COMMON --script modbus-discover -oN $OUTDIR/modbus_502.txt $TARGET"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

if has 102; then
    step_header "Siemens S7 (102) deep enumeration"
    section "SIEMENS S7 (102) — PLC module/firmware info (READ-ONLY)"
    warn "ICS target — read-only discovery only."
    run "$SUDO nmap -Pn -p102 $COMMON --script s7-info -oN $OUTDIR/s7_102.txt $TARGET"
    [[ $INTERRUPTED -eq 1 ]] && finish
fi

# ===========================================================================
#  Finish — build + announce the report
# ===========================================================================
finish
