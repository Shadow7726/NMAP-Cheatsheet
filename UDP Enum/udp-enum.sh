#!/usr/bin/env bash
###############################################################################
#  udp-enum.sh  —  Professional UDP enumeration suite for IoT / embedded devices
#
#  • Interactive menus: choose SCAN SCOPE and TIMING PROFILE (each described)
#  • Curated IoT UDP sweep / top-N / all / custom → identify → per-service NSE
#  • Live progress in the terminal (nmap percentage + ETA, stage timers)
#  • Auto-generated Markdown report at the end of the scan
#  • Interrupt-safe: Ctrl-C still produces a report from whatever completed
#
#  UDP is where embedded devices live (SNMP, TFTP, SSDP, mDNS, CoAP, BACnet…).
#  It is slow and lossy, so -sV is used so results are definitive (not just
#  'open|filtered'), and enumeration defaults to READ-ONLY.
#
#  Authorized testing only. Use solely against systems you own or are
#  explicitly permitted to assess.
#
#  Usage:
#      ./udp-enum.sh [target] [profile] [scope] [custom_ports]
#
#    Any argument you omit is asked for interactively (menu with descriptions).
#      profile : fast | safe | ics
#      scope   : known | top100 | top200 | all | fast | custom
#      custom_ports : required only when scope=custom (e.g. 161,1900,5353)
#
#  Examples (RFC 5737 documentation addresses — replace with your scope):
#      sudo ./udp-enum.sh                      # fully interactive
#      sudo ./udp-enum.sh 192.0.2.10           # asks profile + scope
#      sudo ./udp-enum.sh 192.0.2.10 safe known
#      sudo ./udp-enum.sh 198.51.100.25 ics custom 47808,44818
###############################################################################
set -uo pipefail

# ===========================================================================
#  Presentation helpers
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

STEP=0
TOTAL=2
step_header() {
    STEP=$((STEP + 1))
    local pct=$(( STEP * 100 / (TOTAL > 0 ? TOTAL : 1) ))
    echo
    echo "${BOLD}${MAGENTA}┌──────────────────────────────────────────────────────────────────────┐${RESET}"
    printf "${BOLD}${MAGENTA}│  PROGRESS  [%2d/%-2d]  %3d%%   %-40s│${RESET}\n" "$STEP" "$TOTAL" "$pct" "$1"
    echo "${BOLD}${MAGENTA}└──────────────────────────────────────────────────────────────────────┘${RESET}"
}

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
    eval "$cmd" 2>&1 | tee -a "$LOGFILE"
    t1=$(date +%s)
    echo "${DIM}    ↳ completed in $((t1 - t0))s${RESET}"
    echo
}

# ===========================================================================
#  Curated IoT / embedded UDP port set
# ===========================================================================
#   53 DNS · 67 DHCP · 69 TFTP · 123 NTP · 137 NetBIOS · 161/162 SNMP ·
#   500/4500 IKE · 520 RIP · 623 IPMI · 1900 SSDP/UPnP · 3702 WS-Discovery ·
#   5060 SIP · 5353 mDNS · 5683/5684 CoAP(/DTLS) · 11211 memcached ·
#   2222 EtherNet/IP I/O · 44818 EtherNet/IP · 47808 BACnet · 9600 OMRON FINS
UDP_PORTS="53,67,69,123,137,161,162,500,520,623,1900,3702,4500,5060,5353,5683,5684,9600,11211,2222,44818,47808"
KNOWN_COUNT="$(awk -F',' '{print NF}' <<<"$UDP_PORTS")"

# ===========================================================================
#  Interactive menus
# ===========================================================================
have_tty() { [[ -t 0 && -t 1 ]]; }

ask_target() {
    [[ -n "${TARGET:-}" ]] && return
    if have_tty; then
        read -rp "${BOLD}Enter target (IP or hostname): ${RESET}" TARGET
    fi
    [[ -z "${TARGET:-}" ]] && { err "No target given."; exit 1; }
}

ask_profile() {
    [[ -n "${PROFILE:-}" ]] && return
    if ! have_tty; then PROFILE="safe"; return; fi
    echo
    echo "${BOLD}${CYAN}Select timing profile:${RESET}"
    echo "  ${BOLD}1) fast${RESET}  — ${DIM}-T4, aggressive. Robust hosts / embedded Linux. Fastest, riskier on fragile gear.${RESET}"
    echo "  ${BOLD}2) safe${RESET}  — ${DIM}-T2, polite + rate-capped. Fragile IoT / unknown stacks. ${GREEN}Recommended.${RESET}"
    echo "  ${BOLD}3) ics ${RESET}  — ${DIM}-T2 + scan-delay, gentlest. PLCs / SCADA / medical.${RESET}"
    local c; read -rp "${BOLD}Choice [1-3] (default 2): ${RESET}" c
    case "$c" in
        1) PROFILE="fast" ;;
        3) PROFILE="ics"  ;;
        2|"") PROFILE="safe" ;;
        *) warn "Invalid — defaulting to safe."; PROFILE="safe" ;;
    esac
}

