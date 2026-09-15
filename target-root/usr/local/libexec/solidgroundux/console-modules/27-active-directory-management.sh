# ==================================================================================
# SolidGroundUX Management Console Modules - Active Directory Management
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625721
#   Source      : 27-active-directory-management.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Register Active Directory object-management actions
#
# Description:
#   Registers day-to-day Active Directory administration actions with the SolidGround
#   Management Console. Persistent object management is implemented by
#   manage-active-directory.sh.
# ==================================================================================
set -uo pipefail

# - Library guard ------------------------------------------------------------------
    _sgnd_lib_guard() {
        local lib_base="" guard=""
        lib_base="$(basename "${BASH_SOURCE[0]}" .sh)"; lib_base="${lib_base//-/_}"; guard="SGND_${lib_base^^}_LOADED"
        [[ "${BASH_SOURCE[0]}" != "$0" ]] || { printf 'This is a library; source it, do not execute it: %s\n' "${BASH_SOURCE[0]}" >&2; exit 2; }
        [[ -n "${!guard-}" ]] && return 0
        printf -v "$guard" '1'
    }
    _sgnd_lib_guard
    unset -f _sgnd_lib_guard
    if declare -F sgnd_module_init_metadata >/dev/null 2>&1 && declare -F sgnd_header_buffer_load >/dev/null 2>&1; then sgnd_module_init_metadata "${BASH_SOURCE[0]}"; fi

# - Module metadata ----------------------------------------------------------------
    SGND_AD_MANAGEMENT_MODULE_ID="active-directory-management"
    SGND_AD_MANAGEMENT_MODULE_NAME="Active Directory Management"
    SGND_AD_MANAGEMENT_MODULE_VERSION="1.1.0"
    SGND_AD_MANAGEMENT_MODULE_DESC="Manage Active Directory users, groups, memberships, and computers"
    SGND_MODULE_NAME="$SGND_AD_MANAGEMENT_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_AD_MANAGEMENT_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_AD_MANAGEMENT_MODULE_DESC"

# - Management dispatch -------------------------------------------------------------
    _admg_run_action() { local action="${1:?missing action}"; _sgnd_run_module_script "manage-active-directory.sh" --action "$action"; }
    _admg_validate() { _admg_run_action validate; }
    _admg_status() { _admg_run_action status; }
    _admg_list_users() { _admg_run_action user-list; }
    _admg_show_user() { _admg_run_action user-show; }
    _admg_create_user() { _admg_run_action user-create; }
    _admg_toggle_user() { _admg_run_action user-toggle; }
    _admg_reset_user_password() { _admg_run_action user-password; }
    _admg_set_user_password_noexpiry() { _admg_run_action user-noexpiry; }
    _admg_user_add_groups() { _admg_run_action user-addgroups; }
    _admg_user_remove_groups() { _admg_run_action user-removegroups; }
    _admg_delete_user() { _admg_run_action user-delete; }
    _admg_list_groups() { _admg_run_action group-list; }
    _admg_show_group() { _admg_run_action group-show; }
    _admg_create_group() { _admg_run_action group-create; }
    _admg_group_add_users() { _admg_run_action group-addusers; }
    _admg_group_remove_members() { _admg_run_action group-removemembers; }
    _admg_delete_group() { _admg_run_action group-delete; }
    _admg_list_computers() { _admg_run_action computer-list; }
    _admg_show_computer() { _admg_run_action computer-show; }
    _admg_delete_computer() { _admg_run_action computer-delete; }

