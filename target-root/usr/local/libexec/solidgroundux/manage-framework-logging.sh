#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Framework Logging
# ------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626710
#   Checksum    : 39ac7930bf4136bb58af917acbd99692e967b0d09d120bf9269cba4fba364c35
#   Source      : manage-framework-logging.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Manage framework logging
#
# Description:
#   Runs framework logging actions in a fully bootstrapped executable context.
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
    SGND_SCRIPT_TITLE="Manage Framework Logging"

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
        "action|a|enum|ACTION|Management action||view,follow,errors,rotate"
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
        "  $SGND_SCRIPT_NAME --action view"
        "  $SGND_SCRIPT_NAME --action errors"
        "  $SGND_SCRIPT_NAME --dryrun --action rotate"
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

# - Local script declarations -------------------------------------------------------
    # doc$ Local script declarations
        # Put script-local constants and defaults here, not framework configuration.
        # Prefer local variables inside functions unless a value must be shared.

# - Local script functions ----------------------------------------------------------
    # doc$ Local script functions
        # Organize script-specific functions here.
        # These functions are not reusable framework behavior; they implement the
        # unique logic and features of the executable script.
        #
        # Suggested organization:
        #   - Initialization
        #   - Local script helpers
        #   - Layout and display helpers
        #   - Input handling
        #   - Business logic
        #   - Validation
        #   - Reporting
        #   - Cleanup

    _log_select() {
        local primary="${SGND_LOG_PATH:-}"
        local alternate="${SGND_ALTLOG_PATH:-}"
        local primary_exists=0
        local alternate_exists=0
        local selection=""

        SGND_SELECTED_LOG_PATH=""

        [[ -n "$primary" && -f "$primary" ]] && primary_exists=1
        [[ -n "$alternate" && -f "$alternate" ]] && alternate_exists=1

        if (( primary_exists && alternate_exists )); then
            sgnd_print
            sgnd_print_sectionheader --text "Framework logfiles"
            sgnd_print_labeledvalue --label "Primary logfile" --value "$primary" --labelwidth 20
            sgnd_print_labeledvalue --label "Alternate logfile" --value "$alternate" --labelwidth 20
            sgnd_print

            ask_selection \
                --label "Logfile" \
                --var selection \
                --items "Primary" "Alternate" || return $?

            case "$selection" in
                Primary)   SGND_SELECTED_LOG_PATH="$primary" ;;
                Alternate) SGND_SELECTED_LOG_PATH="$alternate" ;;
                *) return 1 ;;
            esac
        elif (( primary_exists )); then
            SGND_SELECTED_LOG_PATH="$primary"
        elif (( alternate_exists )); then
            SGND_SELECTED_LOG_PATH="$alternate"
        else
            saywarning "No framework logfile exists."
            [[ -n "$primary" ]] && sgnd_print_labeledvalue --label "Primary logfile" --value "$primary" --labelwidth 20
            [[ -n "$alternate" ]] && sgnd_print_labeledvalue --label "Alternate logfile" --value "$alternate" --labelwidth 20
            return 1
        fi

        return 0
    }

    _log_view() {
        local pager="${PAGER:-less}"
        local -a pager_command=()
        _log_select || return $?
        read -r -a pager_command <<< "$pager"
        "${pager_command[@]}" +G -- "$SGND_SELECTED_LOG_PATH"
    }

    _log_follow() {
        local key=""
        local tail_pid=""

        _log_select || return $?

        sgnd_print
        sgnd_print_labeledvalue --label "Following" --value "$SGND_SELECTED_LOG_PATH" --labelwidth 20
        sgnd_print_labeledvalue --label "Return" --value "Esc or Q" --labelwidth 20
        sgnd_print

        # Keep tail as a child of this executable so the action remains in control of
        # terminal input.  This lets Esc/Q return normally to the Management Console
        # instead of requiring Ctrl+C to terminate the process chain.
        tail -n 20 -F -- "$SGND_SELECTED_LOG_PATH" &
        tail_pid=$!

        while kill -0 "$tail_pid" 2>/dev/null; do
            key=""
            if IFS= read -r -s -n 1 -t 0.2 key </dev/tty; then
                case "$key" in
                    $'\e'|q|Q)
                        break
                        ;;
                esac
            fi
        done

        kill "$tail_pid" 2>/dev/null || true
        wait "$tail_pid" 2>/dev/null || true
        return 0
    }

    _log_errors() {
        local pager="${PAGER:-less}"
        local -a pager_command=()
        _log_select || return $?
        read -r -a pager_command <<< "$pager"
        grep -E ' type=(ERROR|FAIL|FATAL) ' -- "$SGND_SELECTED_LOG_PATH" | tail -n 100 | "${pager_command[@]}"
    }

    _log_rotate() {
        local logfile=""
        local keep="${SGND_LOG_KEEP:-5}"
        local compress="${SGND_LOG_COMPRESS:-0}"
        local i=0 src="" dst=""

        _log_select || return $?
        logfile="$SGND_SELECTED_LOG_PATH"

        [[ "$keep" =~ ^[0-9]+$ ]] && (( keep > 0 )) || {
            saywarning "Invalid SGND_LOG_KEEP value: $keep"
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would rotate framework logfile '$logfile'."
            return 0
        fi

        [[ -w "$logfile" && -w "$(dirname "$logfile")" ]] || {
            saywarning "Framework logfile is not writable: $logfile"
            return 1
        }

        for (( i=keep; i>=1; i-- )); do
            src="${logfile}.${i}"
            dst="${logfile}.$((i + 1))"
            [[ -f "$src" ]] && mv -f -- "$src" "$dst"
            [[ -f "${src}.gz" ]] && mv -f -- "${src}.gz" "${dst}.gz"
        done
        mv -f -- "$logfile" "${logfile}.1" || return $?
        : > "$logfile" || return $?
        (( compress )) && [[ -f "${logfile}.1" ]] && gzip -f -- "${logfile}.1"
        rm -f -- "${logfile}.$((keep + 1))" "${logfile}.$((keep + 1)).gz"
        sayok "Framework logfile rotated: $logfile"
    }

    _run_action() {
        case "${1:?missing action}" in
            view)   _log_view ;;
            follow) _log_follow ;;
            errors) _log_errors ;;
            rotate) _log_rotate ;;
            *) sayfail "Unknown framework logging action: $1"; return 2 ;;
        esac
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
        #   main "$@"
    main() {
        local action=""

        _framework_locator || exit $?
        sgnd_exe_start "$@" || return $?

        action="${ACTION:-view}"
        _run_action "$action"
    }

    # Entrypoint: sgnd_bootstrap will split framework args from script args.
    main "$@"
