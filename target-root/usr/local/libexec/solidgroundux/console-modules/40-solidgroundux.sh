# ==================================================================================
# SolidGroundUX - SolidGroundUX
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624123
#   Checksum    : f0226399b8e8fec81db6596957b38d79b09960986a2e8398cc107e53cc5ccf2f
#   Source      : 40-solidgroundux.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Manage the SolidGroundUX framework and release lifecycle
#
# Description:
#   Contains SolidGroundUX framework information, access to the standalone release manager,
#   configuration, state, logging, and diagnostics.
#
# Attribution:
#   Developers    : Mark Fieten
#   Company       : Testadura Consultancy
#   Client        : -
#   Copyright     : © 2025 - 2026 Testadura Consultancy
#   License       : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
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
# - Module metadata -------------------------------------------------------------
    SGND_SOLIDGROUNDUX_MODULE_ID="solidgroundux"
    SGND_SOLIDGROUNDUX_MODULE_NAME="SolidGroundUX"
    SGND_SOLIDGROUNDUX_MODULE_VERSION="1.0.0"
    SGND_SOLIDGROUNDUX_MODULE_DESC="Manage the SolidGroundUX framework and installation"

    SGND_MODULE_NAME="${SGND_SOLIDGROUNDUX_MODULE_NAME}"
    SGND_MODULE_VERSION="${SGND_SOLIDGROUNDUX_MODULE_VERSION}"
    SGND_MODULE_DESC="${SGND_SOLIDGROUNDUX_MODULE_DESC}"

# - SolidGroundUX installation actions -------------------------------------------
    # fn: _release_manager - Open the standalone SolidGroundUX release manager
        # . Purpose
        #   Start the self-sufficient release manager for installation,
        #   update, rollback, reinstallation, and removal operations.
        #
        # . Returns
        #   Returns the release manager exit status.
        #
        # . Usage
        #   _release_manager
    _release_manager() {
        local manager="/var/lib/solidgroundux/release-manager.sh"

        [[ -f "$manager" ]] || {
            saywarning "Release manager not found: $manager"
            return 1
        }

        if [[ -x "$manager" ]]; then
            sudo "$manager" "$@"
        else
            sudo bash "$manager" "$@"
        fi
    }

# - Framework diagnostics --------------------------------------------------------
    # fn: _framework_smoketest
        # Returns:
        #   Exit status of sgnd-framework-smoketest.
        #
        # Usage:
        #   _framework_smoketest
        #
    _framework_smoketest() {
        _sgnd_run_public_command "sgnd-framework-smoketest"
    }

    # fn: _framework_show_environment
        # Returns:
        #   Exit status of sgnd-framework-smoketest --show env.
        #
        # Usage:
        #   _framework_show_environment
        #
    _framework_show_environment() {
        _sgnd_run_public_command "sgnd-framework-smoketest" --show env
    }

    # fn: _framework_show_about
        # Output:
        #   Displays Framework about info
        # Usage:
        #  _framework_show_about
    _framework_show_about()
    {
        sgnd_print
        sgnd_print_sectionheader --text "About SolidGroundUX" 
        sgnd_print
        sgnd_print_labeledvalue --label "Version"          --value "$SGND_VERSION.$SGND_BUILD" --labelwidth 20
        sgnd_print_labeledvalue --label "Company"          --value "$SGND_COMPANY"              --labelwidth 20
        sgnd_print_labeledvalue --label "Copyright"        --value "$SGND_COPYRIGHT"            --labelwidth 20
        sgnd_print_labeledvalue --label "License"          --value "$SGND_LICENSE"              --labelwidth 20
        sgnd_print_labeledvalue --label "License accepted" \
            --value "$([[ ${SGND_LICENSE_ACCEPTED:-0} == 1 ]] && printf 'Yes' || printf 'No')"  \
            --labelwidth 20
        sgnd_print_labeledvalue --label "Release URL"      --value "$SGND_RELEASE_URL"           --labelwidth 20
        sgnd_print_labeledvalue --label "Online docs"      --value "$SGND_ONLINE_DOC"            --labelwidth 20
        sgnd_print
        sgnd_print_sectionheader
        sgnd_print
    }

