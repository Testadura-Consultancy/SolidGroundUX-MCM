#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Samba File Server
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627501
#   Shortname   : MANAGE_SAMBA_SERVER
#   Source      : manage-samba-file-server.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Prepare, validate, and inspect the Samba file-server service
#
#   Checksum : 4a8880accee6a7db6ad40f2ec0c23b5620953c6d27f0b411c0e40670c70445c1
# Description:
#   Implements persistent Samba file-server management actions exposed by the
#   30-samba-file-server Management Console module. Share lifecycle/share-level access
#   remain in manage-samba-shares.sh; directory lifecycle/access remain in
#   manage-samba-directories.sh.
#
# Attribution:
#   Developers    : Mark Fieten
#   Company       : Testadura Consultancy
#   Client        : -
#   Copyright     : © 2025 - 2026 Testadura Consultancy
#   License       : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail

# - Bootstrap ----------------------------------------------------------------------
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
        #   _framework_locator || return $?
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
# - Project libraries ---------------------------------------------------------------
    # fn$ _load_ad_management - Load shared Active Directory discovery APIs
        # . Returns
        #   0 when the project Active Directory management library is loaded.
        #
        # . Usage
        #   _load_ad_management || return $?
    _load_ad_management() {
        local app_root=""
        local lib_file=""
        local script_file=""
        local path_without_root=""
        local component=""
        local index=0
        local root_index=-1
        local -a path_parts=()

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || return 126
        path_without_root="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"

        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in
                usr|etc|var) root_index=$index ;;
            esac
        done

        (( root_index >= 0 )) || {
            sayfail "Cannot determine Samba application root."
            return 126
        }

        if (( root_index == 0 )); then
            app_root="/"
        else
            app_root=""
            for (( index=0; index<root_index; index++ )); do
                app_root+="/${path_parts[$index]}"
            done
        fi

        if [[ "$app_root" == "/" ]]; then
            lib_file="/usr/local/lib/solidgroundux/common/active-directory-management.sh"
        else
            lib_file="${app_root%/}/usr/local/lib/solidgroundux/common/active-directory-management.sh"
        fi

        [[ -r "$lib_file" ]] || {
            sayfail "Cannot read Active Directory management library: $lib_file"
            return 126
        }

        # shellcheck source=/dev/null
        source "$lib_file"
    }

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||prepare,install,authentication,storage,share-root,service,validate,status"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action prepare"
        "  $SGND_SCRIPT_NAME --dryrun --action prepare"
        "  $SGND_SCRIPT_NAME --action validate"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Local declarations --------------------------------------------------------------
    SGND_STORAGE_DEFAULT_MOUNTPOINT="/srv/storage"
    SGND_STORAGE_CONFIG_FILE="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"
    SGND_SAMBA_STORAGE_ROOT="$SGND_STORAGE_DEFAULT_MOUNTPOINT"
    SGND_SAMBA_SHARE_ROOT="$SGND_SAMBA_STORAGE_ROOT/shares"
    SGND_SAMBA_CONFIG="/etc/samba/smb.conf"
    SGND_SSSD_CONFIG="/etc/sssd/sssd.conf"

