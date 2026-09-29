#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX - Active Directory Management Library
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626711
#   Source      : active-directory-management.sh
#   Type        : library
#   Group       : Common Core
#   Purpose     : Provide shared Active Directory discovery and validation primitives
#
#   Checksum : 56e9ceddb6a01551f2c3d6c0a701a0b37b998680858b77a291428a56e4289e36
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
# - Shared DNS configuration -------------------------------------------------------
    # fn: sgnd_console_set_dns_server - Update DNS through the canonical identity tool
        # . Purpose
        #   Update only the configured DNS server through the canonical identity tool.
        #
        # . Arguments
        #   $1  DNS server IPv4 address.
        #
        # . Returns
        #   Exit status from the canonical identity workflow.
    sgnd_console_set_dns_server() {
        local dns_server="${1:-}"
        local identity_script=""

        [[ -n "$dns_server" ]] || {
            sayfail "A DNS server IPv4 address is required."
            return 1
        }

        if [[ "${SGND_FRAMEWORK_ROOT:-/}" == "/" ]]; then
            identity_script="/usr/local/libexec/solidgroundux/manage-identity.sh"
        else
            identity_script="${SGND_FRAMEWORK_ROOT%/}/usr/local/libexec/solidgroundux/manage-identity.sh"
        fi

        [[ -x "$identity_script" ]] || {
            sayfail "Canonical identity manager is unavailable: $identity_script"
            return 1
        }

        "$identity_script" --dns-only --DNS "$dns_server" --Auto
    }

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

    # fn: sgnd_ad_current_netbios_domain - Return the joined AD domain short name
        # . Purpose
        #   Resolve the NetBIOS/short domain name for the currently joined Active Directory realm.
        #
        # . Arguments
        #   $1  Optional realm name. Defaults to the currently joined realm.
        #
        # . Output
        #   Writes the short domain name, for example TESTADURA.
        #
        # . Returns
        #   0 when the short domain name can be discovered; 1 otherwise.
        #
        # . Usage
        #   workgroup="$(sgnd_ad_current_netbios_domain)" || return 1
    sgnd_ad_current_netbios_domain() {
        local realm="${1:-}"
        local workgroup=""

        [[ -n "$realm" ]] || realm="$(sgnd_ad_current_realm 2>/dev/null || true)"
        [[ -n "$realm" ]] || return 1
        command -v adcli >/dev/null 2>&1 || return 1

        workgroup="$(
            adcli info "$realm" 2>/dev/null |
                awk -F'[[:space:]]*=[[:space:]]*' '
                    tolower($1) ~ /^[[:space:]]*domain-short[[:space:]]*$/ {
                        print $2
                        exit
                    }
                '
        )"
        [[ -n "$workgroup" ]] || return 1
        printf '%s\n' "${workgroup^^}"
    }

    # fn: sgnd_ad_normalize_sssd_config - Normalize and validate SolidGroundUX-managed SSSD configuration
        # . Purpose
        #   Remove obsolete SSSD settings created by earlier SolidGroundUX AD-client
        #   releases and verify the resulting configuration before activation.
        #
        # . Behavior
        #   - Reads /etc/sssd/sssd.conf through sudo so protected permissions are respected.
        #   - Removes config_file_version only from the [sssd] section when present.
        #   - Validates a protected temporary candidate with sssctl before replacing the live file.
        #   - Preserves the existing owner, group, and permissions when replacing the live file.
        #   - Restarts SSSD only after a validated change is installed.
        #   - Restores the previous configuration when restart or activation validation fails.
        #   - Routes diagnostics and status messages through SolidGroundUX logging primitives.
        #
        # . Side effects
        #   May update /etc/sssd/sssd.conf and restart sssd.service.
        #
        # . Returns
        #   0 when the configuration is already valid or is normalized successfully.
        #   1 when the configuration cannot be read, validated, installed, or activated.
        #
        # . Usage
        #   sgnd_ad_normalize_sssd_config
    sgnd_ad_normalize_sssd_config() {
        local sssd_config="/etc/sssd/sssd.conf"
        local current_file=""
        local candidate_file=""
        local validation_dir=""
        local validation_file=""
        local snippet_dir="/etc/sssd/conf.d"
        local validation_output=""
        local owner=""
        local group=""
        local mode=""
        local changed=0
        local line=""

        command -v sssctl >/dev/null 2>&1 || {
            sayfail "sssctl is unavailable; the SSSD configuration cannot be safely validated."
            return 1
        }
        sudo test -r "$sssd_config" || {
            sayfail "SSSD configuration is unavailable: $sssd_config"
            return 1
        }

        owner="$(sudo stat -c '%U' "$sssd_config" 2>/dev/null)" || {
            sayfail "Cannot determine the owner of $sssd_config."
            return 1
        }
        group="$(sudo stat -c '%G' "$sssd_config" 2>/dev/null)" || {
            sayfail "Cannot determine the group of $sssd_config."
            return 1
        }
        mode="$(sudo stat -c '%a' "$sssd_config" 2>/dev/null)" || {
            sayfail "Cannot determine the permissions of $sssd_config."
            return 1
        }

        current_file="$(mktemp)" || {
            sayfail "Cannot create a temporary SSSD configuration copy."
            return 1
        }
        candidate_file="$(mktemp)" || {
            rm -f "$current_file"
            sayfail "Cannot create a temporary SSSD configuration candidate."
            return 1
        }

        if ! sudo cat "$sssd_config" > "$current_file"; then
            rm -f "$current_file" "$candidate_file"
            sayfail "Cannot read $sssd_config."
            return 1
        fi

        awk '
            BEGIN { in_sssd=0 }
            /^[[:space:]]*\[/ {
                in_sssd = ($0 ~ /^[[:space:]]*\[sssd\][[:space:]]*$/)
            }
            in_sssd && /^[[:space:]]*config_file_version[[:space:]]*=/ {
                changed=1
                next
            }
            { print }
            END { if (changed) exit 10 }
        ' "$current_file" > "$candidate_file"
        case $? in
            0) changed=0 ;;
            10) changed=1 ;;
            *)
                rm -f "$current_file" "$candidate_file"
                sayfail "Failed to prepare the normalized SSSD configuration candidate."
                return 1
                ;;
        esac

        validation_dir="$(sudo mktemp -d /tmp/sgnd-sssd-validate.XXXXXX)" || {
            rm -f "$current_file" "$candidate_file"
            sayfail "Cannot create the protected SSSD validation workspace."
            return 1
        }
        validation_file="$validation_dir/sssd.conf"
        if ! sudo install -o root -g root -m 0600 "$candidate_file" "$validation_file"; then
            sudo rm -rf "$validation_dir"
            rm -f "$current_file" "$candidate_file"
            sayfail "Cannot prepare the SSSD validation candidate."
            return 1
        fi

        if ! sudo test -d "$snippet_dir"; then
            snippet_dir="$validation_dir/conf.d"
            if ! sudo install -d -o root -g root -m 0755 "$snippet_dir"; then
                sudo rm -rf "$validation_dir"
                rm -f "$current_file" "$candidate_file"
                sayfail "Cannot prepare the SSSD validation snippet directory."
                return 1
            fi
        fi

        if ! validation_output="$(sudo sssctl config-check -c "$validation_file" -s "$snippet_dir" 2>&1)"; then
            while IFS= read -r line; do
                [[ -n "$line" ]] && sayfail "$line"
            done <<< "$validation_output"
            sayfail "SSSD configuration validation failed; the existing configuration was not changed."
            sudo rm -rf "$validation_dir"
            rm -f "$current_file" "$candidate_file"
            return 1
        fi
        sudo rm -rf "$validation_dir"

        if (( changed == 0 )); then
            rm -f "$current_file" "$candidate_file"
            return 0
        fi

        if ! sudo install -o "$owner" -g "$group" -m "$mode" "$candidate_file" "$sssd_config"; then
            rm -f "$current_file" "$candidate_file"
            sayfail "Cannot update $sssd_config."
            return 1
        fi

        if ! sudo systemctl restart sssd.service || ! systemctl is-active --quiet sssd.service; then
            sayfail "SSSD could not be activated after normalizing its configuration."
            if sudo install -o "$owner" -g "$group" -m "$mode" "$current_file" "$sssd_config"; then
                saywarning "The previous SSSD configuration was restored."
                if ! sudo systemctl restart sssd.service; then
                    sayfail "SSSD could not be restarted after restoring the previous configuration."
                fi
            else
                sayfail "The previous SSSD configuration could not be restored."
            fi
            rm -f "$current_file" "$candidate_file"
            return 1
        fi

        rm -f "$current_file" "$candidate_file"
        sayok "SSSD configuration normalized and validated."
        return 0
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