# - Framework configuration actions ----------------------------------------------
    # fn: _framework_config_view_file
        # . Purpose
        #   Open a framework configuration file with the configured pager.
        #
        # . Returns
        #   Exit status from the pager; 1 when the path is unavailable or missing.
        #
        # . Usage
        #   _framework_config_view_file
    _framework_config_view_file() {
        local title="$1"
        local file="$2"
        local pager="${PAGER:-less}"
        local -a pager_command=()

        [[ -n "$file" ]] || {
            saywarning "$title path is not available"
            return 1
        }

        [[ -f "$file" ]] || {
            saywarning "$title does not exist: $file"
            return 1
        }

        read -r -a pager_command <<< "$pager"
        "${pager_command[@]}" -- "$file"
    }

    # fn: _framework_config_edit_file
        # . Purpose
        #   Open a framework configuration file in VISUAL/EDITOR, using sudo when write access requires it.
        #
        # . Returns
        #   Exit status from the editor or required filesystem operation.
        #
        # . Usage
        #   _framework_config_edit_file
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

    # fn: _framework_config_view_system
        # . Purpose
        #   View the system-wide SolidGroundUX framework configuration file.
        #
        # . Returns
        #   Returns _framework_config_view_file status.
        #
        # . Usage
        #   _framework_config_view_system
    _framework_config_view_system() {
        _framework_config_view_file             "System framework configuration"             "${SGND_FRAMEWORK_SYSCFG_FILE:-}"
    }

    # fn: _framework_config_edit_system
        # . Purpose
        #   Edit the system-wide SolidGroundUX framework configuration file.
        #
        # . Returns
        #   Returns _framework_config_edit_file status.
        #
        # . Usage
        #   _framework_config_edit_system
    _framework_config_edit_system() {
        _framework_config_edit_file             "System framework configuration"             "${SGND_FRAMEWORK_SYSCFG_FILE:-}"
    }

    # fn: _framework_config_view_user
        # . Purpose
        #   View the current user SolidGroundUX framework configuration file.
        #
        # . Returns
        #   Returns _framework_config_view_file status.
        #
        # . Usage
        #   _framework_config_view_user
    _framework_config_view_user() {
        _framework_config_view_file             "User framework configuration"             "${SGND_FRAMEWORK_USRCFG_FILE:-}"
    }

    # fn: _framework_config_edit_user
        # . Purpose
        #   Edit the current user SolidGroundUX framework configuration file.
        #
        # . Returns
        #   Returns _framework_config_edit_file status.
        #
        # . Usage
        #   _framework_config_edit_user
    _framework_config_edit_user() {
        _framework_config_edit_file             "User framework configuration"             "${SGND_FRAMEWORK_USRCFG_FILE:-}"
    }

    # fn: _framework_config_validator
        # Returns:
        #   Validator function name suitable for the requested configuration key.
        #
        # Usage:
        #   _framework_config_validator "SGND_LOG_KEEP"
        #
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

    # fn: _framework_config_validate_log_level
        # Returns:
        #   0 for a supported framework log level; 1 otherwise.
        #
        # Usage:
        #   _framework_config_validate_log_level "normal"
        #
    _framework_config_validate_log_level() {
        case "${1,,}" in
            silent|quiet|normal|verbose|debug|trace) return 0 ;;
            *) return 1 ;;
        esac
    }

    # fn: _framework_config_write_value
        # Purpose:
        #   Replace or append one KEY=VALUE assignment in a cfg file.
        #
        # Arguments:
        #   $1 - Target cfg file.
        #   $2 - Configuration key.
        #   $3 - New value.
        #
        # Returns:
        #   0 on success; non-zero when the file cannot be updated.
        #
        # Usage:
        #   _framework_config_write_value "$file" "$key" "$value"
        #
    _framework_config_write_value() {
        local file="${1:?missing cfg file}"
        local key="${2:?missing cfg key}"
        local value="${3-}"
        local temp_file=""

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
        elif command -v sudo >/dev/null 2>&1; then
            sudo cp -- "$temp_file" "$file"
        else
            rm -f -- "$temp_file"
            saywarning "Configuration file is not writable: $file"
            return 1
        fi

        local rc=$?
        rm -f -- "$temp_file"
        return "$rc"
    }

    # fn: framework_configure_file
        # Purpose:
        #   Interactively configure registered settings in a SolidGroundUX cfg file.
        #
        # Behavior:
        #   - Defaults to sgnd_framework_globals.cfg.
        #   - Uses the active value of each registered setting as the prompt default.
        #   - Applies a validator appropriate to each setting.
        #   - Writes accepted values back while retaining comments and ordering.
        #
        # Arguments:
        #   $1 - Optional cfg path. Defaults to SGND_FRAMEWORK_SYSCFG_FILE.
        #
        # Returns:
        #   0 when all selected values were written successfully.
        #
        # Usage:
        #   framework_configure_file
        #   framework_configure_file "$SGND_FRAMEWORK_USRCFG_FILE"
        #
    framework_configure_file() {
        local cfg_file="${1:-${SGND_FRAMEWORK_SYSCFG_FILE:-}}"
        local spec=""
        local audience=""
        local key=""
        local description=""
        local extra=""
        local current=""
        local validator=""
        local answer=""

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

            _framework_config_write_value "$cfg_file" "$key" "$answer" || return $?
            printf -v "$key" '%s' "$answer"
        done

        sayok "Framework configuration saved to $cfg_file"
    }