# - Helpers -------------------------------------------------------------------------
    _dryrun_complete() {
        sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
    }

    _smb_refresh_storage_paths() {
        local mountpoint=""
        local device=""
        local uuid=""

        if [[ -r "$SGND_STORAGE_CONFIG_FILE" ]]; then
            mountpoint="$(awk -F= '
                $1 == "SGND_STORAGE_MOUNTPOINTS" {
                    value=substr($0, index($0, "=") + 1)
                    split(value, parts, ":")
                    print parts[1]
                    exit
                }
                $1 == "SGND_STORAGE_MOUNTPOINT" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$SGND_STORAGE_CONFIG_FILE" 2>/dev/null || true)"
        fi

        if [[ "$mountpoint" != /* || "$mountpoint" == "/" || "$mountpoint" == *[[:space:]]* ]]; then
            mountpoint=""
        fi

        if [[ -z "$mountpoint" ]]; then
            device="$(blkid -L SGND_STORAGE 2>/dev/null || true)"
            if [[ -n "$device" ]]; then
                uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
                if [[ -n "$uuid" ]]; then
                    mountpoint="$(awk -v source="UUID=$uuid" '
                        $0 !~ /^[[:space:]]*#/ && NF >= 2 && $1 == source { print $2; exit }
                    ' /etc/fstab 2>/dev/null || true)"
                fi
            fi
        fi

        if [[ "$mountpoint" != /* || "$mountpoint" == "/" || "$mountpoint" == *[[:space:]]* ]]; then
            mountpoint="$SGND_STORAGE_DEFAULT_MOUNTPOINT"
        fi

        SGND_SAMBA_STORAGE_ROOT="$mountpoint"
        SGND_SAMBA_SHARE_ROOT="$mountpoint/shares"
    }

    _smb_require_storage() {
        _smb_refresh_storage_paths
        mountpoint -q "$SGND_SAMBA_STORAGE_ROOT" || {
            sayfail "SolidGroundUX storage is not mounted at $SGND_SAMBA_STORAGE_ROOT."
            return 1
        }
        return 0
    }

    _smb_list_managed_shares_raw() {
        _smb_refresh_storage_paths
        local share_name=""
        local share_path=""

        command -v testparm >/dev/null 2>&1 || return 0

        while IFS= read -r share_name; do
            [[ -n "$share_name" ]] || continue
            case "${share_name,,}" in
                global|printers|print\$) continue ;;
            esac

            share_path="$(sudo testparm -s --section-name "$share_name" --parameter-name path 2>/dev/null || true)"
            [[ "$share_path" == "$SGND_SAMBA_SHARE_ROOT/"* ]] || continue
            printf '%s\n' "$share_name"
        done < <(
            sudo testparm -s 2>/dev/null | \
                awk '/^\[[^]]+\]$/ { name=$0; gsub(/^\[|\]$/, "", name); print name }'
        )
    }

    # fn: _smb_ask_selection - Render a Samba selection menu and return the selected value(s)
        # . Purpose
        #   Keep selection mechanics local while the manager owns the surrounding UI layout.
        #   The menu uses the standard section header and leaves a blank line between the
        #   final option and the Selection prompt.
        #
        # . Arguments
        #   --label TEXT
        #   --var NAME
        #   --multi
        #   --items ITEM...
        #
        # . Returns
        #   0 on selection; 1 when Q is entered; 2 on invalid invocation.
    _smb_ask_selection() {
        local label="Select an option"
        local var_name="selection"
        local multi=0
        local input=""
        local token=""
        local start=0
        local end=0
        local index=0
        local i=0
        local invalid=0
        local -a items=()
        local -a tokens=()
        local -a selected_values=()
        local -A selected_indexes=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --label) label="$2"; shift 2 ;;
                --var)   var_name="$2"; shift 2 ;;
                --multi) multi=1; shift ;;
                --items)
                    shift
                    items=("$@")
                    break
                    ;;
                --)
                    shift
                    break
                    ;;
                *)
                    items+=("$1")
                    shift
                    ;;
            esac
        done

        [[ "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
        (( ${#items[@]} > 0 )) || return 2

        sgnd_print
        sgnd_print_sectionheader --text "$label"
        for (( i=0; i<${#items[@]}; i++ )); do
            sgnd_print --text "$((i + 1)). ${items[i]}" --pad 2
        done
        sgnd_print --text "Q. Back" --pad 2
        sgnd_print
        sgnd_print_sectionheader ""

        while :; do
            input=""
            if (( multi )); then
                ask --label "Selection (comma/range)" --var input
            else
                ask --label "Selection" --var input
            fi

            input="${input#"${input%%[![:space:]]*}"}"
            input="${input%"${input##*[![:space:]]}"}"

            [[ "${input^^}" == "Q" ]] && return 1

            if (( ! multi )); then
                if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input <= ${#items[@]} )); then
                    printf -v "$var_name" '%s' "${items[input - 1]}"
                    return 0
                fi
                saywarning "Invalid selection: $input"
                continue
            fi

            selected_values=()
            selected_indexes=()
            invalid=0
            IFS=',' read -r -a tokens <<< "$input"

            for token in "${tokens[@]}"; do
                token="${token#"${token%%[![:space:]]*}"}"
                token="${token%"${token##*[![:space:]]}"}"

                if [[ "$token" =~ ^([1-9][0-9]*)-([1-9][0-9]*)$ ]]; then
                    start="${BASH_REMATCH[1]}"
                    end="${BASH_REMATCH[2]}"
                    if (( start > end || end > ${#items[@]} )); then
                        invalid=1
                        break
                    fi
                    for (( index=start; index<=end; index++ )); do
                        selected_indexes["$index"]=1
                    done
                elif [[ "$token" =~ ^[1-9][0-9]*$ ]] && (( token <= ${#items[@]} )); then
                    selected_indexes["$token"]=1
                else
                    invalid=1
                    break
                fi
            done

            if (( invalid || ${#selected_indexes[@]} == 0 )); then
                saywarning "Invalid selection: $input"
                continue
            fi

            for (( index=1; index<=${#items[@]}; index++ )); do
                [[ -n "${selected_indexes[$index]-}" ]] || continue
                selected_values+=("${items[index - 1]}")
            done

            local -n output_ref="$var_name"
            output_ref=("${selected_values[@]}")
            return 0
        done
    }


    # fn: _smb_auth_mode - Return the configured Samba authentication mode
        # . Purpose
        #   Report Samba's active authentication mode independently of the Linux host's
        #   realm membership so a domain-joined host can legitimately run Samba standalone.
        #
        # . Output
        #   Writes "ad" when Samba security is ADS, otherwise "standalone".
        #
        # . Returns
        #   0 always.
        #
        # . Usage
        #   mode="$(_smb_auth_mode)"
    _smb_auth_mode() {
        local security=""

        security="$(sudo testparm -s --parameter-name security 2>/dev/null || true)"
        if [[ "${security^^}" == "ADS" ]]; then
            printf 'ad\n'
        else
            printf 'standalone\n'
        fi
    }

    # fn: _smb_validate_hostname_dns - Verify the server FQDN resolves to its primary IPv4 address
        # . Purpose
        #   Confirm the DNS state required for clients to reach the Samba server by hostname.
        #
        # . Behavior
        #   - Uses the shared Active Directory network/DNS APIs.
        #   - Verifies the local FQDN resolves to the host's primary IPv4 address.
        #   - Does not create or modify DNS records; AD-client provisioning owns DNS registration.
        #
        # . Returns
        #   0 when the FQDN resolves to the primary IPv4 address; non-zero otherwise.
        #
        # . Usage
        #   _smb_validate_hostname_dns || return $?
    _smb_validate_hostname_dns() {
        local fqdn=""
        local ip=""
        local dns_server=""

        fqdn="$(hostname -f 2>/dev/null || true)"
        ip="$(sgnd_ad_primary_ipv4 2>/dev/null || true)"
        dns_server="$(sgnd_ad_current_dns 2>/dev/null || true)"

        [[ -n "$fqdn" && -n "$ip" ]] || {
            sayfail "Cannot determine the Samba server FQDN and primary IPv4 address for DNS validation."
            return 1
        }

        if sgnd_ad_dns_a_record_matches "$fqdn" "$ip" "$dns_server"; then
            sayok "DNS resolves $fqdn to $ip."
            return 0
        fi

        sayfail "DNS does not resolve $fqdn to the server address $ip."
        return 1
    }

    # fn: _smb_write_auth_config - Normalize Samba global authentication settings
        # . Purpose
        #   Keep share definitions intact while replacing only SolidGroundUX-owned global
        #   authentication and identity-mapping settings.
        #
        # . Arguments
        #   $1  Authentication mode: ad or standalone.
        #   $2  AD realm when mode is ad.
        #   $3  AD short/NetBIOS domain when mode is ad.
        #
        # . Returns
        #   0 when smb.conf is updated; non-zero on rewrite/install failure.
        #
        # . Usage
        #   _smb_write_auth_config ad TESTADURA.HQ TESTADURA
    _smb_write_auth_config() {
        local mode="${1:?missing authentication mode}"
        local realm="${2:-}"
        local workgroup="${3:-WORKGROUP}"
        local tmp_file=""

        [[ -f "$SGND_SAMBA_CONFIG" ]] || {
            sayfail "Samba configuration is unavailable: $SGND_SAMBA_CONFIG"
            return 1
        }

        tmp_file="$(mktemp)" || return 1

        awk -v mode="$mode" -v realm="$realm" -v workgroup="$workgroup" '
            function managed(line, key) {
                key=line
                sub(/^[[:space:]]*/, "", key)
                sub(/[[:space:]]*=.*/, "", key)
                key=tolower(key)
                return key == "workgroup" \
                    || key == "security" \
                    || key == "realm" \
                    || key == "kerberos method" \
                    || key == "map to guest" \
                    || key == "winbind use default domain" \
                    || key == "winbind refresh tickets" \
                    || key ~ /^idmap config[[:space:]].*/
            }
            function emit_settings() {
                if (emitted) return
                print ""
                print "\t# SolidGroundUX authentication"
                if (mode == "ad") {
                    print "\tworkgroup = " workgroup
                    print "\tsecurity = ADS"
                    print "\trealm = " realm
                    print "\tkerberos method = secrets and keytab"
                    print "\tmap to guest = Never"
                    print "\twinbind use default domain = No"
                    print "\twinbind refresh tickets = Yes"
                    print "\tidmap config * : backend = tdb"
                    print "\tidmap config * : range = 100000-199999"
                    print "\tidmap config " workgroup " : backend = sss"
                    print "\tidmap config " workgroup " : range = 200000-2147483647"
                } else {
                    print "\tworkgroup = WORKGROUP"
                    print "\tsecurity = USER"
                    print "\tmap to guest = Bad User"
                }
                emitted=1
            }
            BEGIN { in_global=0; saw_global=0; emitted=0 }
            /^\[[^]]+\][[:space:]]*$/ {
                section=tolower($0)
                if (in_global) emit_settings()
                in_global=(section == "[global]")
                if (in_global) saw_global=1
                print
                next
            }
            {
                if (in_global && managed($0)) next
                if (in_global && $0 ~ /^[[:space:]]*#[[:space:]]*SolidGroundUX authentication[[:space:]]*$/) next
                print
            }
            END {
                if (in_global) emit_settings()
                if (!saw_global) {
                    print ""
                    print "[global]"
                    emit_settings()
                }
            }
        ' "$SGND_SAMBA_CONFIG" > "$tmp_file" || {
            rm -f "$tmp_file"
            return 1
        }

        sudo install -o root -g root -m 0644 "$tmp_file" "$SGND_SAMBA_CONFIG" || {
            rm -f "$tmp_file"
            return 1
        }
        rm -f "$tmp_file"
    }

    # fn: _smb_enable_sssd_samba_password_sync - Keep Samba machine credentials synchronized by SSSD
        # . Purpose
        #   Enable SSSD's Samba machine-account password synchronization for the joined domain.
        #
        # . Behavior
        #   - Delegates generic SSSD normalization to the shared Active Directory API.
        #   - Reads the protected SSSD configuration through sudo.
        #   - Adds ad_update_samba_machine_account_password=true to the joined domain section when needed.
        #   - Validates a root-owned temporary candidate with sssctl before replacing the live configuration.
        #   - Preserves the live configuration file's existing owner, group, and mode.
        #   - Reports validation diagnostics through sayfail rather than writing ad-hoc error output.
        #   - Restarts SSSD after validation so the setting is active immediately.
        #   - Restores the original configuration when a changed file cannot be activated successfully.
        #
        # . Arguments
        #   $1  Joined AD realm.
        #
        # . Returns
        #   0 when the setting is present, validated, and active; non-zero otherwise.
        #
        # . Usage
        #   _smb_enable_sssd_samba_password_sync TESTADURA.HQ
    _smb_enable_sssd_samba_password_sync() {
        local realm="${1:?missing realm}"
        local domain_section="domain/${realm,,}"
        local source_file=""
        local candidate_file=""
        local validation_dir=""
        local validation_file=""
        local snippet_dir=""
        local validation_output=""
        local file_uid=""
        local file_gid=""
        local file_mode=""
        local needs_install=0
        local awk_rc=0
        local line=""

        sudo test -r "$SGND_SSSD_CONFIG" || {
            sayfail "SSSD configuration is unavailable: $SGND_SSSD_CONFIG"
            return 1
        }

        command -v sssctl >/dev/null 2>&1 || {
            sayfail "sssctl is unavailable; the SSSD configuration cannot be safely validated."
            return 1
        }

        # Normalize SSSD through the shared Active Directory API before adding
        # Samba-specific password synchronization. This keeps ownership of
        # generic AD-client configuration repair outside the Samba manager.
        sgnd_ad_normalize_sssd_config || return $?

        file_uid="$(sudo stat -c '%u' "$SGND_SSSD_CONFIG")" || {
            sayfail "Cannot determine the owner of $SGND_SSSD_CONFIG."
            return 1
        }
        file_gid="$(sudo stat -c '%g' "$SGND_SSSD_CONFIG")" || {
            sayfail "Cannot determine the group of $SGND_SSSD_CONFIG."
            return 1
        }
        file_mode="$(sudo stat -c '%a' "$SGND_SSSD_CONFIG")" || {
            sayfail "Cannot determine the permissions of $SGND_SSSD_CONFIG."
            return 1
        }

        source_file="$(mktemp)" || {
            sayfail "Cannot create a temporary SSSD configuration copy."
            return 1
        }
        sudo cat "$SGND_SSSD_CONFIG" > "$source_file" || {
            rm -f "$source_file"
            sayfail "Cannot read $SGND_SSSD_CONFIG."
            return 1
        }

        candidate_file="$(mktemp)" || {
            rm -f "$source_file"
            sayfail "Cannot create a temporary SSSD configuration candidate."
            return 1
        }

        awk -v section="[$domain_section]" '
            BEGIN { in_domain=0; saw_domain=0; found=0 }
            function emit_setting() {
                if (!found) {
                    print "ad_update_samba_machine_account_password = true"
                    found=1
                }
            }
            /^\[[^]]+\][[:space:]]*$/ {
                if (in_domain) emit_setting()
                in_domain=(tolower($0)==tolower(section))
                if (in_domain) saw_domain=1
                print
                next
            }
            {
                if (in_domain && /^[[:space:]]*ad_update_samba_machine_account_password[[:space:]]*=/) {
                    if ($0 ~ /^[[:space:]]*ad_update_samba_machine_account_password[[:space:]]*=[[:space:]]*true[[:space:]]*$/) {
                        found=1
                        print
                    }
                    next
                }
                print
            }
            END {
                if (in_domain) emit_setting()
                if (!saw_domain) exit 3
            }
        ' "$source_file" > "$candidate_file"
        awk_rc=$?

        case $awk_rc in
            0) ;;
            3)
                rm -f "$source_file" "$candidate_file"
                sayfail "SSSD domain section [$domain_section] was not found."
                return 1
                ;;
            *)
                rm -f "$source_file" "$candidate_file"
                sayfail "Failed to prepare the SSSD Samba password-synchronization setting."
                return 1
                ;;
        esac

        if ! cmp -s "$source_file" "$candidate_file"; then
            needs_install=1
        fi

        validation_dir="$(sudo mktemp -d /tmp/sgnd-sssd-validate.XXXXXX)" || {
            rm -f "$source_file" "$candidate_file"
            sayfail "Cannot create the protected SSSD validation workspace."
            return 1
        }
        validation_file="$validation_dir/sssd.conf"

        if ! sudo install -o root -g root -m 0600 "$candidate_file" "$validation_file"; then
            sudo rm -rf "$validation_dir"
            rm -f "$source_file" "$candidate_file"
            sayfail "Cannot prepare the SSSD validation candidate."
            return 1
        fi

        if sudo test -d /etc/sssd/conf.d; then
            snippet_dir="/etc/sssd/conf.d"
        else
            snippet_dir="$validation_dir/conf.d"
            if ! sudo mkdir -m 0700 "$snippet_dir"; then
                sudo rm -rf "$validation_dir"
                rm -f "$source_file" "$candidate_file"
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
            rm -f "$source_file" "$candidate_file"
            return 1
        fi

        sudo rm -rf "$validation_dir"

        if (( needs_install == 1 )); then
            if ! sudo install -o "$file_uid" -g "$file_gid" -m "$file_mode" "$candidate_file" "$SGND_SSSD_CONFIG"; then
                rm -f "$source_file" "$candidate_file"
                sayfail "Cannot update $SGND_SSSD_CONFIG."
                return 1
            fi
        fi
        rm -f "$candidate_file"

        if ! sudo systemctl restart sssd.service; then
            sayfail "SSSD could not be restarted after enabling Samba machine-account password synchronization."
            if (( needs_install == 1 )); then
                if sudo install -o "$file_uid" -g "$file_gid" -m "$file_mode" "$source_file" "$SGND_SSSD_CONFIG"; then
                    saywarning "The previous SSSD configuration was restored."
                    if ! sudo systemctl restart sssd.service; then
                        sayfail "SSSD could not be restarted after restoring the previous configuration."
                    fi
                else
                    sayfail "The previous SSSD configuration could not be restored."
                fi
            fi
            rm -f "$source_file"
            return 1
        fi

        if ! systemctl is-active --quiet sssd.service; then
            sayfail "SSSD is not active after applying Samba machine-account password synchronization."
            if (( needs_install == 1 )); then
                if sudo install -o "$file_uid" -g "$file_gid" -m "$file_mode" "$source_file" "$SGND_SSSD_CONFIG"; then
                    saywarning "The previous SSSD configuration was restored."
                    if ! sudo systemctl restart sssd.service; then
                        sayfail "SSSD could not be restarted after restoring the previous configuration."
                    fi
                else
                    sayfail "The previous SSSD configuration could not be restored."
                fi
            fi
            rm -f "$source_file"
            return 1
        fi

        rm -f "$source_file"
        return 0
    }

    # fn: _smb_establish_ads_trust - Establish Samba machine trust for an existing AD member host
        # . Purpose
        #   Populate or repair Samba's own machine-account trust after the AD-client module has
        #   already joined the Linux host to Active Directory.
        #
        # . Behavior
        #   - Requires the host realm membership to remain valid; this function does not own the
        #     Linux realm join or leave lifecycle.
        #   - Prompts for an authorized AD account and uses Samba's net ads join to establish the
        #     Samba machine secret in secrets.tdb.
        #   - Runs net ads join directly against the controlling terminal so Samba can collect
        #     the account password using the same interactive path as a successful shell join.
        #   - Treats net ads testjoin as the authoritative success check; ancillary DNS-update
        #     warnings from net ads join do not invalidate an established Samba trust.
        #   - Leaves hostname DNS registration to the AD-client module.
        #
        # . Arguments
        #   $1  Joined Active Directory realm.
        #
        # . Returns
        #   0 when Samba validates its ADS machine trust; non-zero otherwise.
        #
        # . Usage
        #   _smb_establish_ads_trust TESTADURA.HQ
    _smb_establish_ads_trust() {
        local realm="${1:?missing realm}"
        local join_account="Administrator"

        command -v net >/dev/null 2>&1 || {
            sayfail "Samba net utility is unavailable; Samba ADS trust cannot be established."
            return 1
        }

        # The AD-client module owns host membership. Refuse to turn a Samba trust repair into
        # an implicit host-domain join when the host membership itself is not valid.
        sgnd_ad_is_domain_member || {
            sayfail "The host is not an Active Directory member; Samba ADS trust cannot be established."
            return 1
        }

        ask \
            --label "AD join account" \
            --var join_account \
            --default "$join_account" \
            --validate sgnd_ad_validate_account || return $?

        sayinfo "Establishing Samba Active Directory trust for $realm as $join_account."

        # Keep this command attached to the real terminal. net ads join performs its own
        # interactive password exchange; capturing stdout/stderr in command substitution also
        # captures that prompt and breaks the authentication path.
        sudo net ads join -U "$join_account" </dev/tty >/dev/tty 2>&1 || {
            # Samba can return ancillary diagnostics during a successful join. Check the
            # resulting machine trust before deciding that the operation failed.
            sudo net ads testjoin >/dev/null 2>&1 || {
                sayfail "Samba Active Directory trust could not be established for $realm."
                return 1
            }
        }

        sudo net ads testjoin >/dev/null 2>&1 || {
            sayfail "Samba Active Directory trust could not be established for $realm."
            return 1
        }

        sayok "Samba Active Directory trust established for $realm."
        return 0
    }

    # fn: _smb_configure_authentication - Configure Samba from the host identity state
        # . Purpose
        #   Configure Samba for the authentication model already established on the host.
        #   Active Directory membership is owned by the AD-client module; Samba adapts to it.
        #
        # . Behavior
        #   - Detects existing realm/SSSD membership without asking the administrator to choose a mode.
        #   - Configures standalone USER security when the host is not joined to Active Directory.
        #   - Configures ADS security, Winbind, and SSSD-backed ID mapping when the host is an AD member.
        #   - Never joins or leaves the Linux host realm; AD-client provisioning owns that lifecycle.
        #   - Normalizes SSSD and enables synchronization of future Samba machine-account password changes.
        #   - Starts Winbind and validates both the Samba ADS join and Winbind workstation secret.
        #   - When Samba trust is missing or stale, establishes Samba's own ADS machine trust with
        #     net ads join while leaving Linux realm membership under AD-client ownership.
        #   - Prompts for an authorized AD account only when Samba trust must be established.
        #   - Restarts SSSD, Winbind, and smbd after Samba trust establishment.
        #   - Validates the Samba trust, Winbind trust secret, own domain, NETLOGON, and hostname DNS.
        #   - Leaves host DNS registration under AD-client ownership and validates the resulting
        #     hostname A record separately after Samba trust is established.
        #
        # . Returns
        #   0 when Samba matches the detected host identity state and validates successfully.
        #   Non-zero when configuration, trust establishment, or validation fails.
        #
        # . Usage
        #   _smb_configure_authentication
    _smb_configure_authentication() {
        local mode="standalone"
        local realm=""
        local workgroup=""
        local own_domain=""
        local current_mode=""

        sgnd_print
        sgnd_print_sectionheader --text "Configure Samba Authentication"
        current_mode="$(_smb_auth_mode)"
        sgnd_print_labeledvalue --label "Current mode" --value "$([[ "$current_mode" == "ad" ]] && printf 'Active Directory' || printf 'Standalone')" --labelwidth 22

        if sgnd_ad_is_domain_member; then
            mode="ad"
            sgnd_print_labeledvalue --label "Host identity" --value "Active Directory member" --labelwidth 22
            sgnd_print_labeledvalue --label "Target mode" --value "Active Directory" --labelwidth 22
            sayinfo "Active Directory membership detected; configuring Samba as an AD member server."
        else
            sgnd_print_labeledvalue --label "Host identity" --value "Standalone" --labelwidth 22
            sgnd_print_labeledvalue --label "Target mode" --value "Standalone" --labelwidth 22
            sayinfo "No Active Directory membership detected; configuring Samba as a standalone WORKGROUP server."
        fi

        if [[ "$mode" == "standalone" ]]; then
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would configure Samba as a standalone WORKGROUP server."
                _dryrun_complete
                return 0
            fi

            _smb_write_auth_config standalone || return 1
            sudo testparm -s >/dev/null 2>&1 || {
                sayfail "Standalone Samba configuration validation failed."
                return 1
            }
            sudo systemctl disable --now winbind.service >/dev/null 2>&1 || true
            sudo systemctl restart smbd.service >/dev/null 2>&1 || {
                sayfail "Samba could not be restarted after configuring standalone authentication."
                return 1
            }
            sgnd_print_labeledvalue --label "Result" --value "Standalone WORKGROUP" --labelwidth 22
            sayok "Samba authentication configured for standalone WORKGROUP mode."
            return 0
        fi

        realm="$(sgnd_ad_current_realm 2>/dev/null || true)"
        [[ -n "$realm" ]] || {
            sayfail "Active Directory membership was detected but the joined realm could not be resolved."
            return 1
        }
        realm="${realm^^}"

        workgroup="$(sgnd_ad_current_netbios_domain "$realm" 2>/dev/null || true)"
        [[ -n "$workgroup" ]] || {
            sayfail "Active Directory short/NetBIOS domain could not be discovered for $realm."
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Host is joined to $realm; would configure Samba as an AD member server for $workgroup."
            sayinfo "DRYRUN: Would install Winbind, configure SSSD-backed ID mapping, establish Samba ADS trust when required, restart Winbind, and validate trust and NETLOGON."
            _dryrun_complete
            return 0
        fi

        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y winbind sssd-common || return 1
        _smb_write_auth_config ad "$realm" "$workgroup" || return 1
        sudo testparm -s >/dev/null 2>&1 || {
            sayfail "Active Directory Samba configuration validation failed."
            return 1
        }

        _smb_enable_sssd_samba_password_sync "$realm" || return 1

        if ! sudo systemctl enable winbind.service >/dev/null 2>&1; then
            sayfail "Winbind could not be enabled."
            return 1
        fi

        # The AD-client module owns the host realm membership. Samba still needs its own ADS
        # machine trust in secrets.tdb. A fresh AD-member Samba setup or a standalone-to-AD
        # transition can therefore leave Winbind unable to start until Samba establishes that
        # trust. Try Winbind first; when the Samba trust is absent or stale, establish it with
        # net ads join and then restart the identity services.
        if ! sudo systemctl restart winbind.service >/dev/null 2>&1; then
            saywarning "Winbind could not start because Samba Active Directory trust is missing or stale; establishing it."
            _smb_establish_ads_trust "$realm" || return $?

            sudo systemctl restart sssd.service >/dev/null 2>&1 || {
                sayfail "SSSD could not be restarted after establishing Samba Active Directory trust."
                return 1
            }
            sudo systemctl restart winbind.service >/dev/null 2>&1 || {
                sayfail "Winbind could not be restarted after establishing Samba Active Directory trust."
                return 1
            }
        fi

        if ! sudo net ads testjoin >/dev/null 2>&1 || ! sudo wbinfo -t >/dev/null 2>&1; then
            saywarning "Samba Active Directory trust is missing or stale; establishing it."
            _smb_establish_ads_trust "$realm" || return $?

            sudo systemctl restart sssd.service >/dev/null 2>&1 || {
                sayfail "SSSD could not be restarted after establishing Samba Active Directory trust."
                return 1
            }
            sudo systemctl restart winbind.service >/dev/null 2>&1 || {
                sayfail "Winbind could not be restarted after establishing Samba Active Directory trust."
                return 1
            }
        fi

        sudo systemctl restart smbd.service >/dev/null 2>&1 || {
            sayfail "Samba could not be restarted after configuring Active Directory authentication."
            return 1
        }

        sudo net ads testjoin >/dev/null 2>&1 || {
            sayfail "Samba Active Directory trust validation failed."
            return 1
        }

        own_domain="$(sudo wbinfo --own-domain 2>/dev/null || true)"
        [[ "${own_domain^^}" == "${workgroup^^}" ]] || {
            sayfail "Winbind reports domain '${own_domain:-unknown}' instead of '$workgroup'."
            return 1
        }

        sudo wbinfo -t >/dev/null 2>&1 || {
            sayfail "Winbind machine-account trust validation failed after establishing Samba Active Directory trust."
            return 1
        }
        sudo wbinfo --ping-dc >/dev/null 2>&1 || {
            sayfail "Winbind could not establish a NETLOGON connection to an Active Directory domain controller."
            return 1
        }

        _smb_validate_hostname_dns || return $?

        sgnd_print_labeledvalue --label "Result" --value "Active Directory ($realm / $workgroup)" --labelwidth 22
        sayok "Samba authentication configured for Active Directory realm $realm ($workgroup)."
    }

# - Actions -------------------------------------------------------------------------
    _smb_install_packages() {
        local -a packages=(acl attr samba samba-common-bin smbclient)

        if sgnd_ad_is_domain_member; then
            packages+=(winbind sssd-common)
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would refresh APT package metadata."
            sayinfo "DRYRUN: Would install packages: ${packages[*]}."
            _dryrun_complete
            return 0
        fi

        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" || return 1

        command -v smbd >/dev/null 2>&1 || return 1
        command -v testparm >/dev/null 2>&1 || return 1
        if sgnd_ad_is_domain_member; then
            command -v wbinfo >/dev/null 2>&1 || return 1
        fi
        sayok "Samba file-server prerequisites installed."
    }

    _smb_validate_storage() {
        _smb_require_storage || return 1
        sayok "Storage is mounted and available for Samba file services."
    }

    _smb_prepare_share_root() {
        _smb_refresh_storage_paths
        _smb_require_storage || return 1

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would create or normalize Samba share root '$SGND_SAMBA_SHARE_ROOT'."
            sayinfo "DRYRUN: Would apply directory mode 0711 so authorized share users can traverse to managed shares without listing the container directory."
            _dryrun_complete
            return 0
        fi

        sudo install -d -m 0711 "$SGND_SAMBA_SHARE_ROOT" || return 1
        [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] || return 1
        [[ "$(stat -c '%a' "$SGND_SAMBA_SHARE_ROOT" 2>/dev/null || true)" == "711" ]] || {
            sayfail "Samba share root permissions are not 0711: $SGND_SAMBA_SHARE_ROOT"
            return 1
        }
        sayok "Samba share root prepared at $SGND_SAMBA_SHARE_ROOT."
    }

    _smb_start_service() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            if command -v testparm >/dev/null 2>&1; then
                sayinfo "DRYRUN: Would validate '$SGND_SAMBA_CONFIG' with testparm before starting Samba."
            else
                sayinfo "DRYRUN: Would validate '$SGND_SAMBA_CONFIG' with testparm after Samba prerequisites were installed."
            fi
            sayinfo "DRYRUN: Would enable and start smbd.service."
            sayinfo "DRYRUN: Would verify that smbd.service became active."
            _dryrun_complete
            return 0
        fi

        command -v testparm >/dev/null 2>&1 || {
            sayfail "Samba is not installed."
            return 1
        }

        sudo testparm -s >/dev/null 2>&1 || {
            sayfail "Samba configuration validation failed."
            return 1
        }

        sudo systemctl enable --now smbd.service || return 1
        systemctl is-active --quiet smbd.service || {
            sayfail "smbd.service is not active."
            return 1
        }

        sayok "Samba file-server service is active."
    }

    _smb_prepare_file_server() {
        sgnd_print
        sgnd_print_sectionheader --text "Prepare Samba File Server"

        _smb_install_packages || return $?
        _smb_configure_authentication || return $?
        _smb_validate_storage || return $?
        _smb_prepare_share_root || return $?
        _smb_start_service || return $?

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayok "DRYRUN preparation preview completed. No Samba file-server changes were written."
        else
            sayok "Samba file-server preparation sequence completed."
        fi
    }

    # fn: _smb_validate - Validate Samba file-server configuration and runtime state
        # . Behavior
        #   - Validates Samba tools, smb.conf, smbd, storage, share-root traversal, and configured shares.
        #   - On AD members, validates ADS realm/workgroup settings, the Samba machine trust,
        #     Winbind own-domain identity, the Winbind trust secret, and NETLOGON DC connectivity.
        #   - Validates that SSSD Samba machine-account password synchronization remains enabled.
        #
        # . Returns
        #   0 when all checks pass; non-zero when one or more checks fail.
    _smb_validate() {
        _smb_refresh_storage_paths
        local failures=0
        local result=""
        local share_name=""
        local share_path=""
        local share_count=0
        local auth_mode=""
        local realm=""
        local workgroup=""
        local configured_realm=""
        local configured_security=""
        local configured_workgroup=""

        sgnd_print
        sgnd_print_sectionheader --text "Validate Samba File Server"

        if command -v smbd >/dev/null 2>&1 && command -v testparm >/dev/null 2>&1; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Samba tools" --value "$result" --labelwidth 24

        if command -v testparm >/dev/null 2>&1 && sudo testparm -s >/dev/null 2>&1; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Configuration" --value "$result" --labelwidth 24

        if systemctl is-active --quiet smbd.service; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "smbd service" --value "$result" --labelwidth 24

        auth_mode="$(_smb_auth_mode)"
        configured_security="$(sudo testparm -s --parameter-name security 2>/dev/null || true)"
        configured_workgroup="$(sudo testparm -s --parameter-name workgroup 2>/dev/null || true)"

        if [[ "$auth_mode" == "ad" ]]; then
            realm="$(sgnd_ad_current_realm 2>/dev/null || true)"
            realm="${realm^^}"
            workgroup="$(sgnd_ad_current_netbios_domain "$realm" 2>/dev/null || true)"
            configured_realm="$(sudo testparm -s --parameter-name realm 2>/dev/null || true)"
            configured_realm="${configured_realm^^}"

            if [[ "${configured_security^^}" == "ADS" && "$configured_realm" == "$realm" && "${configured_workgroup^^}" == "${workgroup^^}" ]]; then
                result="Passed ($realm)"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "Authentication" --value "$result" --labelwidth 24

            if systemctl is-active --quiet winbind.service \
                && sudo net ads testjoin >/dev/null 2>&1 \
                && [[ "$(sudo wbinfo --own-domain 2>/dev/null || true)" == "$workgroup" ]] \
                && sudo wbinfo -t >/dev/null 2>&1 \
                && sudo wbinfo --ping-dc >/dev/null 2>&1; then
                result="Passed"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "AD machine trust" --value "$result" --labelwidth 24

            if sudo grep -Eiq '^[[:space:]]*ad_update_samba_machine_account_password[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$SGND_SSSD_CONFIG" 2>/dev/null; then
                result="Passed"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "SSSD Samba sync" --value "$result" --labelwidth 24

            if _smb_validate_hostname_dns >/dev/null 2>&1; then
                result="Passed"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "Hostname DNS" --value "$result" --labelwidth 24
        else
            if [[ "${configured_security^^}" == "USER" && "${configured_workgroup^^}" == "WORKGROUP" ]]; then
                result="Passed (standalone)"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "Authentication" --value "$result" --labelwidth 24
        fi

        if mountpoint -q "$SGND_SAMBA_STORAGE_ROOT"; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Storage mounted" --value "$result" --labelwidth 24

        if [[ -d "$SGND_SAMBA_SHARE_ROOT" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Share root" --value "$result" --labelwidth 24

        if [[ -d "$SGND_SAMBA_SHARE_ROOT" && "$(stat -c '%a' "$SGND_SAMBA_SHARE_ROOT" 2>/dev/null || true)" == "711" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Share root traversal" --value "$result" --labelwidth 24

        if command -v testparm >/dev/null 2>&1; then
            while IFS= read -r share_name; do
                [[ -n "$share_name" ]] || continue
                share_count=$((share_count + 1))
                share_path="$(sudo testparm -s --section-name "$share_name" --parameter-name path 2>/dev/null || true)"

                if [[ "$share_path" == "$SGND_SAMBA_SHARE_ROOT/"* && -d "$share_path" ]]; then
                    result="Passed"
                else
                    result="Failed"
                    failures=$((failures + 1))
                fi
                sgnd_print_labeledvalue --label "Share: $share_name" --value "$result" --labelwidth 24
            done < <(_smb_list_managed_shares_raw)
        fi

        sgnd_print_labeledvalue --label "Configured shares" --value "$share_count" --labelwidth 24
        sgnd_print

        if (( failures == 0 )); then
            sayok "Samba file-server validation passed."
            return 0
        fi

        sayfail "$failures Samba file-server validation check(s) failed."
        return 1
    }

    _smb_status() {
        _smb_refresh_storage_paths
        local service_state="not installed"
        local config_state="unavailable"
        local storage_state="not configured"
        local share_root_state="not available"
        local auth_mode="standalone"
        local realm=""
        local samba_role="unavailable"
        local workgroup=""
        local dns_state="not applicable"

        if command -v smbd >/dev/null 2>&1; then
            service_state="$(systemctl is-active smbd.service 2>/dev/null || true)"
            [[ -n "$service_state" ]] || service_state="inactive"

            if testparm -s >/dev/null 2>&1; then
                config_state="valid"
            else
                config_state="invalid"
            fi
        fi

        if mountpoint -q "$SGND_SAMBA_STORAGE_ROOT"; then
            storage_state="mounted"
            [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] && share_root_state="available"
        fi

        sgnd_print
        sgnd_print_sectionheader --text "Samba File Server"
        sgnd_print_labeledvalue --label "Service" --value "$service_state" --labelwidth 20
        auth_mode="$(_smb_auth_mode)"
        samba_role="$(sudo testparm -s --parameter-name 'server role' 2>/dev/null || true)"
        workgroup="$(sudo testparm -s --parameter-name workgroup 2>/dev/null || true)"
        if [[ "$auth_mode" == "ad" ]]; then
            realm="$(sgnd_ad_current_realm 2>/dev/null || true)"
            auth_mode="Active Directory"
            if _smb_validate_hostname_dns >/dev/null 2>&1; then
                dns_state="valid"
            else
                dns_state="invalid"
            fi
        else
            auth_mode="Standalone"
        fi

        sgnd_print_labeledvalue --label "Configuration" --value "$config_state" --labelwidth 20
        sgnd_print_labeledvalue --label "Authentication" --value "$auth_mode" --labelwidth 20
        [[ -n "$realm" ]] && sgnd_print_labeledvalue --label "Realm" --value "${realm^^}" --labelwidth 20
        [[ -n "$workgroup" ]] && sgnd_print_labeledvalue --label "Workgroup/domain" --value "$workgroup" --labelwidth 20
        [[ -n "$samba_role" ]] && sgnd_print_labeledvalue --label "Samba role" --value "$samba_role" --labelwidth 20
        [[ "$auth_mode" == "Active Directory" ]] && sgnd_print_labeledvalue --label "Hostname DNS" --value "$dns_state" --labelwidth 20
        sgnd_print_labeledvalue --label "Storage" --value "$storage_state" --labelwidth 20
        sgnd_print_labeledvalue --label "Share root" --value "$share_root_state" --labelwidth 20
        sgnd_print
    }

    _run_action() {
        local action="${1:?missing action}"

        case "$action" in
            prepare)    _smb_prepare_file_server ;;
            install)         _smb_install_packages ;;
            authentication)  _smb_configure_authentication ;;
            storage)         _smb_validate_storage ;;
            share-root) _smb_prepare_share_root ;;
            service)    _smb_start_service ;;
            validate)   _smb_validate ;;
            status)     _smb_status ;;
            *)
                sayfail "Unknown Samba file-server management action: $action"
                return 2
                ;;
        esac
    }

