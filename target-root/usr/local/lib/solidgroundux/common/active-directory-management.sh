#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX - Active Directory Management Library
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 1.1
#   Build       : 2625822
#   Source      : active-directory-management.sh
#   Type        : library
#   Group       : Common Core
#   Purpose     : Provide shared Active Directory discovery and validation primitives
#
#   Checksum : caf45218225a2f5b087c1bbee2b2a92419c83227a2922550b14a498546876f61
# Description:
#   Shared Active Directory primitives used by the server, client, and directory
#   management executables. Role-specific provisioning and mutation remain outside
#   this library.
# =====================================================================================
set -uo pipefail

# - Library guard ------------------------------------------------------------------
    # fn$ _sgnd_lib_guard - Enforce source-only, single-load library initialization
        # . Purpose
        #   Ensure the file is sourced as a library and initialized only once.
        #
        # . Behavior
        #   - Derives a unique guard variable name from the current filename.
        #   - Aborts execution when the file is run directly instead of sourced.
        #   - Sets the guard variable on first load.
        #   - Returns immediately when the library was already loaded.
        #
        # Inputs
        #   BASH_SOURCE[0]
        #   $0
        #
        # Outputs (globals)
        #   SGND_<MODULE>_LOADED
        #
        # . Returns
        #   0 when already loaded or successfully initialized.
        #   Exits with code 2 when executed instead of sourced.
        #
        # . Usage
        #   _sgnd_lib_guard
    _sgnd_lib_guard() {
        local lib_base=""
        local guard=""

        lib_base="$(basename "${BASH_SOURCE[0]}" .sh)"
        lib_base="${lib_base//-/_}"
        guard="SGND_${lib_base^^}_LOADED"

        [[ "${BASH_SOURCE[0]}" != "$0" ]] || {
            printf 'This is a library; source it, do not execute it: %s\n' "${BASH_SOURCE[0]}" >&2
            exit 2
        }

        [[ -n "${!guard-}" ]] && return 0
        printf -v "$guard" '1'
    }

    _sgnd_lib_guard
    unset -f _sgnd_lib_guard

    if declare -F sgnd_module_init_metadata >/dev/null 2>&1 \
        && declare -F sgnd_header_buffer_load >/dev/null 2>&1; then
        sgnd_module_init_metadata "${BASH_SOURCE[0]}"
    fi
# - Shared validation --------------------------------------------------------------
    sgnd_ad_validate_realm() {
        [[ "${1-}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
    }

    sgnd_ad_validate_netbios() {
        [[ "${1-}" =~ ^[A-Za-z][A-Za-z0-9_-]{0,14}$ ]]
    }

    sgnd_ad_validate_account() {
        [[ "${1-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
    }

# - Shared host/network discovery --------------------------------------------------
    sgnd_ad_primary_ipv4() {
        ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i=1;i<=NF;i++) if ($i=="src") { print $(i+1); exit } }'
    }

    sgnd_ad_default_gateway() {
        ip -4 route show default 2>/dev/null | awk 'NR==1 { print $3 }'
    }

    sgnd_ad_current_dns() {
        resolvectl dns 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '^127\.' | head -n 1
    }

# - Shared AD state ---------------------------------------------------------------

    sgnd_ad_domain_controller_ipv4() {
        local realm="${1:?missing realm}"
        local target=""
        target="$(host -t SRV "_ldap._tcp.dc._msdcs.${realm,,}" 2>/dev/null | awk '/service =/ { print $NF; exit }')"
        [[ -n "$target" ]] || target="$(host -t SRV "_ldap._tcp.${realm,,}" 2>/dev/null | awk '/service =/ { print $NF; exit }')"
        target="${target%.}"
        [[ -n "$target" ]] || return 1
        host -t A "$target" 2>/dev/null | awk '/has address/ { print $NF; exit }'
    }

    sgnd_ad_current_realm() {
        local realm=""
        if command -v realm >/dev/null 2>&1; then
            realm="$(realm list --name-only 2>/dev/null | head -n 1)"
        fi
        if [[ -z "$realm" ]] && command -v testparm >/dev/null 2>&1; then
            realm="$(sudo testparm -s --parameter-name='realm' 2>/dev/null || true)"
        fi
        [[ -n "$realm" ]] || return 1
        printf '%s\n' "$realm"
    }

    sgnd_ad_is_domain_controller() {
        command -v testparm >/dev/null 2>&1 || return 1
        [[ -s /var/lib/samba/private/sam.ldb ]] || return 1
        sudo testparm -s --parameter-name='server role' 2>/dev/null | grep -qi '^active directory domain controller$'
    }

    sgnd_ad_is_domain_member() {
        command -v realm >/dev/null 2>&1 || return 1
        realm list --name-only 2>/dev/null | grep -q .
    }

    sgnd_ad_require_dc() {
        local realm=""
        command -v samba-tool >/dev/null 2>&1 || { sayfail "samba-tool is not installed."; return 1; }
        command -v testparm >/dev/null 2>&1 || { sayfail "testparm is not installed."; return 1; }
        sgnd_ad_is_domain_controller || { sayfail "No provisioned Samba Active Directory domain controller was found."; return 1; }
        realm="$(sudo testparm -s --parameter-name='realm' 2>/dev/null || true)"
        [[ -n "$realm" ]] || { sayfail "No provisioned Samba Active Directory realm was found."; return 1; }
    }

# - Shared discovery ---------------------------------------------------------------
    sgnd_ad_discover_kerberos() {
        local realm="${1:?missing realm}"
        local dns_server="${2:-}"
        if [[ -n "$dns_server" ]]; then
            host -t SRV "_kerberos._tcp.${realm,,}" "$dns_server" >/dev/null 2>&1
        else
            host -t SRV "_kerberos._tcp.${realm,,}" >/dev/null 2>&1
        fi
    }

    sgnd_ad_discover_ldap() {
        local realm="${1:?missing realm}"
        local dns_server="${2:-}"
        if [[ -n "$dns_server" ]]; then
            host -t SRV "_ldap._tcp.${realm,,}" "$dns_server" >/dev/null 2>&1
        else
            host -t SRV "_ldap._tcp.${realm,,}" >/dev/null 2>&1
        fi
    }

    sgnd_ad_dns_a_record_matches() {
        local fqdn="${1:?missing fqdn}"
        local ip="${2:?missing ip}"
        local dns_server="${3:-}"
        if [[ -n "$dns_server" ]]; then
            host -t A "$fqdn" "$dns_server" 2>/dev/null | awk '/has address/ {print $NF}' | grep -Fxq "$ip"
        else
            host -t A "$fqdn" 2>/dev/null | awk '/has address/ {print $NF}' | grep -Fxq "$ip"
        fi
    }