# - Framework logging actions ----------------------------------------------------
    # fn: _framework_log_validate
        # . Purpose
        #   Verify that the configured framework logfile path exists and is usable for log actions.
        #
        # . Returns
        #   0 when the logfile exists; 1 otherwise.
        #
        # . Usage
        #   _framework_log_validate
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

    # fn: _framework_log_view
        # . Purpose
        #   Open the active framework logfile at its most recent entries.
        #
        # . Returns
        #   Exit status from the configured pager; 1 when the logfile is unavailable.
        #
        # . Usage
        #   _framework_log_view
    _framework_log_view() {
        local pager="${PAGER:-less}"
        local -a pager_command=()

        _framework_log_validate || return $?
        read -r -a pager_command <<< "$pager"
        "${pager_command[@]}" +G -- "$SGND_LOG_PATH"
    }

    # fn: _framework_log_follow
        # . Purpose
        #   Follow new entries appended to the active framework logfile.
        #
        # . Returns
        #   Exit status from tail -F; 1 when the logfile is unavailable.
        #
        # . Usage
        #   _framework_log_follow
    _framework_log_follow() {
        _framework_log_validate || return $?
        tail -F -- "$SGND_LOG_PATH"
    }

    # fn: _framework_log_show_errors
        # . Purpose
        #   Show the most recent ERROR, FAIL, and FATAL entries from the active framework logfile.
        #
        # . Returns
        #   Exit status from the filter/pager pipeline; 1 when the logfile is unavailable.
        #
        # . Usage
        #   _framework_log_show_errors
    _framework_log_show_errors() {
        local pager="${PAGER:-less}"
        local -a pager_command=()

        _framework_log_validate || return $?
        read -r -a pager_command <<< "$pager"

        grep -E ' type=(ERROR|FAIL|FATAL) ' -- "$SGND_LOG_PATH"             | tail -n 100             | "${pager_command[@]}"
    }

    # fn: _framework_log_rotate
        # . Purpose
        #   Rotate the active framework logfile according to configured retention and compression settings.
        #
        # . Returns
        #   0 when rotation succeeds; non-zero on validation or filesystem failure.
        #
        # . Usage
        #   _framework_log_rotate
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

        rm -f --             "${logfile}.$((keep + 1))"             "${logfile}.$((keep + 1)).gz"

        sayok "Framework logfile rotated"
    }

# - Internal helpers -------------------------------------------------------------
    # fn: _framework_state_validate
        # . Purpose
        #   Verify that the transferable framework-state contract is available.
        #
        # . Returns
        #   0 when SGND_FRAMEWORK_STATEFILE and SGND_FRAMEWORK_STATE are available.
        #   1 otherwise.
        #
        # . Usage
        #   _framework_state_validate
    _framework_state_validate() {
        [[ -n "${SGND_FRAMEWORK_STATEFILE:-}" ]] || {
            saywarning "SGND_FRAMEWORK_STATEFILE is not set"
            return 1
        }

        declare -p SGND_FRAMEWORK_STATE >/dev/null 2>&1 || {
            saywarning "SGND_FRAMEWORK_STATE is not defined"
            return 1
        }

        return 0
    }

    # fn: _framework_state_apply_ui
        # . Purpose
        #   Reload the active palette and style after framework state changes.
        #
        # . Returns
        #   0 when UI state is reloaded or no loader is available.
        #   Non-zero when the UI loader fails.
        #
        # . Usage
        #   _framework_state_apply_ui
    _framework_state_apply_ui() {
        if declare -F sgnd_load_ui_style >/dev/null 2>&1; then
            sgnd_load_ui_style
        fi
    }

