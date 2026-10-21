# ==================================================================================
# SolidGroundUX Management Console Modules - Computer Setup
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2629401
#   Shortname   : COMPUTER_SETUP
#   Checksum    : cda3e4e1f0214e4c2de1b380cff356008409980e95169d59f6f11d902a003892
#   Source      : 10-computer-setup.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Configure and validate the base computer
#
# Description:
#   Registers post-clone computer setup and optional outbound SSH deployment
#   access management. Prepare computer retains its existing four-step sequence.
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
    SGND_COMPUTER_SETUP_MODULE_ID="computer-setup"
    SGND_COMPUTER_SETUP_MODULE_NAME="Computer Setup"
    SGND_COMPUTER_SUDOERS_FILE="/etc/sudoers.d/solidgroundux-receiver"

    SGND_MODULE_ID="${SGND_COMPUTER_SETUP_MODULE_ID}"

    SGND_MODULE_NAME="$SGND_COMPUTER_SETUP_MODULE_NAME"
# - Module actions -----------------------------------------------------------------
    # fn: _computer_set_identity
        # . Purpose
        #   Run the canonical SolidGroundUX identity workflow.
        #
        # . Returns
        #   Exit status from manage-identity.sh.
        # . Usage
        #   _computer_set_identity "<args...>"
    _computer_set_identity() {
        _sgnd_run_module_script "manage-identity.sh" "$@"
    }

    # fn: _computer_manage - Dispatch a machine action to its standalone manager.
    _computer_manage() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-computer.sh" --action "$action"
    }

    # fn: _computer_ssh_manage - Dispatch a user SSH action without privilege escalation.
    _computer_ssh_manage() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-ssh-access.sh" --action "$action"
    }

    # fn: Computer Setup menu action proxies - Keep stable handler names and IDs.
    _computer_generate_ssh_keys()    { _computer_manage ssh-host-keys; }
    _computer_configure_ssh_service(){ _computer_manage ssh-service; }
    _computer_configure_sudoers()     { _computer_manage sudoers; }
    _computer_status()               { _computer_manage status; }
    _computer_validate()             { _computer_manage validate; }
    _computer_ssh_generate_user_key(){ _computer_ssh_manage generate-key; }
    _computer_ssh_install_key()      { _computer_ssh_manage install-key; }
    _computer_ssh_unlock_key()       { _computer_ssh_manage unlock-key; }
    _computer_ssh_test_access()      { _computer_ssh_manage test-access; }

    # fn: _computer_prepare
        # . Purpose
        #   Run the normal post-clone computer setup sequence.
        #
        # . Behavior
        #   - Runs the four indented machine setup actions (menu items 2-5), in order:
        #     identity, server host keys, SSH service, and SolidGround sudo access.
        #   - Persists each action result through the console tracker.
        #   - Stops on the first failed step.
        #   - Never executes personal SSH key management or validation actions.
        #
        # . Returns
        #   0 when all steps succeed; otherwise the failing step status.
        # . Usage
        #   _computer_prepare
    _computer_prepare() {
        sgnd_console_run_tracked "setnetid" _computer_set_identity || return $?
        sgnd_console_run_tracked "sshkeys" _computer_generate_ssh_keys || return $?
        sgnd_console_run_tracked "sshcfg" _computer_configure_ssh_service || return $?
        sgnd_console_run_tracked "sudoers" _computer_configure_sudoers || return $?

        sayok "Computer preparation completed successfully."
        return 0
    }


    # fn: _prepare-template.sh
        # . Purpose
        #   Prepare a template computer for cloning.
        #
        # . Returns
        #   0 on success; non-zero on failure.
    _prepare_template() {
        _sgnd_run_public_command "sgnd-prepare-template"
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
    validate_module_computer_setup() {
        if _computer_validate; then
            SGND_MODULE_VALIDATION_MESSAGE="Computer setup validation passed."
            return 0
        fi
        SGND_MODULE_VALIDATION_MESSAGE="Computer setup validation reported one or more failures."
        return 1
    }

# - Console registration ---------------------------------------------------------
    # Provides the base post-clone computer setup workflow, including machine
    # identity, SSH, SolidGround sudo access, status, validation, and preparation
    # for cloning.
    #
    # . Menu items
    # ! Prepare computer
    #   > Run the normal post-clone setup sequence.
    #   > Handler: _computer_prepare
    #
    # ! Set computer identity
    #   > Configure hostname, network identity, DNS, and search domain.
    #   > Handler: _computer_set_identity
    #
    # ! Generate SSH host keys
    #   > Generate missing host keys, validate sshd, and restart SSH.
    #   > Handler: _computer_generate_ssh_keys
    #
    # ! Generate deployment SSH key / Install SSH public key
    #   > Prepare outbound SSH key authentication for a chosen user and remote host.
    # ! Unlock SSH key in agent / Test deployment SSH access
    #   > Reuse a secure user agent and verify non-interactive SSH login.
    # ! Configure SSH service
    #   > Enable or disable the SSH service.
    #   > Handler: _computer_configure_ssh_service
    #
    # ! Setup SolidGround sudo access
    #   > Allow the administrator to run trusted SolidGroundUX tools without a password.
    #   > Handler: _computer_configure_sudoers
    #
    # ! Show computer status
    #   > Show identity, network, SSH, host-key, and SolidGround sudo state.
    #   > Handler: _computer_status
    #
    # ! Validate computer setup
    #   > Validate identity, SSH, host keys, and SolidGround sudo access.
    #   > Handler: _computer_validate
    #
    # ! Prepare for cloning
    #   > Prepare a template computer for cloning.
    #   > Handler: _prepare_template
    #   > Command: sgnd-prepare-template
    # Preserve one chapter per source. Group headings have consecutive sort order,
    # and menu numbering is continuous across groups for this MCM module.
    sgnd_menu_register_group \
        "$SGND_COMPUTER_SETUP_MODULE_ID" \
        "$SGND_COMPUTER_SETUP_MODULE_NAME" \
        "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" \
        0 1 100
    sgnd_menu_register_group "computer-ssh-key-management" "SSH Key Management" "Manage outgoing SSH authentication for the current user" 0 1 101
    sgnd_menu_register_group "computer-validation" "Validation" "Inspect or validate computer setup and prepare for cloning" 0 1 102

    # Composite action; its four tracked substeps immediately follow, indented.
    sgnd_menu_register_item "preparepc" "$SGND_COMPUTER_SETUP_MODULE_ID" "Prepare computer" "_computer_prepare" "Run steps 2-5 in order" 0 15 1 0
    sgnd_menu_register_item "setnetid" "$SGND_COMPUTER_SETUP_MODULE_ID" "Set computer identity" "_computer_set_identity" "Configure hostname, network identity, DNS, and search domain" 0 15 1 1
    sgnd_menu_register_item "sshkeys" "$SGND_COMPUTER_SETUP_MODULE_ID" "Generate SSH host keys" "_computer_generate_ssh_keys" "Generate SSH server host keys, validate sshd, and restart SSH" 0 15 1 1
    sgnd_menu_register_item "sshcfg" "$SGND_COMPUTER_SETUP_MODULE_ID" "Configure SSH service" "_computer_configure_ssh_service" "Enable or disable the SSH service" 0 15 1 1
    sgnd_menu_register_item "sudoers" "$SGND_COMPUTER_SETUP_MODULE_ID" "Setup SolidGround sudo access" "_computer_configure_sudoers" "Allow administrator to run trusted SolidGroundUX tools without a password" 0 15 1 1

    # User credentials: never a part of unattended/standard Prepare computer.
    sgnd_menu_register_item "sshuserkey" "computer-ssh-key-management" "Generate user SSH key" "_computer_ssh_generate_user_key" "Generate a personal SSH key pair for outbound connections" 0 15 1 0
    sgnd_menu_register_item "sshcopykey" "computer-ssh-key-management" "Install public key on remote host" "_computer_ssh_install_key" "Authorize the user's public key on a remote SSH host" 0 15 1 0
    sgnd_menu_register_item "sshagent" "computer-ssh-key-management" "Unlock SSH key in agent" "_computer_ssh_unlock_key" "Start or reuse an SSH agent and unlock a personal key" 0 15 1 0
    sgnd_menu_register_item "sshtest" "computer-ssh-key-management" "Test SSH authentication" "_computer_ssh_test_access" "Verify non-interactive SSH authentication to a remote host" 0 15 1 0

    sgnd_menu_register_item "pcstatus" "computer-validation" "Show computer status" "_computer_status" "Show identity, network, SSH host-key, and sudo status" 0 30 1 0
    sgnd_menu_register_item "pcvalidate" "computer-validation" "Validate computer setup" "_computer_validate" "Validate identity, SSH host keys and service, and sudo access" 0 15 1 0
    sgnd_menu_register_item "preptemplate" "computer-validation" "Prepare for cloning" "_prepare_template" "Prepare a template computer for cloning" 0 15 1 0

    sayinfo "Computer Setup module registered with the console."
