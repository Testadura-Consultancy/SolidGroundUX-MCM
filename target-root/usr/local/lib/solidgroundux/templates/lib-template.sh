# ==================================================================================
# SolidGroundUX - Library Template
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624021
#   Checksum    : 71148731c9d74ea17f44f96eaffd25fad8ec57ad0b74c7f0d70fa294cf20f8d4
#   Source      : lib-template.sh
#   Type        : library
#   Group       : SDK
#   Subgroup    : Templates
#   Purpose     : Canonical template for source-only framework libraries
#
# Description:
#   Provides the standard structure for framework libraries, including:
#     - canonical script header sections
#     - library-only execution guard (must be sourced, never executed)
#     - idempotent load guard
#     - naming conventions for internal and public functions
#     - reference function header layout
#
# Design principles:
#   - Libraries define functions and constants only
#   - No auto-execution (must always be sourced)
#   - Keep behavior deterministic and side-effect aware
#   - Separate mechanism (library) from policy (caller)
#
# Role in framework:
#   - Base template for all SolidGroundUX library modules
#   - Defines structure, conventions, and documentation standards
#
# Non-goals:
#   - Executable scripts (use exe-template.sh)
#   - Application logic
#   - Framework bootstrap or path resolution
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
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
# - Internal helpers ---------------------------------------------------------------
    # doc$ Internal helper naming
        # Prefix internal-only helpers with "_" (never "sgnd_").
        # Example:
        #   _<libname>_helper() { :; }

# - Public API -------------------------------------------------------------------
    # doc$ Public API naming
        # Prefix public framework functions with "sgnd_" (never "_").
        # Example:
        #   sgnd_<libname>_do_something() { :; }

    # doc$ Default function header
        # <function_name>
        # . Purpose
        #   <one-line description>
        #
        # . Behavior
        #   <optional: key behavior summary when non-trivial>
        #
        # . Arguments
        #   $1  ...
        #   $2  ...
        #
        # Inputs (globals):
        #   FOO, BAR   (only if used)
        #
        # Outputs (globals):
        #   BAZ        (only if set)
        #
        # . Output
        #   Writes ... to stdout/stderr (only if applicable)
        #
        # . Side effects
        #   Creates/updates/deletes files, sets permissions, etc.
        #
        # . Returns
        #   0 on success, non-zero on failure
        #
        # . Usage
        #   <function_name> arg1 arg2
        #
        # Examples:
        #   <function_name> "value"
        #
        # Notes:
        #   - Edge cases / gotchas


