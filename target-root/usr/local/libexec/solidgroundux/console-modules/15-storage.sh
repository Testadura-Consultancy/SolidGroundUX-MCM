# ==================================================================================
# SSolidGroundUX Management Console Modules - Storage
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625721
#   Source      : 15-storage.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Configure and inspect local storage volumes
#
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
    SGND_STORAGE_MODULE_VERSION="1.2.0"
    SGND_STORAGE_MODULE_DESC="Configure, reconcile, and inspect local storage volumes"

    SGND_MODULE_NAME="$SGND_STORAGE_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_STORAGE_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_STORAGE_MODULE_DESC"

# - Management dispatch -------------------------------------------------------------
    _storage_run_action() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-storage.sh" --action "$action"
    }

    storage_configure()                 { _storage_run_action configure; }
    storage_mount()                     { _storage_run_action mount; }
    storage_unmount()                   { _storage_run_action unmount; }
    storage_expand()                    { _storage_run_action expand; }
    storage_reconcile()                 { _storage_run_action reconcile; }
    storage_reconcile_persistence()     { _storage_run_action reconcile-persistence; }
    storage_validate_provisioning()     { _storage_run_action validate; }
    storage_status()                    { _storage_run_action status; }
    storage_access_status()             { _storage_run_action access-status; }
    storage_set_owner()                 { _storage_run_action set-owner; }
    storage_set_group()                 { _storage_run_action set-group; }
    storage_set_permissions()           { _storage_run_action set-permissions; }
    storage_restore_access_defaults()   { _storage_run_action restore-defaults; }

# - Console registration ------------------------------------------------------------
    # . Storage
    # ! Configure storage
    #   > Provision an unused disk as persistent local storage.
    # ! Mount storage
    #   > Mount the configured local storage filesystem.
    # ! Unmount storage
    #   > Unmount storage while keeping its persistent configuration.
    # ! Expand storage
    #   > Expand the partition and filesystem after enlarging its disk.
    # ! Reconcile storage configuration
    #   > Update SolidGroundUX storage configuration from the existing SGND_STORAGE volume.
    # ! Reconcile storage persistence
    #   > Remove stale SolidGroundUX-managed storage entries from /etc/fstab.
    # ! Validate storage provisioning
    #   > Run active checks including configuration reconciliation.
    # ! Show storage status
    #   > Show local disks and configured storage status.
    sgnd_menu_register_group \
        "$SGND_STORAGE_MODULE_ID" \
        "$SGND_STORAGE_MODULE_NAME" \
        "$SGND_STORAGE_MODULE_DESC" \
        0 1 240

    sgnd_menu_register_item "storage-configure" "$SGND_STORAGE_MODULE_ID" "Configure storage" "storage_configure" "Provision an unused disk as persistent local storage" 0 15 1 0
    sgnd_menu_register_item "storage-mount" "$SGND_STORAGE_MODULE_ID" "Mount storage" "storage_mount" "Mount the configured local storage filesystem" 0 15 1 1
    sgnd_menu_register_item "storage-unmount" "$SGND_STORAGE_MODULE_ID" "Unmount storage" "storage_unmount" "Unmount storage while keeping its persistent configuration" 0 15 1 1
    sgnd_menu_register_item "storage-expand" "$SGND_STORAGE_MODULE_ID" "Expand storage" "storage_expand" "Expand the partition and filesystem after enlarging its disk" 0 20 1 1
    sgnd_menu_register_item "storage-reconcile" "$SGND_STORAGE_MODULE_ID" "Reconcile storage configuration" "storage_reconcile" "Update SolidGroundUX storage configuration from the existing SGND_STORAGE volume" 0 20 1 0
    sgnd_menu_register_item "storage-reconcile-persistence" "$SGND_STORAGE_MODULE_ID" "Reconcile storage persistence" "storage_reconcile_persistence" "Remove stale SolidGroundUX-managed storage entries from /etc/fstab" 0 22 1 0
    sgnd_menu_register_item "storage-validate" "$SGND_STORAGE_MODULE_ID" "Validate storage provisioning" "storage_validate_provisioning" "Run active checks including configuration reconciliation" 0 25 1 0
    sgnd_menu_register_item "storage-status" "$SGND_STORAGE_MODULE_ID" "Show storage status" "storage_status" "Show local disks and configured storage status" 0 30 1 0

    # . Storage Access
    sgnd_menu_register_group \
        "storage-access" \
        "Storage Access" \
        "Manage ownership and Unix permissions for the storage and shares roots" \
        0 1 245

    sgnd_menu_register_item "storage-access-status" "storage-access" "Show storage ownership" "storage_access_status" "Show ownership and permissions for the storage and shares roots" 0 15 1 0
    sgnd_menu_register_item "storage-access-owner" "storage-access" "Set storage owner" "storage_set_owner" "Set the owner of the storage root or shares root" 0 15 1 1
    sgnd_menu_register_item "storage-access-group" "storage-access" "Set storage group" "storage_set_group" "Set the group of the storage root or shares root" 0 15 1 1
    sgnd_menu_register_item "storage-access-mode" "storage-access" "Set storage permissions" "storage_set_permissions" "Set Unix permissions on the storage root or shares root" 0 20 1 1
    sgnd_menu_register_item "storage-access-reset" "storage-access" "Restore default permissions" "storage_restore_access_defaults" "Restore canonical ownership and permissions for managed storage roots" 0 25 1 1

    sayinfo "Storage module registered with the console."
