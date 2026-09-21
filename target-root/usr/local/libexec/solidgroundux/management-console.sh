#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX - SolidGround Management Console
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626414
#   Checksum    : c35420a64db513d4cfbaf76c2bd19be62ad3729c3338ca7227b00810391661b4
#   Source      : management-console.sh
#   Wrapper     : sgnd-console
#   Type        : script
#   Group       : SolidGround Console
#   Purpose     : Provide a modular console interface for SolidGroundUX tooling
#
# Description:
#   Provides a generic, modular console host that discovers management pages at
#   startup and lazy-loads each implementation module when its page is first opened.
#
#   The script:
#     - Discovers enabled console modules and reads lightweight page metadata
#     - Renders a top-level index without sourcing module implementations
#     - Sources each selected page module once and retains it for the console session
#     - Allows loaded modules to register menu groups and items dynamically
#     - Builds and renders interactive menus
#     - Handles user input, page navigation, paging, and action dispatch
#     - Persists console layout and framework UI/logging state
#
# Design principles:
#   - Modular architecture with clear separation of host and modules
#   - Convention-based module registration
#   - Minimal assumptions about module implementation
#   - Consistent user interaction patterns across all tools
#
# Role in framework:
#   - Generic console engine for module-defined interactive applications
#   - Hosts functionality registered by ordered console modules
#
# Non-goals:
#   - Implementing business logic directly in the console host
#   - Managing module-specific state beyond registration and dispatch
#   - Providing a widget-based or cursor-addressed full-screen TUI
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail
# --- Bootstrap ----------------------------------------------------------------------
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

# --- Script metadata (identity) ------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"

# --- Script metadata (framework integration) -----------------------------------------
    # SGND_USING
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

    # SGND_ARGS_SPEC 
        # Optional: script-specific arguments
        # --- Example: Arguments
        # Each entry:
        #   "name|short|type|var|help|choices"
        #
        #   name    = long option name WITHOUT leading --
        #   short   - short option name WITHOUT leading -
        #   type    = flag | value | enum
        # var: = shell variable that will be set
        #   help    = help string for auto-generated --help output
        #   choices = for enum: comma-separated values (e.g. fast,slow,auto)
        #             for flag/value: leave empty
        #
        # Notes:
        #   - -h / --help is built in, you don't need to define it here.
        #   - After parsing you can use: FLAG_VERBOSE, VAL_CONFIG, ENUM_MODE, ...
    SGND_ARGS_SPEC=(
        "appcfg||value|VAL_APPCFG|Console module file or module directory|"
        "maxrows||value|VAL_MAXROWS|Maximum menu rows per page|"
        "title||value|VAL_TITLE|Override console title|"
    )

    # SGND_SCRIPT_EXAMPLES
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
        "Examples:"
        "  sgnd-console"
        "  sgnd-console --appcfg ./10-sgnd-config.sh"
        "  sgnd-console --appcfg ./20-machine-config.sh"
    ) 

    # SGND_SCRIPT_GLOBALS
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

    # SGND_STATE_VARIABLES
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
        SGND_PAGE_MAX_ROWS
    )

    # SGND_ON_EXIT_HANDLERS
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
    
    # State persistence is opt-in.
        # Scripts that want persistent state must:
        #   1) set SGND_STATE_SAVE=1
        #   2) call sgnd_bootstrap --state
    SGND_STATE_SAVE=1

