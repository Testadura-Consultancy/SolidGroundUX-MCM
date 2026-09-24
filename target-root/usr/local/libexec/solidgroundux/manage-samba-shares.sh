#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Samba Shares
# ------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626711
#   Checksum    : e0ca15a407d641178da1eba0eebc09db4f552cb3b280d623150bfa27b77d07ea
#   Source      : manage-samba-shares.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Manage Samba shares
#
# Description:
#   Provides interactive management of SolidGroundUX Samba shares, including share
#   lifecycle, directory structure, validation, and AD/NSS access control synchronized
#   through POSIX ACLs and Samba valid-users/write-list settings.
#
# Design principles:
#   - Executables are explicit: resolve, bootstrap, then run
#   - Libraries never auto-execute (composition over inheritance)
#   - Framework integration is opt-in and declarative
#   - UI and input must be TTY-safe
#
# Role in framework:
#   - Entry point pattern for all SolidGroundUX-based scripts
#   - Defines how scripts integrate with sgnd-bootstrap and common libraries
#
# Non-goals:
#   - Business logic implementation (provided by the script author)
#   - Library behavior (handled in /common modules)
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
# - Script identity ------------------------------------------------------------------
    # var: SGND_SCRIPT_FILE - Absolute path to the currently executing script
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"

    # var: SGND_SCRIPT_DIR - Directory containing the currently executing script
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"

    # var: SGND_SCRIPT_BASE - Filename of the currently executing script
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"

    # var: SGND_SCRIPT_NAME - Script basename without the .sh extension
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    # var$ SGND_SCRIPT_FILE
        # Absolute path to the currently executing script.
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"

    # var$ SGND_SCRIPT_DIR
        # Directory containing the currently executing script.
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"

    # var$ SGND_SCRIPT_BASE
        # Filename of the currently executing script, including extension.
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"

    # var$ SGND_SCRIPT_NAME
        # Script basename without the .sh extension; used for help and display text.
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_TITLE="Manage Samba Shares"
    : "${SGND_SCRIPT_DESC:=Create, remove, structure, validate, and manage access to Samba shares.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2626021}"
    : "${SGND_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${SGND_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${SGND_SCRIPT_COPYRIGHT:=© 2025 - 2026 Testadura Consultancy}"
    : "${SGND_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.1.}"

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
        sgnd-datatable.sh
        sgnd-menu.sh
    )

    # var: SGND_ARGS_SPEC - Script-specific command-line argument specification
        # Optional: script-specific arguments
        # --- Example: Arguments
        # Each entry:
        #   "name|short|type|var|help|choices"
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

# - Local declarations --------------------------------------------------------------
    SGND_SAMBA_CONFIG="/etc/samba/smb.conf"
    SGND_STORAGE_DEFAULT_MOUNTPOINT="/srv/storage"
    SGND_STORAGE_CONFIG_FILE="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"
    SGND_SAMBA_SHARE_ROOT="/srv/storage/shares"
    MANAGED_SHARES=()
    SELECTED_SHARES=()
    DISCOVERED_GROUPS=()