ask_scope() {
    [[ -n "${SCOPE:-}" ]] && return
    if ! have_tty; then SCOPE="known"; return; fi
    echo
    echo "${BOLD}${CYAN}Select UDP scan scope:${RESET}"
    echo "  ${BOLD}1) Known IoT ports${RESET}  — ${DIM}curated ${KNOWN_COUNT} UDP ports (SNMP, TFTP, SSDP, mDNS, CoAP, BACnet, EtherNet/IP…). Fast & targeted. ${GREEN}Recommended.${RESET}"
    echo "  ${BOLD}2) Top 100 UDP${RESET}     — ${DIM}Nmap's 100 most common UDP ports. Broader, noticeably slower.${RESET}"
    echo "  ${BOLD}3) Top 200 UDP${RESET}     — ${DIM}Nmap's 200 most common UDP ports. Wider net, slower still.${RESET}"
    echo "  ${BOLD}4) All 65535 UDP${RESET}   — ${DIM}${RED}every UDP port. VERY slow (often hours). Only when exhaustive coverage is required.${RESET}"
    echo "  ${BOLD}5) Custom ports${RESET}    — ${DIM}you type a port, list or range (e.g. 161,1900,5353 or 1-1000).${RESET}"
    echo "  ${BOLD}6) Fast discovery${RESET}  — ${DIM}known IoT ports, discovery only (no -sV in stage 1): quickest first pass; detail is recovered in stage 2.${RESET}"
    local c; read -rp "${BOLD}Choice [1-6] (default 1): ${RESET}" c
    case "$c" in
        1|"") SCOPE="known"  ;;
        2)    SCOPE="top100" ;;
        3)    SCOPE="top200" ;;
        4)    SCOPE="all"    ;;
        5)    SCOPE="custom" ;;
        6)    SCOPE="fast"   ;;
        *) warn "Invalid — defaulting to known."; SCOPE="known" ;;
    esac
}

# ===========================================================================
#  Argument parsing  (anything omitted is asked for interactively)
# ===========================================================================
TARGET="${1:-}"
PROFILE="${2:-}"
SCOPE="${3:-}"
CUSTOM_PORTS="${4:-}"

ask_target
ask_profile
ask_scope

# Validate profile
case "$PROFILE" in
    fast) TIMING="-T4 --max-retries 2"                          ; PROFILE_DESC="aggressive (robust hosts / embedded Linux)" ;;
    safe) TIMING="-T2 --max-retries 2 --max-rate 200"           ; PROFILE_DESC="polite (fragile IoT / unknown stacks)" ;;
    ics)  TIMING="-T2 --scan-delay 100ms --max-retries 1 --max-rate 80" ; PROFILE_DESC="gentlest (PLCs / SCADA)" ;;
    *)    err "Unknown profile: $PROFILE (use fast | safe | ics)"; exit 1 ;;
esac

# Resolve scope → PORT_ARG + label + fast flag
FAST_MODE=0
case "$SCOPE" in
    known)  PORT_ARG="-p $UDP_PORTS"       ; SCOPE_LABEL="known IoT ports ($KNOWN_COUNT ports)" ;;
    top100) PORT_ARG="--top-ports 100"     ; SCOPE_LABEL="top 100 UDP ports" ;;
    top200) PORT_ARG="--top-ports 200"     ; SCOPE_LABEL="top 200 UDP ports" ;;
    all)    PORT_ARG="-p 1-65535"          ; SCOPE_LABEL="all 65535 UDP ports" ;;
    fast)   PORT_ARG="-p $UDP_PORTS"       ; SCOPE_LABEL="known IoT ports — fast discovery (no -sV)"; FAST_MODE=1 ;;
    custom)
        if [[ -z "$CUSTOM_PORTS" ]]; then
            if have_tty; then read -rp "${BOLD}Enter custom ports (e.g. 161,1900 or 1-1000): ${RESET}" CUSTOM_PORTS; fi
        fi
        [[ "$CUSTOM_PORTS" =~ ^[0-9,\-]+$ ]] || { err "Invalid custom port spec: '$CUSTOM_PORTS'"; exit 1; }
        PORT_ARG="-p $CUSTOM_PORTS"        ; SCOPE_LABEL="custom ports: $CUSTOM_PORTS" ;;
    *) err "Unknown scope: $SCOPE"; exit 1 ;;