# - Console registration -----------------------------------------------------------
    # Provides day-to-day Active Directory object management after a domain has been
    # provisioned. The module exposes directory status plus focused user, group, and
    # computer-account administration without replacing full directory tooling.
    #
    # . Directory
    # ! Show directory status
    #   > Show realm, controller state, and directory object counts.
    #   > Handler: _admg_status
    #
    # ! Validate directory management
    #   > Validate controller state and directory object enumeration.
    #   > Handler: _admg_validate
    #
    # . Users
    # ! List users
    #   > List Active Directory users.
    #   > Handler: _admg_list_users
    #
    # ! Show user
    #   > Show user details and direct group memberships.
    #   > Handler: _admg_show_user
    #
    # ! Create user
    #   > Create an Active Directory user.
    #   > Handler: _admg_create_user
    #
    # ! Enable / disable user
    #   > Toggle the selected user account state.
    #   > Handler: _admg_toggle_user
    #
    # ! Reset user password
    #   > Reset the selected user's password.
    #   > Handler: _admg_reset_user_password
    #
    # ! Set password never expires
    #   > Disable password expiry for the selected user.
    #   > Handler: _admg_set_user_password_noexpiry
    #
    # ! Add user to groups
    #   > Add a selected user to one or more groups.
    #   > Handler: _admg_user_add_groups
    #
    # ! Remove user from groups
    #   > Remove selected direct group memberships.
    #   > Handler: _admg_user_remove_groups
    #
    # ! Delete user
    #   > Delete a selected non-protected user account.
    #   > Handler: _admg_delete_user
    #
    # . Groups
    # ! List groups
    #   > List Active Directory groups.
    #   > Handler: _admg_list_groups
    #
    # ! Show group
    #   > Show group details and direct members.
    #   > Handler: _admg_show_group
    #
    # ! Create group
    #   > Create an Active Directory group.
    #   > Handler: _admg_create_group
    #
    # ! Add users to group
    #   > Add one or more users to a selected group.
    #   > Handler: _admg_group_add_users
    #
    # ! Remove group members
    #   > Remove one or more direct members from a selected group.
    #   > Handler: _admg_group_remove_members
    #
    # ! Delete group
    #   > Delete a selected non-protected group.
    #   > Handler: _admg_delete_group
    #
    # . Computers
    # ! List computers
    #   > List Active Directory computer accounts.
    #   > Handler: _admg_list_computers
    #
    # ! Show computer
    #   > Show the selected computer account.
    #   > Handler: _admg_show_computer
    #
    # ! Delete computer
    #   > Delete a selected stale computer account.
    #   > Handler: _admg_delete_computer
    sgnd_menu_register_group \
        "admg-directory" \
        "Directory" \
        "Inspect the Active Directory domain" \
        0 1 270

    sgnd_menu_register_item "admg-status" "admg-directory" "Show directory status" "_admg_status" "Show realm, controller state, and directory object counts" 0 15 1 0
    sgnd_menu_register_item "admg-validate" "admg-directory" "Validate directory management" "_admg_validate" "Validate controller state and directory object enumeration" 0 20 1 0

    sgnd_menu_register_group \
        "admg-users" \
        "Users" \
        "Manage Active Directory user accounts and group membership" \
        0 1 271

    sgnd_menu_register_item "admg-user-list" "admg-users" "List users" "_admg_list_users" "List Active Directory users" 0 15 1 0
    sgnd_menu_register_item "admg-user-show" "admg-users" "Show user" "_admg_show_user" "Show user details and direct group memberships" 0 15 1 0
    sgnd_menu_register_item "admg-user-create" "admg-users" "Create user" "_admg_create_user" "Create an Active Directory user" 0 0 1 0
    sgnd_menu_register_item "admg-user-toggle" "admg-users" "Enable / disable user" "_admg_toggle_user" "Toggle the selected user account state" 0 15 1 0
    sgnd_menu_register_item "admg-user-password" "admg-users" "Reset user password" "_admg_reset_user_password" "Reset the selected user's password" 0 15 1 0
    sgnd_menu_register_item "admg-user-noexpiry" "admg-users" "Set password never expires" "_admg_set_user_password_noexpiry" "Disable password expiry for the selected user" 0 15 1 0
    sgnd_menu_register_item "admg-user-addgroups" "admg-users" "Add user to groups" "_admg_user_add_groups" "Add a selected user to one or more groups" 0 15 1 0
    sgnd_menu_register_item "admg-user-removegroups" "admg-users" "Remove user from groups" "_admg_user_remove_groups" "Remove selected direct group memberships" 0 0 1 0
    sgnd_menu_register_item "admg-user-delete" "admg-users" "Delete user" "_admg_delete_user" "Delete a selected non-protected user account" 0 0 1 0

    sgnd_menu_register_group \
        "admg-groups" \
        "Groups" \
        "Manage Active Directory groups and members" \
        0 1 272

    sgnd_menu_register_item "admg-group-list" "admg-groups" "List groups" "_admg_list_groups" "List Active Directory groups" 0 15 1 0
    sgnd_menu_register_item "admg-group-show" "admg-groups" "Show group" "_admg_show_group" "Show group details and direct members" 0 15 1 0
    sgnd_menu_register_item "admg-group-create" "admg-groups" "Create group" "_admg_create_group" "Create an Active Directory group" 0 0 1 0
    sgnd_menu_register_item "admg-group-addusers" "admg-groups" "Add users to group" "_admg_group_add_users" "Add one or more users to a selected group" 0 0 1 0
    sgnd_menu_register_item "admg-group-removemembers" "admg-groups" "Remove group members" "_admg_group_remove_members" "Remove one or more direct members from a selected group" 0 0 1 0
    sgnd_menu_register_item "admg-group-delete" "admg-groups" "Delete group" "_admg_delete_group" "Delete a selected non-protected group" 0 0 1 0

    sgnd_menu_register_group \
        "admg-computers" \
        "Computers" \
        "Inspect and remove Active Directory computer accounts" \
        0 1 273

    sgnd_menu_register_item "admg-computer-list" "admg-computers" "List computers" "_admg_list_computers" "List Active Directory computer accounts" 0 15 1 0
    sgnd_menu_register_item "admg-computer-show" "admg-computers" "Show computer" "_admg_show_computer" "Show the selected computer account" 0 15 1 0
    sgnd_menu_register_item "admg-computer-delete" "admg-computers" "Delete computer" "_admg_delete_computer" "Delete a selected stale computer account" 0 15 1 0

    sayinfo "Active Directory Management module registered with the console."
