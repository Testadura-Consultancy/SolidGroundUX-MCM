#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Samba File Server
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626501
#   Source      : manage-samba-file-server.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Prepare, validate, and inspect the Samba file-server service
#
#   Checksum : 873554ed26c846db5561e6942f2317839cf900ea5d572e3f2ad25467cdafa5c7
# Description:
#   Implements persistent Samba file-server management actions exposed by the
#   30-samba-file-server Management Console module. Share lifecycle and ACL management
#   remain in manage-samba-shares.sh.
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
        #   - Loads sgnd-exe-common.sh from the resolved framework root.
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
        fi

        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read executable common library: %s\n' "$exe_common" >&2
            return 126
        }

        # shellcheck source=/dev/null
        source "$exe_common"
    }
# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Manage Samba File Server"
    : "${SGND_SCRIPT_DESC:=Prepare, validate, and inspect Samba file-server services.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2624123}"
    : "${SGND_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${SGND_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${SGND_SCRIPT_COPYRIGHT:=© 2025 - 2026 Testadura Consultancy}"
    : "${SGND_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.1.}"

# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||prepare,install,storage,share-root,service,validate,status"
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


# - Actions -------------------------------------------------------------------------
    _smb_install_packages() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would refresh APT package metadata."
            sayinfo "DRYRUN: Would install packages: acl attr samba samba-common-bin smbclient."
            _dryrun_complete
            return 0
        fi

        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            acl attr samba samba-common-bin smbclient || return 1

        command -v smbd >/dev/null 2>&1 || return 1
        command -v testparm >/dev/null 2>&1 || return 1
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
            sayinfo "DRYRUN: Would apply directory mode 0770."
            _dryrun_complete
            return 0
        fi

        sudo install -d -m 0770 "$SGND_SAMBA_SHARE_ROOT" || return 1
        [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] || return 1
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
        _smb_validate_storage || return $?
        _smb_prepare_share_root || return $?
        _smb_start_service || return $?

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayok "DRYRUN preparation preview completed. No Samba file-server changes were written."
        else
            sayok "Samba file-server preparation sequence completed."
        fi
    }

    _smb_validate() {
        _smb_refresh_storage_paths
        local failures=0
        local result=""
        local share_name=""
        local share_path=""
        local share_count=0

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
        sgnd_print_labeledvalue --label "Configuration" --value "$config_state" --labelwidth 20
        sgnd_print_labeledvalue --label "Storage" --value "$storage_state" --labelwidth 20
        sgnd_print_labeledvalue --label "Share root" --value "$share_root_state" --labelwidth 20
        sgnd_print
    }

    _run_action() {
        local action="${1:?missing action}"

        case "$action" in
            prepare)    _smb_prepare_file_server ;;
            install)    _smb_install_packages ;;
            storage)    _smb_validate_storage ;;
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
        sgnd_exe_start "$@" || return $?

        action="${ACTION:-}"

        if [[ -z "$action" ]]; then
            _smb_ask_selection \
                --label "Samba File Server Management" \
                --var selection \
                --items \
                    "Prepare Samba file server" \
                    "Install Samba prerequisites" \
                    "Validate storage" \
                    "Prepare share root" \
                    "Start Samba service" \
                    "Validate Samba file server" \
                    "Show Samba file-server status" || return 0

            case "$selection" in
                "Prepare Samba file server") action="prepare" ;;
                "Install Samba prerequisites") action="install" ;;
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