esac

# Confirm the very slow "all" scope
if [[ "$SCOPE" == "all" ]] && have_tty; then
    warn "Scanning all 65535 UDP ports can take HOURS and may stress a fragile device."
    read -rp "${BOLD}Proceed anyway? [y/N]: ${RESET}" yn
    [[ "$yn" =~ ^[Yy]$ ]] || { info "Cancelled."; exit 0; }
fi

# ===========================================================================
#  Pre-flight
# ===========================================================================
command -v nmap >/dev/null 2>&1 || { err "nmap is not installed. Install it and retry."; exit 1; }
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then SUDO=""; else SUDO="sudo"; warn "Not root — UDP scans need privileges; commands use 'sudo'."; fi
NMAP_VER="$(nmap --version 2>/dev/null | head -1)"

COMMON="-n -Pn --open --reason --send-ip -v --stats-every 15s"
STAMP="$(date +%Y%m%d_%H%M%S)"
SAFE_TGT="${TARGET//[^0-9A-Za-z._-]/_}"
OUTDIR="udpenum_${SAFE_TGT}_${STAMP}"
mkdir -p "$OUTDIR"
LOGFILE="$OUTDIR/00_full_session.log"
REPORT="$OUTDIR/REPORT.md"
: > "$LOGFILE"

SCAN_START_EPOCH=$(date +%s)
SCAN_START_HUMAN="$(date '+%Y-%m-%d %H:%M:%S %Z')"
PORTS=""

INTERRUPTED=0
on_interrupt() { echo; warn "Interrupted — finalising report from completed stages…"; INTERRUPTED=1; }
trap on_interrupt INT TERM

build_report() {
    local end_epoch dur_min dur_sec
    end_epoch=$(date +%s); dur_sec=$(( end_epoch - SCAN_START_EPOCH ))
    dur_min=$(( dur_sec / 60 )); dur_sec=$(( dur_sec % 60 ))
    {
        echo "# UDP Enumeration Report"; echo
        echo "> Automated assessment output — **authorized testing only**."; echo
        echo "## Scan metadata"; echo
        echo "| Field | Value |"; echo "|---|---|"
        echo "| Target | \`$TARGET\` |"
        echo "| Profile | $PROFILE — $PROFILE_DESC |"
        echo "| Scan scope | $SCOPE_LABEL |"
        echo "| Timing options | \`$TIMING\` |"
        echo "| Started | $SCAN_START_HUMAN |"
        echo "| Duration | ${dur_min}m ${dur_sec}s |"
        echo "| Nmap | ${NMAP_VER:-unknown} |"
        echo "| Status | $([[ $INTERRUPTED -eq 1 ]] && echo 'INTERRUPTED (partial)' || echo 'completed') |"
        echo
        echo "## Executive summary"; echo
        if [[ -n "$PORTS" ]]; then
            local n; n=$(awk -F',' '{print NF}' <<<"$PORTS")
            echo "- **$n responsive UDP port(s)** discovered: \`$PORTS\`"
        else
            echo "- **No open UDP ports** were confirmed. UDP is lossy — a clean result is not proof of absence."
        fi
        echo "- Full session log: \`00_full_session.log\`"
        echo "- Per-service outputs saved alongside this report."; echo
        echo "## Open ports & services"; echo
        if [[ -f "$OUTDIR/02_identify.nmap" ]]; then
            echo "| Port | State | Service | Version |"; echo "|---|---|---|---|"
            awk '/^[0-9]+\/udp/ {
                port=$1; state=$2; svc=$3; ver="";
                for (i=4;i<=NF;i++) ver=ver $i " ";
                gsub(/\|/,"\\|",ver); if (ver=="") ver="—";
                printf "| %s | %s | %s | %s |\n", port, state, svc, ver;
            }' "$OUTDIR/02_identify.nmap"
        else
            echo "_Identify stage did not complete._"
        fi
        echo
        echo "## Per-service findings"; echo
        local f svc_label
        for f in "$OUTDIR"/dns_*.txt "$OUTDIR"/tftp_*.txt "$OUTDIR"/ntp_*.txt \
                 "$OUTDIR"/snmp_*.txt "$OUTDIR"/ike_*.txt "$OUTDIR"/ipmi_*.txt \
                 "$OUTDIR"/netbios_*.txt "$OUTDIR"/ssdp_*.txt "$OUTDIR"/sip_*.txt \
                 "$OUTDIR"/mdns_*.txt "$OUTDIR"/coap_*.txt "$OUTDIR"/memcached_*.txt \
                 "$OUTDIR"/bacnet_*.txt "$OUTDIR"/enip_*.txt "$OUTDIR"/omron_*.txt; do
            [[ -f "$f" ]] || continue
            svc_label="$(basename "$f" .txt)"
            echo "### $svc_label"; echo; echo '```'
            grep -E '^[0-9]+/udp|^\|' "$f" 2>/dev/null || echo "(no script output captured)"
            echo '```'; echo
        done
        echo "## Recommended next steps"; echo
        echo "1. For SNMP, if 'public' failed, try a community-string brute (\`snmp-brute\`) then \`snmpwalk\` read-only."
        echo "2. Treat any ICS protocol (BACnet / EtherNet-IP / OMRON) as high-consequence — read-only only, maintenance window."
        echo "3. UDP is lossy: re-scan responsive ports to confirm, and widen scope if the device type suggests others."
        echo; echo "---"
        echo "_Generated by udp-enum.sh on $(date '+%Y-%m-%d %H:%M:%S %Z'). For authorized security assessment only._"
    } > "$REPORT"
}

