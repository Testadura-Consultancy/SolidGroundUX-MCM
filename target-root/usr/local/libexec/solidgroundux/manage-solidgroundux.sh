#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX - Manage SolidGroundUX
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624123
#   Source      : manage-solidgroundux.sh
#   Type        : script
#   Group       : SolidGround Console
#   Purpose     : Apply persistent SolidGroundUX framework management actions
#
# Description:
#   Implements persistent framework configuration and logging actions dispatched by
#   the SolidGroundUX Management Console. All mutating actions honor --dryrun and
#   provide a useful preview of the changes that would be made.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
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
    SGND_SCRIPT_TITLE="Manage SolidGroundUX"
    : "${SGND_SCRIPT_DESC:=Manage persistent SolidGroundUX framework settings and logging.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2624123}"
    : "${SGND_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${SGND_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${SGND_SCRIPT_COPYRIGHT:=2025 - 2026 Testadura Consultancy}"
    : "${SGND_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.1.}"

# - Framework integration ---------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||config-system-configure,config-system-edit,config-user-edit,log-rotate"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action config-system-configure"
        "  $SGND_SCRIPT_NAME --dryrun --action log-rotate"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Helpers -----------------------------------------------------------------------
    _framework_config_validator() {
        local key="${1:-}"

        case "$key" in
            SGND_CONSOLE_LOG_LEVEL|SGND_FILE_LOG_LEVEL)
                printf '%s\n' '_framework_config_validate_log_level'
                ;;
            SGND_LOG_MAX_BYTES|SGND_LOG_KEEP)
                printf '%s\n' 'sgnd_validate_int'
                ;;
            SGND_LOG_COMPRESS|SAY_COLORIZE_DEFAULT|SAY_DATE_DEFAULT|SAY_SHOW_DEFAULT)
                printf '%s\n' 'sgnd_validate_bool'
                ;;
            *)
                printf '%s\n' 'sgnd_validate_text'
                ;;
        esac
    }

    _framework_config_validate_log_level() {
        case "${1,,}" in
            silent|quiet|normal|verbose|debug|trace) return 0 ;;
            *) return 1 ;;
        esac
    }

    _framework_config_write_value() {
        local file="${1:?missing cfg file}"
        local key="${2:?missing cfg key}"
        local value="${3-}"
        local temp_file=""
        local rc=0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would set '$key=$value' in '$file'."
            return 0
        fi

        temp_file="$(mktemp)" || return $?

        awk -v key="$key" -v value="$value" '
            BEGIN { replaced = 0 }
            $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
                print key "=" value
                replaced = 1
                next
            }
            { print }
            END {
                if (!replaced) {
                    print key "=" value
                }
            }
        ' "$file" > "$temp_file" || {
            rm -f -- "$temp_file"
            return 1
        }

        if [[ -w "$file" ]]; then
            cat -- "$temp_file" > "$file"
            rc=$?
        elif command -v sudo >/dev/null 2>&1; then
            sudo cp -- "$temp_file" "$file"
            rc=$?
        else
            rm -f -- "$temp_file"
            saywarning "Configuration file is not writable: $file"
            return 1
        fi

        rm -f -- "$temp_file"
        return "$rc"
    }

    _framework_config_edit_file() {
        local title="$1"
        local file="$2"
        local editor="${VISUAL:-${EDITOR:-nano}}"
        local directory=""
        local -a editor_command=()

        [[ -n "$file" ]] || {
            saywarning "$title path is not available"
            return 1
        }

        directory="$(dirname "$file")"
        read -r -a editor_command <<< "$editor"

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would edit '$file' using '$editor'."
            if [[ ! -d "$directory" ]]; then
                sayinfo "DRYRUN: Would create configuration directory '$directory' first."
            fi
            sayok "DRYRUN complete. The edit shown above would have been performed; no changes were written."
            return 0
        fi

        if [[ -d "$directory" && -w "$directory" ]] || [[ -f "$file" && -w "$file" ]]; then
            mkdir -p -- "$directory" || return $?
            "${editor_command[@]}" "$file"
            return $?
        fi

        command -v sudo >/dev/null 2>&1 || {
            saywarning "$title requires write access: $file"
            return 1
        }

        sudo mkdir -p -- "$directory" || return $?
        sudo "${editor_command[@]}" "$file"
    }

    _framework_configure_file() {
        local cfg_file="${1:-${SGND_FRAMEWORK_SYSCFG_FILE:-}}"
        local spec=""
        local audience=""
        local key=""
        local description=""
        local extra=""
        local current=""
        local validator=""
        local answer=""
        local changed=0

        [[ -n "$cfg_file" ]] || {
            saywarning "Framework configuration path is not available"
            return 1
        }

        [[ -f "$cfg_file" ]] || {
            saywarning "Framework configuration does not exist: $cfg_file"
            return 1
        }

        declare -p SGND_FRAMEWORK_GLOBALS >/dev/null 2>&1 || {
            saywarning "SGND_FRAMEWORK_GLOBALS is not defined"
            return 1
        }

        sgnd_print
        sgnd_print_sectionheader --text "Configure $(basename "$cfg_file")"
        sgnd_print_labeledvalue --label "Configuration file" --value "$cfg_file"
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sgnd_print_labeledvalue --label "Mode" --value "DRYRUN - preview only"
        fi
        sgnd_print

        for spec in "${SGND_FRAMEWORK_GLOBALS[@]}"; do
            IFS='|' read -r audience key description extra <<< "$spec"
            [[ -n "$key" ]] || continue

            if [[ "$cfg_file" == "${SGND_FRAMEWORK_SYSCFG_FILE:-}" ]]; then
                [[ "$audience" == "system" || "$audience" == "both" ]] || continue
            elif [[ "$cfg_file" == "${SGND_FRAMEWORK_USRCFG_FILE:-}" ]]; then
                [[ "$audience" == "user" || "$audience" == "both" ]] || continue
            fi

            current="${!key-}"
            validator="$(_framework_config_validator "$key")"
            answer="$current"

            ask \
                --label "$key" \
                --var answer \
                --default "$current" \
                --validate "$validator" \
                --labelwidth 28 || return $?

            if [[ "$answer" != "$current" ]]; then
                changed=1
                _framework_config_write_value "$cfg_file" "$key" "$answer" || return $?
            fi
        done

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            if (( changed == 0 )); then
                sayok "DRYRUN complete. No framework configuration changes would have been required; no changes were written."
            else
                sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
            fi
        else
            sayok "Framework configuration saved to $cfg_file"
        fi
    }

    _framework_log_validate() {
        [[ -n "${SGND_LOG_PATH:-}" ]] || {
            saywarning "SGND_LOG_PATH is not set"
            return 1
        }

        [[ -f "$SGND_LOG_PATH" ]] || {
            saywarning "Framework logfile does not exist: $SGND_LOG_PATH"
            return 1
        }
    }

    _framework_log_rotate() {
        local logfile="${SGND_LOG_PATH:-}"
        local keep="${SGND_LOG_KEEP:-5}"
        local compress="${SGND_LOG_COMPRESS:-0}"
        local i=0
        local src=""
        local dst=""

        _framework_log_validate || return $?

        [[ "$keep" =~ ^[0-9]+$ ]] && (( keep > 0 )) || {
            saywarning "Invalid SGND_LOG_KEEP value: $keep"
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would rotate framework logfile '$logfile'."
            sgnd_print_labeledvalue --label "Retention" --value "$keep archive(s)" --labelwidth 20
            sgnd_print_labeledvalue --label "Compression" --value "$([[ $compress == 1 ]] && printf 'gzip' || printf 'disabled')" --labelwidth 20
            sayinfo "DRYRUN: Would shift existing numbered archives up by one generation."
            sayinfo "DRYRUN: Would move '$logfile' to '${logfile}.1' and create a new empty active logfile."
            if (( compress )); then
                sayinfo "DRYRUN: Would gzip '${logfile}.1'."
            fi
            sayinfo "DRYRUN: Would remove archives older than retention generation $keep."
            sayok "DRYRUN complete. The logfile changes shown above would have been applied; no changes were written."
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

        if (( compress )) && [[ -f "${logfile}.1" ]]; then
            gzip -f -- "${logfile}.1" || return $?
        fi

        rm -f -- \
            "${logfile}.$((keep + 1))" \
            "${logfile}.$((keep + 1)).gz"

        sayok "Framework logfile rotated"
    }

# - Actions -----------------------------------------------------------------------
    _run_action() {
        local action="${1:?missing action}"

        case "$action" in
            config-system-configure)
                _framework_configure_file "${SGND_FRAMEWORK_SYSCFG_FILE:-}"
                ;;
            config-system-edit)
                _framework_config_edit_file \
                    "System framework configuration" \
                    "${SGND_FRAMEWORK_SYSCFG_FILE:-}"
                ;;
            config-user-edit)
                _framework_config_edit_file \
                    "User framework configuration" \
                    "${SGND_FRAMEWORK_USRCFG_FILE:-}"
                ;;
            log-rotate)
                _framework_log_rotate
                ;;
            *)
                sayfail "Unknown SolidGroundUX management action: $action"
                return 2
                ;;
        esac
    }

# - Main --------------------------------------------------------------------------
    main() {
        local action=""
        local selection=""

        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?

        action="${ACTION:-}"

        if [[ -z "$action" ]]; then
            sgnd_print
            sgnd_print_sectionheader --text "SolidGroundUX management"
            sgnd_print

            ask_selection \
                --label "Action" \
                --var selection \
                --items \
                    "Configure framework settings" \
                    "Edit system configuration" \
                    "Edit user configuration" \
                    "Rotate framework logfile" || return 0

            sgnd_print

            case "$selection" in
                "Configure framework settings") action="config-system-configure" ;;
                "Edit system configuration") action="config-system-edit" ;;
                "Edit user configuration") action="config-user-edit" ;;
                "Rotate framework logfile") action="log-rotate" ;;
                *) return 0 ;;
            esac
        fi

        _run_action "$action"
    }

    main "$@"
