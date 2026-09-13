# ==================================================================================
# SolidGroundUX - SolidGround Framework Test
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624102
#   Checksum    : 94cd55309d21543f8c17a2b1cb14dc86a119e9af8e516c62a8a9c6a9fec884fe
#   Source      : 45-solidground-framework-test.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Centralize SolidGroundUX framework and module validation
#
# Description:
#   Provides a single management-console entry point for framework smoke testing,
#   installation checks, console-registration checks, and available module
#   validations. Existing module validators remain owned by their respective modules;
#   this module only discovers and orchestrates them.
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
    SGND_FRAMEWORK_TEST_MODULE_ID="framework-test"
    SGND_FRAMEWORK_TEST_MODULE_NAME="SolidGround Framework Test"
    SGND_FRAMEWORK_TEST_MODULE_VERSION="1.0.0"
    SGND_FRAMEWORK_TEST_MODULE_DESC="Test and validate SolidGroundUX framework and installed modules"

    SGND_MODULE_NAME="${SGND_FRAMEWORK_TEST_MODULE_NAME}"
    SGND_MODULE_VERSION="${SGND_FRAMEWORK_TEST_MODULE_VERSION}"
    SGND_MODULE_DESC="${SGND_FRAMEWORK_TEST_MODULE_DESC}"