# - Helpers -------------------------------------------------------------------------
    _dryrun_complete() {
        sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
    }

    # fn: _refresh_storage_paths - Resolve the configured SolidGroundUX share root
        # . Returns
        #   0 after SGND_SAMBA_SHARE_ROOT is refreshed.
        #
        # . Usage
        #   _refresh_storage_paths
    _refresh_storage_paths() {
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

        SGND_SAMBA_SHARE_ROOT="$mountpoint/shares"
    }

    _refresh_storage_paths


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

    # fn: _share_path - Resolve the configured path for a Samba share
        # . Returns
        #   Writes the configured path to stdout.
        #
        # . Usage
        #   path="$(_share_path "Documents")"
    _share_path() {
        sudo testparm -s --section-name "$1" --parameter-name path 2>/dev/null || true
    }

    # fn: _list_managed_shares - Discover shares beneath the SolidGroundUX share root
        # . Outputs (globals)
        #   MANAGED_SHARES
        #
        # . Returns
        #   0 when at least one managed share exists; 1 otherwise.
        #
        # . Usage
        #   _list_managed_shares || return $?
    _list_managed_shares() {
        local share=""
        local path=""

        MANAGED_SHARES=()
        command -v testparm >/dev/null 2>&1 || {
            sayfail "Samba testparm is not available."
            return 1
        }

        while IFS= read -r share; do
            [[ -n "$share" ]] || continue
            case "${share,,}" in
                global|printers|print\$) continue ;;
            esac

            path="$(_share_path "$share")"
            [[ "$path" == "$SGND_SAMBA_SHARE_ROOT/"* ]] || continue
            MANAGED_SHARES+=("$share")
        done < <(
            sudo testparm -s 2>/dev/null | \
                awk '/^\[[^]]+\]$/ { name=$0; gsub(/^\[|\]$/, "", name); print name }'
        )

        if (( ${#MANAGED_SHARES[@]} == 0 )); then
            saywarning "No managed Samba shares found beneath $SGND_SAMBA_SHARE_ROOT."
            return 1
        fi

        return 0
    }

    # fn: _select_shares - Select one or more managed shares
        # . Outputs (globals)
        #   SELECTED_SHARES
        #
        # . Returns
        #   0 after selection; 1 when the user returns.
        #
        # . Usage
        #   _select_shares || return $?
    _select_shares() {
        _list_managed_shares || return $?
        SELECTED_SHARES=()
        _smb_ask_selection \
            --label "Select Samba share(s)" \
            --var SELECTED_SHARES \
            --multi \
            --items "${MANAGED_SHARES[@]}"
    }

    # fn: _acl_groups_for_share - Return named group ACL entries for one share
        # . Arguments
        #   $1 SHARE
        #
        # . Output
        #   Writes GROUP|PERMISSIONS records.
        #
        # . Usage
        #   _acl_groups_for_share "Documents"
    _acl_groups_for_share() {
        local path=""
        local gid=""
        local perms=""
        local group=""

        path="$(_share_path "$1")"
        sudo test -d "$path" || return 1

        # Read numeric ACL qualifiers first. getfacl's normal output escapes spaces
        # in names (for example Domain\040Users), which is display-safe but is not
        # a usable NSS group name for later setfacl removal/synchronization.
        while IFS='|' read -r gid perms; do
            [[ -n "$gid" ]] || continue
            group="$(getent group "$gid" 2>/dev/null | cut -d: -f1)"
            [[ -n "$group" ]] || {
                saywarning "ACL group id '$gid' cannot be resolved through NSS."
                continue
            }
            printf '%s|%s\n' "$group" "$perms"
        done < <(
            sudo getfacl -cpn -- "$path" 2>/dev/null | \
                awk -F: '$1 == "group" && $2 != "" { print $2 "|" $3 }'
        )
    }

    # fn: _validate_share_name - Validate a managed Samba share name
        # . Usage
        #   _validate_share_name "<arg1>"
    _validate_share_name() {
        [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
    }

    # fn: _validate_relative_path - Validate a relative path beneath a share root
        # . Usage
        #   _validate_relative_path "<relative_path>"
    _validate_relative_path() {
        local relative_path="${1:-}"
        local part=""
        local -a parts=()

        [[ -n "$relative_path" ]] || return 1
        [[ "$relative_path" != /* ]] || return 1
        [[ "$relative_path" != *$'\n'* ]] || return 1

        IFS='/' read -r -a parts <<< "$relative_path"
        for part in "${parts[@]}"; do
            [[ -n "$part" && "$part" != "." && "$part" != ".." ]] || return 1
        done
        return 0
    }

    # fn: _share_exists - Test whether a Samba share exists
        # . Usage
        #   _share_exists "<share_name>"
    _share_exists() {
        local share_name="${1:-}"
        [[ -r "$SGND_SAMBA_CONFIG" ]] || return 1
        grep -Eqi "^[[:space:]]*\\[$share_name\\][[:space:]]*$" "$SGND_SAMBA_CONFIG"
    }

    # fn: _reload_samba - Validate and reload Samba configuration
        # . Usage
        #   _reload_samba
    _reload_samba() {
        sudo testparm -s >/dev/null 2>&1 || {
            sayfail "The Samba configuration is invalid."
            return 1
        }
        sudo systemctl reload smbd.service 2>/dev/null || sudo systemctl restart smbd.service
    }

    # fn: _create_share - Create a managed share and backing directory
        # . Usage
        #   _create_share
    _create_share() {
        local share_name=""
        local comment=""
        local browsable="Yes"
        local read_only="No"
        local share_path=""
        local backup=""
        local dlg_rc=0

        while :; do
            share_name=""
            ask --label "Share name (Q=Back)" --var share_name --validate _validate_share_name --back || return 0

            _share_exists "$share_name" && {
                sayfail "A Samba share named '$share_name' already exists."
                continue
            }

            share_path="$SGND_SAMBA_SHARE_ROOT/$share_name"
            [[ ! -e "$share_path" ]] || {
                sayfail "The backing directory already exists: $share_path"
                continue
            }

            comment="$share_name share"
            ask --label "Description (Q=Back)" --var comment --default "$comment" --back || return 0

            ask_decision --label "Browsable" --choices "Yes|Y,No|N,Quit|Q" --default "Yes" --var browsable || return $?
            [[ "${browsable^^}" == "QUIT" || "${browsable^^}" == "Q" ]] && return 0

            ask_decision --label "Read only" --choices "Yes|Y,No|N,Quit|Q" --default "No" --var read_only || return $?
            [[ "${read_only^^}" == "QUIT" || "${read_only^^}" == "Q" ]] && return 0

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would create backing directory '$share_path' with mode 0770."
                sayinfo "DRYRUN: Would add Samba share '$share_name' to '$SGND_SAMBA_CONFIG'."
                sayinfo "DRYRUN: Share settings would be browseable=${browsable,,}, read only=${read_only,,}, guest ok=no."
                sayinfo "DRYRUN: Would validate the updated Samba configuration and reload smbd.service."
                _dryrun_complete
            else
                backup="$SGND_SAMBA_CONFIG.pre-share.$(date +%Y%m%d%H%M%S)"
                sudo cp -a "$SGND_SAMBA_CONFIG" "$backup" || return 1
                sudo install -d -m 0770 "$share_path" || return 1

                printf '%s\n' \
                    '' \
                    "# SolidGroundUX managed share: $share_name" \
                    "[$share_name]" \
                    "    path = $share_path" \
                    "    comment = $comment" \
                    "    browseable = ${browsable,,}" \
                    "    read only = ${read_only,,}" \
                    '    guest ok = no' \
                    '    create mask = 0660' \
                    '    directory mask = 0770' | \
                    sudo tee -a "$SGND_SAMBA_CONFIG" >/dev/null || return 1

                if ! _reload_samba; then
                    sudo cp -a "$backup" "$SGND_SAMBA_CONFIG"
                    sudo rm -rf -- "$share_path"
                    return 1
                fi

                sayok "Samba share '$share_name' created."
                sgnd_print_labeledvalue --label "Directory" --value "$share_path" --labelwidth 18
            fi

            dlg_rc=0
            ask_dlg_autocontinue --seconds 5 --legend "Enter=return to manager; timeout=create another share" || dlg_rc=$?
            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _remove_share - Remove a managed share and optionally its directory
        # . Usage
        #   _remove_share
    _remove_share() {
        local share_name=""
        local share_path=""
        local remove_data="No"
        local temp_file=""
        local backup=""
        local dlg_rc=0

        while :; do
            _list_managed_shares || return 0
            _smb_ask_selection --label "Select Samba share to remove" --var share_name --items "${MANAGED_SHARES[@]}" || return 0
            share_path="$(_share_path "$share_name")"

            ask_decision --label "Delete share data" --choices "Yes|Y,No|N,Quit|Q" --default "No" --var remove_data || return $?
            [[ "${remove_data^^}" == "QUIT" || "${remove_data^^}" == "Q" ]] && return 0

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would remove Samba share '$share_name' from '$SGND_SAMBA_CONFIG'."
                if [[ "${remove_data^^}" == "YES" ]]; then
                    sayinfo "DRYRUN: Would recursively remove backing directory '$share_path'."
                else
                    sayinfo "DRYRUN: Would leave backing directory '$share_path' and its data intact."
                fi
                sayinfo "DRYRUN: Would validate the updated Samba configuration and reload smbd.service."
                _dryrun_complete
            else
                temp_file="$(mktemp)" || return 1
                backup="$SGND_SAMBA_CONFIG.pre-remove.$(date +%Y%m%d%H%M%S)"
                sudo cp -a "$SGND_SAMBA_CONFIG" "$backup" || { rm -f "$temp_file"; return 1; }

                sudo awk -v section="$share_name" '
                    BEGIN { skip = 0 }
                    /^\[[^]]+\][[:space:]]*$/ {
                        current = $0
                        gsub(/^\[|\][[:space:]]*$/, "", current)
                        skip = (tolower(current) == tolower(section))
                    }
                    !skip { print }
                ' "$SGND_SAMBA_CONFIG" > "$temp_file" || { rm -f "$temp_file"; return 1; }

                sudo install -o root -g root -m 0644 "$temp_file" "$SGND_SAMBA_CONFIG" || { rm -f "$temp_file"; return 1; }
                rm -f "$temp_file"

                if ! _reload_samba; then
                    sudo cp -a "$backup" "$SGND_SAMBA_CONFIG"
                    return 1
                fi

                if [[ "${remove_data^^}" == "YES" ]]; then
                    sudo rm -rf -- "$share_path" || return 1
                fi

                sayok "Samba share '$share_name' removed."
            fi

            SELECTED_SHARES=()
            dlg_rc=0
            ask_dlg_autocontinue --seconds 5 --legend "Enter=return to manager; timeout=remove another share" || dlg_rc=$?
            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _ensure_selected_shares - Ensure one or more managed shares are selected
        # . Purpose
        #   Reuse the current share selection and only prompt when nothing is selected.
        #
        # . Returns
        #   0 when at least one share is selected; 1 when selection is cancelled.
        #
        # . Usage
        #   _ensure_selected_shares || return 0
    _ensure_selected_shares() {
        (( ${#SELECTED_SHARES[@]} > 0 )) && return 0
        _select_shares || return 1
        (( ${#SELECTED_SHARES[@]} > 0 ))
    }

    # fn: _inherit_directory_access - Copy a parent directory's ownership and ACL model
        # . Purpose
        #   Make a newly created subdirectory follow the selected share's existing
        #   Unix ownership, mode, and POSIX ACL/default-ACL model instead of inventing
        #   per-user ownership from the directory name.
        #
        # . Arguments
        #   $1 PARENT
        #   $2 CHILD
        #
        # . Returns
        #   0 when ownership/mode/ACL inheritance succeeds; non-zero otherwise.
        # . Usage
        #   _inherit_directory_access "<parent>" "<child>"
    _inherit_directory_access() {
        local parent="${1:?missing parent directory}"
        local child="${2:?missing child directory}"

        sudo chown --reference="$parent" -- "$child" || return 1
        sudo chmod --reference="$parent" -- "$child" || return 1
        sudo getfacl -cp -- "$parent" 2>/dev/null | sudo setfacl --set-file=- -- "$child" || return 1
        return 0
    }

    # fn: _create_inherited_directory_tree - Create a relative directory tree with inherited access
        # . Arguments
        #   $1 SHARE_PATH
        #   $2 RELATIVE_PATH
        #
        # . Returns
        #   0 when the complete tree exists and newly created components inherited
        #   their parent's ownership/mode/ACL model; non-zero on failure.
        # . Usage
        #   _create_inherited_directory_tree "<share_path>" "<relative_path>"
    _create_inherited_directory_tree() {
        local share_path="${1:?missing share path}"
        local relative_path="${2:?missing relative path}"
        local current="$share_path"
        local child=""
        local part=""
        local -a parts=()

        IFS='/' read -r -a parts <<< "$relative_path"
        for part in "${parts[@]}"; do
            child="$current/$part"
            if ! sudo test -d "$child"; then
                sudo mkdir -- "$child" || return 1
                _inherit_directory_access "$current" "$child" || return 1
            fi
            current="$child"
        done

        sudo test -d "$current"
    }

    # fn: _list_share_subdirectories_raw - Return relative subdirectory paths for one share
        # . Arguments
        #   $1 SHARE
        #
        # . Output
        #   Writes one relative directory path per line.
        # . Usage
        #   _list_share_subdirectories_raw "<share>"
    _list_share_subdirectories_raw() {
        local share="${1:?missing share}"
        local share_path=""

        share_path="$(_share_path "$share")"
        sudo test -d "$share_path" || return 1
        sudo find "$share_path" -mindepth 1 -type d -printf '%P\n' 2>/dev/null | LC_ALL=C sort
    }

    # fn: _create_subdirectory - Create subdirectories beneath the currently selected shares
        # . Purpose
        #   Create one relative path in every selected share. If no share is currently
        #   selected, prompt for a share selection first. Newly created directory
        #   components inherit the parent share's ownership, mode, and ACL model.
        #
        # . Returns
        #   0 after returning to the manager; non-zero on creation failure.
        # . Usage
        #   _create_subdirectory
    _create_subdirectory() {
        local share=""
        local share_path=""
        local relative_path=""
        local full_path=""
        local dlg_rc=0
        local created_count=0

        _ensure_selected_shares || return 0

        while :; do
            relative_path=""
            ask \
                --label "Relative directory path (e.g. Files/Mark) (Q=Back)" \
                --var relative_path \
                --validate _validate_relative_path \
                --back || return 0

            created_count=0
            for share in "${SELECTED_SHARES[@]}"; do
                share_path="$(_share_path "$share")"
                sudo test -d "$share_path" || {
                    sayfail "Share backing directory does not exist: $share_path"
                    return 1
                }

                full_path="$share_path/$relative_path"
                sgnd_print_labeledvalue --label "Share" --value "$share" --labelwidth 18
                sgnd_print_labeledvalue --label "Directory" --value "$full_path" --labelwidth 18

                if sudo test -d "$full_path"; then
                    saywarning "Directory already exists: $full_path"
                    continue
                fi

                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "DRYRUN: Would create '$full_path' and inherit the parent ownership, mode, and ACL model."
                    created_count=$((created_count + 1))
                    continue
                fi

                _create_inherited_directory_tree "$share_path" "$relative_path" || {
                    sayfail "Could not create subdirectory tree: $full_path"
                    return 1
                }

                sudo test -d "$full_path" || {
                    sayfail "Directory creation could not be verified: $full_path"
                    return 1
                }

                sayok "Created '$relative_path' in '$share'."
                created_count=$((created_count + 1))
            done

            if (( ${FLAG_DRYRUN:-0} == 1 && created_count > 0 )); then
                _dryrun_complete
            fi

            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=create another subdirectory" \
                || dlg_rc=$?
            case "$dlg_rc" in
                1|3) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _list_subdirectories - List subdirectories beneath the currently selected shares
        # . Returns
        #   0 after displaying the directory trees.
        # . Usage
        #   _list_subdirectories
    _list_subdirectories() {
        local share=""
        local relative_path=""
        local count=0

        _ensure_selected_shares || return 0

        for share in "${SELECTED_SHARES[@]}"; do
            sgnd_print
            sgnd_print_sectionheader --text "$share subdirectories"
            count=0
            while IFS= read -r relative_path; do
                [[ -n "$relative_path" ]] || continue
                sgnd_print --text "$relative_path" --pad 2
                count=$((count + 1))
            done < <(_list_share_subdirectories_raw "$share" || true)

            (( count > 0 )) || sgnd_print --text "No subdirectories found." --pad 2
        done

        ask_dlg_autocontinue \
            --seconds 15 \
            --message "Press Enter to return to share management." \
            --pause || true
        return 0
    }

    # fn: _remove_subdirectory - Remove a selected subdirectory from a selected share
        # . Purpose
        #   Select a concrete relative directory beneath the current share selection and
        #   remove it. The share root itself is never presented or accepted as a target.
        #
        # . Returns
        #   0 after returning to the manager; non-zero on removal failure.
        # . Usage
        #   _remove_subdirectory
    _remove_subdirectory() {
        local share=""
        local relative_path=""
        local selected=""
        local selected_share=""
        local selected_relative=""
        local share_path=""
        local full_path=""
        local decision="No"
        local dlg_rc=0
        local -a choices=()

        _ensure_selected_shares || return 0

        while :; do
            choices=()
            for share in "${SELECTED_SHARES[@]}"; do
                while IFS= read -r relative_path; do
                    [[ -n "$relative_path" ]] || continue
                    choices+=("$share/$relative_path")
                done < <(_list_share_subdirectories_raw "$share" || true)
            done

            if (( ${#choices[@]} == 0 )); then
                saywarning "No subdirectories found beneath the selected share(s)."
                return 0
            fi

            _smb_ask_selection \
                --label "Select subdirectory to remove" \
                --var selected \
                --items "${choices[@]}" || return 0

            selected_share="${selected%%/*}"
            selected_relative="${selected#*/}"
            _validate_relative_path "$selected_relative" || {
                sayfail "Invalid relative directory path: $selected_relative"
                return 1
            }

            share_path="$(_share_path "$selected_share")"
            full_path="$share_path/$selected_relative"
            [[ "$full_path" == "$share_path/"* && "$full_path" != "$share_path" ]] || {
                sayfail "Refusing to remove the share root."
                return 1
            }
            sudo test -d "$full_path" || {
                saywarning "Directory no longer exists: $full_path"
                continue
            }

            if sudo find "$full_path" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
                decision="No"
                ask_decision \
                    --label "Directory is not empty. Remove it and all contents" \
                    --choices "Yes|Y,No|N,Quit|Q" \
                    --default "No" \
                    --var decision || return $?
                [[ "${decision^^}" == "QUIT" || "${decision^^}" == "Q" ]] && return 0
                [[ "${decision^^}" == "YES" ]] || continue
            fi

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would recursively remove subdirectory '$full_path'."
                _dryrun_complete
            else
                sudo rm -rf -- "$full_path" || return 1
                sudo test ! -e "$full_path" || {
                    sayfail "Directory removal could not be verified: $full_path"
                    return 1
                }
                sayok "Removed '$selected_relative' from '$selected_share'."
            fi

            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=remove another subdirectory" \
                || dlg_rc=$?
            case "$dlg_rc" in
                1|3) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _ensure_kerberos_ticket - Ensure an authenticated Kerberos ticket is available
        # . Purpose
        #   Require an existing Kerberos TGT before querying Active Directory through LDAP/GSSAPI.
        #
        # . Returns
        #   0 when a valid ticket cache exists; 1 otherwise.
        # . Usage
        #   _ensure_kerberos_ticket
    _ensure_kerberos_ticket() {
        local realm=""
        local principal=""
        local username="Administrator"

        if klist -s 2>/dev/null; then
            return 0
        fi

        realm="$(realm list --name-only 2>/dev/null | head -n 1 || true)"
        realm="${realm^^}"
        [[ -n "$realm" ]] || {
            saywarning "No joined Active Directory realm was found."
            return 1
        }

        saywarning "No valid Kerberos ticket is available."

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would require a Kerberos ticket to query Active Directory groups."
            sayinfo "DRYRUN: No new Kerberos ticket will be created in dry-run mode."
            return 1
        fi

        sgnd_print --text "AD Admin rights are needed to query Active Directory. Please enter the AD administrator account."

        ask \
            --label "AD user (Q=Back)" \
            --var username \
            --default "Administrator" \
            --back || return 1

        [[ "$username" == *"@"* ]] && username="${username%@*}"
        principal="${username}@${realm}"

        sayinfo "Authenticate as $principal."
        if ! kinit "$principal"; then
            sayfail "Kerberos authentication failed for $principal."
            return 1
        fi

        if ! klist -s 2>/dev/null; then
            sayfail "Kerberos authentication completed without a usable ticket."
            return 1
        fi

        sayok "Kerberos authentication succeeded."
        return 0
    }

    # fn: _discover_ad_groups - Discover domain groups visible through NSS
        # . Purpose
        #   Query Active Directory directly for group names and include groups already
        #   present on selected share ACLs. NSS is used only to resolve the selected
        #   group to the local fully-qualified identity required for ACL operations.
        #
        # Outputs (globals):
        #   DISCOVERED_GROUPS
        #
        # . Returns
        #   0 always.
        #
        # . Usage
        #   _discover_ad_groups
    _discover_ad_groups() {
        local realm=""
        local realm_lower=""
        local dc=""
        local base_dn=""
        local group=""
        local share=""
        local acl_record=""
        local -A seen=()

        DISCOVERED_GROUPS=()

        realm="$(realm list --name-only 2>/dev/null | head -n 1 || true)"
        [[ -n "$realm" ]] || {
            saywarning "No joined Active Directory realm was found."
            return 1
        }
        realm="${realm^^}"
        realm_lower="${realm,,}"

        dc="$(
            host -t SRV "_ldap._tcp.${realm_lower}" 2>/dev/null |
                awk '{ print $NF }' |
                sed 's/\.$//' |
                head -n 1
        )"
        [[ -n "$dc" ]] || {
            saywarning "No LDAP domain controller could be discovered for $realm."
            return 1
        }

        base_dn="$(
            awk -v realm="$realm_lower" 'BEGIN {
                n=split(realm, parts, ".")
                for (i=1; i<=n; i++) {
                    if (i > 1) printf ","
                    printf "DC=%s", parts[i]
                }
                printf "\n"
            }'
        )"

        _ensure_kerberos_ticket || return 1

        command -v ldapsearch >/dev/null 2>&1 || {
            saywarning "ldapsearch is not installed."
            return 1
        }

        # LDAP group discovery uses the existing Kerberos ticket. -N is required
        # so SASL does not canonicalize the DC hostname away from its registered SPN.
        while IFS= read -r group; do
            [[ -n "$group" ]] || continue
            [[ -n "${seen[$group]-}" ]] && continue
            seen["$group"]=1
            DISCOVERED_GROUPS+=("$group")
        done < <(
            ldapsearch -N -Y GSSAPI \
                -H "ldap://$dc" \
                -b "$base_dn" \
                '(objectClass=group)' \
                sAMAccountName 2>/dev/null |
            awk -F': ' '/^sAMAccountName: / { print $2 }' |
            LC_ALL=C sort -fu
        )

        # Preserve groups already assigned on selected share ACLs.
        for share in "${SELECTED_SHARES[@]}"; do
            while IFS= read -r acl_record; do
                group="${acl_record%%|*}"
                [[ -n "$group" ]] || continue

                if [[ "${group,,}" == *"@${realm_lower}" ]]; then
                    group="${group%@*}"
                fi

                [[ -n "${seen[$group]-}" ]] && continue
                seen["$group"]=1
                DISCOVERED_GROUPS+=("$group")
            done < <(_acl_groups_for_share "$share" || true)
        done

        (( ${#DISCOVERED_GROUPS[@]} > 0 )) || {
            saywarning "No Active Directory groups could be discovered."
            return 1
        }

        mapfile -t DISCOVERED_GROUPS < <(
            printf '%s\n' "${DISCOVERED_GROUPS[@]}" | LC_ALL=C sort -fu
        )

        return 0
    }

    # fn: _select_group - Select or enter an AD/NSS group
        # . Arguments
        #   $1 OUTPUT_VAR
        #
        # . Returns
        #   0 with a resolvable group; 1 on cancellation.
        #
        # . Usage
        #   _select_group group_name || return $?
    _select_group() {
        local output_var="$1"
        local selected=""
        local entered=""
        local realm=""
        local realm_lower=""
        local qualified=""
        local -a choices=()

        realm="$(realm list --name-only 2>/dev/null | head -n 1 || true)"
        [[ -n "$realm" ]] || {
            saywarning "No joined Active Directory realm was found."
            return 1
        }
        realm="${realm^^}"
        realm_lower="${realm,,}"

        _discover_ad_groups || return 1
        choices=("${DISCOVERED_GROUPS[@]}" "Enter group manually")

        _smb_ask_selection \
            --label "Select Active Directory group" \
            --var selected \
            --items "${choices[@]}" || return 1

        if [[ "$selected" == "Enter group manually" ]]; then
            ask --label "AD group (Q=Back)" --var entered --back || return 1
            selected="$entered"
        fi

        if [[ "$selected" == *"@"* ]]; then
            qualified="$selected"
        else
            qualified="${selected}@${realm_lower}"
        fi

        if ! getent group "$qualified" >/dev/null 2>&1; then
            sayfail "Group cannot be resolved through NSS: $qualified"
            return 1
        fi

        printf -v "$output_var" '%s' "$qualified"
        return 0
    }

    # fn: _samba_principal - Format an NSS group for a Samba user-list parameter
        # . Output
        #   Writes a quoted Samba group principal.
        #
        # . Usage
        #   _samba_principal "domain admins@testadura.hq"
    _samba_principal() {
        local group="${1//\"/}"
        printf '@"%s"' "$group"
    }

    # fn: _sync_share_samba_access - Synchronize Samba access lists from POSIX ACLs
        # . Arguments
        #   $1 SHARE
        #
        # . Returns
        #   0 when smb.conf validates and reload succeeds; non-zero otherwise.
        #
        # . Usage
        #   _sync_share_samba_access "Documents"
    _sync_share_samba_access() {
        local share="$1"
        local group=""
        local perms=""
        local principal=""
        local valid_users=""
        local write_list=""
        local temp_file=""
        local backup=""
        local have_groups=0

        while IFS='|' read -r group perms; do
            [[ -n "$group" ]] || continue
            principal="$(_samba_principal "$group")"
            [[ -n "$valid_users" ]] && valid_users+=" "
            valid_users+="$principal"
            have_groups=1

            if [[ "$perms" == *w* ]]; then
                [[ -n "$write_list" ]] && write_list+=" "
                write_list+="$principal"
            fi
        done < <(_acl_groups_for_share "$share")

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would synchronize Samba access lists for share '$share' in '$SGND_SAMBA_CONFIG'."
            if (( have_groups )); then
                sayinfo "DRYRUN: Would set valid users to: $valid_users"
                [[ -n "$write_list" ]] && sayinfo "DRYRUN: Would set write list to: $write_list"
            else
                sayinfo "DRYRUN: No managed group ACLs are present; no Samba group list would be written."
            fi
            sayinfo "DRYRUN: Would validate the resulting Samba configuration and reload smbd.service."
            return 0
        fi

        temp_file="$(mktemp)" || return 1
        backup="$SGND_SAMBA_CONFIG.pre-access.$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$SGND_SAMBA_CONFIG" "$backup" || { rm -f "$temp_file"; return 1; }

        awk \
            -v target="$share" \
            -v valid="$valid_users" \
            -v writers="$write_list" \
            -v managed="$have_groups" '
            BEGIN { in_target=0 }
            /^\[[^]]+\][[:space:]]*$/ {
                name=$0
                gsub(/^\[|\][[:space:]]*$/, "", name)
                in_target=(tolower(name) == tolower(target))
                print
                if (in_target && managed) {
                    print "    read only = yes"
                    print "    valid users = " valid
                    if (writers != "") print "    write list = " writers
                }
                next
            }
            in_target && /^[[:space:]]*(valid users|write list)[[:space:]]*=/ { next }
            in_target && managed && /^[[:space:]]*read only[[:space:]]*=/ { next }
            { print }
        ' "$SGND_SAMBA_CONFIG" > "$temp_file" || { rm -f "$temp_file"; return 1; }

        sudo install -o root -g root -m 0644 "$temp_file" "$SGND_SAMBA_CONFIG" || {
            rm -f "$temp_file"
            return 1
        }
        rm -f "$temp_file"

        if ! sudo testparm -s >/dev/null 2>&1; then
            sudo cp -a "$backup" "$SGND_SAMBA_CONFIG"
            sayfail "Samba configuration validation failed; previous configuration restored."
            return 1
        fi

        sudo systemctl reload smbd.service 2>/dev/null || sudo systemctl restart smbd.service || {
            sudo cp -a "$backup" "$SGND_SAMBA_CONFIG"
            sayfail "Samba reload failed; previous configuration restored."
            return 1
        }

        return 0
    }

    # fn: _apply_group_access - Apply read or write ACLs to selected shares
        # . Arguments
        #   $1 MODE - read or write
        #
        # . Returns
        #   0 after all selected shares are updated; non-zero on failure.
        #
        # . Usage
        #   _apply_group_access write
    _apply_group_access() {
        local mode="$1"
        local group=""
        local share=""
        local path=""
        local perms="r-x"

        [[ "$mode" == "write" ]] && perms="rwx"
        _select_group group || return $?

        for share in "${SELECTED_SHARES[@]}"; do
            path="$(_share_path "$share")"
            sudo test -d "$path" || { sayfail "Share path not found: $path"; return 1; }

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would grant $mode ACL access to '$group' on '$share' and synchronize the Samba access lists."
                continue
            fi

            sudo setfacl -m "g:$group:$perms" -m "m::rwx" -- "$path" || return 1
            sudo setfacl -m "d:g:$group:$perms" -m "d:m::rwx" -- "$path" || return 1
            _sync_share_samba_access "$share" || return $?
            sayok "Granted $mode access to '$group' on '$share'."
        done

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            _dryrun_complete
        fi

        return 0
    }

    # fn: _select_assigned_group - Select a group currently assigned to the selected shares
        # . Arguments
        #   $1 OUTPUT_VAR
        #
        # . Returns
        #   0 with a selected group; 1 when none are assigned or the user returns.
        # . Usage
        #   _select_assigned_group "<output_var>"
    _select_assigned_group() {
        local output_var="${1:?missing output variable}"
        local share=""
        local record=""
        local group=""
        local selected=""
        local -A seen=()
        local -a groups=()

        for share in "${SELECTED_SHARES[@]}"; do
            while IFS= read -r record; do
                group="${record%%|*}"
                [[ -n "$group" ]] || continue
                [[ -n "${seen[$group]-}" ]] && continue
                seen["$group"]=1
                groups+=("$group")
            done < <(_acl_groups_for_share "$share" || true)
        done

        (( ${#groups[@]} > 0 )) || {
            saywarning "No AD/NSS groups are assigned to the selected shares."
            return 1
        }

        if (( ${#groups[@]} > 1 )); then
            mapfile -t groups < <(printf '%s\n' "${groups[@]}" | LC_ALL=C sort -fu)
        fi

        _smb_ask_selection \
            --label "Select assigned AD/NSS group" \
            --var selected \
            --items "${groups[@]}" || return 1

        printf -v "$output_var" '%s' "$selected"
        return 0
    }

    # fn: _remove_group_access - Remove one AD/NSS group's access from selected shares
        # . Returns
        #   0 after all selected shares are updated; non-zero on failure.
        #
        # . Usage
        #   _remove_group_access
    _remove_group_access() {
        local group=""
        local share=""
        local path=""
        local group_count=0
        local group_present=0

        _select_assigned_group group || return $?

        for share in "${SELECTED_SHARES[@]}"; do
            path="$(_share_path "$share")"
            sudo test -d "$path" || { sayfail "Share path not found: $path"; return 1; }

            group_count=0
            group_present=0
            while IFS='|' read -r acl_group _; do
                [[ -n "$acl_group" ]] || continue
                group_count=$((group_count + 1))
                [[ "$acl_group" == "$group" ]] && group_present=1
            done < <(_acl_groups_for_share "$share" || true)

            (( group_present )) || {
                saywarning "Group '$group' is not assigned to '$share'."
                continue
            }

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would remove ACL access for '$group' from '$share' and synchronize the Samba access lists."
                continue
            fi

            sudo setfacl -x "g:$group" -- "$path" 2>/dev/null || true
            sudo setfacl -x "d:g:$group" -- "$path" 2>/dev/null || true
            _sync_share_samba_access "$share" || return $?
            sayok "Removed '$group' access from '$share'."
        done

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            _dryrun_complete
        fi

        return 0
    }

    # fn: _show_access - Display current share paths and named group ACLs
        # . Returns
        #   0 after displaying access state.
        #
        # . Usage
        #   _show_access
    _show_access() {
        local share=""
        local path=""
        local group=""
        local perms=""
        local role=""
        local count=0

        for share in "${SELECTED_SHARES[@]}"; do
            path="$(_share_path "$share")"
            sgnd_print
            sgnd_print_sectionheader --text "$share"
            sgnd_print_labeledvalue --label "Path" --value "$path" --labelwidth 20
            count=0

            while IFS='|' read -r group perms; do
                [[ -n "$group" ]] || continue
                role="Read only"
                [[ "$perms" == *w* ]] && role="Read / write"
                sgnd_print_labeledvalue --label "$group" --value "$role ($perms)" --labelwidth 30
                count=$((count + 1))
            done < <(_acl_groups_for_share "$share" || true)

            (( count > 0 )) || sgnd_print --text "No named group ACLs assigned." --pad 2
        done
        return 0
    }

    # fn: _validate_selected - Validate selected share paths, ACLs, and Samba configuration
        # . Returns
        #   0 when selected shares validate; 1 otherwise.
        #
        # . Usage
        #   _validate_selected
    _validate_selected() {
        local share=""
        local path=""
        local failures=0
        local result=""

        sgnd_print
        sgnd_print_sectionheader --text "Validate selected Samba shares"

        if sudo testparm -s >/dev/null 2>&1; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Samba configuration" --value "$result" --labelwidth 24

        for share in "${SELECTED_SHARES[@]}"; do
            path="$(_share_path "$share")"

            sgnd_print
            sgnd_print_sectionheader --text "$share"

            if [[ "$path" == "$SGND_SAMBA_SHARE_ROOT/"* ]] && sudo test -d "$path"; then
                result="Passed"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "Managed path" --value "$result" --labelwidth 24
            sgnd_print_labeledvalue --label "Path" --value "${path:-Unavailable}" --labelwidth 24

            if [[ -n "$path" ]] && sudo getfacl -cp -- "$path" >/dev/null 2>&1; then
                result="Passed"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "ACL readable" --value "$result" --labelwidth 24

            if [[ -n "$path" ]] && sudo test -d "$path"; then
                result="Passed"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "Backing directory" --value "$result" --labelwidth 24
        done

        local validation_rc=0

        sgnd_print
        if (( failures == 0 )); then
            sgnd_print_labeledvalue --label "Result" --value "Passed" --labelwidth 24
            validation_rc=0
        else
            sgnd_print_labeledvalue --label "Result" --value "Failed ($failures check(s))" --labelwidth 24
            validation_rc=1
        fi

        # Keep the validation report visible before the manager redraws.
        ask_dlg_autocontinue \
            --seconds 15 \
            --message "Press Enter to return to share management." \
            --pause || true

        return "$validation_rc"
    }

# - Standard share-management menu -------------------------------------------------
    _smb_menu_require_selection() {
        (( ${#SELECTED_SHARES[@]} > 0 )) || {
            saywarning "Select one or more shares first."
            return 1
        }
    }

    _smb_menu_create_share()        { _create_share; }
    _smb_menu_remove_share()        { _remove_share; }
    _smb_menu_create_subdirectory() { _create_subdirectory; }
    _smb_menu_list_subdirectories() { _list_subdirectories; }
    _smb_menu_remove_subdirectory() { _remove_subdirectory; }
    _smb_menu_select_shares()       { _select_shares; }
    _smb_menu_show_access() {
        _smb_menu_require_selection || return $?
        _show_access
        local rc=$?
        sgnd_print
        sgnd_print_sectionheader ""
        ask_dlg_autocontinue --seconds 15 --message "Press Enter to return to share management." --pause || true
        return "$rc"
    }
    _smb_menu_grant_read() {
        _smb_menu_require_selection || return $?
        _apply_group_access read
    }
    _smb_menu_grant_write() {
        _smb_menu_require_selection || return $?
        _apply_group_access write
    }
    _smb_menu_remove_access() {
        _smb_menu_require_selection || return $?
        _remove_group_access
    }
    _smb_menu_validate() {
        _smb_menu_require_selection || return $?
        _validate_selected
    }

    _smb_menu_build() {
        local selection_state=2
        local selected_text="None selected"

        (( ${#SELECTED_SHARES[@]} > 0 )) && {
            selection_state=1
            selected_text="$(IFS=', '; printf '%s' "${SELECTED_SHARES[*]}")"
        }

        sgnd_menu_create "Manage Samba Shares" "Selected Samba shares: $selected_text"
        SGND_MENU_SHOW_TOGGLEBAR=0
        SGND_CURRENT_MODULE_SOURCE="manage-samba-shares"
        SGND_MENU_ACTIVE_SOURCE="$SGND_CURRENT_MODULE_SOURCE"

        sgnd_menu_register_group "share-create-remove" "Create/remove shares" "" 0 1 10
        sgnd_menu_register_item "create"     "share-create-remove" "Create share"                        "_smb_menu_create_share"        "" 0 0 1 0
        sgnd_menu_register_item "remove"     "share-create-remove" "Remove share"                        "_smb_menu_remove_share"        "" 0 0 1 0

        sgnd_menu_register_group "share-management" "Share management" "" 0 1 20
        sgnd_menu_register_item "select"     "share-management" "Select shares"                        "_smb_menu_select_shares"       "" 0 0 1 0
        sgnd_menu_register_item "mkdir"      "share-management" "Create subdirectory"                  "_smb_menu_create_subdirectory" "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "listdirs"   "share-management" "List subdirectories"                  "_smb_menu_list_subdirectories" "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "rmdir"      "share-management" "Remove subdirectory"                  "_smb_menu_remove_subdirectory" "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "access"     "share-management" "Show access"                          "_smb_menu_show_access"         "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "grant-read" "share-management" "Grant read-only access to AD group"   "_smb_menu_grant_read"          "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "grant-rw"   "share-management" "Grant read/write access to AD group"  "_smb_menu_grant_write"         "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "remove-acl" "share-management" "Remove AD group access"               "_smb_menu_remove_access"       "" 0 0 "$selection_state" 0

        sgnd_menu_register_group "share-validation" "Validation" "" 0 1 30
        sgnd_menu_register_item "validate"   "share-validation" "Validate selected shares"             "_smb_menu_validate"            "" 0 0 "$selection_state" 0
    }

# - Main ----------------------------------------------------------------------------
    # fn: main - Run interactive Samba share management
    main() {
        local choice=""
        local dispatch_rc=0

        _framework_locator || exit $?
        sgnd_exe_start "$@" || return $?

        command -v setfacl >/dev/null 2>&1 || { sayfail "setfacl is not installed."; return 1; }
        command -v getfacl >/dev/null 2>&1 || { sayfail "getfacl is not installed."; return 1; }
        [[ -r "$SGND_SAMBA_CONFIG" ]] || { sayfail "Samba configuration not found: $SGND_SAMBA_CONFIG"; return 1; }
        [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] || { sayfail "Share root not found: $SGND_SAMBA_SHARE_ROOT"; return 1; }

        while :; do
            _smb_menu_build || return $?
            sgnd_menu_show_menu

            choice=""
            sgnd_print
            sgnd_print_sectionheader ""
            printf 'Selection : ' >/dev/tty
            sgnd_menu_read_choice choice || return $?

            case "$choice" in
                EXIT|ESC) return 0 ;;
                RESET|REDRAW) continue ;;
            esac

            dispatch_rc=0
            sgnd_menu_dispatch "$choice" || dispatch_rc=$?

            sgnd_print
            sgnd_print_sectionheader ""

            if (( dispatch_rc != 0 )); then
                sleep 1
            fi
        done
    }

    main "$@"