# - Public module actions --------------------------------------------------------
    # fn: framework_state_show
        # . Purpose
        #   Display all transferable framework-state variables and their values.
        #
        # . Returns
        #   0 on success.
        #   1 when framework state is unavailable.
        #
        # . Usage
        #   framework_state_show
    framework_state_show() {
        _framework_state_validate || return 1

        local key=""
        local value=""

        sgnd_print
        sgnd_print_sectionheader --text "Transferable framework state"
        sgnd_print_labeledvalue --label "State file" --value "$SGND_FRAMEWORK_STATEFILE"
        sgnd_print

        for key in "${SGND_FRAMEWORK_STATE[@]}"; do
            value="${!key-}"
            sgnd_print_labeledvalue --label "$key" --value "$value" --labelwidth 30
        done
    }

    # fn: framework_state_edit
        # . Purpose
        #   Edit and save all transferable framework-state variables.
        #
        # . Behavior
        #   - Builds an input form from SGND_FRAMEWORK_STATE.
        #   - Uses the current runtime values as defaults.
        #   - Saves the edited values to SGND_FRAMEWORK_STATEFILE.
        #   - Reloads the active UI style after a successful save.
        #
        # Outputs (globals):
        #   Variables listed in SGND_FRAMEWORK_STATE.
        #
        # Side effects:
        #   Updates SGND_FRAMEWORK_STATEFILE.
        #
        # . Returns
        #   0 on success.
        #   Non-zero when editing, saving, or UI reloading fails.
        #
        # . Usage
        #   framework_state_edit
    framework_state_edit() {
        _framework_state_validate || return 1

        local key=""
        local -a fields=()

        for key in "${SGND_FRAMEWORK_STATE[@]}"; do
            fields+=("$key|$key|${!key-}|")
        done

        sgnd_print
        sgnd_print_sectionheader --text "Edit transferable framework state"

        ask_prompt_form --autoalign --pad 2 -- "${fields[@]}" || return $?

        sgnd_state_save_keys \
            --file "$SGND_FRAMEWORK_STATEFILE" \
            --array SGND_FRAMEWORK_STATE || return $?

        _framework_state_apply_ui || return $?
        sayok "Framework state saved"
    }

    # fn: framework_state_save
        # . Purpose
        #   Save current transferable framework-state values.
        #
        # . Returns
        #   0 on success.
        #   Non-zero when state is unavailable or cannot be saved.
        #
        # . Usage
        #   framework_state_save
    framework_state_save() {
        _framework_state_validate || return 1

        sgnd_state_save_keys \
            --file "$SGND_FRAMEWORK_STATEFILE" \
            --array SGND_FRAMEWORK_STATE || return $?

        sayok "Framework state saved to $SGND_FRAMEWORK_STATEFILE"
    }

    # fn: framework_state_reload
        # . Purpose
        #   Reload transferable framework state from disk into the console instance.
        #
        # Outputs (globals):
        #   Variables listed in SGND_FRAMEWORK_STATE.
        #
        # . Returns
        #   0 on success.
        #   Non-zero when state is unavailable or cannot be loaded.
        #
        # . Usage
        #   framework_state_reload
    framework_state_reload() {
        _framework_state_validate || return 1

        sgnd_state_load_keys \
            --file "$SGND_FRAMEWORK_STATEFILE" \
            --array SGND_FRAMEWORK_STATE || return $?

        _framework_state_apply_ui || return $?
        sayok "Framework state reloaded"
    }

