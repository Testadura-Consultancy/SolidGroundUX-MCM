# ==================================================================================
# SolidGroundUX - SolidGround Framework Test
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Source      : 45-solidground-framework-test.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Register SolidGroundUX framework test and validation actions
#
# Description:
#   Provides the Management Console presentation layer for framework testing.
#   Test implementation is owned by framework-smoketest.sh; this module only
#   registers menu actions and dispatches the requested test suite.
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

    SGND_MODULE_NAME="${SGND_FRAMEWORK_TEST_MODULE_NAME}"
    SGND_MODULE_VERSION="${SGND_FRAMEWORK_TEST_MODULE_VERSION}"
    SGND_MODULE_DESC="${SGND_FRAMEWORK_TEST_MODULE_DESC}"

# - Dispatch -----------------------------------------------------------------------
    # fn$ _framework_test_run - Dispatch a framework test suite to the test executable
    _framework_test_run() {
        local suite="${1:?missing test suite}"
        local -a args=(--suite "$suite")

        # The validation suites are read-only, but propagating DRYRUN keeps the
        # executable in the same framework mode as the parent console. Interactive
        # smoke tests use it to suppress tests that intentionally write to the log.
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            args+=(--dryrun)
        fi

        _sgnd_run_public_command "sgnd-framework-smoketest" "${args[@]}"
    }

    _framework_test_smoketest() {
        _framework_test_run "smoke"
    }

    _framework_test_validate_installation() {
        _framework_test_run "installation"
    }

    _framework_test_validate_console() {
        _framework_test_run "console"
    }

    _framework_test_validate_modules() {
        _framework_test_run "modules"
    }

    _framework_test_run_all() {
        _framework_test_run "all"
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

    sgnd_menu_register_item "framework-test-modules" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Run module validations" "_framework_test_validate_modules" "Run existing validators for components applicable to this host" 0 15 1 0

    sgnd_menu_register_item "framework-test-all" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Run all framework tests" "_framework_test_run_all" "Run installation, console, module, and interactive smoke tests" 0 30 1 0

    sayinfo "SolidGround Framework Test module registered with the console."
