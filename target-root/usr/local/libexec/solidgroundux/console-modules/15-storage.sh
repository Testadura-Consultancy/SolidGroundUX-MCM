# ==================================================================================
# SolidGroundUX Management Console Modules - Storage
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627515
#   Shortname   : STORAGE
#   Source      : 15-storage.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Configure and inspect local storage volumes and directories
#
#   Checksum : bcbd429937a05d126eb06babf74e0d344728fb38e2babbc36d9a551e8aa7e007
# Description:
#   Registers local-storage management actions with the SolidGround Management Console.
#   Persistent storage operations are implemented by manage-storage.sh.
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
# - Module metadata ----------------------------------------------------------------
    SGND_STORAGE_MODULE_ID="storage"
    SGND_STORAGE_MODULE_NAME="Storage"
    SGND_MODULE_ID="${SGND_STORAGE_MODULE_ID}"

    SGND_MODULE_NAME="$SGND_STORAGE_MODULE_NAME"
# - Management dispatch -------------------------------------------------------------
    _storage_run_action() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-storage.sh" --action "$action"
    }

    _storage_run_compound_step() {
        local action="${1:?missing action}"

        (
            export SGND_STORAGE_COMPOUND_STEP=1
            _sgnd_run_module_script "manage-storage.sh" --action "$action"
        )
    }

    _storage_step_provision() { _storage_run_compound_step provision; }
    _storage_step_validate()  { _storage_run_compound_step validate; }

    # fn: storage_prepare - Provision and validate persistent SolidGroundUX storage
        # . Purpose
        #   Execute the registered happy-path storage actions as one compound workflow while
        #   keeping the individual console action statuses synchronized.
        #
        # . Behavior
        #   - Runs Provision storage first; provisioning performs the destructive disk setup,
        #     persistence configuration, initial mount, and SolidGroundUX configuration save.
        #   - Runs Validate storage provisioning after provisioning succeeds.
        #   - Uses management-console action tracking when available so each child receives
        #     the same persisted checkmark/cross status as an individually selected action.
        #   - Suppresses each child script's normal end-of-action auto-continue dialog while
        #     it is running as part of this compound workflow.
        #   - Does not mark Mount storage or reconciliation actions as completed merely because
        #     provisioning performed equivalent internal work.
        #
        # . Returns
        #   0 when provisioning and validation both succeed; otherwise the first failing child code.
        #
        # . Usage
        #   storage_prepare
    storage_prepare() {
        sgnd_print
        sgnd_print_sectionheader --text "Prepare Storage"

        if declare -F sgnd_console_run_tracked >/dev/null 2>&1; then
            sgnd_print_labeledvalue --label "Step" --value "Provision storage" --labelwidth 18
            sgnd_console_run_tracked "storage-provision" _storage_step_provision || return $?
            sgnd_print_labeledvalue --label "Step" --value "Validate storage provisioning" --labelwidth 18
            sgnd_console_run_tracked "storage-validate" _storage_step_validate || return $?
            return 0
        fi

        _storage_step_provision || return $?
        _storage_step_validate || return $?
    }

    storage_provision()                 { _storage_run_action provision; }
    storage_mount()                     { _storage_run_action mount; }
    storage_unmount()                   { _storage_run_action unmount; }
    storage_expand()                    { _storage_run_action expand; }
    storage_reconcile()                 { _storage_run_action reconcile; }
    storage_reconcile_persistence()     { _storage_run_action reconcile-persistence; }
    storage_validate_provisioning()     { _storage_run_action validate; }
    storage_status()                    { _storage_run_action status; }

    # fn: storage_manage_directories - Manage directories below a SolidGroundUX storage root
        # . Purpose
        #   Open the Storage-owned directory manager for simple filesystem directory lifecycle
        #   operations beneath a configured SolidGroundUX storage mount point.
        #
        # . Behavior
        #   - Delegates to manage-storage.sh; no Samba module or ACL tooling is required.
        #   - Keeps Storage responsible only for filesystem directories, not share or identity policy.
        #
        # . Returns
        #   The return code from the storage directory-management action.
        #
        # . Usage
        #   storage_manage_directories
    storage_manage_directories()          { _storage_run_action directories; }

    storage_access_status()             { _storage_run_action access-status; }
    storage_set_access()                 { _storage_run_action set-access; }
    storage_restore_access_defaults()   { _storage_run_action restore-defaults; }