# - Console registration ---------------------------------------------------------
    # Provides operational management of the SolidGroundUX installation itself,
    # including release lifecycle, framework configuration and state, logging, and
    # diagnostics.
    #
    # . SolidGroundUX
    # ! About SolidGroundUX
    #   > Show SolidGroundUX information.
    #   > Handler: _framework_show_about
    #
    # ! Release manager
    #   > Open the interactive standalone SolidGroundUX release manager.
    #   > Check, download, update, install, roll back, remove, and manage project releases there.
    #   > Handler: _release_manager
    #   > Script: /var/lib/solidgroundux/release-manager.sh
    #
    # . Framework Configuration
    # ! Show effective configuration
    #   > Show the resolved SolidGroundUX framework environment and effective settings.
    #   > Handler: _framework_show_environment
    #
    # ! View system configuration
    #   > View the system-wide framework configuration file.
    #   > Handler: _framework_config_view_system
    #
    # ! Configure framework settings
    #   > Interactively configure sgnd_framework_globals.cfg with validated values.
    #   > Handler: framework_configure_file
    #
    # ! Edit system configuration file
    #   > Edit the raw system-wide framework configuration file.
    #   > Handler: _framework_config_edit_system
    #
    # ! View user configuration
    #   > View the user-specific framework configuration file.
    #   > Handler: _framework_config_view_user
    #
    # ! Edit user configuration
    #   > Edit the user-specific framework configuration file.
    #   > Handler: _framework_config_edit_user
    #
    # . Framework State
    # ! Show state
    #   > Display current transferable framework-state values.
    #   > Handler: framework_state_show
    #
    # ! Edit state
    #   > Edit and save transferable framework-state values.
    #   > Handler: framework_state_edit
    #
    # ! Save state
    #   > Save current transferable values to the state file.
    #   > Handler: framework_state_save
    #
    # ! Reload state
    #   > Reload transferable values from the state file.
    #   > Handler: framework_state_reload
    #
    # . Framework Logging
    # ! View current logfile
    #   > Open the active framework logfile at its most recent entries.
    #   > Handler: _framework_log_view
    #
    # ! Follow current logfile
    #   > Follow new entries written to the active framework logfile.
    #   > Handler: _framework_log_follow
    #
    # ! Show recent errors
    #   > Show the most recent error, failure, and fatal log entries.
    #   > Handler: _framework_log_show_errors
    #
    # ! Rotate current logfile
    #   > Rotate the active framework logfile using the configured retention settings.
    #   > Handler: _framework_log_rotate
    #
    # . Framework Diagnostics
    # ! Framework smoke test
    #   > Run the complete SolidGroundUX framework smoke test.
    #   > Handler: _framework_smoketest
    #   > Command: sgnd-framework-smoketest
    sgnd_menu_register_group "sgndinst" "SolidGroundUX" "SolidGroundUX framework information and release management" 0 1 810
    sgnd_menu_register_item "about" "sgndinst" "About SolidGroundUX" "_framework_show_about" "Show SolidGroundUX information" 0 15 1
    sgnd_menu_register_item "release-manager" "sgndinst" "Release manager" "_release_manager" "Open the standalone release manager for check, download, update, install, rollback, removal, and project release management" 0 15 1

    sgnd_menu_register_group "framework-config" "Framework Configuration" "View and edit framework configuration files and effective settings" 0 1 820
    sgnd_menu_register_item "config-env" "framework-config" "Show effective configuration" "_framework_show_environment" "Show the resolved SolidGroundUX framework environment and effective settings" 0 30 1
    sgnd_menu_register_item "config-system-view" "framework-config" "View system configuration" "_framework_config_view_system" "View the system-wide framework configuration file" 0 30 1
    sgnd_menu_register_item "config-system-configure" "framework-config" "Configure framework settings" "framework_configure_file" "Interactively configure sgnd_framework_globals.cfg with validated current values" 0 30 1
    sgnd_menu_register_item "config-system-edit" "framework-config" "Edit system configuration file" "_framework_config_edit_system" "Edit the raw system-wide framework configuration file" 0 30 1
    sgnd_menu_register_item "config-user-view" "framework-config" "View user configuration" "_framework_config_view_user" "View the user-specific framework configuration file" 0 30 1
    sgnd_menu_register_item "config-user-edit" "framework-config" "Edit user configuration" "_framework_config_edit_user" "Edit the user-specific framework configuration file" 0 30 1

    sgnd_menu_register_group "framework-state" "Framework State" "Inspect and edit transferable SolidGroundUX framework runtime settings" 0 1 830
    sgnd_menu_register_item "state-show" "framework-state" "Show state" "framework_state_show" "Display current transferable framework-state values" 0 30 1
    sgnd_menu_register_item "state-edit" "framework-state" "Edit state" "framework_state_edit" "Edit and save transferable framework-state values" 0 30 1
    sgnd_menu_register_item "state-save" "framework-state" "Save state" "framework_state_save" "Save current transferable values to the state file" 0 30 1
    sgnd_menu_register_item "state-reload" "framework-state" "Reload state" "framework_state_reload" "Reload transferable values from the state file" 0 30 1

    sgnd_menu_register_group "framework-logging" "Framework Logging" "Inspect, follow, filter, and rotate the active framework logfile" 0 1 840
    sgnd_menu_register_item "log-view" "framework-logging" "View current logfile" "_framework_log_view" "Open the active framework logfile at its most recent entries" 0 30 1
    sgnd_menu_register_item "log-follow" "framework-logging" "Follow current logfile" "_framework_log_follow" "Follow new entries written to the active framework logfile" 0 30 1
    sgnd_menu_register_item "log-errors" "framework-logging" "Show recent errors" "_framework_log_show_errors" "Show the most recent error, failure, and fatal log entries" 0 30 1
    sgnd_menu_register_item "log-rotate" "framework-logging" "Rotate current logfile" "_framework_log_rotate" "Rotate the active framework logfile using the configured retention settings" 0 30 1

    sgnd_menu_register_group "diagnostics" "Framework Diagnostics" "Run the complete framework smoke test" 0 1 850
    sgnd_menu_register_item "smoketest" "diagnostics" "Framework smoke test" "_framework_smoketest" "Run the complete SolidGroundUX framework smoke test" 0 30 1
