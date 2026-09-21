# ==================================================================================
# SolidGroundUX Management Console Modules - Samba File Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626414
#   Source      : 30-samba-file-server.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Register and orchestrate Samba file-server management actions
#
#   Checksum : 9e87d430abe2b98a3d25f48bcabe56df2c05a10b78e6ec0bbbde7fa215669f74
# Description:
#   Registers Samba file-server and share-management actions with the Management
#   Console. Persistent server-management functionality is implemented by
#   manage-samba-file-server.sh; share lifecycle and access management is implemented
#   by manage-samba-shares.sh.
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
    SGND_SAMBA_FILE_MODULE_ID="samba-file-server"
    SGND_SAMBA_FILE_MODULE_NAME="Samba File Server"
    SGND_MODULE_ID="${SGND_SAMBA_FILE_MODULE_ID}"

    SGND_MODULE_NAME="$SGND_SAMBA_FILE_MODULE_NAME"
# - Project executable dispatch ----------------------------------------------------
    # fn$ _smb_run_project_script - Run a management executable owned by this project
    #
    # The module repository is intentionally separate from the SolidGroundUX framework
    # repository. Resolve project-owned executables relative to this module rather than
    # through SGND_FRAMEWORK_ROOT. Pass the active framework root explicitly so a
    # development project executable can still load the framework runtime used by the
    # current console.
    _smb_run_project_script() {
        local script_name="${1:?missing script name}"
        shift || true

        local module_dir=""
        local project_exec_dir=""
        local script_path=""
        local -a script_args=()

        module_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || return 1
        project_exec_dir="$(cd -- "$module_dir/.." && pwd)" || return 1
        script_path="$project_exec_dir/$script_name"

        [[ -x "$script_path" ]] || {
            sayfail "Project management script is not executable: $script_path"
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            script_args+=(--dryrun)
        fi
        script_args+=("$@")

        saydebug "Executing project management script: $script_path ${script_args[*]}"
        SGND_FRAMEWORK_ROOT="${SGND_FRAMEWORK_ROOT:-/}" \
            "$script_path" "${script_args[@]}"
    }

    _smb_run_server_action() {
        local action="${1:?missing action}"
        _smb_run_project_script "manage-samba-file-server.sh" --action "$action"
    }

# - Server management dispatchers --------------------------------------------------
    _smb_step_install_packages() {
        _smb_run_server_action install
    }

    _smb_step_validate_storage() {
        _smb_run_server_action storage
    }

    _smb_step_prepare_share_root() {
        _smb_run_server_action share-root
    }

    _smb_step_start_service() {
        _smb_run_server_action service
    }

    _smb_prepare_file_server() {
        _smb_run_server_action prepare
    }

    _smb_validate() {
        _smb_run_server_action validate
    }

    _smb_status() {
        _smb_run_server_action status
    }

# - Share management dispatch ------------------------------------------------------
    _smb_manage_shares() {
        _smb_run_project_script "manage-samba-shares.sh"
    }

# - Module validation contract ------------------------------------------------------
    # Return codes:
    #   0 = Passed
    #   1 = Failed
    #   2 = Warning
    #   3 = Skipped / not applicable
    #
    # Every validator sets SGND_MODULE_VALIDATION_MESSAGE to a concise result summary.
    # Detailed diagnostic output may be written by the validator or delegated action.
    validate_module_samba_file_server() {
        if ! command -v smbd >/dev/null 2>&1; then
            SGND_MODULE_VALIDATION_MESSAGE="Samba file-server service is not installed on this host."
            return 3
        fi
        if grep -Eiq '^[[:space:]]*server[[:space:]]+role[[:space:]]*=[[:space:]]*active[[:space:]]+directory[[:space:]]+domain[[:space:]]+controller' /etc/samba/smb.conf 2>/dev/null; then
            SGND_MODULE_VALIDATION_MESSAGE="Host is an Active Directory domain controller, not a standalone Samba file server."
            return 3
        fi
        if _smb_validate; then
            SGND_MODULE_VALIDATION_MESSAGE="Samba file-server validation passed."
            return 0
        fi
        SGND_MODULE_VALIDATION_MESSAGE="Samba file-server validation reported one or more failures."
        return 1
    }

# - Console registration -----------------------------------------------------------
    # Provides host-level Samba file-server preparation, validation, status, and
    # managed-share administration. Storage is consumed from the configured
    # SolidGroundUX storage root rather than being independently provisioned here.
    #
    # . Samba File Server
    # ! Prepare Samba file server
    #   > Run the complete Samba file-server preparation sequence.
    #   > Handler: _smb_prepare_file_server
    #
    # ! Install Samba prerequisites
    #   > Install Samba file-server packages and command-line utilities.
    #   > Handler: _smb_step_install_packages
    #
    # ! Validate storage
    #   > Require the configured SolidGroundUX storage mount.
    #   > Handler: _smb_step_validate_storage
    #
    # ! Prepare share root
    #   > Create and validate the configured Samba share root.
    #   > Handler: _smb_step_prepare_share_root
    #
    # ! Start Samba service
    #   > Validate the configuration and start smbd.service.
    #   > Handler: _smb_step_start_service
    #
    # ! Validate Samba file server
    #   > Validate tools, configuration, service, storage, and managed shares.
    #   > Handler: _smb_validate
    #
    # ! Show Samba file-server status
    #   > Show service, configuration, storage, and share-root status.
    #   > Handler: _smb_status
    #
    # . Samba Shares
    # ! Manage shares
    #   > Create, remove, structure, validate, and manage access to Samba shares.
    #   > Handler: _smb_manage_shares
    #   > Script: /usr/local/libexec/solidgroundux/manage-samba-shares.sh
    sgnd_menu_register_group \
        "$SGND_SAMBA_FILE_MODULE_ID" \
        "$SGND_SAMBA_FILE_MODULE_NAME" \
        "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" \
        0 1 300

    sgnd_menu_register_item "smb-prepare" "$SGND_SAMBA_FILE_MODULE_ID" "Prepare Samba file server" "_smb_prepare_file_server" "Run the complete Samba file-server preparation sequence" 0 15 1 0
    sgnd_menu_register_item "smb-install" "$SGND_SAMBA_FILE_MODULE_ID" "Install Samba prerequisites" "_smb_step_install_packages" "Install Samba file-server packages and command-line utilities" 0 15 1 1
    sgnd_menu_register_item "smb-storage" "$SGND_SAMBA_FILE_MODULE_ID" "Validate storage" "_smb_step_validate_storage" "Require the configured SolidGroundUX storage mount" 0 15 1 1
    sgnd_menu_register_item "smb-share-root" "$SGND_SAMBA_FILE_MODULE_ID" "Prepare share root" "_smb_step_prepare_share_root" "Create and validate the configured Samba share root" 0 20 1 1
    sgnd_menu_register_item "smb-service" "$SGND_SAMBA_FILE_MODULE_ID" "Start Samba service" "_smb_step_start_service" "Validate the configuration and start smbd.service" 0 25 1 1

    sgnd_menu_register_item "smb-validate" "$SGND_SAMBA_FILE_MODULE_ID" "Validate Samba file server" "_smb_validate" "Validate tools, configuration, service, storage, and managed shares" 0 30 1 0
    sgnd_menu_register_item "smb-status" "$SGND_SAMBA_FILE_MODULE_ID" "Show Samba file-server status" "_smb_status" "Show service, configuration, storage, and share-root status" 0 35 1 0

    sgnd_menu_register_group \
        "samba-shares" \
        "Samba Shares" \
        "Create, remove, structure, and secure managed Samba shares" \
        0 1 310

    sgnd_menu_register_item "smb-share-manage" "samba-shares" "Manage shares" "_smb_manage_shares" "Create, remove, structure, validate, and manage access to Samba shares" 0 15 1 0

    sayinfo "Samba File Server module registered with the console."
