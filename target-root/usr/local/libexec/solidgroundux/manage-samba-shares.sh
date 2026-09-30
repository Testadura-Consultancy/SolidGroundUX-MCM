#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Samba Shares
# ------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626712
#   Checksum    : e0ca15a407d641178da1eba0eebc09db4f552cb3b280d623150bfa27b77d07ea
#   Source      : manage-samba-shares.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Manage Samba shares
#
# Description:
#   Provides interactive management of SolidGroundUX Samba shares, including share
#   lifecycle, validation, standalone identities, and AD/NSS group access synchronized
#   through POSIX ACLs and Samba valid-users/write-list settings. Directory lifecycle and
#   directory-level ACL management are implemented by manage-samba-directories.sh.
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
    : "${SGND_SCRIPT_DESC:=Create, remove, validate, and manage access to Samba shares.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2626712}"
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
        DEFAULT_ACCESS_GROUP
        DEFAULT_ACCESS_LEVEL
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
    SGND_STATE_SAVE=1

# - Local declarations --------------------------------------------------------------
    SGND_SAMBA_CONFIG="/etc/samba/smb.conf"
    SGND_STORAGE_DEFAULT_MOUNTPOINT="/srv/storage"
    SGND_STORAGE_CONFIG_FILE="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"
    SGND_SAMBA_SHARE_ROOT="/srv/storage/shares"
    MANAGED_SHARES=()
    SELECTED_SHARES=()
    DISCOVERED_GROUPS=()
    DEFAULT_ACCESS_GROUP="${DEFAULT_ACCESS_GROUP:-}"
    DEFAULT_ACCESS_LEVEL="${DEFAULT_ACCESS_LEVEL:-Read / write}"

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

    # fn: _share_root_traversable - Verify the managed share container traversal contract
        # . Purpose
        #   Ensure authenticated share users can traverse the SolidGroundUX share container
        #   without granting filesystem-level directory listing access to that container.
        #
        # . Behavior
        #   - Requires the managed share root to exist.
        #   - Requires mode 0711, the canonical SolidGroundUX Samba share-root mode.
        #
        # . Returns
        #   0 when the share root exists with mode 0711; 1 otherwise.
        #
        # . Usage
        #   _share_root_traversable
    _share_root_traversable() {
        [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] || return 1
        [[ "$(stat -c '%a' "$SGND_SAMBA_SHARE_ROOT" 2>/dev/null || true)" == "711" ]]
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

    # fn: _validate_relative_path - Validate a relative path beneath the share root
        # . Arguments
        #   $1  Relative directory path.
        # . Returns
        #   0 for a safe relative path; 1 otherwise.
        # . Usage
        #   _validate_relative_path "Department/Files"
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


    # fn: _share_path_in_use - Test whether a backing directory is already used by a managed share
        # . Arguments
        #   $1 PATH
        #
        # . Returns
        #   0 when another managed Samba share already uses PATH; 1 otherwise.
        #
        # . Usage
        #   _share_path_in_use "/srv/storage/shares/Install"
    _share_path_in_use() {
        local candidate_path="${1:-}"
        local share=""
        local share_path=""

        [[ -n "$candidate_path" ]] || return 1
        command -v testparm >/dev/null 2>&1 || return 1

        while IFS= read -r share; do
            [[ -n "$share" ]] || continue
            case "${share,,}" in
                global|printers|print\$) continue ;;
            esac

            share_path="$(_share_path "$share")"
            [[ "$share_path" == "$SGND_SAMBA_SHARE_ROOT/"* ]] || continue
            [[ "$share_path" == "$candidate_path" ]] && return 0
        done < <(
            sudo testparm -s 2>/dev/null |
                awk '/^\[[^]]+\]$/ { name=$0; gsub(/^\[|\]$/, "", name); print name }'
        )

        return 1
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

    # fn: _resolve_access_group_input - Resolve a typed default access group for the active authentication mode
        # . Purpose
        #   Normalize and validate a persisted/default group without guessing across authentication modes.
        # . Arguments
        #   $1  User-entered group name; empty means no default access group.
        #   $2  Output variable name.
        # . Returns
        #   0 with an empty or resolvable group; 1 when the group cannot be resolved.
        # . Usage
        #   _resolve_access_group_input "$DEFAULT_ACCESS_GROUP" resolved_group || return 1
    _resolve_access_group_input() {
        local entered="${1:-}"
        local output_var="${2:?missing output variable}"
        local mode=""
        local realm=""
        local resolved=""

        entered="${entered#"${entered%%[![:space:]]*}"}"
        entered="${entered%"${entered##*[![:space:]]}"}"
        if [[ -z "$entered" ]]; then
            printf -v "$output_var" '%s' ""
            return 0
        fi

        mode="$(_smb_runtime_auth_mode)"
        if [[ "$mode" == "ad" ]]; then
            realm="$(realm list --name-only 2>/dev/null | head -n 1 || true)"
            [[ -n "$realm" ]] || { saywarning "No joined Active Directory realm was found."; return 1; }
            if [[ "$entered" == *"@"* ]]; then
                resolved="$entered"
            else
                resolved="${entered}@${realm,,}"
            fi
            getent group "$resolved" >/dev/null 2>&1 || {
                saywarning "Active Directory group cannot be resolved through NSS: $resolved"
                return 1
            }
        else
            resolved="$entered"
            getent -s files group "$resolved" >/dev/null 2>&1 || {
                saywarning "Local group does not exist: $resolved"
                return 1
            }
        fi

        printf -v "$output_var" '%s' "$resolved"
    }

    # fn: _apply_group_access_to_groups - Apply one access level to explicit groups on selected shares
        # . Purpose
        #   Share the ACL/Samba synchronization implementation between interactive access changes
        #   and stateful default access applied during share creation.
        # . Arguments
        #   $1  MODE - read or write.
        #   $@  One or more resolved group names.
        # . Returns
        #   0 after all selected shares are updated; non-zero on failure.
        # . Usage
        #   _apply_group_access_to_groups write "domain users@testadura.hq"
    _apply_group_access_to_groups() {
        local mode="${1:?missing access mode}"
        shift
        local group=""
        local share=""
        local path=""
        local perms="r-x"
        local -a groups=("$@")

        [[ "$mode" == "write" ]] && perms="rwx"
        (( ${#groups[@]} > 0 )) || return 0

        for share in "${SELECTED_SHARES[@]}"; do
            path="$(_share_path "$share")"
            sudo test -d "$path" || { sayfail "Share path not found: $path"; return 1; }

            for group in "${groups[@]}"; do
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "DRYRUN: Would grant $mode ACL access to '$group' on '$share'."
                    continue
                fi
                sudo setfacl -m "g:$group:$perms" -m "m::rwx" -- "$path" || return 1
                sudo setfacl -m "d:g:$group:$perms" -m "d:m::rwx" -- "$path" || return 1
                sayok "Granted $mode access to '$group' on '$share'."
            done

            if (( ${FLAG_DRYRUN:-0} == 0 )); then
                _sync_share_samba_access "$share" || return $?
            fi
        done

        return 0
    }

    # fn: _create_share - Create a managed share and backing directory
        # . Purpose
        #   Create a Samba share and optionally apply a stateful default access group/access level.
        # . Behavior
        #   - Requires the managed share root to satisfy the 0711 traversal contract.
        #   - Defaults the backing-directory path to the share name but allows another relative path.
        #   - Reuses an existing backing directory or creates it with mode 0770.
        #   - Rejects backing paths already used by another managed Samba share.
        #   - Prompts for a persisted default access group; empty means no access is assigned.
        #   - Persists the default access group and access level through SolidGroundUX state.
        #   - Validates the resulting Samba configuration and reloads smbd.
        # . Returns
        #   0 after returning to the manager; non-zero on creation/access failure.
        # . Usage
        #   _create_share
    _create_share() {
        local share_name=""
        local directory_path=""
        local comment=""
        local browsable="Yes"
        local read_only="No"
        local share_path=""
        local create_directory=0
        local backup=""
        local dlg_rc=0
        local entered_access_group=""
        local resolved_access_group=""
        local access_mode=""

        _share_root_traversable || {
            sayfail "Samba share root is unavailable or not traversable with mode 0711: $SGND_SAMBA_SHARE_ROOT"
            return 1
        }

        while :; do
            share_name=""
            ask --label "Share name (Q=Back)" --var share_name --validate _validate_share_name --back || return 0

            _share_exists "$share_name" && {
                sayfail "A Samba share named '$share_name' already exists."
                continue
            }

            directory_path="$share_name"
            sgnd_print_labeledvalue --label "Share root" --value "$SGND_SAMBA_SHARE_ROOT"
            ask \
                --label "Directory (Q=Back)" \
                --var directory_path \
                --default "$directory_path" \
                --validate _validate_relative_path \
                --back || return 0

            share_path="$SGND_SAMBA_SHARE_ROOT/$directory_path"
            if _share_path_in_use "$share_path"; then
                sayfail "Backing directory is already used by another managed Samba share: $share_path"
                continue
            fi

            create_directory=0
            if sudo test -d "$share_path"; then
                sayinfo "Backing directory already exists; it will be used: $share_path"
            elif sudo test -e "$share_path"; then
                sayfail "The selected backing path exists but is not a directory: $share_path"
                continue
            else
                create_directory=1
            fi

            comment="$share_name share"
            ask --label "Description (Q=Back)" --var comment --default "$comment" --back || return 0

            ask_decision --label "Browsable" --choices "Yes|Y,No|N,Quit|Q" --default "Yes" --var browsable || return $?
            [[ "${browsable^^}" == "QUIT" || "${browsable^^}" == "Q" ]] && return 0

            ask_decision --label "Read only" --choices "Yes|Y,No|N,Quit|Q" --default "No" --var read_only || return $?
            [[ "${read_only^^}" == "QUIT" || "${read_only^^}" == "Q" ]] && return 0

            while :; do
                entered_access_group=""
                sgnd_print_labeledvalue --label "Previous default group" --value "${DEFAULT_ACCESS_GROUP:-None}" --labelwidth 24
                ask \
                    --label "Default access group (empty=none, Q=Back)" \
                    --var entered_access_group \
                    --back || return 0
                if _resolve_access_group_input "$entered_access_group" resolved_access_group; then
                    DEFAULT_ACCESS_GROUP="$resolved_access_group"
                    break
                fi
            done

            if [[ -n "$DEFAULT_ACCESS_GROUP" ]]; then
                ask_decision \
                    --label "Default access level" \
                    --choices "Read only|R,Read / write|W,Quit|Q" \
                    --default "$DEFAULT_ACCESS_LEVEL" \
                    --var DEFAULT_ACCESS_LEVEL || return $?
                [[ "${DEFAULT_ACCESS_LEVEL^^}" == "QUIT" || "${DEFAULT_ACCESS_LEVEL^^}" == "Q" ]] && return 0
            fi

            sgnd_save_state || return $?

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                if (( create_directory == 1 )); then
                    sayinfo "DRYRUN: Would create backing directory '$share_path' with mode 0770."
                else
                    sayinfo "DRYRUN: Would reuse existing backing directory '$share_path'."
                fi
                sayinfo "DRYRUN: Would add Samba share '$share_name' to '$SGND_SAMBA_CONFIG'."
                sayinfo "DRYRUN: Share settings would be browseable=${browsable,,}, read only=${read_only,,}, guest ok=no."
                if [[ -n "$DEFAULT_ACCESS_GROUP" ]]; then
                    sayinfo "DRYRUN: Would grant '$DEFAULT_ACCESS_LEVEL' access to '$DEFAULT_ACCESS_GROUP'."
                else
                    sayinfo "DRYRUN: No default access group is configured."
                fi
                sayinfo "DRYRUN: Would validate the updated Samba configuration and reload smbd.service."
                _dryrun_complete
            else
                backup="$SGND_SAMBA_CONFIG.pre-share.$(date +%Y%m%d%H%M%S)"
                sudo cp -a "$SGND_SAMBA_CONFIG" "$backup" || return 1
                if (( create_directory == 1 )); then
                    sudo install -d -m 0770 "$share_path" || return 1
                fi

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
                    if (( create_directory == 1 )); then
                        sudo rm -rf -- "$share_path"
                    fi
                    return 1
                fi

                sayok "Samba share '$share_name' created."
                sgnd_print_labeledvalue --label "Directory" --value "$share_path" --labelwidth 22
                sgnd_print_labeledvalue --label "Default access group" --value "${DEFAULT_ACCESS_GROUP:-None}" --labelwidth 22
                [[ -n "$DEFAULT_ACCESS_GROUP" ]] && sgnd_print_labeledvalue --label "Default access level" --value "$DEFAULT_ACCESS_LEVEL" --labelwidth 22

                if [[ -n "$DEFAULT_ACCESS_GROUP" ]]; then
                    SELECTED_SHARES=("$share_name")
                    access_mode="read"
                    [[ "$DEFAULT_ACCESS_LEVEL" == "Read / write" ]] && access_mode="write"
                    _apply_group_access_to_groups "$access_mode" "$DEFAULT_ACCESS_GROUP" || return $?
                fi
            fi

            dlg_rc=0
            sgnd_print_sectionheader ""
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=create another share" \
                || dlg_rc=$?
            case "$dlg_rc" in
                1|3) continue ;;
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
            sgnd_print_sectionheader ""
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=remove another share" \
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

    # fn: _select_groups - Select or enter one or more AD/NSS groups
        # . Purpose
        #   Allow one or more Active Directory groups to be selected in a single operation.
        #   A manual group entry remains available as a single additional identity.
        #
        # . Arguments
        #   $1 OUTPUT_ARRAY_VAR
        #
        # . Returns
        #   0 with one or more resolvable groups; 1 on cancellation or lookup failure.
        #
        # . Usage
        #   _select_groups groups || return $?
    _select_groups() {
        local output_var="${1:?missing output array variable}"
        local entered=""
        local realm=""
        local realm_lower=""
        local selected=""
        local qualified=""
        local -a choices=()
        local -a selections=()
        local -a resolved=()

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
            --label "Select Active Directory group(s)" \
            --var selections \
            --multi \
            --items "${choices[@]}" || return 1

        for selected in "${selections[@]}"; do
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
            resolved+=("$qualified")
        done

        (( ${#resolved[@]} > 0 )) || return 1
        local -n output_ref="$output_var"
        output_ref=("${resolved[@]}")
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
        #   $1 MODE - read or write.
        # . Returns
        #   0 after all selected shares are updated; non-zero on failure.
        # . Usage
        #   _apply_group_access write
    _apply_group_access() {
        local mode="${1:?missing access mode}"
        local -a groups=()

        _select_access_groups groups || return $?
        _apply_group_access_to_groups "$mode" "${groups[@]}" || return $?

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

    # fn: _validate_selected - Validate selected share paths, traversal, ACLs, and Samba configuration
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

            if _share_root_traversable; then
                result="Passed"
            else
                result="Failed"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "Path traversal" --value "$result" --labelwidth 24

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

# - Authentication-aware identity management ---------------------------------------
    # fn: _smb_runtime_auth_mode - Return the configured Samba authentication mode
        # . Returns
        #   Writes "ad" for ADS security and "standalone" otherwise.
        # . Usage
        #   mode="$(_smb_runtime_auth_mode)"
    _smb_runtime_auth_mode() {
        local security=""
        security="$(sudo testparm -s --parameter-name security 2>/dev/null || true)"
        [[ "${security^^}" == "ADS" ]] && printf 'ad\n' || printf 'standalone\n'
    }

    # fn: _list_local_samba_users_raw - List enabled local Samba users
        # . Output
        #   Writes one Samba user name per line.
        # . Returns
        #   pdbedit status.
        # . Usage
        #   mapfile -t users < <(_list_local_samba_users_raw)
    _list_local_samba_users_raw() {
        sudo pdbedit -L 2>/dev/null | cut -d: -f1 | LC_ALL=C sort -fu
    }

    # fn: _list_local_groups_raw - List deliberate local access groups
        # . Purpose
        #   Return local groups suitable for explicit Samba access management without
        #   cluttering selectors with automatic user-private primary groups.
        # . Behavior
        #   - Uses only the local files NSS source.
        #   - Includes groups with GID >= 1000.
        #   - Excludes nogroup.
        #   - Excludes a group when a same-named local user has that group as its primary GID.
        # . Output
        #   Writes one local access-group name per line.
        # . Returns
        #   0 after enumeration.
        # . Usage
        #   mapfile -t groups < <(_list_local_groups_raw)
    _list_local_groups_raw() {
        local group=""
        local gid=""

        while IFS=: read -r group _ gid _; do
            [[ -n "$group" && "$gid" =~ ^[0-9]+$ ]] || continue
            (( gid >= 1000 )) || continue
            [[ "$group" != "nogroup" ]] || continue

            if getent -s files passwd | awk -F: -v name="$group" -v gid="$gid" '
                $1 == name && $4 == gid { found=1; exit }
                END { exit(found ? 0 : 1) }
            '; then
                continue
            fi

            printf '%s\n' "$group"
        done < <(getent -s files group)
    }

    # fn: _local_group_display - Format one local access group for selection/display
        # . Purpose
        #   Label deliberate standalone access groups consistently in selectors.
        # . Arguments
        #   $1  Local group name.
        # . Output
        #   Writes a display label.
        # . Returns
        #   0 always.
        # . Usage
        #   label="$(_local_group_display SambaUsers)"
    _local_group_display() {
        local group="${1:?missing group}"
        local gid=""
        local primary_user=""

        gid="$(getent -s files group "$group" 2>/dev/null | cut -d: -f3)"
        if [[ -n "$gid" ]]; then
            primary_user="$(getent -s files passwd | awk -F: -v gid="$gid" '$4 == gid { print $1; exit }')"
        fi

        if [[ -n "$primary_user" && "$primary_user" == "$group" ]]; then
            printf '%s [user private group]\n' "$group"
        else
            printf '%s [group]\n' "$group"
        fi
    }

    # fn: _select_local_samba_user - Select one enabled local Samba user
        # . Arguments
        #   $1  Output variable name.
        # . Returns
        #   0 on selection; 1 on cancel or when no users exist.
        # . Usage
        #   _select_local_samba_user user || return 0
    _select_local_samba_user() {
        local output_var="${1:?missing output variable}"
        local selected=""
        local -a users=()

        mapfile -t users < <(_list_local_samba_users_raw)
        (( ${#users[@]} > 0 )) || { saywarning "No local Samba users are available."; return 1; }
        _smb_ask_selection --label "Select local Samba user" --var selected --items "${users[@]}" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    # fn: _select_local_groups - Select one or more local groups
        # . Arguments
        #   $1  Output array variable name.
        # . Returns
        #   0 on selection; 1 on cancel or when no groups exist.
        # . Usage
        #   _select_local_groups selected_groups || return 0
    _select_local_groups() {
        local output_var="${1:?missing output array variable}"
        local group=""
        local selected_label=""
        local -a groups=()
        local -a labels=()
        local -a selected_labels=()
        local -a resolved=()

        mapfile -t groups < <(_list_local_groups_raw)
        (( ${#groups[@]} > 0 )) || { saywarning "No local groups are available."; return 1; }
        for group in "${groups[@]}"; do
            labels+=("$(_local_group_display "$group")")
        done

        _smb_ask_selection --label "Select local group(s)" --var selected_labels --multi --items "${labels[@]}" || return 1
        for selected_label in "${selected_labels[@]}"; do
            for group in "${groups[@]}"; do
                [[ "$selected_label" == "$(_local_group_display "$group")" ]] || continue
                resolved+=("$group")
                break
            done
        done

        (( ${#resolved[@]} > 0 )) || return 1
        local -n output_ref="$output_var"
        output_ref=("${resolved[@]}")
    }

    # fn: _select_local_group - Select exactly one local group
        # . Arguments
        #   $1  Output variable name.
        # . Returns
        #   0 on selection; 1 on cancel or when no groups exist.
        # . Usage
        #   _select_local_group group || return 0
    _select_local_group() {
        local output_var="${1:?missing output variable}"
        local -a groups=()

        while :; do
            groups=()
            _select_local_groups groups || return 1
            if (( ${#groups[@]} == 1 )); then
                printf -v "$output_var" '%s' "${groups[0]}"
                return 0
            fi
            saywarning "Select exactly one local group."
        done
    }

    # fn: _pause_return_to_share_manager - Keep terminal action results visible
        # . Arguments
        #   $1  Optional message.
        # . Returns
        #   0 always.
        # . Usage
        #   _pause_return_to_share_manager "Press Enter to return to share management."
    _pause_return_to_share_manager() {
        local message="${1:-Press Enter to return to share management.}"
        sgnd_print_sectionheader ""
        ask_dlg_autocontinue --seconds 15 --message "$message" --pause || true
        return 0
    }

    # fn: _smb_manage_local_users - Manage local Linux/Samba accounts for standalone authentication
        # . Purpose
        #   List, create, update, and remove standalone Samba users with selection-first workflows.
        # . Behavior
        #   - Creating a Samba account creates the matching Linux account when absent.
        #   - Password changes select an existing Samba account.
        #   - Removal supports multi-selection and preserves Linux accounts/files.
        #   - Terminal actions use the standard SolidGroundUX auto-continue pattern.
        # . Returns
        #   0 after the requested operation; non-zero on command failure.
        # . Usage
        #   _smb_manage_local_users
    _smb_manage_local_users() {
        local action=""
        local user=""
        local dlg_rc=0
        local failures=0
        local -a users=()
        local -a selected_users=()

        _smb_ask_selection --label "Manage local Samba users" --var action --items \
            "List Samba users" "Create/enable Samba user" "Change Samba password" "Remove Samba user(s)" || return 0

        case "$action" in
            "List Samba users")
                sgnd_print
                sgnd_print_sectionheader --text "Local Samba users"
                mapfile -t users < <(_list_local_samba_users_raw)
                if (( ${#users[@]} == 0 )); then
                    sgnd_print --text "No local Samba users found." --pad 2
                else
                    for user in "${users[@]}"; do
                        sgnd_print_labeledvalue --label "User" --value "$user" --labelwidth 18
                    done
                fi
                _pause_return_to_share_manager
                ;;

            "Create/enable Samba user")
                while :; do
                    user=""
                    ask --label "Local user (Q=Back)" --var user --validate _validate_share_name --back || return 0
                    if ! getent -s files passwd "$user" >/dev/null 2>&1; then
                        sudo useradd -m -s /bin/bash "$user" || { sayfail "Local Linux user '$user' could not be created."; return 1; }
                        sayok "Local Linux user '$user' created."
                    fi
                    sayinfo "Enter the Samba password for '$user'."
                    sudo smbpasswd -a "$user" </dev/tty || { sayfail "Samba account '$user' could not be enabled."; return 1; }
                    sayok "Local Samba user '$user' is enabled."

                    dlg_rc=0
                    sgnd_print_sectionheader ""
                    ask_dlg_autocontinue \
                        --seconds 5 \
                        --again \
                        --legend "Enter=return to manager; A=another; timeout=create/enable another Samba user" \
                        || dlg_rc=$?
                    case "$dlg_rc" in
                        1|3) continue ;;
                        *) return 0 ;;
                    esac
                done
                ;;

            "Change Samba password")
                _select_local_samba_user user || return 0
                sudo smbpasswd "$user" </dev/tty || { sayfail "Samba password for '$user' could not be changed."; return 1; }
                sayok "Samba password for '$user' changed."
                _pause_return_to_share_manager
                ;;

            "Remove Samba user(s)")
                mapfile -t users < <(_list_local_samba_users_raw)
                (( ${#users[@]} > 0 )) || { saywarning "No local Samba users are available."; _pause_return_to_share_manager; return 0; }
                _smb_ask_selection --label "Select Samba user(s) to remove" --var selected_users --multi --items "${users[@]}" || return 0
                failures=0
                for user in "${selected_users[@]}"; do
                    if sudo smbpasswd -x "$user" >/dev/null 2>&1; then
                        sayok "Samba user '$user' removed; the Linux account was preserved."
                    else
                        failures=$((failures + 1))
                        saywarning "Samba user '$user' could not be removed."
                    fi
                done
                _pause_return_to_share_manager
                (( failures == 0 ))
                ;;
        esac
    }

    # fn: _smb_manage_local_groups - Manage local groups used for standalone share access
        # . Purpose
        #   Provide selection-first local group and membership management for standalone Samba.
        # . Behavior
        #   - Lists local-file groups only and labels user-private groups explicitly.
        #   - Adds multiple selected Samba users to one selected group.
        #   - Removes multiple selected current members from one selected group.
        #   - Removes multiple selected local groups.
        # . Returns
        #   0 after the requested operation; non-zero on command failure.
        # . Usage
        #   _smb_manage_local_groups
    _smb_manage_local_groups() {
        local action=""
        local group=""
        local user=""
        local dlg_rc=0
        local failures=0
        local member=""
        local -a groups=()
        local -a users=()
        local -a members=()
        local -a selected_groups=()
        local -a selected_users=()
        local -a selected_members=()

        _smb_ask_selection --label "Manage local Samba groups" --var action --items \
            "List local groups" "Create local group" "Add user(s) to local group" "Remove user(s) from local group" "Remove local group(s)" || return 0

        case "$action" in
            "List local groups")
                sgnd_print
                sgnd_print_sectionheader --text "Local groups"
                mapfile -t groups < <(_list_local_groups_raw)
                if (( ${#groups[@]} == 0 )); then
                    sgnd_print --text "No local groups found." --pad 2
                else
                    for group in "${groups[@]}"; do
                        sgnd_print_labeledvalue --label "Group" --value "$(_local_group_display "$group")" --labelwidth 18
                    done
                fi
                _pause_return_to_share_manager
                ;;

            "Create local group")
                while :; do
                    group=""
                    ask --label "Group name (Q=Back)" --var group --validate _validate_share_name --back || return 0
                    if getent -s files group "$group" >/dev/null 2>&1; then
                        saywarning "Group '$group' already exists."
                    else
                        sudo groupadd "$group" || { sayfail "Local group '$group' could not be created."; return 1; }
                        sayok "Local group '$group' created."
                    fi

                    dlg_rc=0
                    sgnd_print_sectionheader ""
                    ask_dlg_autocontinue \
                        --seconds 5 \
                        --again \
                        --legend "Enter=return to manager; A=another; timeout=create another local group" \
                        || dlg_rc=$?
                    case "$dlg_rc" in
                        1|3) continue ;;
                        *) return 0 ;;
                    esac
                done
                ;;

            "Add user(s) to local group")
                while :; do
                    group=""
                    users=()
                    selected_users=()
                    failures=0
                    _select_local_group group || return 0
                    mapfile -t users < <(_list_local_samba_users_raw)
                    (( ${#users[@]} > 0 )) || { saywarning "No local Samba users are available."; return 0; }
                    _smb_ask_selection --label "Add users to '$group'" --var selected_users --multi --items "${users[@]}" || return 0
                    for user in "${selected_users[@]}"; do
                        if sudo usermod -aG "$group" "$user"; then
                            sayok "User '$user' added to '$group'."
                        else
                            failures=$((failures + 1))
                            saywarning "User '$user' could not be added to '$group'."
                        fi
                    done
                    (( failures == 0 )) || return 1

                    dlg_rc=0
                    sgnd_print_sectionheader ""
                    ask_dlg_autocontinue \
                        --seconds 5 \
                        --again \
                        --legend "Enter=return to manager; A=another; timeout=add users to another local group" \
                        || dlg_rc=$?
                    case "$dlg_rc" in
                        1|3) continue ;;
                        *) return 0 ;;
                    esac
                done
                ;;

            "Remove user(s) from local group")
                while :; do
                    group=""
                    members=()
                    selected_members=()
                    failures=0
                    _select_local_group group || return 0
                    IFS=',' read -r -a members <<< "$(getent -s files group "$group" 2>/dev/null | cut -d: -f4)"
                    local -a filtered_members=()
                    for member in "${members[@]}"; do
                        [[ -n "$member" ]] && filtered_members+=("$member")
                    done
                    (( ${#filtered_members[@]} > 0 )) || { sayinfo "'$group' has no supplementary members to remove."; _pause_return_to_share_manager; return 0; }
                    _smb_ask_selection --label "Remove users from '$group'" --var selected_members --multi --items "${filtered_members[@]}" || return 0
                    for user in "${selected_members[@]}"; do
                        if sudo gpasswd -d "$user" "$group" >/dev/null 2>&1; then
                            sayok "User '$user' removed from '$group'."
                        else
                            failures=$((failures + 1))
                            saywarning "User '$user' could not be removed from '$group'."
                        fi
                    done
                    (( failures == 0 )) || return 1

                    dlg_rc=0
                    sgnd_print_sectionheader ""
                    ask_dlg_autocontinue \
                        --seconds 5 \
                        --again \
                        --legend "Enter=return to manager; A=another; timeout=remove users from another local group" \
                        || dlg_rc=$?
                    case "$dlg_rc" in
                        1|3) continue ;;
                        *) return 0 ;;
                    esac
                done
                ;;

            "Remove local group(s)")
                _select_local_groups selected_groups || return 0
                failures=0
                for group in "${selected_groups[@]}"; do
                    if sudo groupdel "$group"; then
                        sayok "Local group '$group' removed."
                    else
                        failures=$((failures + 1))
                        saywarning "Local group '$group' could not be removed."
                    fi
                done
                _pause_return_to_share_manager
                (( failures == 0 ))
                ;;
        esac
    }

    # fn: _select_access_groups - Select one or more access groups appropriate to the active Samba mode
        # . Purpose
        #   Return multiple AD groups in AD mode while retaining single-group selection for
        #   standalone local groups. Copies the selected identities into the caller-provided
        #   array explicitly so Bash dynamic scoping cannot redirect the result into a helper-local
        #   array with the same name.
        # . Arguments
        #   $1 OUTPUT_ARRAY_VAR
        # . Returns
        #   0 with one or more resolvable groups; 1 on cancellation or lookup failure.
        # . Usage
        #   _select_access_groups groups || return $?
    _select_access_groups() {
        local output_var="${1:?missing output array variable}"
        local mode=""
        local -a selected_groups=()
        local -n output_ref="$output_var"

        mode="$(_smb_runtime_auth_mode)"
        if [[ "$mode" == "ad" ]]; then
            _select_groups selected_groups || return $?
            output_ref=("${selected_groups[@]}")
            return 0
        fi

        _select_local_groups selected_groups || return $?
        output_ref=("${selected_groups[@]}")
        return 0
    }

    # fn: _select_access_group - Select exactly one access group for identity reconciliation
        # . Purpose
        #   Reuse the authentication-aware access-group selector while enforcing the single
        #   replacement target required by access-identity reconciliation.
        # . Arguments
        #   $1 OUTPUT_VAR
        # . Returns
        #   0 with exactly one resolvable group; non-zero on cancellation or lookup failure.
        # . Usage
        #   _select_access_group target || return $?
    _select_access_group() {
        local output_var="${1:?missing output variable}"
        local -a groups=()

        while :; do
            groups=()
            _select_access_groups groups || return $?
            if (( ${#groups[@]} == 1 )); then
                printf -v "$output_var" '%s' "${groups[0]}"
                return 0
            fi
            saywarning "Select exactly one target access group for reconciliation."
        done
    }

    # fn: _show_shares_overview - Display comprehensive managed-share access information
        # . Behavior
        #   - Shows the active authentication mode and canonical share-root traversal state.
        #   - Shows each managed path and backing-directory state.
        #   - Shows explicit group ACLs and their read-only/read-write access level.
        #   - Reports whether a Samba access list is present when explicit ACL groups exist.
        #
        # . Returns
        #   0 after displaying the overview.
        # . Usage
        #   _show_shares_overview
    _show_shares_overview() {
        local share="" path="" group="" perms="" access="" mode="" count=0
        local traversal="Blocked"
        local config_state=""
        local valid_users=""

        mode="$(_smb_runtime_auth_mode)"
        _share_root_traversable && traversal="Available"
        _list_managed_shares || return $?
        sgnd_print
        sgnd_print_sectionheader --text "Samba shares"
        sgnd_print_labeledvalue --label "Authentication" --value "$([[ "$mode" == ad ]] && printf 'Active Directory' || printf 'Standalone')" --labelwidth 20
        sgnd_print_labeledvalue --label "Share-root traversal" --value "$traversal" --labelwidth 20

        for share in "${MANAGED_SHARES[@]}"; do
            path="$(_share_path "$share")"
            sgnd_print
            sgnd_print_sectionheader --text "$share"
            sgnd_print_labeledvalue --label "Path" --value "${path:-Unavailable}" --labelwidth 20
            sgnd_print_labeledvalue --label "Backing directory" --value "$(sudo test -d "$path" && printf 'Available' || printf 'Missing')" --labelwidth 20
            sgnd_print_labeledvalue --label "Path traversal" --value "$traversal" --labelwidth 20

            count=0
            while IFS='|' read -r group perms; do
                [[ -n "$group" ]] || continue
                access="Read only"; [[ "$perms" == *w* ]] && access="Read / write"
                sgnd_print_labeledvalue --label "$group" --value "$access" --labelwidth 32
                count=$((count + 1))
            done < <(_acl_groups_for_share "$share" || true)

            valid_users="$(sudo testparm -s --section-name "$share" --parameter-name 'valid users' 2>/dev/null || true)"
            if (( count == 0 )); then
                config_state="No access assigned"
                sgnd_print --text "No explicit group access assigned." --pad 2
            elif [[ -n "$valid_users" ]]; then
                config_state="Configured"
            else
                config_state="Missing Samba access list"
            fi
            sgnd_print_labeledvalue --label "Access configuration" --value "$config_state" --labelwidth 20
        done
        ask_dlg_autocontinue --seconds 15 --message "Press Enter to return to share management." --pause || true
    }

    # fn: _reconcile_access_group - Replace one assigned group identity with another
        # . Purpose
        #   Reconcile share ACL identities after changing Samba authentication mode without guessing mappings.
        # . Returns
        #   0 after replacement; non-zero on failure or cancellation.
        # . Usage
        #   _reconcile_access_group
    _reconcile_access_group() {
        local source="" target="" share="" path="" group="" perms="" found=0
        _smb_menu_require_selection || return $?
        _select_assigned_group source || return $?
        _select_access_group target || return $?
        [[ "$source" != "$target" ]] || { saywarning "Source and target groups are the same."; return 0; }
        for share in "${SELECTED_SHARES[@]}"; do
            path="$(_share_path "$share")"
            found=0
            while IFS='|' read -r group perms; do
                [[ "$group" == "$source" ]] || continue
                found=1
                sudo setfacl -m "g:$target:$perms" -- "$path" || return 1
                sudo setfacl -m "d:g:$target:$perms" -- "$path" || return 1
                sudo setfacl -x "g:$source" -- "$path" 2>/dev/null || true
                sudo setfacl -x "d:g:$source" -- "$path" 2>/dev/null || true
            done < <(_acl_groups_for_share "$share" || true)
            if (( found )); then
                _sync_share_samba_access "$share" || return $?
            fi
        done
        sayok "Access identity '$source' reconciled to '$target' on the selected shares."
    }

# - Share-management menu ----------------------------------------------------------
    _smb_menu_require_selection() {
        (( ${#SELECTED_SHARES[@]} > 0 )) || {
            saywarning "Select one or more shares first."
            return 1
        }
    }

    _smb_menu_create_share()        { _create_share; }
    _smb_menu_show_shares()          { _show_shares_overview; }
    _smb_menu_local_users()          { _smb_manage_local_users; }
    _smb_menu_local_groups()         { _smb_manage_local_groups; }
    _smb_menu_reconcile() {
        _reconcile_access_group || return $?
        _pause_return_to_share_manager
    }
    _smb_menu_remove_share()        { _remove_share; }
    _smb_menu_select_shares()       { _select_shares; }
    _smb_menu_grant_read() {
        _smb_menu_require_selection || return $?
        _apply_group_access read || return $?
        _pause_return_to_share_manager
    }
    _smb_menu_grant_write() {
        _smb_menu_require_selection || return $?
        _apply_group_access write || return $?
        _pause_return_to_share_manager
    }
    _smb_menu_remove_access() {
        _smb_menu_require_selection || return $?
        _remove_group_access || return $?
        _pause_return_to_share_manager
    }
    _smb_menu_validate() {
        _smb_menu_require_selection || return $?
        _validate_selected
    }

    _smb_menu_build() {
        local selection_state=2
        local standalone_identity_state=2
        local selected_text="None selected"

        [[ "$(_smb_runtime_auth_mode)" == "standalone" ]] && standalone_identity_state=1

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
        sgnd_menu_register_item "show"       "share-management" "Show shares"                         "_smb_menu_show_shares"         "" 0 0 1 0
        sgnd_menu_register_item "select"     "share-management" "Select shares"                        "_smb_menu_select_shares"       "" 0 0 1 0
        sgnd_menu_register_item "grant-read" "share-management" "Grant read-only access to group"   "_smb_menu_grant_read"          "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "grant-rw"   "share-management" "Grant read/write access to group"  "_smb_menu_grant_write"         "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "remove-acl" "share-management" "Remove group access"                  "_smb_menu_remove_access"       "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "reconcile"  "share-management" "Reconcile access identity"            "_smb_menu_reconcile"           "" 0 0 "$selection_state" 0

        sgnd_menu_register_group "standalone-identities" "Standalone identities" "" 0 1 30
        sgnd_menu_register_item "local-users"  "standalone-identities" "Manage local Samba users"           "_smb_menu_local_users"         "" 0 0 "$standalone_identity_state" 0
        sgnd_menu_register_item "local-groups" "standalone-identities" "Manage local groups"                "_smb_menu_local_groups"        "" 0 0 "$standalone_identity_state" 0

        sgnd_menu_register_group "share-validation" "Validation" "" 0 1 40
        sgnd_menu_register_item "validate"   "share-validation" "Validate selected shares"             "_smb_menu_validate"            "" 0 0 "$selection_state" 0
    }

# - Main ----------------------------------------------------------------------------
    # fn: main - Run interactive Samba share management
    main() {
        local choice=""
        local dispatch_rc=0

        _framework_locator || exit $?
        sgnd_exe_start --autostate -- "$@" || return $?

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
