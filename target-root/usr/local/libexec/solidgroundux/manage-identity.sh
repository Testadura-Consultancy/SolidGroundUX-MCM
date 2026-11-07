#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Identity
# ------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2631102
#   Shortname   : MANAGE_IDENTITY
#   Checksum    : e173e1b5cd27c52670548bdd650ab2f94011d021890adf839db9cd8f2c373d52
#   Source      : manage-identity.sh
#   Type        : script
#   Group       : Modules
#   Subgroup    : Computer Setup
#   Purpose     : Sets the hostname and IPv4 network configuration for a VM
#
# Description:
#  This script sets the hostname and IPv4 network configuration for a VM.
#
# Usage:
#   Run the executable from its shell command (or installed wrapper):
#   ```bash
#   manage-identity --dryrun
#   manage-identity --verbose
#   ```
#
#   Script-specific options:
#   - `--Ipv4 VALUE`, `-i`: Target static IPv4 address with CIDR.
#   - `--dhcp NAME`: Use DHCP for IPv4 configuration (choices: `yes`, `no`).
#   - `--DNS VALUE`, `-d`: Target DNS server IP address.
#   - `--DNS-search VALUE`: Target DNS search domain.
#   - `--dns-only`: Update only the configured DNS server and search domain.
#   - `--Gateway VALUE`, `-g`: Target gateway IP address.
#   - `--Hostname VALUE`, `-n`: Target hostname for the VM.
#   - `--Netplan VALUE`, `-p`: Path to the netplan configuration file.
#   - `--Auto`, `-a`: Run in non-interactive mode, using defaults or provided values.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail
# - Bootstrap -----------------------------------------------------------------------
    # fn$ _framework_locator - Resolve and load the active SolidGroundUX framework
        # . Purpose
        #   Determine the filesystem root of the currently executing SolidGroundUX tree
        #   from the script's physical path, then load the executable runtime library.
        #
        # . Behavior
        #   - Resolves the physical path of the executing script.
        #   - Treats usr, etc, and var as the canonical top-level SolidGroundUX tree roots.
        #   - Uses the last occurrence of one of those path components to determine the
        #     active filesystem root.
        #   - Resolves production scripts beneath /usr, /etc, or /var to root (/).
        #   - Resolves staged/development trees to the path prefix preceding the detected
        #     usr, etc, or var component.
        #   - Loads sgnd-exe-common.sh from the resolved framework root when available.
        #   - For staged/development trees where the executable common library is not
        #     present, falls back to the installed framework copy without changing
        #     SGND_FRAMEWORK_ROOT.
        #
        # . Globals (write)
        #   SGND_FRAMEWORK_ROOT
        #
        # . Output
        #   Writes fatal bootstrap errors to stderr using printf because framework UI
        #   helpers are not available until sgnd-exe-common.sh has been loaded.
        #
        # . Returns
        #   0 when the framework root was resolved and executable common library loaded.
        #   126 when the script path cannot be resolved, no canonical root component can
        #   be found, or the executable common library is unreadable.
        #
        # . Usage
        #   ```bash
        #   _framework_locator || return $?
        #   ```
    _framework_locator() {
        local script_file=""
        local path_without_root=""
        local component=""
        local framework_root=""
        local exe_common=""
        local index=0
        local root_index=-1
        local -a path_parts=()

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || {
            printf 'FATAL: Cannot resolve executable path: %s\n' "${BASH_SOURCE[0]}" >&2
            return 126
        }

        path_without_root="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"

        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in
                usr|etc|var)
                    root_index=$index
                    ;;
            esac
        done

        if (( root_index < 0 )); then
            printf 'FATAL: Cannot determine SolidGroundUX framework root from: %s\n' "$script_file" >&2
            return 126
        fi

        if (( root_index == 0 )); then
            framework_root="/"
        else
            framework_root=""
            for (( index=0; index<root_index; index++ )); do
                framework_root+="/${path_parts[$index]}"
            done
        fi

        SGND_FRAMEWORK_ROOT="$framework_root"

        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
        else
            exe_common="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"

            if [[ ! -r "$exe_common" ]]; then
                exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            fi
        fi

        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read executable common library: %s\n' "$exe_common" >&2
            return 126
        }

        # shellcheck source=/dev/null
        source "$exe_common"
    }
# - Script identity ------------------------------------------------------------------
    # var: SGND_SCRIPT_FILE - Absolute path to the currently executing script
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"

    # var: SGND_SCRIPT_DIR - Directory containing the currently executing script
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"

    # var: SGND_SCRIPT_BASE - Filename of the currently executing script
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"

    # var: SGND_SCRIPT_NAME - Script basename without the .sh extension
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"