# - Internal helpers ------------------------------------------------------------
    # fn: _framework_test_root_path - Resolve an installed path below SGND_FRAMEWORK_ROOT
        # Returns:
        #   Prints the resolved path and returns 0.
        #
        # Usage:
        #   path="$(_framework_test_root_path /usr/local/lib/solidgroundux/common/sgnd-core.sh)"
    _framework_test_root_path() {
        local relative="${1:?missing path}"
        local root="${SGND_FRAMEWORK_ROOT:-/}"

        relative="${relative#/}"
        if [[ "$root" == "/" ]]; then
            printf '/%s\n' "$relative"
        else
            printf '%s/%s\n' "${root%/}" "$relative"
        fi
    }

    # fn: _framework_test_result - Render one PASS, FAIL, or SKIP result
        # . Purpose
        #   Render a consistent result line and optional explanatory detail.
        #
        # . Arguments
        #   $1  LABEL   - Check name.
        #   $2  STATUS  - PASS, FAIL, or SKIP.
        #   $3  DETAIL  - Optional explanatory text.
        #
        # . Returns
        #   0 for PASS/SKIP; 1 for FAIL.
        #
        # . Usage
        #   _framework_test_result "Console model" "PASS" "10 groups, 42 items"
    _framework_test_result() {
        local label="${1:?missing label}"
        local status="${2:?missing status}"
        local detail="${3:-}"
        local value="$status"

        [[ -z "$detail" ]] || value="$status - $detail"
        sgnd_print_labeledvalue --label "$label" --value "$value" --labelwidth 30

        [[ "$status" != "FAIL" ]]
    }

    # fn: _framework_test_load_module - Ensure a console module is loaded
        # . Purpose
        #   Load a discovered console module before invoking one of its handlers.
        #
        # . Arguments
        #   $1  MODULE_ID - Console module ID derived from its filename.
        #
        # . Returns
        #   0 when the module is already loaded or was loaded successfully; 1 otherwise.
        #
        # . Usage
        #   _framework_test_load_module "computer-setup"
    _framework_test_load_module() {
        local module_id="${1:?missing module id}"
        local i=0
        local page_id=""
        local module_file=""

        if [[ "${SGND_CONSOLE_LOADED_MODULES[$module_id]:-0}" == "1" ]]; then
            return 0
        fi

        for (( i=0; i<${#SGND_CONSOLE_PAGE_ROWS[@]}; i++ )); do
            page_id="$(sgnd_dt_get "$SGND_PAGE_SCHEMA" SGND_CONSOLE_PAGE_ROWS "$i" id)"
            [[ "$page_id" == "$module_id" ]] || continue

            module_file="$(sgnd_dt_get "$SGND_PAGE_SCHEMA" SGND_CONSOLE_PAGE_ROWS "$i" source)"
            [[ -r "$module_file" ]] || return 1
            _sgnd_console_source_module "$module_file" || return 1
            SGND_CONSOLE_LOADED_MODULES["$module_id"]=1
            return 0
        done

        return 1
    }

    # fn: _framework_test_run_validator - Run one existing module validation handler
        # . Purpose
        #   Invoke a module-owned validator when its component is applicable.
        #
        # . Arguments
        #   $1  LABEL       - Friendly component name.
        #   $2  MODULE_ID   - Console module that owns the validator.
        #   $3  HANDLER     - Existing validation function.
        #   $4  APPLICABLE  - 1 when configured/installed, otherwise 0.
        #   $5  SKIP_REASON - Explanation shown when not applicable.
        #
        # . Returns
        #   0 for PASS/SKIP; 1 when the validator fails or is unexpectedly missing.
        #
        # . Usage
        #   _framework_test_run_validator "Web server" "web-server" "_web_server_validate" 1
    _framework_test_run_validator() {
        local label="${1:?missing label}"
        local module_id="${2:?missing module id}"
        local handler="${3:?missing handler}"
        local applicable="${4:-1}"
        local skip_reason="${5:-not configured on this host}"

        if (( ! applicable )); then
            _framework_test_result "$label" "SKIP" "$skip_reason"
            return 0
        fi

        if ! declare -F "$handler" >/dev/null; then
            if ! _framework_test_load_module "$module_id"; then
                _framework_test_result "$label" "FAIL" "could not load module: $module_id"
                return 1
            fi
        fi

        if ! declare -F "$handler" >/dev/null; then
            _framework_test_result "$label" "FAIL" "validator missing after module load: $handler"
            return 1
        fi

        sgnd_print
        sgnd_print_sectionheader --text "$label"
        if "$handler"; then
            _framework_test_result "$label" "PASS"
            return 0
        fi

        _framework_test_result "$label" "FAIL"
        return 1
    }

    # fn: _framework_test_is_storage_configured - Test whether managed storage is configured
        # Returns:
        #   0 when SolidGroundUX storage configuration or an SGND_STORAGE fstab entry exists.
        #
        # Usage:
        #   _framework_test_is_storage_configured
    _framework_test_is_storage_configured() {
        [[ -s /etc/solidgroundux/storage.cfg ]] || grep -Eq '(^|[[:space:]])SGND_STORAGE([[:space:]]|$)' /etc/fstab 2>/dev/null
    }

    # fn: _framework_test_is_ad_server - Test whether this host is an AD domain controller
        # Returns:
        #   0 when smb.conf identifies an Active Directory domain controller.
        #
        # Usage:
        #   _framework_test_is_ad_server
    _framework_test_is_ad_server() {
        grep -Eiq '^[[:space:]]*server[[:space:]]+role[[:space:]]*=[[:space:]]*active[[:space:]]+directory[[:space:]]+domain[[:space:]]+controller' \
            /etc/samba/smb.conf 2>/dev/null
    }

    # fn: _framework_test_is_ad_client - Test whether this host has an active realm membership
        # Returns:
        #   0 when realmd reports at least one configured realm.
        #
        # Usage:
        #   _framework_test_is_ad_client
    _framework_test_is_ad_client() {
        command -v realm >/dev/null 2>&1 && [[ -n "$(realm list 2>/dev/null)" ]]
    }

    # fn: _framework_test_is_samba_file_server - Test whether the Samba file service is installed
        # Returns:
        #   0 when smbd is available and the host is not an AD domain controller.
        #
        # Usage:
        #   _framework_test_is_samba_file_server
    _framework_test_is_samba_file_server() {
        command -v smbd >/dev/null 2>&1 && ! _framework_test_is_ad_server
    }

# - Framework test actions ------------------------------------------------------
    # fn: _framework_test_smoketest - Open the canonical framework smoke tester
        # Returns:
        #   Exit status of sgnd-framework-smoketest.
        #
        # Usage:
        #   _framework_test_smoketest
    _framework_test_smoketest() {
        _sgnd_run_public_command "sgnd-framework-smoketest"
    }

    # fn: _framework_test_validate_installation - Validate the installed framework surface
        # . Purpose
        #   Check the core framework libraries, console executable, smoke tester, module
        #   directory, and public command wrappers required by an installed system.
        #
        # . Returns
        #   0 when all installation checks pass; 1 otherwise.
        #
        # . Usage
        #   _framework_test_validate_installation
    _framework_test_validate_installation() {
        local failures=0
        local path=""
        local module_dir=""
        local module_count=0
        local relative=""
        local -a required_files=(
            "/usr/local/lib/solidgroundux/common/sgnd-bootstrap.sh"
            "/usr/local/lib/solidgroundux/common/sgnd-core.sh"
            "/usr/local/lib/solidgroundux/common/sgnd-menu.sh"
            "/usr/local/lib/solidgroundux/common/ui.sh"
            "/usr/local/libexec/solidgroundux/management-console.sh"
            "/usr/local/libexec/solidgroundux/framework-smoketest.sh"
        )
        local -a required_commands=(
            "sgnd-console"
            "sgnd-framework-smoketest"
        )
        local command_name=""

        sgnd_print
        sgnd_print_sectionheader --text "Framework installation"

        for relative in "${required_files[@]}"; do
            path="$(_framework_test_root_path "$relative")"
            if [[ -r "$path" ]]; then
                _framework_test_result "$(basename "$relative")" "PASS"
            else
                _framework_test_result "$(basename "$relative")" "FAIL" "$path" || true
                failures=$((failures + 1))
            fi
        done

        module_dir="$(_framework_test_root_path /usr/local/libexec/solidgroundux/console-modules)"
        if [[ -d "$module_dir" ]]; then
            module_count="$(find "$module_dir" -maxdepth 1 -type f -name '*.sh' -printf '.' 2>/dev/null | wc -c)"
            _framework_test_result "Console modules" "PASS" "$module_count module(s)"
        else
            _framework_test_result "Console modules" "FAIL" "$module_dir" || true
            failures=$((failures + 1))
        fi

        for command_name in "${required_commands[@]}"; do
            path="$(_framework_test_root_path "/usr/local/bin/$command_name")"
            if [[ -x "$path" ]]; then
                _framework_test_result "$command_name" "PASS" "$path"
            else
                _framework_test_result "$command_name" "FAIL" "public command not executable: $path" || true
                failures=$((failures + 1))
            fi
        done

        sgnd_print
        if (( failures == 0 )); then
            sayok "Framework installation validation passed."
            return 0
        fi

        sayfail "$failures framework installation check(s) failed."
        return 1
    }

    # fn: _framework_test_validate_console - Validate the current console registration model
        # . Purpose
        #   Verify that registered menu rows have unique keys, valid group references,
        #   and loaded handlers.
        #
        # . Returns
        #   0 when the active console model is internally consistent; 1 otherwise.
        #
        # . Usage
        #   _framework_test_validate_console
    _framework_test_validate_console() {
        local failures=0
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

        sgnd_print
        sgnd_print_sectionheader --text "Console registration"

        if ! declare -p SGND_GROUP_ROWS >/dev/null 2>&1 || ! declare -p SGND_ITEM_ROWS >/dev/null 2>&1; then
            _framework_test_result "Console model" "FAIL" "menu registration arrays are unavailable" || true
            return 1
        fi

        group_count="${#SGND_GROUP_ROWS[@]}"
        item_count="${#SGND_ITEM_ROWS[@]}"

        for row in "${SGND_GROUP_ROWS[@]}"; do
            IFS='|' read -r key label desc source builtin visible ord <<< "$row"
            if [[ -z "$key" ]]; then
                failures=$((failures + 1))
                continue
            fi
            if [[ -n "${group_keys[$key]+x}" ]]; then
                sayfail "Duplicate console group key: $key"
                failures=$((failures + 1))
            fi
            group_keys["$key"]=1
        done

        for row in "${SGND_ITEM_ROWS[@]}"; do
            IFS='|' read -r key group label handler desc source builtin waitsecs visible indent status <<< "$row"

            if [[ -z "$key" ]]; then
                sayfail "Console item with empty key detected"
                failures=$((failures + 1))
                continue
            fi

            if [[ -n "${item_keys[$key]+x}" ]]; then
                sayfail "Duplicate console item key: $key"
                failures=$((failures + 1))
            fi
            item_keys["$key"]=1

            if [[ -z "${group_keys[$group]+x}" ]]; then
                sayfail "Menu item '$key' references missing group '$group'"
                failures=$((failures + 1))
            fi

            if ! declare -F "$handler" >/dev/null; then
                sayfail "Menu item '$key' references missing handler '$handler'"
                failures=$((failures + 1))
            fi
        done

        _framework_test_result "Registered groups" "PASS" "$group_count"
        _framework_test_result "Registered items" "PASS" "$item_count"

        if [[ -n "${group_keys[$SGND_FRAMEWORK_TEST_MODULE_ID]+x}" ]]; then
            _framework_test_result "Framework test module" "PASS" "registered"
        else
            _framework_test_result "Framework test module" "FAIL" "group not registered" || true
            failures=$((failures + 1))
        fi

        sgnd_print
        if (( failures == 0 )); then
            sayok "Console registration validation passed."
            return 0
        fi

        sayfail "$failures console registration check(s) failed."
        return 1
    }

    # fn: _framework_test_validate_modules - Run validators owned by applicable modules
        # . Purpose
        #   Run existing module validations without duplicating their test logic.
        #
        # . Behavior
        #   - Always validates Computer Setup when its validator is loaded.
        #   - Runs service/storage validators only when the related component appears
        #     configured or installed on the current host.
        #   - Reports non-applicable components as SKIP rather than FAIL.
        #
        # . Returns
        #   0 when all applicable validators pass; 1 when one or more fail.
        #
        # . Usage
        #   _framework_test_validate_modules
    _framework_test_validate_modules() {
        local failures=0
        local applicable=0

        sgnd_print
        sgnd_print_sectionheader --text "Module validations"

        _framework_test_run_validator "Computer setup" "computer-setup" "_computer_validate" 1 || failures=$((failures + 1))

        applicable=0
        _framework_test_is_storage_configured && applicable=1
        _framework_test_run_validator "Storage" "storage" "storage_validate_provisioning" "$applicable" "storage is not configured" || failures=$((failures + 1))

        applicable=0
        _framework_test_is_ad_server && applicable=1
        _framework_test_run_validator "Active Directory server" "active-directory-server" "_adsvr_validate" "$applicable" "host is not an AD domain controller" || failures=$((failures + 1))

        applicable=0
        _framework_test_is_ad_client && applicable=1
        _framework_test_run_validator "Active Directory client" "active-directory-client" "_adc_validate" "$applicable" "host is not joined through realmd" || failures=$((failures + 1))

        applicable=0
        _framework_test_is_samba_file_server && applicable=1
        _framework_test_run_validator "Samba file server" "samba-file-server" "_smb_validate" "$applicable" "standalone Samba file service is not installed" || failures=$((failures + 1))

        applicable=0
        command -v nginx >/dev/null 2>&1 && applicable=1
        _framework_test_run_validator "Web server" "web-server" "_web_server_validate" "$applicable" "nginx is not installed" || failures=$((failures + 1))

        applicable=0
        [[ -x /opt/mssql/bin/sqlservr ]] && applicable=1
        _framework_test_run_validator "SQL Server" "sqlserver" "_sqlserver_validate" "$applicable" "SQL Server is not installed" || failures=$((failures + 1))

        sgnd_print
        if (( failures == 0 )); then
            sayok "All applicable module validations passed."
            return 0
        fi

        sayfail "$failures module validation(s) failed."
        return 1
    }

    # fn: _framework_test_run_all - Run the aggregate non-destructive validation suite
        # . Purpose
        #   Run framework-installation, console-registration, and applicable module
        #   validations as one release/integration verification pass.
        #
        # . Notes
        #   The interactive framework smoke tester remains a separate menu item because
        #   it intentionally exercises prompts, rendering, progress, and other manual UI.
        #
        # . Returns
        #   0 when every aggregate validation passes; 1 otherwise.
        #
        # . Usage
        #   _framework_test_run_all
    _framework_test_run_all() {
        local failures=0

        _framework_test_validate_installation || failures=$((failures + 1))
        _framework_test_validate_console || failures=$((failures + 1))
        _framework_test_validate_modules || failures=$((failures + 1))

        sgnd_print
        sgnd_print_sectionheader --text "Test summary"
        if (( failures == 0 )); then
            sayok "SolidGroundUX validation suite passed."
            return 0
        fi

        sayfail "$failures test area(s) reported failures."
        return 1
    }

# - Console registration ---------------------------------------------------------
    # Provides one central testing and validation surface for SolidGroundUX. The
    # framework smoke tester remains responsible for interactive framework/UI tests,
    # while this module adds structural installation and console checks and delegates
    # service-specific validation to the modules that own those services.
    #
    # . Menu items
    # ! Run framework smoke test
    #   > Open the comprehensive interactive framework smoke tester.
    #   > Handler: _framework_test_smoketest
    #   > Command: sgnd-framework-smoketest
    #
    # ! Validate framework installation
    #   > Validate required framework files, module directory, and public commands.
    #   > Handler: _framework_test_validate_installation
    #
    # ! Validate console registration
    #   > Validate registered groups, items, group references, and handlers.
    #   > Handler: _framework_test_validate_console
    #
    # ! Run module validations
    #   > Run existing validators for the components applicable to this host.
    #   > Handler: _framework_test_validate_modules
    #
    # ! Run full validation suite
    #   > Run installation, console, and applicable module validations in sequence.
    #   > Handler: _framework_test_run_all
    sgnd_menu_register_group \
        "$SGND_FRAMEWORK_TEST_MODULE_ID" \
        "$SGND_FRAMEWORK_TEST_MODULE_NAME" \
        "$SGND_FRAMEWORK_TEST_MODULE_DESC" \
        0 \
        1 \
        450

    sgnd_menu_register_item "framework-test-smoke" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Run framework smoke test" "_framework_test_smoketest" "Open the comprehensive interactive framework smoke tester" 0 15 1 0
    sgnd_menu_register_item "framework-test-install" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Validate framework installation" "_framework_test_validate_installation" "Validate required framework files, module directory, and public commands" 0 15 1 0
    sgnd_menu_register_item "framework-test-console" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Validate console registration" "_framework_test_validate_console" "Validate registered groups, items, group references, and handlers" 0 15 1 0
    sgnd_menu_register_item "framework-test-modules" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Run module validations" "_framework_test_validate_modules" "Run existing validators for components applicable to this host" 0 15 1 0
    sgnd_menu_register_item "framework-test-all" "$SGND_FRAMEWORK_TEST_MODULE_ID" "Run full validation suite" "_framework_test_run_all" "Run framework, console, and applicable module validations" 0 30 1 0

    sayinfo "SolidGround Framework Test module registered with the console."