finish() {
    banner "REPORT"; build_report
    ok "Report written: ${WHITE}$OUTDIR/REPORT.md${RESET}"
    echo "${BOLD}Artifacts in $OUTDIR/:${RESET}"; ls -1 "$OUTDIR/" | sed "s/^/    /"
    echo; echo "${BOLD}${BLUE}Tip:${RESET} render with any Markdown viewer, or ${DIM}glow $OUTDIR/REPORT.md${RESET}"
    [[ $INTERRUPTED -eq 1 ]] && exit 130 || exit 0
}

# ===========================================================================
#  Header
# ===========================================================================
banner "UDP ENUM"
echo "${BOLD}Target  : ${WHITE}$TARGET${RESET}"
echo "${BOLD}Profile : ${WHITE}$PROFILE${RESET}  ${DIM}($PROFILE_DESC)${RESET}"
echo "${BOLD}Scope   : ${WHITE}$SCOPE_LABEL${RESET}"
echo "${BOLD}Timing  : ${WHITE}$TIMING${RESET}"
echo "${BOLD}Output  : ${WHITE}$OUTDIR/${RESET}"
echo "${BOLD}Started : ${WHITE}$SCAN_START_HUMAN${RESET}"
warn "UDP scanning is slow and lossy — this is expected. Let it finish."

# ===========================================================================
#  STAGE 1 — UDP sweep (live progress). -sV unless fast-discovery mode.
# ===========================================================================
banner "STAGE 1 SWEEP"
if [[ $FAST_MODE -eq 1 ]]; then
    step_header "Fast UDP discovery (no -sV)"
    run "$SUDO nmap -sU $PORT_ARG $TIMING $COMMON -oN $OUTDIR/01_udp.txt -oG $OUTDIR/01_udp.gnmap $TARGET"
else
    step_header "UDP sweep with version detection (-sU -sV)"
    run "$SUDO nmap -sU -sV $PORT_ARG $TIMING $COMMON -oN $OUTDIR/01_udp.txt -oG $OUTDIR/01_udp.gnmap $TARGET"
fi

PORTS="$(grep -oP '\d+/open' "$OUTDIR/01_udp.gnmap" 2>/dev/null | cut -d/ -f1 | sort -un | paste -sd, || true)"
[[ $INTERRUPTED -eq 1 ]] && finish

if [[ -z "$PORTS" ]]; then
    warn "No confirmed open UDP ports. UDP is lossy — this is NOT proof of absence."
    echo "    ${DIM}Try a wider scope (re-run and pick Top 200 or All), or re-scan with 'safe'.${RESET}"
    finish
fi
ok "Responsive UDP ports: ${WHITE}$PORTS${RESET}"

has() { [[ ",$PORTS," == *",$1,"* ]]; }

EXTRA=0
for p in 53 69 123 137 161 500 623 1900 5060 5353 5683 11211 44818 47808 9600; do
    has "$p" && EXTRA=$((EXTRA+1))
done
TOTAL=$(( 2 + EXTRA ))

# ===========================================================================
#  STAGE 2 — Identify (version + default scripts) on responsive ports
# ===========================================================================
banner "STAGE 2 IDENTIFY"
step_header "Version + default-script identification"
run "$SUDO nmap -sU -sV -sC -p $PORTS $TIMING $COMMON -oA $OUTDIR/02_identify $TARGET"
[[ $INTERRUPTED -eq 1 ]] && finish

# ===========================================================================
#  STAGE 3 — Per-service deep enumeration (read-only by default)
# ===========================================================================
banner "STAGE 3 DEEP"