# - Framework integration ----------------------------------------------------------
    # var: SGND_USING - Optional framework libraries to source after core bootstrap
        # Libraries to source from SGND_COMMON_LIB.
        # These are loaded automatically by sgnd_bootstrap AFTER core libraries.
        #
        # Example:
        #   SGND_USING=( net.sh fs.sh )
        #
        # Leave empty if no extra libs are needed.
    SGND_USING=(
    )

    # var: SGND_ARGS_SPEC - Script-specific command-line argument specification
        # Optional: script-specific arguments
        # --- Example: Arguments
        # Each entry:
        #   "name|short|type|var|help|default|choices"
        #
        #   name    = long option name WITHOUT leading --
        #   short   - short option name WITHOUT leading -
        #   type    = flag | value | enum
        #   var     = shell variable that will be set
        #   help    = help string for auto-generated --help output
        #   choices = for enum: comma-separated values (e.g. fast,slow,auto)
        #             for flag/value: leave empty
        #
        # Notes:
        #   - -h / --help is built in, you don't need to define it here.
        #   - After parsing you can use: FLAG_VERBOSE, VAL_CONFIG, ENUM_MODE, ...
    SGND_ARGS_SPEC=(
        "Ipv4|i|value|TARGET_IPV4|Target static IPv4 address with CIDR|"
        "dhcp||enum|USE_DHCP|Use DHCP for IPv4 configuration||yes,no"
        "DNS|d|value|TARGET_DNS|Target DNS server IP address|"
        "DNS-search||value|TARGET_DNS_SEARCH|Target DNS search domain|"
        "dns-only||flag|FLAG_DNS_ONLY|Update only the configured DNS server and search domain|"
        "Gateway|g|value|TARGET_GATEWAY|Target gateway IP address|"
        "Hostname|n|value|TARGET_HOSTNAME|Target hostname for the VM|"
        "Netplan|p|value|NETPLAN_FILE|Path to the netplan configuration file|"
        "Auto|a|flag|FLAG_AUTO|Run in non-interactive mode, using defaults or provided values|"
    )

    # var: SGND_SCRIPT_EXAMPLES - Optional help examples for this script
        # Optional: examples for --help output.
        # Each entry is a string that will be printed verbatim.
        #
        # Example:
        #   SGND_SCRIPT_EXAMPLES=(
        #       "Example usage:"
        #       "  script.sh --verbose --mode fast"
        #       "  script.sh -v -m slow"
        #   )
        #
        # Leave empty if no examples are needed.
    SGND_SCRIPT_EXAMPLES=(
        "Run in dry-run mode:"
        "  $SGND_SCRIPT_NAME --dryrun"
        ""
        "Show verbose logging"
        "  $SGND_SCRIPT_NAME --verbose"
    ) 

    # var: SGND_SCRIPT_GLOBALS - Script globals participating in configuration loading# var: SGND_SCRIPT_GLOBALS - Script globals participating in configuration loading
        # Explicit declaration of global variables intentionally used by this script.
        #
        # . Purpose
        #   - Declares which globals are part of the script’s public/config contract.
        #   - Enables optional configuration loading when non-empty.
        #
        # . Behavior
        #   - If this array is non-empty, sgnd_bootstrap enables config integration.
        #   - Variables listed here may be populated from configuration files.
        #   - Unlisted globals will NOT be auto-populated.
        #
        # Use this to:
        #   - Document intentional globals
        #   - Prevent accidental namespace leakage
        #   - Make configuration behavior explicit and predictable
        #
        # Only list:
        #   - Variables that must be globally accessible
        #   - Variables that may be defined in config files
        #
        # Leave empty if:
        #   - The script does not use configuration-driven globals
    SGND_SCRIPT_GLOBALS=(
    )

    # var: SGND_STATE_VARIABLES - Script variables participating in persistent state
        # List of variables participating in persistent state.
        #
        # . Purpose
        #   - Declares which variables should be saved/restored when state is enabled.
        #
        # . Behavior
        #   - Only used when sgnd_bootstrap is invoked with --state.
        #   - Variables listed here are serialized on exit (if SGND_STATE_SAVE=1).
        #   - On startup, previously saved values are restored before main logic runs.
        #
        # Contract:
        #   - Variables must be simple scalars (no arrays/associatives unless explicitly supported).
        #   - Script remains fully functional when state is disabled.
        #
        # Leave empty if:
        #   - The script does not use persistent state.
    SGND_STATE_VARIABLES=(
        TARGET_IPV4
        TARGET_HOSTNAME
        TARGET_GATEWAY
        TARGET_DNS
        TARGET_DNS_SEARCH
        USE_DHCP
    )

    # var: SGND_ON_EXIT_HANDLERS - Script-specific exit handler list
        # List of functions to be invoked on script termination.
        #
        # . Purpose
        #   - Allows scripts to register cleanup or finalization hooks.
        #
        # . Behavior
        #   - Functions listed here are executed during framework exit handling.
        #   - Execution order follows array order.
        #   - Handlers run regardless of normal exit or controlled termination.
        #
        # Contract:
        #   - Functions must exist before exit occurs.
        #   - Handlers must not call exit directly.
        #   - Handlers should be idempotent (safe if executed once).
        #
        # Typical uses:
        #   - Cleanup temporary files
        #   - Persist additional state
        #   - Release locks
        #
        # Leave empty if:
        #   - No custom exit behavior is required.
    SGND_ON_EXIT_HANDLERS=(
    )
    
    # var$ SGND_STATE_SAVE
        # State persistence toggle used by sgnd_bootstrap when state support is enabled.
        #
        # Scripts that want persistent state must:
        #   1) set SGND_STATE_SAVE=1
        #   2) call sgnd_bootstrap --state or --autostate
    SGND_STATE_SAVE=0

# - Local script declarations -------------------------------------------------------
    # doc$ Local script declarations
        # Put script-local constants and defaults here, not framework configuration.
        # Prefer local variables inside functions unless a value must be shared.

