# =====================================================================================
# SolidGroundUX Management Console Modules - Project Definitions
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2630201
#   Checksum    : 1b8f86c4120978bf1ef9ec3336fc29bbc77b99cb4142fc4ddb79c5068fb61ccb
#   Source      : solidgroundux-management-modules-definitions.sh
#   Type        : library
#   Group       : Globals
#   Purpose     : Project-wide identity and release globals
# =====================================================================================
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
        #   ```bash
        #   _sgnd_lib_guard
        #   ```
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
# - Framework identity --------------------------------------------------------------
    # def: Framework identity
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_PRODUCT="SolidGroundUX Management Console Modules"
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_VERSION=2.1
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_BUILD=2630201

    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_COMPANY="Testadura Consultancy"
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_COPYRIGHT="© 2025 - 2026 Testadura Consultancy"
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_LICENSE="Testadura Non-Commercial License (TD-NC) v1.1."
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_DOCUMENTATION=""
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_RELEASE_URL="https://github.com/Testadura-Consultancy/solidgrond-management-modules/releases"
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_APPENDICES="attribution,license,changelog"
    SGND_SOLIDGROUND_MANAGEMENT_CONSOLE_MODULES_RELEASE_EXCLUDES="usr/local/lib/solidgroundux/templates"
    # def$