# ==================================================================================
# SolidGroundUX Management Console Modules - SolidGround Framework Test
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 1.2
#   Source      : 45-solidground-framework-test.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Register SolidGroundUX framework test and validation actions
#
#   Build : 2626021
#   Checksum : d652f54935eeaf507ebaea5304389c925a0ac9192b1be5a0ef187253a52fe6a7
# Description:
#   Provides the Management Console presentation layer for framework testing.
#   Framework smoke tests are owned by the SolidGroundUX framework. This module acts as
#   the Management Console test agent and owns module-contract validation/reporting.
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
# - Module metadata ----------------------------------------------------------------
    SGND_FRAMEWORK_TEST_MODULE_ID="framework-test"
    SGND_FRAMEWORK_TEST_MODULE_NAME="SolidGround Framework Test"
    SGND_FRAMEWORK_TEST_MODULE_VERSION="2.0.0"
    SGND_FRAMEWORK_TEST_MODULE_DESC="Test and validate SolidGroundUX framework and installed modules"

    SGND_MODULE_ID="${SGND_FRAMEWORK_TEST_MODULE_ID}"

    SGND_MODULE_NAME="${SGND_FRAMEWORK_TEST_MODULE_NAME}"
    SGND_MODULE_VERSION="${SGND_FRAMEWORK_TEST_MODULE_VERSION}"
    SGND_MODULE_DESC="${SGND_FRAMEWORK_TEST_MODULE_DESC}"