# - Local script functions ----------------------------------------------------------
    # fn: _set_defaults - Set defaults
        # . Purpose
        #   Initialize missing identity and network settings with the wizard defaults.
        #
        # . Returns
        #   . Returns
        #     the underlying command or workflow status.
        #
        # . Usage
        #   ```bash
        #   _set_defaults
        #   ```
    _set_defaults() {
        : "${TARGET_HOSTNAME:=}"
        : "${TARGET_IPV4:=}"
        : "${TARGET_GATEWAY:=}"
        : "${TARGET_DNS:=}"
        : "${TARGET_DNS_SEARCH:=}"
        : "${NETPLAN_FILE:=}"
        : "${PRIMARY_IFACE:=}"
        : "${USE_DHCP:=}"
    }

    # fn: _load_current_values - Load current values
        # . Purpose
        #   Load current values.
        #
        # . Returns
        #   . Returns
        #     the underlying command or workflow status.
        #
        # . Usage
        #   ```bash
        #   _load_current_values
        #   ```
    _load_current_values() {
        local detected=""
        local current_netplan=""
        local nm_uuid=""
        local nm_method=""

        [[ -n "$TARGET_HOSTNAME" ]] || TARGET_HOSTNAME="$(hostnamectl --static 2>/dev/null || hostname)"

        if [[ -z "$PRIMARY_IFACE" ]]; then
            PRIMARY_IFACE="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
            if [[ -z "$PRIMARY_IFACE" ]]; then
                PRIMARY_IFACE="$(find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | grep -v '^lo$' | head -n 1)"
            fi
        fi

        if [[ -z "$NETPLAN_FILE" ]]; then
            current_netplan="$(find /etc/netplan -maxdepth 1 -type f -name '*.yaml' -print 2>/dev/null | sort | head -n 1)"
            NETPLAN_FILE="${current_netplan:-/etc/netplan/00-installer-config.yaml}"
        fi

        if [[ -z "$USE_DHCP" ]]; then
            if [[ -n "$PRIMARY_IFACE" ]] && _interface_uses_networkmanager; then
                nm_uuid="$(_networkmanager_connection_uuid)" || nm_uuid=""
                if [[ -n "$nm_uuid" ]]; then
                    nm_method="$(nmcli -g ipv4.method connection show "$nm_uuid" 2>/dev/null)" || nm_method=""
                fi
                case "$nm_method" in
                    auto) USE_DHCP="Y" ;;
                    manual) USE_DHCP="N" ;;
                    *)
                        saywarning "Could not determine NetworkManager IPv4 mode; verify the DHCP selection."
                        USE_DHCP="N"
                        ;;
                esac
            elif [[ -r "$NETPLAN_FILE" ]] && grep -Eq '^[[:space:]]*dhcp4:[[:space:]]*true([[:space:]]|$)' "$NETPLAN_FILE"; then
                USE_DHCP="Y"
            else
                USE_DHCP="N"
            fi
        fi

        if [[ -n "$PRIMARY_IFACE" ]]; then
            detected="$(ip -o -4 address show dev "$PRIMARY_IFACE" scope global 2>/dev/null | awk '{print $4; exit}')"
            [[ -n "$TARGET_IPV4" ]] || TARGET_IPV4="$detected"

            detected="$(ip -o -4 route show default dev "$PRIMARY_IFACE" 2>/dev/null | awk '{print $3; exit}')"
            [[ -n "$TARGET_GATEWAY" ]] || TARGET_GATEWAY="$detected"
        fi

        if [[ -z "$TARGET_DNS" ]]; then
            if command -v resolvectl >/dev/null 2>&1 && [[ -n "$PRIMARY_IFACE" ]]; then
                TARGET_DNS="$(resolvectl dns "$PRIMARY_IFACE" 2>/dev/null | awk -F: 'NR == 1 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); split($2, dns, /[[:space:]]+/); print dns[1]}')"
            fi
            if [[ -z "$TARGET_DNS" && -r /etc/resolv.conf ]]; then
                TARGET_DNS="$(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2; exit}' /etc/resolv.conf)"
            fi
        fi

        if [[ -z "$TARGET_DNS_SEARCH" ]]; then
            if command -v resolvectl >/dev/null 2>&1 && [[ -n "$PRIMARY_IFACE" ]]; then
                TARGET_DNS_SEARCH="$(resolvectl domain "$PRIMARY_IFACE" 2>/dev/null | awk -F: 'NR == 1 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); split($2, domains, /[[:space:]]+/); for (i = 1; i <= length(domains); i++) if (domains[i] !~ /^~/ && domains[i] != "") {print domains[i]; exit}}')"
            fi
            if [[ -z "$TARGET_DNS_SEARCH" && -r "$NETPLAN_FILE" ]]; then
                TARGET_DNS_SEARCH="$(awk '/^[[:space:]]*search:[[:space:]]*$/ {getline; sub(/^[[:space:]]*-[[:space:]]*/, ""); print; exit}' "$NETPLAN_FILE")"
            fi
        fi
    }

    # fn: _get_usr_input - Get usr input
        # . Purpose
        #   Collect identity and network values using the shared prompt functions.
        #
        # . Returns
        #   . Returns
        #     the underlying command or workflow status.
        #
        # . Usage
        #   ```bash
        #   _get_usr_input
        #   ```
    _get_usr_input() {
        local mxw=80
        local lw=35
        local dhcp="N"

        if (( ${FLAG_AUTO:-0} == 1 )) && [[ -n "$TARGET_HOSTNAME" && -n "$USE_DHCP" ]]; then
            if [[ "${USE_DHCP^^}" == "Y" || "${USE_DHCP,,}" == "yes" || -n "$TARGET_IPV4" ]]; then
                return 0
            fi
        fi

        case "${USE_DHCP^^}" in
            Y|YES|TRUE|1|ON) dhcp="Y" ;;
            *) dhcp="N" ;;
        esac

        sgnd_print_sectionheader "Enter identifying information for this host" --maxwidth "$mxw"
        ask --label "Hostname" --var TARGET_HOSTNAME --default "$TARGET_HOSTNAME" --labelwidth "$lw"
        ask --label "Use DHCP (Y/N)" --var dhcp --default "$dhcp" --labelwidth "$lw"
        if _interface_uses_networkmanager; then
            sayinfo "NetworkManager owns $PRIMARY_IFACE; the active connection profile will be updated."
        else
            ask --label "Netplan file" --var NETPLAN_FILE --default "$NETPLAN_FILE" --labelwidth "$lw"
        fi

        case "${dhcp^^}" in
            Y|YES) USE_DHCP="Y" ;;
            *) USE_DHCP="N" ;;
        esac

        if [[ "$USE_DHCP" == "N" ]]; then
            ask --label "IPv4 address" --var TARGET_IPV4 --default "$TARGET_IPV4" --labelwidth "$lw"
            ask --label "Gateway" --var TARGET_GATEWAY --default "$TARGET_GATEWAY" --labelwidth "$lw"
            ask --label "DNS" --var TARGET_DNS --default "$TARGET_DNS" --labelwidth "$lw"
            ask --label "DNS search domain" --var TARGET_DNS_SEARCH --default "$TARGET_DNS_SEARCH" --labelwidth "$lw"
        fi
    }

    # fn: _set_hostname - Set hostname
        # . Purpose
        #   Apply the selected hostname to the current machine.
        #
        # . Returns
        #   . Returns
        #     the underlying command or workflow status.
        #
        # . Usage
        #   ```bash
        #   _set_hostname
        #   ```
    _set_hostname() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would set hostname to '$TARGET_HOSTNAME'."
            return 0
        fi

        sayinfo "Setting hostname to $TARGET_HOSTNAME"
        hostnamectl set-hostname "$TARGET_HOSTNAME" || return $?

        if grep -q '^127\.0\.1\.1' /etc/hosts; then
            sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $TARGET_HOSTNAME/" /etc/hosts || return $?
        else
            printf '127.0.1.1 %s\n' "$TARGET_HOSTNAME" >> /etc/hosts || return $?
        fi
    }

    # fn: _detect_primary_iface - Detect primary iface
        # . Purpose
        #   Detect primary iface.
        #
        # . Returns
        #   . Returns
        #     the underlying command or workflow status.
        #
        # . Usage
        #   ```bash
        #   _detect_primary_iface
        #   ```
    _detect_primary_iface() {
        sayinfo 'Detecting primary network interface'

        PRIMARY_IFACE="$(ip -o -4 route show to default | awk '{print $5; exit}')"
        if [[ -z "$PRIMARY_IFACE" ]]; then
            PRIMARY_IFACE="$(find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n' | grep -v '^lo$' | head -n 1)"
        fi

        if [[ -z "$PRIMARY_IFACE" ]]; then
            sayfail 'No network interface found.'
            return 1
        fi

        sayinfo "Primary network interface: $PRIMARY_IFACE"
    }

    # fn: _static_ip_conflict_check - Static ip conflict check
        # . Purpose
        #   Static ip conflict check.
        #
        # . Returns
        #   . Returns
        #     the underlying command or workflow status.
        #
        # . Usage
        #   ```bash
        #   _static_ip_conflict_check
        #   ```
    _static_ip_conflict_check() {
        local target_ip="${TARGET_IPV4%%/*}"
        local current_ip=""
        local ping_conflict=0
        local arp_conflict=0

        [[ -n "$target_ip" ]] || {
            sayfail "Cannot check an empty static IPv4 address."
            return 1
        }

        current_ip="$(ip -o -4 address show dev "$PRIMARY_IFACE" scope global 2>/dev/null | awk '{print $4; exit}')"
        current_ip="${current_ip%%/*}"

        if [[ -n "$current_ip" && "$target_ip" == "$current_ip" ]]; then
            sayinfo "Static IPv4 $target_ip is already assigned to this machine; skipping availability checks."
            return 0
        fi

        sayinfo "Checking whether static IPv4 $target_ip is already in use"

        if command -v ping >/dev/null 2>&1; then
            if ping -c 1 -W 1 "$target_ip" >/dev/null 2>&1; then
                ping_conflict=1
                saywarning "Ping check: $target_ip responded."
            else
                sayinfo "Ping check: no response from $target_ip."
            fi
        else
            saywarning "Ping is unavailable; skipping the ICMP availability check."
        fi

        if command -v arping >/dev/null 2>&1; then
            if arping -c 2 -w 3 -I "$PRIMARY_IFACE" "$target_ip" >/dev/null 2>&1; then
                arp_conflict=1
                saywarning "ARP check: another device responded for $target_ip."
            else
                sayinfo "ARP check: no device responded for $target_ip."
            fi
        else
            saywarning "arping is unavailable; skipping the ARP availability check."
        fi

        if (( ping_conflict == 0 && arp_conflict == 0 )); then
            sayok "Static IPv4 $target_ip appears to be available."
            return 0
        fi

        saywarning "The selected address $target_ip appears to be in use."
        saywarning "Assigning it may make this machine or another device unreachable."

        if (( ${FLAG_AUTO:-0} == 1 )); then
            sayfail "Refusing to use an address that appears occupied in automatic mode."
            return 1
        fi

        ask_continue "Continue and assign $target_ip anyway?" || {
            saycancel "Network configuration cancelled; the address was not changed."
            return 1
        }

        saywarning "Continuing with the occupied address at the user's request."
        return 0
    }

    # fn: _interface_uses_networkmanager - Check whether NetworkManager owns the interface.
        # . Purpose
        #   Ask NetworkManager itself whether the primary interface is managed. Do not
        #   infer ownership only from the installed desktop or a Netplan filename.
        # . Usage
        #   ```bash
        #   _interface_uses_networkmanager
        #   ```
    _interface_uses_networkmanager() {
        local managed=""

        command -v nmcli >/dev/null 2>&1 || return 1
        managed="$(nmcli -g GENERAL.NM-MANAGED device show "$PRIMARY_IFACE" 2>/dev/null)" || return 1
        [[ "${managed,,}" == "yes" || "${managed,,}" == "true" ]]
    }

    # fn: _networkmanager_connection_uuid - Resolve the active profile for an interface.
        # . Purpose
        #   Resolve the profile UUID without creating another NetworkManager connection.
        #   An inactive/unconnected interface is not safe to configure automatically.
        # . Usage
        #   ```bash
        #   _networkmanager_connection_uuid
        #   ```
    _networkmanager_connection_uuid() {
        local connection=""
        local uuid=""

        connection="$(nmcli -g GENERAL.CONNECTION device show "$PRIMARY_IFACE" 2>/dev/null)" || return 1
        [[ -n "$connection" && "$connection" != "--" ]] || return 1
        uuid="$(nmcli -g connection.uuid connection show "$connection" 2>/dev/null)" || return 1
        [[ -n "$uuid" && "$uuid" != "--" ]] || return 1
        printf '%s\n' "$uuid"
    }

    # fn: _apply_networkmanager_config - Update an existing NetworkManager IPv4 profile.
        # . Purpose
        #   Preserve the existing NetworkManager connection and Netplan-backed 90-NM
        #   profiles rather than replacing their YAML with a networkd configuration.
        #   Snapshot the IPv4 fields and restore them if reactivation fails.
        # . Arguments
        #   - `$1`: `static`, `dhcp` or `dns-only`.
        # . Usage
        #   ```bash
        #   _apply_networkmanager_config "dhcp"
        #   ```
    _apply_networkmanager_config() {
        local mode="${1:-}"
        local uuid=""
        local field=""
        local original=""
        local output=""
        local -a previous=()
        local -a desired=()
        local -a fields=(ipv4.method ipv4.addresses ipv4.gateway ipv4.dns ipv4.dns-search ipv4.ignore-auto-dns)

        uuid="$(_networkmanager_connection_uuid)" || {
            sayfail "No active NetworkManager connection found for $PRIMARY_IFACE; refusing to create a competing profile."
            return 1
        }

        for field in "${fields[@]}"; do
            original="$(nmcli -g "$field" connection show "$uuid" 2>/dev/null)" || {
                sayfail "Cannot inspect NetworkManager field '$field' for $PRIMARY_IFACE."
                return 1
            }
            [[ "$original" == "--" ]] && original=""
            previous+=("$field" "$original")
        done

        case "$mode" in
            static)
                desired=(
                    ipv4.method manual
                    ipv4.addresses "$TARGET_IPV4"
                    ipv4.gateway "$TARGET_GATEWAY"
                    ipv4.dns "$TARGET_DNS"
                    ipv4.dns-search "$TARGET_DNS_SEARCH"
                    ipv4.ignore-auto-dns no
                )
                ;;
            dhcp)
                desired=(
                    ipv4.method auto
                    ipv4.addresses ""
                    ipv4.gateway ""
                    ipv4.dns ""
                    ipv4.dns-search ""
                    ipv4.ignore-auto-dns no
                )
                ;;
            dns-only)
                desired=(
                    ipv4.dns "$TARGET_DNS"
                    ipv4.dns-search "$TARGET_DNS_SEARCH"
                    ipv4.ignore-auto-dns yes
                )
                ;;
            *)
                sayfail "Unknown NetworkManager configuration mode: $mode"
                return 1
                ;;
        esac

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would update the existing NetworkManager connection on $PRIMARY_IFACE ($mode)."
            sayinfo "DRYRUN: Would reactivate the connection; unrelated Netplan files would remain untouched."
            return 0
        fi

        sayinfo "Updating the existing NetworkManager connection on $PRIMARY_IFACE ($mode)."
        if ! output="$(nmcli connection modify "$uuid" "${desired[@]}" 2>&1)"; then
            sayfail "NetworkManager refused the connection update: $output"
            return 1
        fi

        if ! output="$(nmcli connection up "$uuid" ifname "$PRIMARY_IFACE" 2>&1)"; then
            sayfail "NetworkManager failed to activate the updated connection: $output"
            if ! nmcli connection modify "$uuid" "${previous[@]}" >/dev/null 2>&1; then
                saywarning "Failed to restore the previous NetworkManager IPv4 settings."
            elif ! nmcli connection up "$uuid" ifname "$PRIMARY_IFACE" >/dev/null 2>&1; then
                saywarning "Previous settings restored, but the connection could not be reactivated."
            fi
            return 1
        fi

        sayok "NetworkManager connection updated; unrelated profiles preserved."
        return 0
    }

    # fn: _netplan_file_is_dedicated - Refuse to overwrite unrelated Netplan interfaces.
        # . Purpose
        #   The networkd writer replaces its selected file. Permit that only when
        #   the file contains the selected interface and standard network settings.
        #   A complex/multi-interface configuration must be edited manually.
        # . Usage
        #   ```bash
        #   _netplan_file_is_dedicated
        #   ```
    _netplan_file_is_dedicated() {
        [[ -f "$NETPLAN_FILE" ]] || return 0
        awk -v iface="$PRIMARY_IFACE" '
            /^  (wifis|bridges|bonds|vlans|tunnels|modems|vrfs|nm-devices|dummy-devices):/ { exit 1 }
            /^  [^ #][^:]*:/ {
                key=$0
                sub(/^  /, "", key)
                sub(/:.*/, "", key)
                if (key != "version" && key != "renderer" && key != "ethernets") exit 1
            }
            /^    [^ #][^:]*:/ {
                key=$0
                sub(/^    /, "", key)
                sub(/:.*/, "", key)
                gsub(/["\047]/, "", key)
                if (key != iface) exit 1
            }
        ' "$NETPLAN_FILE"
    }

    # fn: _netplan_other_file_defines_iface - Detect multiple definitions of the selected interface.
        # . Purpose
        #   Refuse ambiguous Netplan configurations rather than accidentally overriding
        #   a later YAML definition while keeping the files themselves untouched.
        # . Usage
        #   ```bash
        #   _netplan_other_file_defines_iface
        #   ```
    _netplan_other_file_defines_iface() {
        local file=""
        while IFS= read -r -d '' file; do
            [[ "$file" == "$NETPLAN_FILE" ]] && continue
            if awk -v iface="$PRIMARY_IFACE" '
                /^    [^ #][^:]*:/ {
                    key=$0
                    sub(/^    /, "", key)
                    sub(/:.*/, "", key)
                    gsub(/["\047]/, "", key)
                    if (key == iface) found=1
                }
                END { exit (found ? 0 : 1) }
            ' "$file"; then
                return 0
            fi
        done < <(find /etc/netplan -maxdepth 1 -type f -name '*.yaml' -print0 2>/dev/null)
        return 1
    }

    # fn: _networkd_renderer_is_safe - Guard against switching a NetworkManager system to networkd.
        # . Purpose
        #   Check the effective Netplan renderer before writing a networkd-only file.
        #   NetworkManager-owned interfaces are handled through nmcli instead.
        # . Usage
        #   ```bash
        #   _networkd_renderer_is_safe
        #   ```
    _networkd_renderer_is_safe() {
        local renderer=""

        renderer="$(netplan get "network.ethernets.${PRIMARY_IFACE}.renderer" 2>/dev/null)" || renderer=""
        if [[ -z "$renderer" || "$renderer" == "null" ]]; then
            renderer="$(netplan get network.renderer 2>/dev/null)" || renderer=""
        fi
        case "${renderer,,}" in
            ""|null|networkd) return 0 ;;
            networkmanager)
                sayfail "NetworkManager is the selected Netplan renderer, but $PRIMARY_IFACE has no active managed connection."
                return 1
                ;;
            *)
                sayfail "Unsupported Netplan renderer '$renderer' for $PRIMARY_IFACE."
                return 1
                ;;
        esac
    }

    # fn: _network_config - Apply the chosen DHCP or static network configuration to the primary interface.
        # . Purpose
        #   Configure the selected network interface using the chosen network settings.
        #
        # . Usage
        #   ```bash
        #   _network_config
        #   ```
    _network_config() {
        _detect_primary_iface || return $?

        if _interface_uses_networkmanager; then
            if (( ${FLAG_DNS_ONLY:-0} == 1 )); then
                _apply_networkmanager_config dns-only
            else
                case "${USE_DHCP^^}" in
                    Y|YES|TRUE|1|ON) _apply_networkmanager_config dhcp ;;
                    *) _apply_networkmanager_config static ;;
                esac
            fi
            return $?
        fi

        _networkd_renderer_is_safe || return $?
        case "${USE_DHCP^^}" in
            Y|YES|TRUE|1|ON)
                sayinfo "Configuring DHCP on $PRIMARY_IFACE"
                _set_dhcp
                ;;
            *)
                [[ -n "$TARGET_IPV4" ]] || { sayfail "A static IPv4 address is required when DHCP is disabled."; return 1; }
                sayinfo "Configuring static IPv4 $TARGET_IPV4 on $PRIMARY_IFACE"
                _set_static_ip
                ;;
        esac
    }

    # fn: _set_static_ip - Set static ip in the management workflow.
        # . Purpose
        #   Write network configuration for the selected static IPv4 address.
        #
        # . Usage
        #   ```bash
        #   _set_static_ip
        #   ```
    _set_static_ip() {
        _apply_netplan_config static
    }

    # fn: _set_dhcp - Set dhcp in the management workflow.
        # . Purpose
        #   Switch the selected network interface to DHCP addressing.
        #
        # . Usage
        #   ```bash
        #   _set_dhcp
        #   ```
    _set_dhcp() {
        _apply_netplan_config dhcp
    }

    # fn: _write_netplan_static - Render a static IPv4 Netplan configuration to a file.
        # . Purpose
        #   Write a Netplan networkd YAML file using the chosen interface, address,
        #   gateway, DNS addresses and optional DNS search domain.
        #
        # . Arguments
        #   - `$1`: Optional output path; defaults to NETPLAN_FILE.
        #
        # . Usage
        #   ```bash
        #   _write_netplan_static "/tmp/sgnd-static-netplan.yaml"
        #   ```
    _write_netplan_static() {
        local output_file="${1:-$NETPLAN_FILE}"

        {
            printf '%s\n' 'network:'
            printf '%s\n' '  version: 2'
            printf '%s\n' '  renderer: networkd'
            printf '%s\n' '  ethernets:'
            printf '    %s:\n' "$PRIMARY_IFACE"
            printf '%s\n' '      dhcp4: false'
            printf '%s\n' '      addresses:'
            printf '        - %s\n' "$TARGET_IPV4"
            printf '%s\n' '      routes:'
            printf '%s\n' '        - to: default'
            printf '          via: %s\n' "$TARGET_GATEWAY"
            printf '%s\n' '      nameservers:'
            printf '%s\n' '        addresses:'
            printf '          - %s\n' "$TARGET_DNS"
            if [[ -n "$TARGET_DNS_SEARCH" ]]; then
                printf '%s\n' '        search:'
                printf '          - %s\n' "$TARGET_DNS_SEARCH"
            fi
        } > "$output_file"
    }

    # fn: _write_netplan_dhcp - Write netplan dhcp in the management workflow.
        # . Purpose
        #   Write a Netplan configuration that enables DHCP for the chosen interface.
        #
        # . Arguments
        #   - `$1`: Optional: output file path.
        # . Usage
        #   ```bash
        #   _write_netplan_dhcp "/tmp/sgnd-dhcp-netplan.yaml"
        #   ```
    _write_netplan_dhcp() {
        local output_file="${1:-$NETPLAN_FILE}"

        {
            printf '%s\n' 'network:'
            printf '%s\n' '  version: 2'
            printf '%s\n' '  renderer: networkd'
            printf '%s\n' '  ethernets:'
            printf '    %s:\n' "$PRIMARY_IFACE"
            printf '%s\n' '      dhcp4: true'

            if (( ${FLAG_DNS_ONLY:-0} == 1 )); then
                printf '%s\n' '      dhcp4-overrides:'
                printf '%s\n' '        use-dns: false'
                printf '%s\n' '      nameservers:'
                printf '%s\n' '        addresses:'
                printf '          - %s\n' "$TARGET_DNS"
                if [[ -n "$TARGET_DNS_SEARCH" ]]; then
                    printf '%s\n' '        search:'
                    printf '          - %s\n' "$TARGET_DNS_SEARCH"
                fi
            fi
        } > "$output_file"
    }

    # fn: _backup_netplan_files - Preserve only the target Netplan file before updating it.
        # . Purpose
        #   Back up the selected file without taking ownership of unrelated YAML files.
        # . Arguments
        #   - `$1`: Required directory path for the backup.
        # . Usage
        #   ```bash
        #   _backup_netplan_files "/tmp/sgnd-netplan-backup"
        #   ```
    _backup_netplan_files() {
        local backup_dir="${1:-}"

        [[ -n "$backup_dir" ]] || return 1
        mkdir -p "$backup_dir" || return $?
        if [[ -f "$NETPLAN_FILE" ]]; then
            cp -a -- "$NETPLAN_FILE" "$backup_dir/previous.yaml" || return $?
        else
            : > "$backup_dir/previous-missing" || return $?
        fi
    }

    # fn: _restore_netplan_files - Roll back only the target Netplan file.
        # . Purpose
        #   Restore the original selected YAML without deleting other network profiles.
        # . Arguments
        #   - `$1`: Required directory containing the previous file state.
        # . Usage
        #   ```bash
        #   _restore_netplan_files "/tmp/sgnd-netplan-backup"
        #   ```
    _restore_netplan_files() {
        local backup_dir="${1:-}"

        [[ -d "$backup_dir" ]] || return 1
        if [[ -e "$backup_dir/previous.yaml" ]]; then
            cp -a -- "$backup_dir/previous.yaml" "$NETPLAN_FILE" || return $?
        elif [[ -e "$backup_dir/previous-missing" ]]; then
            rm -f -- "$NETPLAN_FILE" || return $?
        else
            return 1
        fi
    }

    # fn: _apply_netplan_config - Apply Netplan changes with backup and rollback handling.
        # . Purpose
        #   Render and compare static or DHCP network settings, back up only the
        #   selected YAML file, and apply with failure rollback. Unrelated YAML stays intact.
        #
        # . Arguments
        #   - `$1`: Required configuration mode, `static` or `dhcp`.
        # . Usage
        #   ```bash
        #   _apply_netplan_config "dhcp"
        #   ```
    _apply_netplan_config() {
        local mode="${1:-}"
        local candidate_file=""
        local backup_dir=""
        local changed=0

        candidate_file="$(mktemp)" || return 1
        backup_dir="$(mktemp -d)" || {
            rm -f -- "$candidate_file"
            return 1
        }

        case "$mode" in
            static)
                _write_netplan_static "$candidate_file" || {
                    rm -f -- "$candidate_file"
                    rm -rf -- "$backup_dir"
                    return 1
                }
                ;;
            dhcp)
                _write_netplan_dhcp "$candidate_file" || {
                    rm -f -- "$candidate_file"
                    rm -rf -- "$backup_dir"
                    return 1
                }
                ;;
            *)
                sayfail "Unknown netplan configuration mode: $mode"
                rm -f -- "$candidate_file"
                rm -rf -- "$backup_dir"
                return 1
                ;;
        esac

        if ! _netplan_file_is_dedicated; then
            sayfail "Netplan file '$NETPLAN_FILE' contains unrelated network settings; refusing to overwrite it."
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 1
        fi

        if _netplan_other_file_defines_iface; then
            sayfail "Multiple Netplan files define $PRIMARY_IFACE; refusing an ambiguous network update."
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 1
        fi

        if [[ ! -f "$NETPLAN_FILE" ]] || ! cmp -s -- "$candidate_file" "$NETPLAN_FILE"; then
            changed=1
        fi

        if (( changed == 0 )); then
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: No network configuration changes would be required."
            else
                sayinfo "No network configuration changes detected."
            fi
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 0
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would update netplan configuration '$NETPLAN_FILE'."
            sayinfo "DRYRUN: Would run 'netplan generate'."
            sayinfo "DRYRUN: Would run 'netplan apply'."
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 0
        fi

        mkdir -p "$(dirname "$NETPLAN_FILE")" || {
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 1
        }

        _backup_netplan_files "$backup_dir" || {
            sayfail "Failed to back up the current netplan configuration."
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 1
        }

        install -o root -g root -m 600 -- "$candidate_file" "$NETPLAN_FILE" || {
            sayfail "Failed to install netplan configuration: $NETPLAN_FILE"
            _restore_netplan_files "$backup_dir" || true
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 1
        }

        if ! netplan generate; then
            sayfail "Netplan validation failed; restoring the previous configuration."
            _restore_netplan_files "$backup_dir" || saywarning "Failed to restore the previous netplan configuration."
            netplan generate >/dev/null 2>&1 || true
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 1
        fi

        if ! netplan apply; then
            sayfail "Netplan apply failed; restoring the previous configuration."
            _restore_netplan_files "$backup_dir" || saywarning "Failed to restore the previous netplan configuration."
            netplan generate >/dev/null 2>&1 || true
            rm -f -- "$candidate_file"
            rm -rf -- "$backup_dir"
            return 1
        fi

        sayok "Network configuration updated and applied."
        rm -f -- "$candidate_file"
        rm -rf -- "$backup_dir"
        return 0
    }

    # fn: _dryrun_complete - Report completion of a dry-run preview
        # . Purpose
        #   Confirm explicitly that the preview completed without persistent changes.
        #
        # . Returns
        #   Always returns 0.
        #
        # . Usage
        #   ```bash
        #   _dryrun_complete
        #   ```
    _dryrun_complete() {
        (( ${FLAG_DRYRUN:-0} == 1 )) || return 0
        sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
        return 0
    }