# --- Local scripts and definitions ---------------------------------------------------
    # --- Console state
        SGND_GROUP_SCHEMA="key|label|desc|source|builtin|visible|ord"
        declare -ag SGND_GROUP_ROWS=()

        SGND_ITEM_SCHEMA="key|group|label|handler|desc|source|builtin|waitsecs|visible"
        declare -ag SGND_ITEM_ROWS=()

        SGND_MODULE_SCHEMA="id|name|version|desc|source"
        declare -ag SGND_MODULE_ROWS=()

        SGND_PAGE_SCHEMA="id|name|desc|source|loaded"
        declare -ag SGND_CONSOLE_PAGE_ROWS=()
        declare -Ag SGND_CONSOLE_LOADED_MODULES=()
        SGND_CONSOLE_VIEW="index"
        SGND_CONSOLE_ACTIVE_PAGE=""
        SGND_MENU_ACTIVE_SOURCE=""

        SGND_CONSOLE_TITLE=""
        SGND_CONSOLE_DESC=""
        SGND_CONSOLE_BIN_DIRECTORY=""
        SGND_CONSOLE_SBIN_DIRECTORY=""
        SGND_CONSOLE_LIBEXEC_DIRECTORY=""
        SGND_CONSOLE_DEFAULT_MODULE_DIRECTORY=""
        SGND_CONSOLE_MODULE_PATH=""
        SGND_CONSOLE_APP_ROOT=""
        SGND_CONSOLE_APP_BIN_DIRECTORY=""
        SGND_CONSOLE_APP_SBIN_DIRECTORY=""
        SGND_CONSOLE_APP_LIBEXEC_DIRECTORY=""
        SGND_CONSOLE_MODULE_STATE_FILE=""
        SGND_CONSOLE_ACTION_STATE_FILE=""
        SGND_CONSOLE_SUCCESS_TTL_DAYS=7
        SGND_CURRENT_MODULE=""
        SGND_LAST_WAITSECS=15
        declare -ag SGND_CONSOLE_ORIGINAL_ARGS=()

        declare -ag SGND_VISIBLE_ITEM_INDEXES=()
        declare -ag SGND_GROUP_RENDER_INDEXES=()

        SGND_CONSOLE_MODEL_CACHE_GROUP_COUNT=-1
        SGND_CONSOLE_MODEL_CACHE_ITEM_COUNT=-1
        SGND_CONSOLE_MODEL_CACHE_GENERATION=0
        SGND_CONSOLE_GROUP_INDEX_CACHE_GENERATION=-1
        SGND_CONSOLE_VISIBLE_INDEX_CACHE_GENERATION=0
        SGND_CONSOLE_VISIBLE_INDEX_CACHE_SIGNATURE=""
        SGND_CONSOLE_LABEL_WIDTH_CACHE_GENERATION=-1
        SGND_CONSOLE_LABEL_WIDTH_CACHE_VALUE=0
        declare -ag SGND_GROUP_CACHE_KEY=()
        declare -ag SGND_GROUP_CACHE_LABEL=()
        declare -ag SGND_GROUP_CACHE_BUILTIN=()
        declare -ag SGND_GROUP_CACHE_VISIBLE=()
        declare -ag SGND_GROUP_CACHE_ORD=()
        declare -Ag SGND_GROUP_CACHE_INDEX_BY_KEY=()
        declare -ag SGND_ITEM_CACHE_KEY=()
        declare -ag SGND_ITEM_CACHE_GROUP=()
        declare -ag SGND_ITEM_CACHE_LABEL=()
        declare -ag SGND_ITEM_CACHE_HANDLER=()
        declare -ag SGND_ITEM_CACHE_DESC=()
        declare -ag SGND_ITEM_CACHE_BUILTIN=()
        declare -ag SGND_ITEM_CACHE_WAITSECS=()
        declare -ag SGND_ITEM_CACHE_VISIBLE=()

        SGND_CLEAR_ONRENDER=1

        SGND_PAGE_INDEX=0
        declare -ag SGND_PAGE_STARTS=()
        declare -ag SGND_PAGE_ROW_OFFSETS=()
        declare -ag SGND_PAGE_ROW_COUNTS=()
        declare -ag SGND_PAGE_ROWS=()
        declare -ag SGND_PAGE_GROUP_OFFSETS=()
        declare -ag SGND_PAGE_GROUP_COUNTS=()
        declare -ag SGND_PAGE_GROUPS=()
        SGND_CONSOLE_LAYOUT_CACHE_KEY=""
        SGND_PAGE_HAS_PREV=0
        SGND_PAGE_HAS_NEXT=0
        : "${SGND_PAGE_MAX_ROWS:=25}"
            
    # --- Console state ownership -----------------------------------------------------
    # fn: _sgnd_console_state_owner - Resolve the user that should own console state
        # . Purpose
        #   Keep per-user console state owned by the invoking standard user when the
        #   console is temporarily relaunched with root access through sudo.
        #
        # . Output
        #   Writes the target user name to stdout.
        #
        # . Returns
        #   0 when a user name is resolved.
        # . Usage
        #   _sgnd_console_state_owner
    _sgnd_console_state_owner() {
        if (( EUID == 0 )) && [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            printf '%s\n' "$SUDO_USER"
            return 0
        fi

        id -un
    }

    # fn: _sgnd_console_prepare_state_directory - Ensure a writable per-user state directory
        # . Arguments
        #   $1  DIRECTORY - State directory to prepare.
        #
        # . Returns
        #   0 when the directory is ready; non-zero on failure.
        # . Usage
        #   _sgnd_console_prepare_state_directory "<directory>"
    _sgnd_console_prepare_state_directory() {
        local directory="${1:?missing state directory}"
        local owner=""
        local group=""

        mkdir -p -- "$directory" || return 1

        if (( EUID == 0 )) && [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            owner="$(_sgnd_console_state_owner)" || return 1
            group="$(id -gn "$owner" 2>/dev/null)" || return 1
            chown "$owner:$group" "$directory" || return 1
        fi

        chmod 0700 "$directory" || return 1
    }

    # fn: _sgnd_console_finalize_state_file - Normalize ownership and permissions of a state file
        # . Arguments
        #   $1  FILE - State file that was just created or replaced.
        #
        # . Returns
        #   0 when ownership and mode are correct; non-zero on failure.
        # . Usage
        #   _sgnd_console_finalize_state_file "<file>"
    _sgnd_console_finalize_state_file() {
        local file="${1:?missing state file}"
        local owner=""
        local group=""

        [[ -e "$file" ]] || return 0
        chmod 0600 "$file" || return 1

        if (( EUID == 0 )) && [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
            owner="$(_sgnd_console_state_owner)" || return 1
            group="$(id -gn "$owner" 2>/dev/null)" || return 1
            chown "$owner:$group" "$file" || return 1
        fi
    }

    # --- Console paths ---------------------------------------------------------------
    # _sgnd_console_init_paths
        # . Purpose
        #   Derive console host paths from SGND_FRAMEWORK_ROOT.
        #
        # . Returns
        #   0 on success; 1 when SGND_FRAMEWORK_ROOT is unavailable.
        #
        # . Usage
        #   _sgnd_console_init_paths || return $?
    _sgnd_console_init_paths() {
        [[ -n "${SGND_FRAMEWORK_ROOT:-}" ]] || {
            sayfail "SGND_FRAMEWORK_ROOT is not initialized"
            return 1
        }

        SGND_CONSOLE_BIN_DIRECTORY="${SGND_FRAMEWORK_ROOT%/}/usr/local/bin"
        SGND_CONSOLE_SBIN_DIRECTORY="${SGND_FRAMEWORK_ROOT%/}/usr/local/sbin"
        SGND_CONSOLE_LIBEXEC_DIRECTORY="${SGND_FRAMEWORK_ROOT%/}/usr/local/libexec/solidgroundux"
        SGND_CONSOLE_DEFAULT_MODULE_DIRECTORY="${SGND_CONSOLE_LIBEXEC_DIRECTORY%/}/console-modules"
        SGND_CONSOLE_MODULE_STATE_FILE="${SGND_STATE_DIR%/}/console-modules.state"
        SGND_CONSOLE_ACTION_STATE_FILE="${SGND_STATE_DIR%/}/console-actions.state"

        _sgnd_console_prepare_state_directory "$SGND_STATE_DIR" || return 1
        _sgnd_console_finalize_state_file "$SGND_CONSOLE_MODULE_STATE_FILE" || return 1
        _sgnd_console_finalize_state_file "$SGND_CONSOLE_ACTION_STATE_FILE" || return 1
    }

    # --- Console application context -------------------------------------------------
    # fn$: _sgnd_console_resolve_app_root - Resolve the application root from a module source
        # . Purpose
        #   Derive the root of the management application tree independently from the
        #   SolidGroundUX framework root. This allows an installed management console to
        #   host modules and module-owned executables from a staged/development tree.
        #
        # . Behavior
        #   - Uses the normalized module file/directory path selected through --appcfg.
        #   - Uses the last usr, etc, or var path component as the application-tree marker,
        #     matching the framework locator convention.
        #   - Resolves /usr, /etc, or /var based application sources to root (/).
        #   - Resolves staged trees to the path prefix preceding that canonical component.
        #   - Falls back to SGND_FRAMEWORK_ROOT when no canonical component is present;
        #     this preserves support for arbitrary module-only directories.
        #
        # . Output
        #   Writes the resolved application root to stdout.
        #
        # . Usage
        #   SGND_CONSOLE_APP_ROOT="$(_sgnd_console_resolve_app_root "$module_path")"
    _sgnd_console_resolve_app_root() {
        local source_path="${1:?missing application module source}"
        local path_without_root=""
        local component=""
        local app_root=""
        local index=0
        local root_index=-1
        local -a path_parts=()

        source_path="$(readlink -f -- "$source_path" 2>/dev/null || printf '%s' "$source_path")"
        path_without_root="${source_path#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"

        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in
                usr|etc|var) root_index=$index ;;
            esac
        done

        if (( root_index < 0 )); then
            printf '%s\n' "${SGND_FRAMEWORK_ROOT:-/}"
            return 0
        fi

        if (( root_index == 0 )); then
            printf '/\n'
            return 0
        fi

        for (( index=0; index<root_index; index++ )); do
            app_root+="/${path_parts[$index]}"
        done

        printf '%s\n' "${app_root:-/}"
    }

    # fn: _sgnd_console_set_app_context - Initialize application-owned executable paths
        # . Purpose
        #   Establish the management-application root and executable locations from the
        #   active console module source without changing SGND_FRAMEWORK_ROOT.
        #
        # . Behavior
        #   - Keeps framework/runtime ownership and management-application ownership separate.
        #   - Makes module-owned bin, sbin, and libexec locations available to dispatchers.
        #   - Leaves presentation of DEV context to the console index renderer.
        #
        # . Usage
        #   _sgnd_console_set_app_context "$module_path"
    _sgnd_console_set_app_context() {
        local module_path="${1:?missing application module source}"

        SGND_CONSOLE_APP_ROOT="$(_sgnd_console_resolve_app_root "$module_path")"
        SGND_CONSOLE_APP_BIN_DIRECTORY="${SGND_CONSOLE_APP_ROOT%/}/usr/local/bin"
        SGND_CONSOLE_APP_SBIN_DIRECTORY="${SGND_CONSOLE_APP_ROOT%/}/usr/local/sbin"
        SGND_CONSOLE_APP_LIBEXEC_DIRECTORY="${SGND_CONSOLE_APP_ROOT%/}/usr/local/libexec/solidgroundux"

        saydebug "Framework root          : $SGND_FRAMEWORK_ROOT"
        saydebug "Console application root: $SGND_CONSOLE_APP_ROOT"
        saydebug "Application libexec     : $SGND_CONSOLE_APP_LIBEXEC_DIRECTORY"
    }

    # --- Console configuration -------------------------------------------------------
    # fn: _sgnd_console_load_config - Resolve the console module source
        # . Purpose
        #   Resolve the module file or directory used by this console instance.
        #
        # . Behavior
        #   - Without --appcfg, loads the standard console-modules directory beside
        #     management-console.sh.
        #   - With --appcfg pointing to a .sh file, loads only that module.
        #   - With --appcfg pointing to a directory, loads every .sh file in it.
        #   - Normalizes the selected path to an absolute path.
        #
        # Inputs (globals):
        #   VAL_APPCFG
        #   SGND_SCRIPT_DIR
        #
        # Outputs (globals):
        #   SGND_CONSOLE_MODULE_PATH
        #
        # . Returns
        #   0   success
        #   126 module source does not exist or is not a readable .sh file/directory
        #
        # . Usage
        #   _sgnd_console_load_config || return $?
    _sgnd_console_load_config() {
        local module_path="${VAL_APPCFG-}"

        : "${SGND_CONSOLE_TITLE:=${SGND_SCRIPT_TITLE}}"
        : "${SGND_CONSOLE_DESC:=${SGND_SCRIPT_DESCRIPTION:-$SGND_SCRIPT_DESC}}"
        : "${SGND_PAGE_MAX_ROWS:=25}"

        if [[ -n "${VAL_TITLE:-}" ]]; then
            SGND_CONSOLE_TITLE="$VAL_TITLE"
        fi

        if [[ -z "$module_path" ]]; then
            module_path="$SGND_CONSOLE_DEFAULT_MODULE_DIRECTORY"
        fi

        module_path="$(readlink -f -- "$module_path" 2>/dev/null || printf '%s' "$module_path")"

        if [[ -d "$module_path" ]]; then
            [[ -r "$module_path" ]] || {
                sayfail "Module directory is not readable: $module_path"
                return 126
            }
        elif [[ -f "$module_path" && "$module_path" == *.sh ]]; then
            [[ -r "$module_path" ]] || {
                sayfail "Module file is not readable: $module_path"
                return 126
            }
        else
            sayfail "Module source must be a .sh file or directory: $module_path"
            return 126
        fi

        SGND_CONSOLE_MODULE_PATH="$module_path"
        _sgnd_console_set_app_context "$SGND_CONSOLE_MODULE_PATH"

        saydebug "Console title      : $SGND_CONSOLE_TITLE"
        saydebug "Console desc       : $SGND_CONSOLE_DESC"
        saydebug "Module source      : $SGND_CONSOLE_MODULE_PATH"
    }

    # --- Action result tracking ------------------------------------------------------
    # fn: sgnd_console_action_status - Read persisted status for a menu action
        # . Usage
        #   sgnd_console_action_status "<item_key>"
    sgnd_console_action_status() {
        local item_key="${1:?missing item key}"
        local line=""
        local status="never"
        local timestamp="0"
        local now=""
        local max_age=""

        [[ -r "$SGND_CONSOLE_ACTION_STATE_FILE" ]] || { printf '%s\n' never; return 0; }
        line="$(awk -F'|' -v key="$item_key" '$1 == key { value=$0 } END { print value }' "$SGND_CONSOLE_ACTION_STATE_FILE")"
        [[ -n "$line" ]] || { printf '%s\n' never; return 0; }
        IFS='|' read -r _ status timestamp <<< "$line"

        if [[ "$status" == success && "$timestamp" =~ ^[0-9]+$ ]]; then
            now="$(date +%s)"
            max_age=$(( SGND_CONSOLE_SUCCESS_TTL_DAYS * 86400 ))
            if (( now - timestamp > max_age )); then
                status="never"
            fi
        fi

        printf '%s\n' "$status"
    }

    # fn: sgnd_console_record_action_result - Persist and display an action result
        # . Usage
        #   sgnd_console_record_action_result "<item_key>" "<rc>"
    sgnd_console_record_action_result() {
        local item_key="${1:?missing item key}"
        local rc="${2:-1}"
        local status="failed"
        local timestamp="$(date +%s)"
        local state_dir=""
        local temp_file=""

        case "$rc" in
            0) status="success" ;;
            2) status="warning" ;;
            *) status="failed" ;;
        esac

        state_dir="$(dirname -- "$SGND_CONSOLE_ACTION_STATE_FILE")"
        _sgnd_console_prepare_state_directory "$state_dir" || return 1
        temp_file="$(mktemp "${TMPDIR:-/tmp}/management-console-actions.XXXXXX")" || return 1

        if [[ -r "$SGND_CONSOLE_ACTION_STATE_FILE" ]]; then
            awk -F'|' -v key="$item_key" '$1 != key { print }' "$SGND_CONSOLE_ACTION_STATE_FILE" > "$temp_file" || {
                rm -f -- "$temp_file"
                return 1
            }
        fi

        printf '%s|%s|%s\n' "$item_key" "$status" "$timestamp" >> "$temp_file" || {
            rm -f -- "$temp_file"
            return 1
        }
        mv -f -- "$temp_file" "$SGND_CONSOLE_ACTION_STATE_FILE" || return 1
        _sgnd_console_finalize_state_file "$SGND_CONSOLE_ACTION_STATE_FILE" || return 1
        sgnd_menu_set_item_status "$item_key" "$status" 2>/dev/null || true
        return 0
    }

    # fn: sgnd_console_run_tracked - Execute one registered action and track its result
        # . Usage
        #   sgnd_console_run_tracked "<item_key>" "<handler>"
    sgnd_console_run_tracked() {
        local item_key="${1:?missing item key}"
        local handler="${2:?missing handler}"
        shift 2
        local rc=0

        "$handler" "$@" || rc=$?
        sgnd_console_record_action_result "$item_key" "$rc" || true
        return "$rc"
    }

    # fn: _sgnd_console_execute_menu_item - Execute a menu item with console result tracking
        # . Purpose
        #   Execute menu actions through the console tracking layer while leaving
        #   builtin console controls untracked.
        #
        # . Arguments
        #   $1  ITEM_KEY - Registered menu item key.
        #   $2  HANDLER  - Registered handler function.
        #   $3  BUILTIN  - 1 for console builtin items, otherwise 0.
        #
        # . Returns
        #   Exit status from the executed handler.
        # . Usage
        #   _sgnd_console_execute_menu_item "<item_key>" "<handler>" "<builtin>"
    _sgnd_console_execute_menu_item() {
        local item_key="${1:?missing item key}"
        local handler="${2:?missing handler}"
        local builtin="${3:-0}"

        if (( builtin )); then
            "$handler"
            return $?
        fi

        sgnd_console_run_tracked "$item_key" "$handler"
    }

    # fn: _sgnd_console_refresh_action_statuses - Apply persisted statuses to menu items
        # . Usage
        #   _sgnd_console_refresh_action_statuses "<NR>"
    _sgnd_console_refresh_action_statuses() {
        local i
        local row_count="${#SGND_ITEM_ROWS[@]}"
        local key=""
        local builtin="0"
        local status=""

        for (( i=0; i<row_count; i++ )); do
            key="$(sgnd_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"
            builtin="$(sgnd_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"
            (( builtin )) && continue
            status="$(sgnd_console_action_status "$key")"
            sgnd_menu_set_item_status "$key" "$status" || true
        done
    }

    # fn: _sgnd_console_reset_page_results - Clear tracked action results for the active management page
        # . Purpose
        #   Reset the persisted last-run status for every non-builtin action belonging
        #   to the currently active management page.
        #
        # . Behavior
        #   - Removes matching action rows from the console action-state file.
        #   - Resets the corresponding in-memory menu status to never.
        #   - Leaves result state for all other management pages untouched.
        #   - Performs no configuration or business-logic changes.
        #
        # . Returns
        #   0 when reset or when no module page is active.
        #   1 when the action-state file cannot be rewritten.
        #
        # . Usage
        #   _sgnd_console_reset_page_results
    _sgnd_console_reset_page_results() {
        local active_source="${SGND_MENU_ACTIVE_SOURCE:-}"
        local i=0
        local row_count="${#SGND_ITEM_ROWS[@]}"
        local key=""
        local source=""
        local builtin="0"
        local state_dir=""
        local temp_file=""
        local key_file=""
        local reset_count=0

        [[ "$SGND_CONSOLE_VIEW" == "module" && -n "$active_source" ]] || return 0

        state_dir="$(dirname -- "$SGND_CONSOLE_ACTION_STATE_FILE")"
        _sgnd_console_prepare_state_directory "$state_dir" || return 1

        key_file="$(mktemp "${TMPDIR:-/tmp}/management-console-reset-keys.XXXXXX")" || return 1
        temp_file="$(mktemp "${TMPDIR:-/tmp}/management-console-actions.XXXXXX")" || {
            rm -f -- "$key_file"
            return 1
        }

        for (( i=0; i<row_count; i++ )); do
            builtin="$(sgnd_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" builtin)"
            (( builtin )) && continue

            source="$(sgnd_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" source)"
            [[ "$source" == "$active_source" ]] || continue

            key="$(sgnd_dt_get "$SGND_ITEM_SCHEMA" SGND_ITEM_ROWS "$i" key)"
            printf '%s\n' "$key" >> "$key_file"
            sgnd_menu_set_item_status "$key" "never" 2>/dev/null || true
            reset_count=$(( reset_count + 1 ))
        done

        if (( reset_count > 0 )) && [[ -r "$SGND_CONSOLE_ACTION_STATE_FILE" ]]; then
            awk -F'|' '
                NR==FNR { reset[$1]=1; next }
                !($1 in reset) { print }
            ' "$key_file" "$SGND_CONSOLE_ACTION_STATE_FILE" > "$temp_file" || {
                rm -f -- "$key_file" "$temp_file"
                return 1
            }

            mv -f -- "$temp_file" "$SGND_CONSOLE_ACTION_STATE_FILE" || {
                rm -f -- "$key_file" "$temp_file"
                return 1
            }
            _sgnd_console_finalize_state_file "$SGND_CONSOLE_ACTION_STATE_FILE" || {
                rm -f -- "$key_file"
                return 1
            }
        else
            rm -f -- "$temp_file"
        fi

        rm -f -- "$key_file"

        SGND_CONSOLE_LAYOUT_CACHE_KEY=""
        SGND_CONSOLE_LABEL_WIDTH_CACHE_SIGNATURE=""
        SGND_LAST_WAITSECS=0
        return 0
    }

    # --- Built-in menu registration -------------------------------------------------
    # fn: _sgnd_console_register_builtin_items - Register host-owned navigation items
        # . Purpose
        #   Add the hidden previous/next page controls used by the menu dispatcher.
        #
        # . Returns
        #   0 when both built-in navigation items are registered; non-zero on failure.
        #
        # . Usage
        #   _sgnd_console_register_builtin_items
    _sgnd_console_register_builtin_items() {
        SGND_GROUP_NAVIGATION="navigation"
        sgnd_menu_register_group "$SGND_GROUP_NAVIGATION" "Navigation" "" 1 0 990
        sgnd_menu_register_item "<" "$SGND_GROUP_NAVIGATION" "Previous page" "_sgnd_console_prevpage" "Show previous menu page" 1 0 0
        sgnd_menu_register_item ">" "$SGND_GROUP_NAVIGATION" "Next page" "_sgnd_console_nextpage" "Show next menu page" 1 0 0
    }


    # fn: _sgnd_console_register_fallback_group - Register fallback console group
        # . Purpose
        #   Register a fallback group for an item that references an unknown group key.
        #
        # . Behavior
        #   - Uses "Other" as the default fallback label.
        #   - For keys of the form "module:<id>", attempts to resolve the module
        #     name from SGND_MODULE_ROWS and uses that as the group label.
        #   - Registers the derived group as a non-builtin visible group.
        #
        # . Arguments
        #   $1  GROUP_KEY
        #       Missing group key to register.
        #
        # . Returns
        #   0 on success
        #   Non-zero if registration fails
        #
        # . Usage
        #   _sgnd_console_register_fallback_group "module:devtools"
        #
        # Examples:
        #   _sgnd_console_register_fallback_group "module:devtools"
    _sgnd_console_register_fallback_group() {
        local key="${1:?missing group key}"
        local label="Other"
        local module_id=""
        local module_name=""
        local i
        local row_count=0

        case "$key" in
            module:*)
                module_id="${key#module:}"
                row_count="$(sgnd_dt_row_count SGND_MODULE_ROWS)"

                for (( i=0; i<row_count; i++ )); do
                    if [[ "$(sgnd_dt_get "$SGND_MODULE_SCHEMA" SGND_MODULE_ROWS "$i" id)" == "$module_id" ]]; then
                        module_name="$(sgnd_dt_get "$SGND_MODULE_SCHEMA" SGND_MODULE_ROWS "$i" name)"
                        break
                    fi
                done

                if [[ -n "${module_name//[[:space:]]/}" ]]; then
                    label="$module_name"
                else
                    label="$module_id"
                fi
                ;;
        esac

        sgnd_menu_register_group "$key" "$label" "" 0 1 800
    }

    # fn: _sgnd_console_group_exists - Test whether a console group exists
        # . Purpose
        #   Test whether a group key already exists in the console group model.
        #
        # . Arguments
        #   $1  GROUP_KEY
        #       Group key to test.
        #
        # . Returns
        #   0 if the group exists
        #   1 if the group does not exist
        #
        # . Usage
        #   _sgnd_console_group_exists "runtime" && printf 'Group exists\n'
        #
        # Examples:
        #   _sgnd_console_group_exists "runtime"
    _sgnd_console_group_exists() {
        local key="${1:?missing group key}"

        sgnd_dt_has_row "$SGND_GROUP_SCHEMA" SGND_GROUP_ROWS key "$key"
    }

    # fn: _sgnd_console_show_module_metadata - Show metadata for discovered console modules
        # . Purpose
        #   Display lightweight metadata for every console module present in the configured
        #   module source without sourcing module implementations.
        #
        # . Behavior
        #   - Available only from a root console session.
        #   - Discovers all module files, including modules not yet lazy-loaded and modules
        #     currently hidden from the console index.
        #   - Displays ID, name, version, description, visibility state, and source file.
        #
        # . Returns
        #   0 after displaying metadata; 126 when not running as root or discovery fails.
        # . Usage
        #   _sgnd_console_show_module_metadata
    _sgnd_console_show_module_metadata() {
        local i=0
        local module_count=0
        local module_file=""
        local module_id=""
        local module_name=""
        local module_version=""
        local module_build=""
        local module_desc=""
        local module_state=""
        local render_width="${SGND_MENU_RENDER_WIDTH:-$(sgnd_terminal_width)}"
        local -a module_files=()

        (( EUID == 0 )) || {
            saywarning "Module metadata is available only from a root console session."
            return 126
        }

        mapfile -t module_files < <(_sgnd_console_discover_module_files) || return $?
        module_count="${#module_files[@]}"

        sgnd_clear
        _sgnd_console_render_menu_title
        sgnd_print "$(sgnd_sgr "$SGND_UI_TEXT" "" "$FX_BOLD")Module metadata${RESET}"
        sgnd_print_sectionheader --border "$LN_H" --maxwidth "$render_width"
        sgnd_print

        if (( module_count == 0 )); then
            sgnd_print_labeledvalue --label "Present modules" --value "None" --labelwidth 18
        else
            sgnd_print_labeledvalue --label "Present modules" --value "$module_count" --labelwidth 18
            sgnd_print

            for (( i=0; i<module_count; i++ )); do
                module_file="${module_files[$i]}"
                module_id="$(_sgnd_console_module_id_from_filename "$module_file")"
                _sgnd_console_module_metadata "$module_file" module_name module_desc module_version module_build
                module_state="$(_sgnd_console_module_state_get "$module_id")"

                sgnd_print_sectionheader "$module_name"
                sgnd_print_labeledvalue --label "ID" --value "$module_id" --labelwidth 18
                if [[ -n "$module_build" ]]; then
                    module_version="${module_version:--} (${module_build})"
                fi
                sgnd_print_labeledvalue --label "Version" --value "${module_version:--}" --labelwidth 18
                sgnd_print_labeledvalue --label "Description" --value "$module_desc" --labelwidth 18
                sgnd_print_labeledvalue --label "Visibility" --value "${module_state^}" --labelwidth 18
                sgnd_print_labeledvalue --label "Source" --value "$module_file" --labelwidth 18
                sgnd_print
            done
        fi

        ask_dlg_autocontinue \
            --seconds 15 \
            --message "" \
            --cancel \
            --pause || true
        SGND_LAST_WAITSECS=0
        return 0
    }

    # --- Module visibility ----------------------------------------------------------
    # fn$: _sgnd_console_module_id_from_filename - Derive module ID from filename
        # . Returns
        #   0 after writing the normalized module ID to stdout.
        #
        # . Usage
        #   _sgnd_console_module_id_from_filename "20-active-directory.sh"
    _sgnd_console_module_id_from_filename() {
        local module_name=""

        module_name="$(basename -- "${1:?missing module file}")"
        module_name="${module_name%.sh}"
        module_name="${module_name#[0-9][0-9]-}"
        printf '%s\n' "$module_name"
    }

    # fn$: _sgnd_console_module_state_get - Read module visibility state
        # . Returns
        #   Writes enabled or disabled. Missing entries default to enabled.
        #
        # . Usage
        #   _sgnd_console_module_state_get "active-directory"
    _sgnd_console_module_state_get() {
        local module_id="${1:?missing module ID}"
        local state=""

        if [[ -r "$SGND_CONSOLE_MODULE_STATE_FILE" ]]; then
            state="$(awk -F= -v id="$module_id" '$1 == id { value=$2 } END { print value }' "$SGND_CONSOLE_MODULE_STATE_FILE")"
        fi

        case "$state" in
            disabled) printf '%s\n' "disabled" ;;
            *)        printf '%s\n' "enabled" ;;
        esac
    }

    # fn$: _sgnd_console_module_enabled - Test whether a module is enabled
        # . Returns
        #   0 when enabled or unspecified; 1 when explicitly disabled.
        #
        # . Usage
        #   _sgnd_console_module_enabled "active-directory"
    _sgnd_console_module_enabled() {
        local module_id="${1:?missing module ID}"
        [[ "$(_sgnd_console_module_state_get "$module_id")" == "enabled" ]]
    }

    # fn: _sgnd_console_module_state_set - Persist module visibility state
        # . Purpose
        #   Save one module's enabled/disabled state without sourcing that module.
        #
        # . Arguments
        #   $1  MODULE_ID - Filename-derived console module ID.
        #   $2  STATE     - Either enabled or disabled.
        #
        # Side effects:
        #   Rewrites SGND_CONSOLE_MODULE_STATE_FILE atomically.
        #
        # . Returns
        #   0 when the state file is updated; 1 on filesystem failure; 2 for an invalid state.
        #
        # . Usage
        #   _sgnd_console_module_state_set "storage" "disabled"
    _sgnd_console_module_state_set() {
        local module_id="${1:?missing module ID}"
        local state="${2:?missing module state}"
        local state_dir=""
        local temp_file=""

        case "$state" in
            enabled|disabled) ;;
            *) return 2 ;;
        esac

        state_dir="$(dirname -- "$SGND_CONSOLE_MODULE_STATE_FILE")"
        _sgnd_console_prepare_state_directory "$state_dir" || return 1
        temp_file="$(mktemp "${SGND_CONSOLE_MODULE_STATE_FILE}.XXXXXX")" || return 1

        if [[ -r "$SGND_CONSOLE_MODULE_STATE_FILE" ]]; then
            awk -F= -v id="$module_id" '$1 != id { print }' "$SGND_CONSOLE_MODULE_STATE_FILE" > "$temp_file" || {
                rm -f -- "$temp_file"
                return 1
            }
        fi

        printf '%s=%s\n' "$module_id" "$state" >> "$temp_file" || {
            rm -f -- "$temp_file"
            return 1
        }

        mv -f -- "$temp_file" "$SGND_CONSOLE_MODULE_STATE_FILE" || return 1
        _sgnd_console_finalize_state_file "$SGND_CONSOLE_MODULE_STATE_FILE"
    }

    # fn: _sgnd_console_manage_visibility - Manage index-page module visibility
        # . Purpose
        #   Let a root console session enable or disable discovered management pages.
        #
        # . Behavior
        #   - Discovers all module files, including modules currently hidden from the index.
        #   - Shows each module by its literal display name and current persisted state.
        #   - Toggles the selected module between enabled and disabled.
        #   - Does not source module implementation code.
        #   - The caller rebuilds the lightweight index immediately after this dialog returns.
        #
        # . Returns
        #   0 when the user returns; 1 on discovery or state-write failure; 126 when not root.
        #
        # . Usage
        #   _sgnd_console_manage_visibility
    _sgnd_console_manage_visibility() {
        local choice=""
        local module=""
        local module_id=""
        local module_name=""
        local module_desc=""
        local state=""
        local next_state=""
        local i=0
        local key_width=1
        local rendered_key=""
        local context_shown=0
        local context_style=""
        local -a module_files=()
        local -a module_ids=()

        (( EUID == 0 )) || {
            saywarning "Module visibility can only be changed from a root console session."
            return 126
        }

        mapfile -t module_files < <(_sgnd_console_discover_module_files) || return $?
        (( ${#module_files[@]} > 0 )) || {
            saywarning "No console modules were found."
            return 0
        }

        key_width="${#module_files[@]}"
        (( key_width < 1 )) && key_width=1

        while true; do
            module_ids=()
            sgnd_clear
            _sgnd_console_render_menu_title
            sgnd_print "$(sgnd_sgr "$SGND_UI_TEXT" "" "$FX_BOLD")Manage visibility${RESET}"
            sgnd_print_sectionheader --border "$LN_H" --maxwidth "${SGND_MENU_RENDER_WIDTH:-$(sgnd_terminal_width)}"
            sgnd_print

            for i in "${!module_files[@]}"; do
                module="${module_files[$i]}"
                module_id="$(_sgnd_console_module_id_from_filename "$module")"
                _sgnd_console_module_metadata "$module" module_name module_desc
                state="$(_sgnd_console_module_state_get "$module_id")"
                module_ids+=("$module_id")
                printf -v rendered_key '%*d' "$key_width" "$((i + 1))"
                sgnd_print_labeledvalue \
                    --label "${rendered_key}) $module_name" \
                    --value "${state^}" \
                    --labelwidth 34
            done

            sgnd_print
            sgnd_print_sectionheader --border "$LN_H" --maxwidth "${SGND_MENU_RENDER_WIDTH:-$(sgnd_terminal_width)}"
            sgnd_print "Q) Return"
            printf '%sSelect option%s : ' "$(sgnd_sgr "$SGND_UI_LABEL")" "$RESET" >/dev/tty
            SGND_LAST_WAITSECS=0
            sgnd_menu_read_choice choice || return $?

            case "$choice" in
                EXIT|ESC) return 0 ;;
            esac

            if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
                saywarning "Invalid selection: $choice"
                continue
            fi

            local choice_number=$((10#$choice))
            if (( choice_number < 1 || choice_number > ${#module_ids[@]} )); then
                saywarning "Invalid selection: $choice"
                continue
            fi

            module_id="${module_ids[$((choice_number - 1))]}"
            state="$(_sgnd_console_module_state_get "$module_id")"
            if [[ "$state" == "enabled" ]]; then
                next_state="disabled"
            else
                next_state="enabled"
            fi

            _sgnd_console_module_state_set "$module_id" "$next_state" || {
                sayfail "Could not update module visibility for $module_id"
                return 1
            }
        done
    }

    # fn$: _sgnd_console_discover_module_files - Discover configured module files
        # . Returns
        #   Writes sorted module paths to stdout.
        #
        # . Usage
        #   mapfile -t modules < <(_sgnd_console_discover_module_files)
    _sgnd_console_discover_module_files() {
        local module_path="${SGND_CONSOLE_MODULE_PATH:?missing module source}"

        if [[ -f "$module_path" ]]; then
            printf '%s\n' "$module_path"
            return 0
        fi

        [[ -d "$module_path" ]] || return 126
        find "$module_path" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z | tr '\0' '\n'
    }

    # fn: _sgnd_console_module_metadata - Read module metadata without sourcing the module
        # . Purpose
        #   Read lightweight page identity plus canonical header version and description.
        #
        # . Arguments
        #   $1  MODULE_FILE - Console module file.
        #   $2  OUTPUT_NAME - Variable receiving the display name.
        #   $3  OUTPUT_DESC - Variable receiving the canonical Description section.
        #   $4  OUTPUT_VERSION - Optional variable receiving Metadata/Version.
        #   $5  OUTPUT_BUILD - Optional variable receiving Metadata/Build.
        #
        # . Returns
        #   0 after producing metadata, using a filename-derived name fallback when needed.
        #
        # . Usage
        #   _sgnd_console_module_metadata "$module" name desc version build
    _sgnd_console_module_metadata() {
        local module_file="${1:?missing module file}"
        local output_name="${2:?missing name output variable}"
        local output_desc="${3:?missing description output variable}"
        local output_version="${4:-}"
        local output_build="${5:-}"
        local module_id=""
        local name=""
        local version=""
        local build=""
        local desc=""
        local fallback=""

        name="$(sed -nE 's/^[[:space:]]*[A-Z0-9_]+_MODULE_NAME="([^"]*)"[[:space:]]*$/\1/p' "$module_file" | head -n 1)"
        sgnd_header_get_field "$module_file" "Metadata" "Version" version || version=""
        sgnd_header_get_field "$module_file" "Metadata" "Build" build || build=""
        sgnd_header_get_section "$module_file" "Description" desc || desc=""
        desc="$(printf '%s\n' "$desc" | awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); printf "%s%s", sep, $0; sep=" " } END { print "" }')"

        if [[ -z "$name" ]]; then
            module_id="$(_sgnd_console_module_id_from_filename "$module_file")"
            fallback="${module_id//-/ }"
            name="$(printf '%s\n' "$fallback" | awk '{ for (i=1; i<=NF; i++) $i=toupper(substr($i,1,1)) substr($i,2); print }')"
            [[ "$module_id" == "solidgroundux" ]] && name="SolidGroundUX"
        fi

        printf -v "$output_name" '%s' "$name"
        printf -v "$output_desc" '%s' "$desc"
        [[ -n "$output_version" ]] && printf -v "$output_version" '%s' "$version"
        [[ -n "$output_build" ]] && printf -v "$output_build" '%s' "$build"
    }

    # fn: _sgnd_console_register_pages - Build the lightweight startup page index
        # . Purpose
        #   Discover enabled module files and register page metadata without sourcing them.
        #
        # . Behavior
        #   - Keeps startup work limited to file discovery and literal metadata reads.
        #   - Honors persisted module enabled/disabled state.
        #   - Defers module parsing and menu registration until the page is opened.
        #
        # . Returns
        #   0 on success; discovery errors are propagated.
        #
        # . Usage
        #   _sgnd_console_register_pages || return $?
    _sgnd_console_register_pages() {
        local module=""
        local module_id=""
        local module_name=""
        local module_desc=""
        local -a discovered_files=()

        SGND_CONSOLE_PAGE_ROWS=()
        mapfile -t discovered_files < <(_sgnd_console_discover_module_files) || return $?

        for module in "${discovered_files[@]}"; do
            module_id="$(_sgnd_console_module_id_from_filename "$module")"
            _sgnd_console_module_enabled "$module_id" || continue
            _sgnd_console_module_metadata "$module" module_name module_desc
            sgnd_dt_append "$SGND_PAGE_SCHEMA" SGND_CONSOLE_PAGE_ROWS \
                "$module_id" "$module_name" "$module_desc" "$module" "0" || return $?
        done

        return 0
    }

    # fn: _sgnd_console_open_page - Lazy-load and activate one registered module page
        # . Purpose
        #   Source a module the first time its index page is selected and activate its menu rows.
        #
        # . Arguments
        #   $1  PAGE_INDEX - Zero-based row index in SGND_CONSOLE_PAGE_ROWS.
        #
        # . Returns
        #   0 on success; 1 for an invalid page; 126 when module loading fails.
        #
        # . Usage
        #   _sgnd_console_open_page 0
    _sgnd_console_open_page() {
        local page_index="${1:?missing page index}"
        local page_count="${#SGND_CONSOLE_PAGE_ROWS[@]}"
        local module_id=""
        local module_file=""
        local module_source=""

        (( page_index >= 0 && page_index < page_count )) || return 1
        module_id="$(sgnd_dt_get "$SGND_PAGE_SCHEMA" SGND_CONSOLE_PAGE_ROWS "$page_index" id)"
        module_file="$(sgnd_dt_get "$SGND_PAGE_SCHEMA" SGND_CONSOLE_PAGE_ROWS "$page_index" source)"
        module_source="$(basename -- "$module_file" .sh)"

        if [[ "${SGND_CONSOLE_LOADED_MODULES[$module_id]:-0}" != "1" ]]; then
            _sgnd_console_source_module "$module_file" || return 126
            SGND_CONSOLE_LOADED_MODULES["$module_id"]=1
            _sgnd_console_refresh_action_statuses
        fi

        SGND_CONSOLE_ACTIVE_PAGE="$module_id"
        SGND_MENU_ACTIVE_SOURCE="$module_source"
        SGND_CONSOLE_VIEW="module"
        SGND_PAGE_INDEX=0
        SGND_CONSOLE_GROUP_INDEX_CACHE_GENERATION=-1
        SGND_CONSOLE_VISIBLE_INDEX_CACHE_SIGNATURE=""
        return 0
    }

    # fn: _sgnd_console_show_index - Render the lightweight module index page
        # . Purpose
        #   Show all enabled console pages without loading their implementation modules.
        #
        # . Returns
        #   0 after rendering.
        #
        # . Usage
        #   _sgnd_console_show_index
    _sgnd_console_show_index() {
        local i=0
        local page_count="${#SGND_CONSOLE_PAGE_ROWS[@]}"
        local name=""
        local desc=""
        local left_text=""
        local wrapped_line=""
        local first_line=1
        local left_width_max=28
        local term_width=80
        local desc_width=0
        local candidate_width=0
        local gap=3
        local tpad=3
        local label_style=""
        local value_style=""
        local key_width=1
        local rendered_key=""

        term_width="${SGND_MENU_RENDER_WIDTH:-$(sgnd_terminal_width)}"
        key_width="${#page_count}"
        (( key_width < 1 )) && key_width=1

        # The lightweight console index is rendered outside the normal sgnd-menu
        # item model, so determine its label column from the page names directly.
        for (( i=0; i<page_count; i++ )); do
            name="$(sgnd_dt_get "$SGND_PAGE_SCHEMA" SGND_CONSOLE_PAGE_ROWS "$i" name)"
            printf -v rendered_key '%*d' "$key_width" "$((i + 1))"
            left_text="${rendered_key}) · $name"
            candidate_width="$(sgnd_visible_length "$left_text")"
            (( candidate_width > left_width_max )) && left_width_max="$candidate_width"
        done

        if (( EUID == 0 )); then
            candidate_width="$(sgnd_visible_length "V) · Manage visibility")"
            (( candidate_width > left_width_max )) && left_width_max="$candidate_width"
            candidate_width="$(sgnd_visible_length "M) · Module metadata")"
            (( candidate_width > left_width_max )) && left_width_max="$candidate_width"
        fi

        (( left_width_max > 45 )) && left_width_max=45

        desc_width=$(( term_width - tpad - left_width_max - gap ))
        (( desc_width < 20 )) && desc_width=20

        label_style="$(sgnd_sgr "$SGND_UI_LABEL")"
        value_style="$(sgnd_sgr "$SGND_UI_VALUE" "" "$FX_ITALIC")"

        _sgnd_console_render_menu_title

        context_style="$(sgnd_sgr "$SGND_UI_TEXT")"
        context_shown=0
        if [[ "${SGND_FRAMEWORK_ROOT:-/}" != "/" ]]; then
            sgnd_print "${context_style}Console host: ${MSG_CLR_WARN}DEV${RESET}"
            context_shown=1
        fi

        if [[ "${SGND_CONSOLE_APP_ROOT:-/}" != "/" ]]; then
            sgnd_print "${context_style}Console application: ${MSG_CLR_WARN}DEV${RESET}"
            context_shown=1
        fi

        (( context_shown )) && sgnd_print

        sgnd_print "$(sgnd_sgr "$SGND_UI_TEXT" "" "$FX_BOLD")Console pages${RESET}"
        sgnd_print_sectionheader --border "$LN_H" --maxwidth "$term_width"
        sgnd_print

        for (( i=0; i<page_count; i++ )); do
            name="$(sgnd_dt_get "$SGND_PAGE_SCHEMA" SGND_CONSOLE_PAGE_ROWS "$i" name)"
            desc="$(sgnd_dt_get "$SGND_PAGE_SCHEMA" SGND_CONSOLE_PAGE_ROWS "$i" desc)"
            printf -v rendered_key '%*d' "$key_width" "$((i + 1))"
            left_text="${rendered_key}) · $name"

            if [[ -z "$desc" ]]; then
                printf '%*s%s' "$tpad" "" "$label_style"
                sgnd_padded_visible "$left_text" "$left_width_max"
                printf '%s\n' "$RESET"
                continue
            fi

            first_line=1
            while IFS= read -r wrapped_line; do
                if (( first_line )); then
                    printf '%*s%s' "$tpad" "" "$label_style"
                    sgnd_padded_visible "$left_text" "$left_width_max"
                    printf '%s%*s%s%s%s\n' \
                        "$RESET" \
                        "$gap" "" \
                        "$value_style" "$wrapped_line" "$RESET"
                    first_line=0
                else
                    printf '%*s%*s%*s%s%s%s\n' \
                        "$tpad" "" \
                        "$left_width_max" "" \
                        "$gap" "" \
                        "$value_style" "$wrapped_line" "$RESET"
                fi
            done < <(sgnd_wrap_words --width "$desc_width" --text "$desc")
        done

        sgnd_print

        if (( EUID == 0 )); then
            sgnd_print "$(sgnd_sgr "$SGND_UI_TEXT" "" "$FX_BOLD")Console management${RESET}"
            sgnd_print_sectionheader --border "$LN_H" --maxwidth "$term_width"
            sgnd_print

            left_text="V) · Manage visibility"
            desc="Show or hide management-console pages"
            printf '%*s%s' "$tpad" "" "$label_style"
            sgnd_padded_visible "$left_text" "$left_width_max"
            printf '%s%*s%s%s%s\n' \
                "$RESET" \
                "$gap" "" \
                "$value_style" "$desc" "$RESET"

            left_text="M) · Module metadata"
            desc="Show metadata for all modules present in the configured module source"
            printf '%*s%s' "$tpad" "" "$label_style"
            sgnd_padded_visible "$left_text" "$left_width_max"
            printf '%s%*s%s%s%s\n' \
                "$RESET" \
                "$gap" "" \
                "$value_style" "$desc" "$RESET"
            sgnd_print
        fi
        
        _sgnd_console_render_togglebar
    }

    # --- Module loading -------------------------------------------------------------
    # fn: _sgnd_console_source_module - Source one console module
        # . Arguments
        #   $1  MODULE_FILE
        #       Readable .sh file to source.
        #
        # Outputs (globals):
        #   SGND_CURRENT_MODULE
        #   SGND_CURRENT_MODULE_DIR
        #
        # . Returns
        #   0 on success.
        #   126 when the module cannot be loaded.
        #
        # . Usage
        #   _sgnd_console_source_module "/usr/local/libexec/solidgroundux/console-modules/20-machine-config.sh"
    _sgnd_console_source_module() {
        local module_file="${1:?missing module file}"
        local module_id=""
        local module_name=""
        local module_version=""
        local module_desc=""
        local module_count=0

        unset SGND_MODULE_ID SGND_MODULE_NAME
        unset SGND_CONSOLE_TITLE_OVERRIDE SGND_CONSOLE_DESC_OVERRIDE
        SGND_CURRENT_MODULE="$(_sgnd_console_module_id_from_filename "$module_file")"
        SGND_CURRENT_MODULE_SOURCE="$(basename -- "$module_file" .sh)"
        SGND_CURRENT_MODULE_DIR="$(dirname "$module_file")"
        saydebug "Loading module: $module_file"

        # shellcheck source=/dev/null
        source "$module_file" || {
            sayfail "Failed to load module: $module_file"
            unset SGND_CURRENT_MODULE SGND_CURRENT_MODULE_SOURCE SGND_CURRENT_MODULE_DIR
            unset SGND_MODULE_ID SGND_MODULE_NAME
            unset SGND_CONSOLE_TITLE_OVERRIDE SGND_CONSOLE_DESC_OVERRIDE
            return 126
        }

        module_id="$(_sgnd_console_module_id_from_filename "$module_file")"
        module_name="${SGND_MODULE_NAME:-}"
        sgnd_header_get_field "$module_file" "Metadata" "Version" module_version || module_version=""
        sgnd_header_get_section "$module_file" "Description" module_desc || module_desc=""
        module_desc="$(printf '%s\n' "$module_desc" | awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); printf "%s%s", sep, $0; sep=" " } END { print "" }')"

        if [[ -z "$module_name" || -z "$module_version" || -z "$module_desc" ]]; then
            sayfail "Module metadata is incomplete: $module_file"
            unset SGND_CURRENT_MODULE SGND_CURRENT_MODULE_SOURCE SGND_CURRENT_MODULE_DIR
            unset SGND_MODULE_ID SGND_MODULE_NAME
            unset SGND_CONSOLE_TITLE_OVERRIDE SGND_CONSOLE_DESC_OVERRIDE
            return 126
        fi

        if sgnd_dt_has_row "$SGND_MODULE_SCHEMA" SGND_MODULE_ROWS id "$module_id"; then
            sayfail "Duplicate module ID rejected: $module_id"
            unset SGND_CURRENT_MODULE SGND_CURRENT_MODULE_SOURCE SGND_CURRENT_MODULE_DIR
            unset SGND_MODULE_ID SGND_MODULE_NAME
            unset SGND_CONSOLE_TITLE_OVERRIDE SGND_CONSOLE_DESC_OVERRIDE
            return 126
        fi

        module_count="$(sgnd_dt_row_count SGND_MODULE_ROWS)"
        if (( module_count == 0 )); then
            [[ -n "${SGND_CONSOLE_TITLE_OVERRIDE:-}" ]] && SGND_CONSOLE_TITLE="$SGND_CONSOLE_TITLE_OVERRIDE"
            [[ -n "${SGND_CONSOLE_DESC_OVERRIDE:-}" ]] && SGND_CONSOLE_DESC="$SGND_CONSOLE_DESC_OVERRIDE"
        fi

        sgnd_dt_append "$SGND_MODULE_SCHEMA" SGND_MODULE_ROWS \
            "$module_id" "$module_name" "$module_version" "$module_desc" "$module_file" || {
            sayfail "Failed to record module metadata: $module_id"
            unset SGND_CURRENT_MODULE SGND_CURRENT_MODULE_SOURCE SGND_CURRENT_MODULE_DIR
            unset SGND_MODULE_ID SGND_MODULE_NAME
            unset SGND_CONSOLE_TITLE_OVERRIDE SGND_CONSOLE_DESC_OVERRIDE
            return 126
        }

        unset SGND_CURRENT_MODULE SGND_CURRENT_MODULE_SOURCE SGND_CURRENT_MODULE_DIR
        unset SGND_MODULE_ID SGND_MODULE_NAME
        unset SGND_CONSOLE_TITLE_OVERRIDE SGND_CONSOLE_DESC_OVERRIDE
    }


# --- Script execution ----------------------------------------------------------------
    # fn: _sgnd_build_command_args - Build arguments for a public SolidGroundUX command
        # . Purpose
        #   Copy caller arguments into a target array and prepend --dryrun when the console
        #   is currently in dry-run mode.
        #
        # . Returns
        #   0 after populating the requested argument array.
        #
        # . Usage
        #   _sgnd_build_command_args command_args "$@"
    _sgnd_build_command_args() {
        local -n result_ref="${1:?missing result array}"
        shift

        result_ref=()
        _sgnd_flag_is_on "${FLAG_DRYRUN:-0}" && result_ref+=("--dryrun")
        result_ref+=("$@")
    }

    # fn: _sgnd_run_public_command - Resolve and run a SolidGroundUX public command
        # . Purpose
        #   Resolve a command from the console bin/sbin roots or PATH, propagate console
        #   dry-run state, and execute it with the supplied arguments.
        #
        # . Returns
        #   Exit status from the resolved command; 1 when the command cannot be found.
        #
        # . Usage
        #   _sgnd_run_public_command "framework-smoketest"
    _sgnd_run_public_command() {
        local command_name="${1:?missing command name}"
        shift || true
        local resolved=""
        local -a command_args=()

        if [[ -n "${SGND_CONSOLE_APP_BIN_DIRECTORY:-}" && -x "${SGND_CONSOLE_APP_BIN_DIRECTORY%/}/$command_name" ]]; then
            resolved="${SGND_CONSOLE_APP_BIN_DIRECTORY%/}/$command_name"
        elif [[ -n "${SGND_CONSOLE_APP_SBIN_DIRECTORY:-}" && -x "${SGND_CONSOLE_APP_SBIN_DIRECTORY%/}/$command_name" ]]; then
            resolved="${SGND_CONSOLE_APP_SBIN_DIRECTORY%/}/$command_name"
        elif [[ -x "${SGND_CONSOLE_BIN_DIRECTORY%/}/$command_name" ]]; then
            resolved="${SGND_CONSOLE_BIN_DIRECTORY%/}/$command_name"
        elif [[ -x "${SGND_CONSOLE_SBIN_DIRECTORY%/}/$command_name" ]]; then
            resolved="${SGND_CONSOLE_SBIN_DIRECTORY%/}/$command_name"
        else
            resolved="$(command -v -- "$command_name" 2>/dev/null || true)"
        fi

        [[ -n "$resolved" && -x "$resolved" ]] || {
            sayfail "Public command not found or not executable: $command_name"
            return 1
        }

        _sgnd_build_command_args command_args "$@"
        saydebug "Executing public command: $resolved ${command_args[*]}"
        "$resolved" "${command_args[@]}"
    }

    # _sgnd_run_module_script
        # . Purpose
        #   Locates and executes a console helper script from the canonical
        #   SolidGroundUX executable or library directories.
        #
        # . Arguments
        #   $1  Script filename.
        #   $@  Optional arguments passed to the script.
        #
        # . Returns
        #   Returns the exit status of the executed script.
        #   Returns 1 when the script cannot be found or is not executable.
        #
        # . Usage
        #   _sgnd_run_module_script "set-identity.sh"
        #   _sgnd_run_module_script "prepare-template.sh" --dryrun
    _sgnd_run_module_script() {
        local script_name="${1:?missing script name}"
        shift

        local resolved=""
        local candidate=""
        local -a search_directories=(
            "${SGND_CONSOLE_APP_LIBEXEC_DIRECTORY:-}"
            "$SGND_COMMON_EXE"
            "$SGND_COMMON_LIB"
        )
        local -a command_args=()

        [[ "$script_name" != */* ]] || {
            sayfail "Module script must be a filename: $script_name"
            return 1
        }

        for candidate in "${search_directories[@]}"; do
            [[ -n "$candidate" ]] || continue

            candidate="${candidate%/}/${script_name}"

            if [[ -f "$candidate" && -x "$candidate" ]]; then
                resolved="$candidate"
                break
            fi
        done

        if [[ -z "$resolved" ]]; then
            sayfail "Module script not found or not executable: $script_name"
            saydebug "Searched: ${search_directories[*]}"
            return 1
        fi

        _sgnd_build_command_args command_args "$@"

        saydebug "Executing module script: $resolved ${command_args[*]}"
        "$resolved" "${command_args[@]}"
    }

    # fn: _sgnd_console_open_shell - Open an interactive child shell
        # . Purpose
        #   Open a new interactive shell and return to the Management Console on exit.
        #
        # . Behavior
        #   - Uses the current user's configured shell when available.
        #   - Falls back to /bin/bash.
        #   - Inherits the current console privilege level and environment.
        #   - Does not replace the console process.
        #
        # . Usage
        #   _sgnd_console_open_shell
    _sgnd_console_open_shell() {
        local shell_path="${SHELL:-/bin/bash}"

        [[ -x "$shell_path" ]] || shell_path="/bin/bash"
        [[ -x "$shell_path" ]] || {
            sayfail "No usable interactive shell was found."
            return 1
        }

        sgnd_print "$SGND_UI_TEXT Opening $shell_path. Type 'exit' to return to the Management Console."
        "$shell_path" -i
        SGND_LAST_WAITSECS=0
    }


    # fn: _sgnd_console_toggle_access - Relaunch with the opposite privilege level
        # . Purpose
        #   Replace the current console process with a root or standard-access instance.
        #
        # . Behavior
        #   - Standard sessions relaunch through sudo.
        #   - Sessions started through sudo relaunch as the original SUDO_USER.
        #   - Direct root logins cannot infer a standard user and remain unchanged.
        #   - Preserves the current dry-run state and original console arguments.
        #
        # . Returns
        #   Does not return after a successful relaunch; returns 1 on failure.
        #
        # . Usage
        #   _sgnd_console_toggle_access
    _sgnd_console_toggle_access() {
        local arg=""
        local -a relaunch_args=()

        for arg in "${SGND_CONSOLE_ORIGINAL_ARGS[@]}"; do
            case "$arg" in
                --dryrun) ;;
                *) relaunch_args+=("$arg") ;;
            esac
        done

        _sgnd_flag_is_on "${FLAG_DRYRUN:-0}" && relaunch_args=("--dryrun" "${relaunch_args[@]}")

        if (( EUID != 0 )); then
            command -v sudo >/dev/null 2>&1 || {
                sayfail "sudo is unavailable; cannot switch to root access"
                return 1
            }

            sayinfo "Relaunching console with root access"
            sudo -k
            exec sudo --preserve-env=SGND_UI_STYLE,SGND_UI_PALETTE,SGND_CONSOLE_LOG_LEVEL,SGND_FILE_LOG_LEVEL \
                -- "$SGND_SCRIPT_FILE" "${relaunch_args[@]}"
        fi

        if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == "root" ]]; then
            saywarning "This is a direct root session; no original standard user is available"
            return 1
        fi

        local target_user="$SUDO_USER"
        local target_home=""

        target_home="$(getent passwd "$target_user" | cut -d: -f6)"
        [[ -n "$target_home" && -d "$target_home" ]] || {
            sayfail "Cannot resolve home directory for standard user: $target_user"
            return 1
        }

        _sgnd_console_prepare_state_directory "$SGND_STATE_DIR" || return 1
        _sgnd_console_finalize_state_file "$SGND_CONSOLE_MODULE_STATE_FILE" || return 1
        _sgnd_console_finalize_state_file "$SGND_CONSOLE_ACTION_STATE_FILE" || return 1

        sayinfo "Relaunching console with standard access as $target_user"
        exec sudo -H -u "$target_user" -- \
            env \
                -u SUDO_USER \
                -u SUDO_UID \
                -u SUDO_GID \
                HOME="$target_home" \
                USER="$target_user" \
                LOGNAME="$target_user" \
                "$SGND_SCRIPT_FILE" "${relaunch_args[@]}"
    }

# --- Console loop --------------------------------------------------------------------

# --- Console execution-context controls ---------------------------------------------
    # fn: _sgnd_console_toggle_dryrun - Toggle dry-run/commit mode
        # . Purpose
        #   Switch FLAG_DRYRUN between dry-run and commit mode and redraw immediately.
        #
        # . Outputs (globals)
        #   FLAG_DRYRUN
        #   SGND_LAST_WAITSECS=0
        #
        # . Returns
        #   0 after toggling the current mode.
        #
        # . Usage
        #   _sgnd_console_toggle_dryrun
    _sgnd_console_toggle_dryrun() {
        : "${FLAG_DRYRUN:=0}"

        if (( FLAG_DRYRUN )); then
            FLAG_DRYRUN=0
            sayinfo "Dry-run disabled"
        else
            FLAG_DRYRUN=1
            sayinfo "Dry-run enabled"
        fi
        SGND_LAST_WAITSECS=0
    }
    # fn: _sgnd_console_cycle_loglevel_value - Resolve the adjacent framework log level
        # . Arguments
        #   $1  Current log level.
        #   $2  Direction: 1 forward, -1 backward.
        #
        # . Returns
        #   Prints the selected log-level name.
        #
        # . Usage
        #   _sgnd_console_cycle_loglevel_value normal 1
    _sgnd_console_cycle_loglevel_value() {
        local current="${1:-silent}"
        local direction="${2:-1}"
        local i=0
        local current_index=0
        local -a levels=(silent quiet normal verbose debug trace)

        for i in "${!levels[@]}"; do
            if [[ "${levels[$i]}" == "$current" ]]; then
                current_index="$i"
                break
            fi
        done

        i=$(( (current_index + direction + ${#levels[@]}) % ${#levels[@]} ))
        printf '%s' "${levels[$i]}"
    }
    # fn: _sgnd_console_persist_framework_value - Persist one framework state value
        # . Purpose
        #   Save a quick-access setting to SGND_FRAMEWORK_STATEFILE when framework state
        #   persistence is available.
        #
        # . Returns
        #   0 when no state file is configured; otherwise the sgnd_state_set status.
        #
        # . Usage
        #   _sgnd_console_persist_framework_value
    _sgnd_console_persist_framework_value() {
        local key="${1:?missing key}"
        local value="${2-}"

        [[ -n "${SGND_FRAMEWORK_STATEFILE:-}" ]] || return 0
        sgnd_state_set --file "$SGND_FRAMEWORK_STATEFILE" "$key" "$value"
    }
    # fn: _sgnd_console_cycle_console_loglevel - Cycle and persist console log level
        # . Purpose
        #   Select the adjacent console log level, persist it, and redraw immediately.
        #
        # . Returns
        #   0 unless persistence fails.
        #
        # . Usage
        #   _sgnd_console_cycle_console_loglevel
    _sgnd_console_cycle_console_loglevel() {
        local direction="${1:-1}"

        SGND_CONSOLE_LOG_LEVEL="$(_sgnd_console_cycle_loglevel_value             "${SGND_CONSOLE_LOG_LEVEL:-silent}"             "$direction")"
        _sgnd_console_persist_framework_value SGND_CONSOLE_LOG_LEVEL "$SGND_CONSOLE_LOG_LEVEL"
        SGND_LAST_WAITSECS=0
    }
    # fn: _sgnd_console_cycle_file_loglevel - Cycle and persist file log level
        # . Purpose
        #   Select the adjacent file log level, persist it, and redraw immediately.
        #
        # . Returns
        #   0 unless persistence fails.
        #
        # . Usage
        #   _sgnd_console_cycle_file_loglevel
    _sgnd_console_cycle_file_loglevel() {
        local direction="${1:-1}"

        SGND_FILE_LOG_LEVEL="$(_sgnd_console_cycle_loglevel_value             "${SGND_FILE_LOG_LEVEL:-silent}"             "$direction")"
        _sgnd_console_persist_framework_value SGND_FILE_LOG_LEVEL "$SGND_FILE_LOG_LEVEL"
        SGND_LAST_WAITSECS=0
    }
    # fn: _sgnd_console_cycle_theme - Cycle the active console theme
        # . Purpose
        #   Select the adjacent installed style file, apply it through sgnd_theme, and
        #   redraw immediately.
        #
        # . Returns
        #   0 when the theme is applied; non-zero when no themes exist or loading fails.
        #
        # . Usage
        #   _sgnd_console_cycle_theme
    _sgnd_console_cycle_theme() {
        local direction="${1:-1}"
        local current_file="${SGND_UI_STYLE##*/}"
        local candidate=""
        local theme_file=""
        local i=0
        local current_index=-1
        local next_index=0
        local -a theme_paths=()
        local -a theme_files=()

        shopt -s nullglob
        theme_paths=("${SGND_STYLE_DIR%/}"/[0-9][0-9]-style-*.sh)
        shopt -u nullglob

        (( ${#theme_paths[@]} > 0 )) || return 1

        mapfile -t theme_paths < <(
            printf '%s\n' "${theme_paths[@]}" | LC_ALL=C sort
        )

        for candidate in "${theme_paths[@]}"; do
            theme_files+=("${candidate##*/}")
        done

        if [[ ! "$current_file" =~ ^[0-9][0-9]-style-.+\.sh$ ]]; then
            current_file="${current_file%.sh}"
            current_file="${current_file#style-}"
            [[ "$current_file" == "default-ui-style" ]] && current_file="default"

            for candidate in "${theme_files[@]}"; do
                if [[ "$candidate" == [0-9][0-9]-style-"${current_file}".sh ]]; then
                    current_file="$candidate"
                    break
                fi
            done
        fi

        for i in "${!theme_files[@]}"; do
            if [[ "${theme_files[$i]}" == "$current_file" ]]; then
                current_index="$i"
                break
            fi
        done

        if (( current_index < 0 )); then
            if (( direction < 0 )); then
                current_index=0
            else
                current_index=-1
            fi
        fi

        next_index=$(( (current_index + direction + ${#theme_files[@]}) % ${#theme_files[@]} ))
        theme_file="${theme_files[$next_index]}"

        sgnd_theme "$theme_file" || return $?
        SGND_LAST_WAITSECS=0
    }

    # fn: _sgnd_console_handle_control - Handle console-owned direct controls
        # . Purpose
        #   Apply execution-context controls that belong to management-console rather than
        #   the reusable menu library.
        #
        # . Arguments
        #   $1  CONTROL - Normalized key returned by sgnd_menu_read_choice.
        #
        # . Returns
        #   0 when handled.
        #   2 when the key is not a console execution-context control.
        # . Usage
        #   _sgnd_console_handle_control "<control>"
    _sgnd_console_handle_control() {
        local control="${1:-}"

        case "$control" in
            M|m) _sgnd_console_toggle_dryrun ;;
            A|a) _sgnd_console_toggle_access ;;
            S)   _sgnd_console_open_shell ;;
            c)   _sgnd_console_cycle_console_loglevel 1 ;;
            C)   _sgnd_console_cycle_console_loglevel -1 ;;
            f)   _sgnd_console_cycle_file_loglevel 1 ;;
            F)   _sgnd_console_cycle_file_loglevel -1 ;;
            t)   _sgnd_console_cycle_theme 1 ;;
            T)   _sgnd_console_cycle_theme -1 ;;
            *)   return 2 ;;
        esac
    }

    # fn: _sgnd_console_run - Run the console interaction loop
        # . Purpose
        #   Run the interactive console event loop.
        #
        # . Behavior
        #   - Renders the menu.
        #   - Builds the valid choice list for the current menu state.
        #   - Reads normalized keyboard input through sgnd_menu_read_choice.
        #   - Dispatches the selected handler.
        #   - Exits when a handler returns sentinel value 200.
        #   - Shows an interruptible post-action countdown when SGND_LAST_WAITSECS is non-zero.
        #   - Normal registered actions use at least 15 seconds; host controls may set the wait to 0.
        #
        # . Returns
        #   0 on normal console exit
        #   1 on input or dispatch failure
        #
        # . Usage
        #   _sgnd_console_run
        #
        # Examples:
        #   _sgnd_console_run
    _sgnd_console_run() {
        local choice=""
        local rc=0

        while true; do
            if [[ "$SGND_CONSOLE_VIEW" == "index" ]]; then
                _sgnd_console_show_index
            else
                sgnd_menu_show_menu
            fi

            sgnd_print_sectionheader --border "$DL_H" --maxwidth "${SGND_MENU_RENDER_WIDTH:-$(sgnd_terminal_width)}"
            printf '%sSelect option%s : ' "$(sgnd_sgr "$SGND_UI_LABEL")" "$RESET" >/dev/tty
            SGND_LAST_WAITSECS=0
            sgnd_menu_read_choice choice || return $?

            case "$choice" in
                EXIT)
                    sayinfo "Exiting console"
                    return 0
                    ;;
                REDRAW)
                    _sgnd_console_redraw
                    continue
                    ;;
                RESET)
                    _sgnd_console_reset_page_results || true
                    continue
                    ;;
                ESC)
                    if [[ "$SGND_CONSOLE_VIEW" == "module" ]]; then
                        SGND_CONSOLE_VIEW="index"
                        SGND_CONSOLE_ACTIVE_PAGE=""
                        SGND_MENU_ACTIVE_SOURCE=""
                        SGND_PAGE_INDEX=0
                    fi
                    continue
                    ;;
            esac

            if [[ "$SGND_CONSOLE_VIEW" == "index" && ( "$choice" == "V" || "$choice" == "v" ) ]]; then
                if (( EUID == 0 )); then
                    _sgnd_console_manage_visibility || true
                    _sgnd_console_register_pages || true
                fi
                continue
            fi

            if [[ "$SGND_CONSOLE_VIEW" == "index" && ( "$choice" == "M" || "$choice" == "m" ) && $EUID -eq 0 ]]; then
                _sgnd_console_show_module_metadata || true
                continue
            fi

            _sgnd_console_handle_control "$choice"
            rc=$?
            if (( rc == 0 )); then
                continue
            fi

            if [[ "$SGND_CONSOLE_VIEW" == "index" ]]; then
                if [[ "$choice" =~ ^[0-9]+$ ]]; then
                    local choice_number=$((10#$choice))
                    if (( choice_number >= 1 && choice_number <= ${#SGND_CONSOLE_PAGE_ROWS[@]} )); then
                        _sgnd_console_open_page "$((choice_number - 1))" || true
                    else
                        saywarning "Invalid selection: $choice"
                    fi
                else
                    saywarning "Invalid selection: $choice"
                fi
                continue
            fi

            _sgnd_console_dispatch "$choice" || true

            if (( ${SGND_LAST_WAITSECS:-0} > 0 )); then
                ask_dlg_autocontinue \
                    --seconds "$SGND_LAST_WAITSECS" \
                    --message "" \
                    --cancel \
                    --pause || true
            fi
        done
    }

# --- Console module API ---------------------------------------------------------------
    # Public menu registration functions are defined by sgnd-menu.sh.
    # Modules should use sgnd_menu_register_group/item; the public
    # sgnd_console_register_group/item compatibility API remains available there.

# --- Main ----------------------------------------------------------------------------
    # fn: main - Run the SolidGround management console
        # . Purpose
        #   Initialize the framework, discover console pages, and run the interactive host.
        #
        # . Behavior
        #   - Resolves and starts the SolidGroundUX framework runtime.
        #   - Loads console configuration and persisted console state.
        #   - Creates the menu model and registers built-in navigation items.
        #   - Discovers enabled module files and registers lightweight index-page metadata.
        #   - Does not source a page module until that page is first opened.
        #   - Retains loaded page modules for the remainder of the console session.
        #   - Runs the interactive index/page navigation and action-dispatch loop.
        #
        # . Arguments
        #   $@  Framework and console command-line arguments.
        #
        # . Returns
        #   Exits with the resulting status from framework startup or console execution.
        #
        # . Usage
        #   main "$@"
    main() {
        SGND_CONSOLE_ORIGINAL_ARGS=("$@")

        # -- Startup
            _framework_locator || exit $?
            sgnd_exe_start --no-title --autostate -- "$@"

            sgnd_clear
            sgnd_print "Initializing SolidGroundUX Management Console"
            sgnd_print "Initializing paths" 
            _sgnd_console_init_paths || exit $?

        # -- Main script logic

        declare -F sgnd_dt_append >/dev/null || {
            sayfail "sgnd-datatable.sh did not load correctly"
            exit 126
        }

        sgnd_print "Loading console configuration"
        _sgnd_console_load_config || exit $?

        # Console preferences have already been restored from management-console state.
        # An explicitly supplied command-line value has the highest precedence.
        if [[ -n "${VAL_MAXROWS:-}" ]]; then
            SGND_PAGE_MAX_ROWS="$VAL_MAXROWS"
        fi

        SGND_PAGE_INDEX=0
        sgnd_menu_create "$SGND_CONSOLE_TITLE" "$SGND_CONSOLE_DESC" || exit $?
        SGND_MENU_ITEM_EXECUTOR="_sgnd_console_execute_menu_item"

        sgnd_print "Registering builtin menu items"
        _sgnd_console_register_builtin_items || exit $?

        sgnd_print "Registering console pages"
        _sgnd_console_register_pages || exit $?

        if (( SGND_CLEAR_ONRENDER )); then
            sgnd_clear
        fi

        if (( $(sgnd_dt_row_count SGND_ITEM_ROWS) == 0 )); then
            saywarning "No menu items registered"
        fi

        sgnd_print "Starting interactive console"
        _sgnd_console_run
    }

    # Entrypoint: sgnd_bootstrap will split framework args from script args.
    main "$@"