# - Test agent ---------------------------------------------------------------------
    _framework_test_run_framework_suite() {
        local suite="${1:?missing test suite}"
        local -a args=(--suite "$suite")

        (( ${FLAG_DRYRUN:-0} == 1 )) && args+=(--dryrun)
        _sgnd_run_public_command "sgnd-smoketest" "${args[@]}"
    }

    _framework_test_smoketest() {
        _framework_test_run_framework_suite "smoke"
    }

    _framework_test_validate_installation() {
        _framework_test_run_framework_suite "installation"
    }

    _framework_test_console_result() {
        local label="${1:?missing label}"
        local status="${2:?missing status}"
        local detail="${3:-}"
        local value="$status"

        [[ -z "$detail" ]] || value="$status - $detail"
        sgnd_print_labeledvalue --label "$label" --value "$value" --labelwidth 32

        case "$status" in
            PASS) FRAMEWORK_TEST_CONSOLE_PASS=$((FRAMEWORK_TEST_CONSOLE_PASS + 1)); return 0 ;;
            FAIL) FRAMEWORK_TEST_CONSOLE_FAIL=$((FRAMEWORK_TEST_CONSOLE_FAIL + 1)); return 1 ;;
        esac
        return 1
    }

    _framework_test_validate_console() {
        local row=""
        local key=""
        local group=""
        local label=""
        local handler=""
        local desc=""
        local source=""
        local builtin=""
        local waitsecs=""
        local visible=""
        local indent=""
        local status=""
        local ord=""
        local group_count=0
        local item_count=0
        local -A group_keys=()
        local -A item_keys=()

        FRAMEWORK_TEST_CONSOLE_PASS=0
        FRAMEWORK_TEST_CONSOLE_FAIL=0

        sgnd_print
        sgnd_print_sectionheader "Console registration"

        if ! declare -p SGND_GROUP_ROWS SGND_ITEM_ROWS >/dev/null 2>&1; then
            _framework_test_console_result "Console registration" "FAIL" "menu registration model is not available" || true
        else
            group_count="${#SGND_GROUP_ROWS[@]}"
            item_count="${#SGND_ITEM_ROWS[@]}"

            for row in "${SGND_GROUP_ROWS[@]}"; do
                IFS='|' read -r key label desc source builtin visible ord <<< "$row"
                if [[ -z "$key" ]]; then
                    _framework_test_console_result "Console group" "FAIL" "empty group key" || true
                    continue
                fi
                if [[ -n "${group_keys[$key]+x}" ]]; then
                    _framework_test_console_result "Console group $key" "FAIL" "duplicate key" || true
                else
                    group_keys["$key"]=1
                fi
            done

            for row in "${SGND_ITEM_ROWS[@]}"; do
                IFS='|' read -r key group label handler desc source builtin waitsecs visible indent status <<< "$row"

                if [[ -z "$key" ]]; then
                    _framework_test_console_result "Console item" "FAIL" "empty item key" || true
                    continue
                fi

                if [[ -n "${item_keys[$key]+x}" ]]; then
                    _framework_test_console_result "Console item $key" "FAIL" "duplicate key" || true
                else
                    item_keys["$key"]=1
                fi

                if [[ -z "${group_keys[$group]+x}" ]]; then
                    _framework_test_console_result "Console item $key" "FAIL" "missing group: $group" || true
                fi

                if [[ -n "$handler" ]] && ! declare -F "$handler" >/dev/null 2>&1; then
                    _framework_test_console_result "Console item $key" "FAIL" "missing handler: $handler" || true
                fi
            done

            _framework_test_console_result "Registered groups" "PASS" "$group_count" || true
            _framework_test_console_result "Registered items" "PASS" "$item_count" || true
        fi

        sgnd_print
        sgnd_print_sectionheader "Console registration summary"
        sgnd_print_labeledvalue --label "Passed" --value "$FRAMEWORK_TEST_CONSOLE_PASS" --labelwidth 18
        sgnd_print_labeledvalue --label "Failed" --value "$FRAMEWORK_TEST_CONSOLE_FAIL" --labelwidth 18
        sgnd_print

        if (( FRAMEWORK_TEST_CONSOLE_FAIL == 0 )); then
            sayok "Console registration passed."
        else
            sayfail "Console registration reported $FRAMEWORK_TEST_CONSOLE_FAIL failure(s)."
        fi

        sgnd_print
        sgnd_print_sectionheader ""
        (( FRAMEWORK_TEST_CONSOLE_FAIL == 0 ))
    }

    _framework_test_read_module_metadata() {
        local module_file="${1:?missing module file}"
        local line=""
        local value=""

        FRAMEWORK_TEST_DISCOVERED_ID=""
        FRAMEWORK_TEST_DISCOVERED_NAME=""

        line="$(grep -m1 -E '^[[:space:]]*SGND_[A-Z0-9_]+_MODULE_ID="[^"]+"' "$module_file" 2>/dev/null || true)"
        value="${line#*=}"
        value="${value#\"}"
        value="${value%\"}"
        FRAMEWORK_TEST_DISCOVERED_ID="$value"

        line="$(grep -m1 -E '^[[:space:]]*SGND_[A-Z0-9_]+_MODULE_NAME="[^"]+"' "$module_file" 2>/dev/null || true)"
        value="${line#*=}"
        value="${value#\"}"
        value="${value%\"}"
        FRAMEWORK_TEST_DISCOVERED_NAME="$value"

        [[ -n "$FRAMEWORK_TEST_DISCOVERED_ID" && -n "$FRAMEWORK_TEST_DISCOVERED_NAME" ]]
    }

    _framework_test_render_validation_result() {
        local status="${1:?missing status}"
        local label="${2:?missing label}"
        local message="${3:-}"

        case "$status" in
            0) sayok "$label: ${message:-Passed}" ;;
            1) sayfail "$label: ${message:-Failed}" ;;
            2) saywarning "$label: ${message:-Warning}" ;;
            3) sayinfo "$label: ${message:-Skipped}" ;;
            *) sayfail "$label: Invalid validator return code $status. ${message}" ;;
        esac
    }

    _framework_test_validate_modules() {
        local module_dir="${SGND_FRAMEWORK_ROOT%/}/usr/local/libexec/solidgroundux/console-modules"
        local module_file=""
        local module_id=""
        local module_name=""
        local validator=""
        local message=""
        local rc=0
        local passed=0
        local failed=0
        local warnings=0
        local skipped=0
        local contract_errors=0
        local -a result_status=()
        local -a result_name=()
        local -a result_message=()
        local -a passed_modules=()
        local -a warning_modules=()
        local -a failed_modules=()
        local -a skipped_modules=()

        [[ "$SGND_FRAMEWORK_ROOT" == "/" ]] && module_dir="/usr/local/libexec/solidgroundux/console-modules"

        sgnd_print
        sgnd_print_sectionheader "Module validations"
        saystart "Running module validations."

        while IFS= read -r -d '' module_file; do
            if ! _framework_test_read_module_metadata "$module_file"; then
                result_status+=(1)
                result_name+=("$(basename "$module_file")")
                result_message+=("Module metadata contract is incomplete.")
                failed=$((failed + 1))
                failed_modules+=("$(basename "$module_file")")
                contract_errors=$((contract_errors + 1))
                continue
            fi

            module_id="$FRAMEWORK_TEST_DISCOVERED_ID"
            module_name="$FRAMEWORK_TEST_DISCOVERED_NAME"
            validator="validate_module_${module_id//-/_}"
            rc=0
            message=""
            SGND_MODULE_VALIDATION_MESSAGE=""

            # Validators live in the implementation modules. The console discovers
            # modules lazily, so a discovered module is not necessarily loaded yet.
            # Use the console-owned loader rather than sourcing the file directly; this
            # preserves module context/registration and records the module as loaded.
            if ! declare -F "$validator" >/dev/null 2>&1; then
                if declare -F _sgnd_console_source_module >/dev/null 2>&1; then
                    if _sgnd_console_source_module "$module_file"; then
                        if declare -p SGND_CONSOLE_LOADED_MODULES >/dev/null 2>&1; then
                            SGND_CONSOLE_LOADED_MODULES["$module_id"]=1
                        fi
                    else
                        rc=1
                        message="Module could not be loaded for validation: $module_id"
                        contract_errors=$((contract_errors + 1))
                    fi
                else
                    rc=1
                    message="Console module loader is unavailable."
                    contract_errors=$((contract_errors + 1))
                fi
            fi

            if (( rc == 0 )); then
                if ! declare -F "$validator" >/dev/null 2>&1; then
                    rc=1
                    message="Validation contract missing: $validator"
                    contract_errors=$((contract_errors + 1))
                else
                    "$validator"
                    rc=$?
                    message="${SGND_MODULE_VALIDATION_MESSAGE:-}"
                fi
            fi

            case "$rc" in
                0)
                    passed=$((passed + 1))
                    passed_modules+=("$module_name")
                    ;;
                1)
                    failed=$((failed + 1))
                    failed_modules+=("$module_name")
                    ;;
                2)
                    warnings=$((warnings + 1))
                    warning_modules+=("$module_name")
                    ;;
                3)
                    skipped=$((skipped + 1))
                    skipped_modules+=("$module_name")
                    ;;
                *)
                    message="Invalid validator return code $rc${message:+: $message}"
                    rc=1
                    failed=$((failed + 1))
                    failed_modules+=("$module_name")
                    contract_errors=$((contract_errors + 1))
                    ;;
            esac

            result_status+=("$rc")
            result_name+=("$module_name")
            result_message+=("$message")
        done < <(find "$module_dir" -maxdepth 1 -type f -name '*.sh' -print0 2>/dev/null | LC_ALL=C sort -z)

        sayend "Module validations completed."

        sgnd_print
        sgnd_print_sectionheader "Module validation report"
        local i=0
        for i in "${!result_status[@]}"; do
            _framework_test_render_validation_result                 "${result_status[$i]}"                 "${result_name[$i]}"                 "${result_message[$i]}"
        done

        sgnd_print
        if (( passed > 0 )); then
            sgnd_print_labeledmultivalue --label "Passed ($passed)" --labelwidth 16 --items "${passed_modules[@]}"
        else
            sgnd_print_labeledvalue --label "Passed" --value "0" --labelwidth 16
        fi
        if (( warnings > 0 )); then
            sgnd_print_labeledmultivalue --label "Warnings ($warnings)" --labelwidth 16 --items "${warning_modules[@]}"
        else
            sgnd_print_labeledvalue --label "Warnings" --value "0" --labelwidth 16
        fi
        if (( failed > 0 )); then
            sgnd_print_labeledmultivalue --label "Failed ($failed)" --labelwidth 16 --items "${failed_modules[@]}"
        else
            sgnd_print_labeledvalue --label "Failed" --value "0" --labelwidth 16
        fi
        if (( skipped > 0 )); then
            sgnd_print_labeledmultivalue --label "Skipped ($skipped)" --labelwidth 16 --items "${skipped_modules[@]}"
        else
            sgnd_print_labeledvalue --label "Skipped" --value "0" --labelwidth 16
        fi
        (( contract_errors == 0 )) || sgnd_print_labeledvalue --label "Contract errors" --value "$contract_errors" --labelwidth 16
        sgnd_print
        sgnd_print_sectionheader ""

        local validation_rc=0
        (( failed == 0 )) || validation_rc=1
        return "$validation_rc"
    }

    _framework_test_run_all() {
        local rc=0

        _framework_test_validate_installation || rc=1
        _framework_test_validate_console || rc=1
        _framework_test_validate_modules || rc=1
        _framework_test_smoketest || rc=1
        return "$rc"
    }

