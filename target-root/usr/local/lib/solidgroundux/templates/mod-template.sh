# ==================================================================================
# SolidGroundUX - Console Module Template
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626414
#   Checksum    : d9225da61eb4ccc87ec2a1c10491859ce1e335acdc72213fbac6e927071178c1
#   Source      : mod-template.sh
#   Type        : module
#   Group       : SDK
#   Subgroup    : Templates
#   Purpose     : Canonical template for sgnd-console modules
#
# Description:
#   Provides the standard structure for modules that extend sgnd-console with:
#     - one or more menu groups
#     - one or more registered menu actions
#     - optional internal helper functions
#
#   Console modules are source-only plugin libraries. Their only intended
#   load-time side effect is self-registration with sgnd-console.
#
# Design principles:
#   - Modules define functions first, then register themselves explicitly
#   - Registration is data-driven through the public sgnd_menu_register_group/item API
#   - Keep module logic local and menu-facing
#   - Avoid framework-wide policy decisions inside modules
#
# Role in framework:
#   - Extends sgnd-console with domain-specific actions and menu entries
#   - Acts as a lazy-loaded page/plugin layer on top of the console host
#   - May depend on framework and console common libraries declared by the host, but not on another page module having been opened
#
# Assumptions:
#   - Lazy-loaded by sgnd-console when the module page is first opened
#   - sgnd_menu_register_group and sgnd_menu_register_item are available
#   - Framework helpers such as say* and sgnd_print_* may be used
#
# Non-goals:
#   - Standalone execution
#   - Bootstrap, path resolution, or framework initialization
#   - Full-screen UI behavior outside the sgnd-console host
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
    # Replace SAMPLE_MODULE in all variable names and values below.
    # MODULE_NAME and MODULE_DESC must remain literal quoted assignments because the
    # main index reads them before sourcing this file.
    SGND_SAMPLE_MODULE_ID="sample-module"
    SGND_SAMPLE_MODULE_NAME="Sample Module"
    SGND_SAMPLE_MODULE_VERSION="1.0.0"
    SGND_SAMPLE_MODULE_DESC="Describe the module capability"

    # Transient console-loader metadata contract.
    SGND_MODULE_ID="${SGND_SAMPLE_MODULE_ID}"
    SGND_MODULE_NAME="${SGND_SAMPLE_MODULE_NAME}"
    SGND_MODULE_VERSION="${SGND_SAMPLE_MODULE_VERSION}"
    SGND_MODULE_DESC="${SGND_SAMPLE_MODULE_DESC}"

# - Internal helpers -------------------------------------------------------------
    # fn$ _sample_format_status
        # . Purpose
        #   Format a status value for display by a public module action.
        #
        # . Behavior
        #   - Accepts a raw status value.
        #   - Substitutes a readable fallback when the value is empty.
        #   - Writes the formatted value to stdout.
        #
        # Inputs:
        #   $1 - Raw status value.
        #
        # Outputs (stdout):
        #   Formatted status value.
        #
        # . Returns
        #   0 after writing the formatted value.
        #
        # . Usage
        #   _sample_format_status "active"
    _sample_format_status() {
        local status="${1:-}"

        [[ -n "$status" ]] || status="Unavailable"
        printf '%s\n' "$status"
    }

# - Public module actions --------------------------------------------------------
    # fn$ sample_show_status
        # . Purpose
        #   Display example module status using the canonical console helpers.
        #
        # . Behavior
        #   - Resolves the current example status through the internal helper.
        #   - Displays the module section and status value.
        #
        # Outputs (console):
        #   Example module status.
        #
        # . Returns
        #   0 after displaying status.
        #
        # . Usage
        #   sample_show_status
    sample_show_status() {
        local status=""

        status="$(_sample_format_status "active")"

        sgnd_print
        sgnd_print_sectionheader "$SGND_SAMPLE_MODULE_NAME"
        sgnd_print_labeledvalue --label "Status" --value "$status" --labelwidth 20
    }

    # fn: sample_run_action - Run the example module action
        # . Returns
        #   0 after reporting successful execution.
        #
        # . Usage
        #   sample_run_action
    sample_run_action() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would run the sample module action."
            return 0
        fi

        sayok "Sample module action completed successfully."
    }

# - Console registration ---------------------------------------------------------
    sgnd_menu_register_group \
        "$SGND_SAMPLE_MODULE_ID" \
        "$SGND_SAMPLE_MODULE_NAME" \
        "$SGND_SAMPLE_MODULE_DESC" \
        0 \
        1 \
        300

    sgnd_menu_register_item \
        "sample-action" \
        "$SGND_SAMPLE_MODULE_ID" \
        "Run sample action" \
        "sample_run_action" \
        "Run the example module action" \
        0 \
        5 \
        1

    sgnd_menu_register_item \
        "sample-status" \
        "$SGND_SAMPLE_MODULE_ID" \
        "Show sample status" \
        "sample_show_status" \
        "Show example module status" \
        0 \
        15 \
        1
