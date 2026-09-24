# ==================================================================================
# SolidGroundUX Management Console Modules - Development
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626710
#   Checksum    : 586fb658d0ad54a31464cae643789799b660585ce5e2227d86426c848de5b075
#   Source      : 90-development.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Tools for workspace creation, deployment, release preparation, wrapper generation, and documentation.
# Description:
#   Provides SolidGroundUX SDK development tooling for workspace creation,
#   deployment, release preparation, wrapper generation, and documentation.
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
    SGND_DEVELOPMENT_MODULE_ID="development"
    SGND_DEVELOPMENT_MODULE_NAME="Development"
    SGND_MODULE_ID="${SGND_DEVELOPMENT_MODULE_ID}"

    SGND_MODULE_NAME="$SGND_DEVELOPMENT_MODULE_NAME"
# - Development actions ------------------------------------------------------------
    # fn: _dev_create_workspace
        # . Purpose
        #   Launch the canonical SolidGroundUX workspace-creation tool.
        #
        # . Returns
        #   Returns the underlying public-command status.
        #
        # . Usage
        #   _dev_create_workspace
    _dev_create_workspace() {
        _sgnd_run_public_command "sgnd-create-workspace"
    }

    # fn: _dev_deploy_workspace
        # . Purpose
        #   Launch the canonical SolidGroundUX workspace-deployment tool.
        #
        # . Returns
        #   Returns the underlying public-command status.
        #
        # . Usage
        #   _dev_deploy_workspace
    _dev_deploy_workspace() {
        _sgnd_run_public_command "sgnd-deploy-workspace"
    }

    # fn: _dev_prepare_release
        # . Purpose
        #   Launch the canonical SolidGroundUX release-preparation tool.
        #
        # . Returns
        #   Returns the underlying public-command status.
        #
        # . Usage
        #   _dev_prepare_release
    _dev_prepare_release() {
        _sgnd_run_public_command "sgnd-prepare-release"
    }

    # fn: _dev_create_wrappers
        # . Purpose
        #   Launch the canonical SolidGroundUX wrapper-creation tool.
        #
        # . Returns
        #   Returns the underlying public-command status.
        #
        # . Usage
        #   _dev_create_wrappers
    _dev_create_wrappers() {
        _sgnd_run_public_command "sgnd-create-wrappers"
    }

    # fn: _dev_generate_docs
        # . Purpose
        #   Launch the canonical SolidGroundUX documentation generator.
        #
        # . Returns
        #   Returns the underlying public-command status.
        #
        # . Usage
        #   _dev_generate_docs
    _dev_generate_docs() {
        _sgnd_run_public_command "sgnd-doc-generator"
    }



# - Module validation contract -----------------------------------------------------
    # Return codes:
    #   0 = Passed
    #   1 = Failed
    #   2 = Warning
    #   3 = Skipped / not applicable
    #
    # Every validator sets SGND_MODULE_VALIDATION_MESSAGE to a concise result summary.
    # Detailed diagnostic output may be written by the validator or delegated action.
    validate_module_development() {
        SGND_MODULE_VALIDATION_MESSAGE="Development module is loaded and registered."
        return 0
    }

# - Console registration -----------------------------------------------------------
    # Provides SolidGroundUX development and release tooling from the management
    # console. Each menu item is a thin wrapper around the corresponding standalone
    # public command so the same workflows remain available outside the console.
    #
    # . Menu items
    # ! Create workspace
    #   > Create a template workspace with target-root structure.
    #   > Handler: _dev_create_workspace
    #   > Command: sgnd-create-workspace
    #
    # ! Deploy workspace
    #   > Select and deploy workspace files locally or remotely.
    #   > Handler: _dev_deploy_workspace
    #   > Command: sgnd-deploy-workspace
    #
    # ! Prepare release
    #   > Create a release archive with checksums and manifests.
    #   > Handler: _dev_prepare_release
    #   > Command: sgnd-prepare-release
    #
    # ! Create wrappers
    #   > Create root-aware bin or sbin wrappers for selected scripts.
    #   > Handler: _dev_create_wrappers
    #   > Command: sgnd-create-wrappers
    #
    # ! Generate documentation
    #   > Generate SolidGroundUX source documentation.
    #   > Handler: _dev_generate_docs
    #   > Command: sgnd-generate-docs
    sgnd_menu_register_group \
        "$SGND_DEVELOPMENT_MODULE_ID" \
        "$SGND_DEVELOPMENT_MODULE_NAME" \
        "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" \
        0 1 900

    sgnd_menu_register_item "dev-createws" "$SGND_DEVELOPMENT_MODULE_ID" "Create workspace" "_dev_create_workspace" "Create a template workspace with target-root structure" 0 15 1 0
    sgnd_menu_register_item "dev-deployws" "$SGND_DEVELOPMENT_MODULE_ID" "Deploy workspace" "_dev_deploy_workspace" "Select and deploy workspace files locally or remotely" 0 15 1 0
    sgnd_menu_register_item "dev-preprel" "$SGND_DEVELOPMENT_MODULE_ID" "Prepare release" "_dev_prepare_release" "Create a release archive with checksums and manifests" 0 15 1 0
    sgnd_menu_register_item "dev-wrappers" "$SGND_DEVELOPMENT_MODULE_ID" "Create wrappers" "_dev_create_wrappers" "Create root-aware bin or sbin wrappers for selected scripts" 0 20 1 0
    sgnd_menu_register_item "dev-gendocs" "$SGND_DEVELOPMENT_MODULE_ID" "Generate documentation" "_dev_generate_docs" "Generate SolidGroundUX source documentation" 0 25 1 0

    sayinfo "Development module registered with the console."