# - Module validation contract ------------------------------------------------------
    validate_module_framework_test() {
        SGND_MODULE_VALIDATION_MESSAGE="Framework Test agent is loaded and registered."
        return 0
    }

# - Console registration -----------------------------------------------------------
    sgnd_menu_register_group \
        "$SGND_FRAMEWORK_TEST_MODULE_ID" \
        "$SGND_FRAMEWORK_TEST_MODULE_NAME" \
        "$SGND_FRAMEWORK_TEST_MODULE_DESC" \
        0 \
        1 \
        450

    # The standalone smoke tester owns its own interactive finish/return flow, so it
    # does not need an additional console auto-continue pause after exiting.
    sgnd_menu_register_item "framework-test-smoke" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Run framework smoke tests" "_framework_test_smoketest" "Open the interactive framework UI smoke-test suite" 0 0 1 0

    sgnd_menu_register_item "framework-test-install" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Validate framework installation" "_framework_test_validate_installation" "Validate required framework files, module directory, and public commands" 0 15 1 0

    sgnd_menu_register_item "framework-test-console" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Validate console registration" "_framework_test_validate_console" "Load all console modules and validate groups, items, references, and handlers" 0 15 1 0

    sgnd_menu_register_item "framework-test-modules" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Run module validations" "_framework_test_validate_modules" "Run each loaded module validator through the standard module validation contract" 0 15 1 0

    sgnd_menu_register_item "framework-test-all" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Run all framework tests" "_framework_test_run_all" "Run installation, console, module, and interactive smoke tests" 0 30 1 0

    sayinfo "SolidGround Framework Test module registered with the console."