if has 53;   then step_header "DNS (53)";        section "DNS (53) — recursion, NSID, service discovery";          run "$SUDO nmap -sU -p53 $COMMON --script dns-recursion,dns-nsid,dns-service-discovery -oN $OUTDIR/dns_53.txt $TARGET";          [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 69;   then step_header "TFTP (69)";       section "TFTP (69) — no-auth file transfer enumeration";          run "$SUDO nmap -sU -p69 $COMMON --script tftp-enum -oN $OUTDIR/tftp_69.txt $TARGET";                                          [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 123;  then step_header "NTP (123)";       section "NTP (123) — info + monlist (amplification / info leak)"; run "$SUDO nmap -sU -p123 $COMMON --script ntp-info,ntp-monlist -oN $OUTDIR/ntp_123.txt $TARGET";                               [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 137;  then step_header "NetBIOS (137)";   section "NetBIOS (137) — name table";                             run "$SUDO nmap -sU -p137 $COMMON --script nbstat -oN $OUTDIR/netbios_137.txt $TARGET";                                        [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 161;  then step_header "SNMP (161)";      section "SNMP (161) — full device profile (READ-ONLY)";           run "$SUDO nmap -sU -p161 $COMMON --script snmp-info,snmp-sysdescr,snmp-interfaces,snmp-netstat,snmp-processes,snmp-win32-software -oN $OUTDIR/snmp_161.txt $TARGET"; echo "${BOLD}${BLUE}[hint]${RESET} If 'public' fails: ${WHITE}nmap -sU -p161 --script snmp-brute $TARGET${RESET} then ${WHITE}snmpwalk -v2c -c <community> $TARGET${RESET}"; [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 500;  then step_header "IKE (500)";       section "IKE/IPsec (500) — version & vendor";                     run "$SUDO nmap -sU -p500 $COMMON --script ike-version -oN $OUTDIR/ike_500.txt $TARGET";                                       [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 623;  then step_header "IPMI (623)";      section "IPMI (623) — version & cipher-zero auth bypass check";   run "$SUDO nmap -sU -p623 $COMMON --script ipmi-version,ipmi-cipher-zero -oN $OUTDIR/ipmi_623.txt $TARGET";                     [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 1900; then step_header "SSDP/UPnP (1900)";section "SSDP / UPnP (1900) — device description & control URLs"; run "$SUDO nmap -sU -p1900 $COMMON --script upnp-info -oN $OUTDIR/ssdp_1900.txt $TARGET";                                       [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 5060; then step_header "SIP (5060)";      section "SIP (5060) — methods & user enumeration";                run "$SUDO nmap -sU -p5060 $COMMON --script sip-methods,sip-enum-users -oN $OUTDIR/sip_5060.txt $TARGET";                      [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 5353; then step_header "mDNS (5353)";     section "mDNS (5353) — service / hostname discovery";             run "$SUDO nmap -sU -p5353 $COMMON --script dns-service-discovery -oN $OUTDIR/mdns_5353.txt $TARGET";                          [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 5683; then step_header "CoAP (5683)";     section "CoAP (5683) — resource discovery";                       run "$SUDO nmap -sU -p5683 $COMMON --script coap-resources -oN $OUTDIR/coap_5683.txt $TARGET";                                 [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 11211;then step_header "memcached (11211)";section "memcached (11211) — info & stats (exposure check)";      run "$SUDO nmap -sU -p11211 $COMMON --script memcached-info -oN $OUTDIR/memcached_11211.txt $TARGET";                          [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 44818;then step_header "EtherNet/IP (44818)"; section "ETHERNET/IP (44818) — ICS identity (READ-ONLY)"; warn "ICS target — read-only discovery only."; run "$SUDO nmap -sU -p44818 $COMMON --script enip-info -oN $OUTDIR/enip_44818.txt $TARGET"; [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 47808;then step_header "BACnet (47808)";  section "BACNET (47808) — building controller (READ-ONLY)"; warn "ICS target — read-only discovery only."; run "$SUDO nmap -sU -p47808 $COMMON --script bacnet-info -oN $OUTDIR/bacnet_47808.txt $TARGET"; [[ $INTERRUPTED -eq 1 ]] && finish; fi
if has 9600; then step_header "OMRON FINS (9600)"; section "OMRON FINS (9600) — PLC identity (READ-ONLY)"; warn "ICS target — read-only discovery only."; run "$SUDO nmap -sU -p9600 $COMMON --script omron-info -oN $OUTDIR/omron_9600.txt $TARGET"; [[ $INTERRUPTED -eq 1 ]] && finish; fi

finish