# - Module validation contract ------------------------------------------------------
    # Return codes:
    #   0 = Passed
    #   1 = Failed
    #   2 = Warning
    #   3 = Skipped / not applicable
    #
    # Every validator sets SGND_MODULE_VALIDATION_MESSAGE to a concise result summary.
    # Detailed diagnostic output may be written by the validator or delegated action.
    validate_module_storage() {
        if [[ ! -s /etc/solidgroundux/storage.cfg ]] && ! grep -Eq '(^|[[:space:]])SGND_STORAGE([[:space:]]|$)' /etc/fstab 2>/dev/null; then
            SGND_MODULE_VALIDATION_MESSAGE="Storage is not configured on this host."
            return 3
        fi
        if storage_validate_provisioning; then
            SGND_MODULE_VALIDATION_MESSAGE="Storage provisioning validation passed."
            return 0
        fi
        SGND_MODULE_VALIDATION_MESSAGE="Storage provisioning validation reported one or more failures."
        return 1
    }

# - Console registration ------------------------------------------------------------
    # . Storage
    # ! Prepare storage
    #   > Provision and validate persistent local storage.
    # ! Provision storage
    #   > Provision one or more unused disks as persistent local storage.
    # ! Mount storage
    #   > Mount a configured local storage filesystem.
    # ! Unmount storage
    #   > Unmount a configured storage filesystem while keeping its persistent configuration.
    # ! Expand storage
    #   > Expand the partition and filesystem after enlarging its disk.
    # ! Reconcile storage configuration
    #   > Update SolidGroundUX storage configuration from all managed SGND_STORAGE volumes.
    # ! Reconcile storage persistence
    #   > Repair stale UUID mappings from detected SGND_STORAGE filesystems or remove stale entries explicitly.
    # ! Validate storage provisioning
    #   > Run active checks including configuration reconciliation.
    # ! Show storage status
    #   > Show local disks and configured storage status.
    # ! Manage directories
    #   > Create, rename, list, or remove directories beneath managed storage roots.
    sgnd_menu_register_group \
        "$SGND_STORAGE_MODULE_ID" \
        "$SGND_STORAGE_MODULE_NAME" \
        "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" \
        0 1 240

    # Actions that own an auto-continue/end dialog use menu wait 0.
    sgnd_menu_register_item "storage-prepare" "$SGND_STORAGE_MODULE_ID" "Prepare storage" "storage_prepare" "Provision and validate persistent local storage" 0 0 1 0
    sgnd_menu_register_item "storage-provision" "$SGND_STORAGE_MODULE_ID" "Provision storage" "storage_provision" "Provision an unused disk as persistent local storage" 0 0 1 1
    sgnd_menu_register_item "storage-validate" "$SGND_STORAGE_MODULE_ID" "Validate storage provisioning" "storage_validate_provisioning" "Validate configured SolidGroundUX storage" 0 0 1 1
    sgnd_menu_register_item "storage-mount" "$SGND_STORAGE_MODULE_ID" "Mount storage" "storage_mount" "Mount the configured local storage filesystem" 0 0 1 0
    sgnd_menu_register_item "storage-unmount" "$SGND_STORAGE_MODULE_ID" "Unmount storage" "storage_unmount" "Unmount storage while keeping its persistent configuration" 0 0 1 0
    sgnd_menu_register_item "storage-expand" "$SGND_STORAGE_MODULE_ID" "Expand storage" "storage_expand" "Expand the partition and filesystem after enlarging its disk" 0 0 1 0
    sgnd_menu_register_item "storage-reconcile" "$SGND_STORAGE_MODULE_ID" "Reconcile storage configuration" "storage_reconcile" "Update SolidGroundUX storage configuration from the existing SGND_STORAGE volume" 0 0 1 0
    sgnd_menu_register_item "storage-reconcile-persistence" "$SGND_STORAGE_MODULE_ID" "Reconcile storage persistence" "storage_reconcile_persistence" "Repair stale SGND_STORAGE UUID mappings or explicitly remove stale managed entries" 0 0 1 0
    sgnd_menu_register_item "storage-status" "$SGND_STORAGE_MODULE_ID" "Show storage status" "storage_status" "Show local disks and configured storage status" 0 0 1 0
    sgnd_menu_register_item "storage-directories" "$SGND_STORAGE_MODULE_ID" "Manage directories" "storage_manage_directories" "Create, rename, list, or remove directories beneath managed storage roots" 0 0 1 0

    # . Storage Access
    sgnd_menu_register_group \
        "storage-access" \
        "Storage Access" \
        "Manage ownership and Unix permissions for managed storage roots" \
        0 1 245

    sgnd_menu_register_item "storage-access-status" "storage-access" "Show storage access" "storage_access_status" "Show ownership and permissions for managed storage roots" 0 15 1 0
    sgnd_menu_register_item "storage-access-set" "storage-access" "Set storage access" "storage_set_access" "Set owner, group, and Unix permissions for one or more managed storage roots" 0 0 1 0
    sgnd_menu_register_item "storage-access-reset" "storage-access" "Restore default access" "storage_restore_access_defaults" "Restore canonical ownership and permissions for managed storage roots" 0 0 1 0

    sayinfo "Storage module registered with the console."