# - Main ----------------------------------------------------------------------------
    # fn: main - Run the executable main sequence
        # . Purpose
        #   Run the standard executable startup sequence and then execute
        #   script-specific logic.
        #
        # . Arguments
        #   $@  Command-line arguments.
        #
        # . Behavior
        #   - Locates the SolidGroundUX framework.
        #   - Loads executable runtime support.
        #   - Starts the framework runtime through sgnd_exe_start.
        #   - Continues with script-specific logic.
        #
        # . Returns
        #   Exits with the resulting status code from startup or script logic.
        #
        # . Usage
        #   ```bash
        #   main "$@"
        #   ```
    main() {
        _framework_locator || exit $?

        _set_defaults
        sgnd_exe_start --needroot --no-clear "$@"
        _load_current_values || exit $?

        if (( ${FLAG_DNS_ONLY:-0} == 1 )); then
            [[ -n "$TARGET_DNS" ]] || {
                sayfail "A DNS server address is required in DNS-only mode."
                exit 1
            }

            sgnd_validate_ipv4 "$TARGET_DNS" || {
                sayfail "Invalid DNS server IPv4 address: $TARGET_DNS"
                exit 1
            }

            _network_config || exit $?
            _dryrun_complete
            exit 0
        fi

        _get_usr_input || exit $?
        _detect_primary_iface || exit $?

        case "${USE_DHCP^^}" in
            Y|YES|TRUE|1|ON) ;;
            *) _static_ip_conflict_check || exit $? ;;
        esac

        _set_hostname || exit $?
        _network_config || exit $?
        _dryrun_complete
    }

    # Entrypoint: sgnd_bootstrap will split framework args from script args.
    main "$@"