# - Main ---------------------------------------------------------------------------
    main() {
        local action=""
        local selection=""

        _framework_locator || return $?
        _load_ad_management || return $?
        sgnd_exe_start "$@" || return $?

        action="${ACTION:-}"

        if [[ -z "$action" ]]; then
            _smb_ask_selection \
                --label "Samba File Server Management" \
                --var selection \
                --items \
                    "Prepare Samba file server" \
                    "Install Samba prerequisites" \
                    "Configure Samba authentication" \
                    "Validate storage" \
                    "Prepare share root" \
                    "Start Samba service" \
                    "Validate Samba file server" \
                    "Show Samba file-server status" || return 0

            case "$selection" in
                "Prepare Samba file server") action="prepare" ;;
                "Install Samba prerequisites") action="install" ;;
                "Configure Samba authentication") action="authentication" ;;
                "Validate storage") action="storage" ;;
                "Prepare share root") action="share-root" ;;
                "Start Samba service") action="service" ;;
                "Validate Samba file server") action="validate" ;;
                "Show Samba file-server status") action="status" ;;
                *) return 0 ;;
            esac
        fi

        local action_rc=0
        _run_action "$action" || action_rc=$?

        sgnd_print
        sgnd_print_sectionheader ""
        return "$action_rc"
    }

    main "$@"
