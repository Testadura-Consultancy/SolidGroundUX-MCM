# ==================================================================================
# SolidGroundUX - Active Directory Management
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624123
#   Checksum    :1ef6a4603357da93826fd818a5c3f89a2fc110451d3e59286451334e8697ca90
#   Source      : 27-active-directory-management.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Manage Samba Active Directory users, groups, memberships, and computers
#
# Description:
#   Provides day-to-day administration of a provisioned Samba Active Directory
#   domain controller. The module manages directory users, groups, memberships,
#   and computer accounts through samba-tool and uses ask_selection for object
#   selection throughout.
#
# Design principles:
#   - Keep provisioning and directory administration separate
#   - Use samba-tool as the canonical directory-management backend
#   - Reuse one membership implementation from both user and group workflows
#   - Prefer selection from live directory objects over typed object names
#   - Keep advanced AD concerns such as OUs, GPOs, trusts, and replication out of scope
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
    SGND_AD_MANAGEMENT_MODULE_ID="active-directory-management"
    SGND_AD_MANAGEMENT_MODULE_NAME="Active Directory Management"
    SGND_AD_MANAGEMENT_MODULE_VERSION="1.0.0"
    SGND_AD_MANAGEMENT_MODULE_DESC="Manage Active Directory users, groups, memberships, and computers"

    SGND_MODULE_NAME="$SGND_AD_MANAGEMENT_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_AD_MANAGEMENT_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_AD_MANAGEMENT_MODULE_DESC"

# - Internal helpers ---------------------------------------------------------------
    # fn: _admg_require_dc - Require a provisioned Samba AD domain controller
        # . Purpose
        #   Verify that samba-tool and a provisioned AD realm are available locally.
        #
        # . Returns
        #   0 when directory management is available; 1 otherwise.
        #
        # . Usage
        #   _admg_require_dc
    _admg_require_dc() {
        local realm=""

        command -v samba-tool >/dev/null 2>&1 || {
            sayfail "samba-tool is not installed."
            return 1
        }

        command -v testparm >/dev/null 2>&1 || {
            sayfail "testparm is not installed."
            return 1
        }

        realm="$(sudo testparm -s --parameter-name='realm' 2>/dev/null || true)"
        [[ -n "$realm" ]] || {
            sayfail "No provisioned Samba Active Directory realm was found."
            return 1
        }

        return 0
    }

    # fn: _admg_validate_sam_name - Validate a simple AD account name
        # . Purpose
        #   Validate a practical sAMAccountName-style value for interactive creation.
        #
        # . Returns
        #   0 for a supported account name; 1 otherwise.
        #
        # . Usage
        #   _admg_validate_sam_name "jsmith"
    _admg_validate_sam_name() {
        [[ "${1-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
    }

    # fn: _admg_list_users_raw - Return directory users
        # . Purpose
        #   Return current AD user sAMAccountNames in stable display order.
        #
        # . Output
        #   Writes one user per line.
        #
        # . Returns
        #   samba-tool user list status.
        #
        # . Usage
        #   mapfile -t users < <(_admg_list_users_raw)
    _admg_list_users_raw() {
        sudo samba-tool user list 2>/dev/null | LC_ALL=C sort
    }

    # fn: _admg_list_groups_raw - Return directory groups
        # . Purpose
        #   Return current AD group names in stable display order.
        #
        # . Output
        #   Writes one group per line.
        #
        # . Returns
        #   samba-tool group list status.
        #
        # . Usage
        #   mapfile -t groups < <(_admg_list_groups_raw)
    _admg_list_groups_raw() {
        sudo samba-tool group list 2>/dev/null | LC_ALL=C sort
    }

    # fn: _admg_list_computers_raw - Return directory computers
        # . Purpose
        #   Return current AD computer account names in stable display order.
        #
        # . Output
        #   Writes one computer per line.
        #
        # . Returns
        #   samba-tool computer list status.
        #
        # . Usage
        #   mapfile -t computers < <(_admg_list_computers_raw)
    _admg_list_computers_raw() {
        sudo samba-tool computer list 2>/dev/null | LC_ALL=C sort
    }

    # fn: _admg_select_user - Select one AD user
        # . Purpose
        #   Enumerate users and store one selected user in the requested variable.
        #
        # . Arguments
        #   $1 - Output variable name.
        #
        # . Returns
        #   0 on selection; 1 on cancel or unavailable users.
        #
        # . Usage
        #   _admg_select_user selected_user
    _admg_select_user() {
        local output_var="${1:?missing output variable}"
        local selected=""
        local -a users=()

        mapfile -t users < <(_admg_list_users_raw)
        (( ${#users[@]} > 0 )) || {
            saywarning "No Active Directory users were found."
            return 1
        }

        ask_selection --label "Select Active Directory user" --var selected --items "${users[@]}" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    # fn: _admg_select_group - Select one AD group
        # . Purpose
        #   Enumerate groups and store one selected group in the requested variable.
        #
        # . Arguments
        #   $1 - Output variable name.
        #
        # . Returns
        #   0 on selection; 1 on cancel or unavailable groups.
        #
        # . Usage
        #   _admg_select_group selected_group
    _admg_select_group() {
        local output_var="${1:?missing output variable}"
        local selected=""
        local -a groups=()

        mapfile -t groups < <(_admg_list_groups_raw)
        (( ${#groups[@]} > 0 )) || {
            saywarning "No Active Directory groups were found."
            return 1
        }

        ask_selection --label "Select Active Directory group" --var selected --items "${groups[@]}" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    # fn: _admg_select_computer - Select one AD computer
        # . Purpose
        #   Enumerate computer accounts and store one selected computer in the requested variable.
        #
        # . Arguments
        #   $1 - Output variable name.
        #
        # . Returns
        #   0 on selection; 1 on cancel or unavailable computers.
        #
        # . Usage
        #   _admg_select_computer selected_computer
    _admg_select_computer() {
        local output_var="${1:?missing output variable}"
        local selected=""
        local -a computers=()

        mapfile -t computers < <(_admg_list_computers_raw)
        (( ${#computers[@]} > 0 )) || {
            saywarning "No Active Directory computer accounts were found."
            return 1
        }

        ask_selection --label "Select Active Directory computer" --var selected --items "${computers[@]}" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    # fn: _admg_user_is_disabled - Test whether an AD user account is disabled
        # . Purpose
        #   Read userAccountControl and test the ACCOUNTDISABLE flag.
        #
        # . Arguments
        #   $1 - User sAMAccountName.
        #
        # . Returns
        #   0 when disabled; 1 when enabled or the state cannot be read.
        #
        # . Usage
        #   _admg_user_is_disabled Administrator
    _admg_user_is_disabled() {
        local user="${1:?missing user}"
        local flags=""

        flags="$(sudo samba-tool user show "$user" --attributes=userAccountControl 2>/dev/null | awk -F': ' '/^userAccountControl:/ { print $2; exit }')"
        [[ "$flags" =~ ^[0-9]+$ ]] || return 1
        (( (flags & 2) != 0 ))
    }

    # fn: _admg_add_member_to_group - Add one member to one AD group
        # . Purpose
        #   Provide the shared implementation used by user- and group-oriented workflows.
        #
        # . Arguments
        #   $1 - Group name.
        #   $2 - Member sAMAccountName.
        #
        # . Returns
        #   0 on success or dry-run; samba-tool status otherwise.
        #
        # . Usage
        #   _admg_add_member_to_group "File Server Users" jsmith
    _admg_add_member_to_group() {
        local group="${1:?missing group}"
        local member="${2:?missing member}"

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would add '$member' to '$group'."
            return 0
        fi

        sudo samba-tool group addmembers "$group" "$member"
    }

    # fn: _admg_remove_member_from_group - Remove one member from one AD group
        # . Purpose
        #   Provide the shared removal implementation used by user- and group-oriented workflows.
        #
        # . Arguments
        #   $1 - Group name.
        #   $2 - Member sAMAccountName.
        #
        # . Returns
        #   0 on success or dry-run; samba-tool status otherwise.
        #
        # . Usage
        #   _admg_remove_member_from_group "File Server Users" jsmith
    _admg_remove_member_from_group() {
        local group="${1:?missing group}"
        local member="${2:?missing member}"

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would remove '$member' from '$group'."
            return 0
        fi

        sudo samba-tool group removemembers "$group" "$member"
    }

    # fn: _admg_user_is_protected - Test whether a user is protected from destructive actions
        # . Purpose
        #   Prevent accidental deletion or disabling of core Samba AD service accounts.
        #
        # . Returns
        #   0 for a protected account; 1 otherwise.
        #
        # . Usage
        #   _admg_user_is_protected Administrator
    _admg_user_is_protected() {
        case "${1,,}" in
            administrator|guest|krbtgt) return 0 ;;
            *) return 1 ;;
        esac
    }

    # fn: _admg_group_is_protected - Test whether a group is protected from deletion
        # . Purpose
        #   Prevent accidental deletion of core domain and built-in security groups.
        #
        # . Returns
        #   0 for a protected group; 1 otherwise.
        #
        # . Usage
        #   _admg_group_is_protected "Domain Admins"
    _admg_group_is_protected() {
        case "${1,,}" in
            "domain admins"|"domain users"|"domain guests"|"domain computers"|administrators|users|guests) return 0 ;;
            *) return 1 ;;
        esac
    }

    # fn: _admg_decision_is_quit - Test whether a canonical decision means quit/back
        # . Returns
        #   0 when the value is Quit/Q (case-insensitive); 1 otherwise.
        # . Usage
        #   _admg_decision_is_quit "<arg1>"
    _admg_decision_is_quit() {
        [[ "${1^^}" == "QUIT" || "${1^^}" == "Q" ]]
    }

# - Directory overview -------------------------------------------------------------
    # fn: _admg_status - Show Active Directory management summary
        # . Purpose
        #   Display realm, controller, service state, and directory object counts.
        #
        # . Returns
        #   0 when status is displayed; 1 when no local AD domain is available.
        #
        # . Usage
        #   _admg_status
    _admg_status() {
        local realm=""
        local service_state="inactive"
        local users=0
        local groups=0
        local computers=0

        _admg_require_dc || return 1

        realm="$(sudo testparm -s --parameter-name='realm' 2>/dev/null || true)"
        systemctl is-active --quiet samba-ad-dc.service && service_state="active"
        users="$(_admg_list_users_raw | awk 'END { print NR + 0 }')"
        groups="$(_admg_list_groups_raw | awk 'END { print NR + 0 }')"
        computers="$(_admg_list_computers_raw | awk 'END { print NR + 0 }')"

        sgnd_print
        sgnd_print_sectionheader "Active Directory Management"
        sgnd_print_labeledvalue --label "Realm" --value "$realm"
        sgnd_print_labeledvalue --label "Domain controller" --value "$(hostname -f 2>/dev/null || hostname)"
        sgnd_print_labeledvalue --label "AD/DC service" --value "$service_state"
        sgnd_print_labeledvalue --label "Users" --value "$users"
        sgnd_print_labeledvalue --label "Groups" --value "$groups"
        sgnd_print_labeledvalue --label "Computers" --value "$computers"
    }

# - User actions -------------------------------------------------------------------
    # fn: _admg_list_users - List Active Directory users
        # . Purpose
        #   Display all directory user accounts.
        #
        # . Returns
        #   0 after listing users; 1 when management is unavailable.
        #
        # . Usage
        #   _admg_list_users
    _admg_list_users() {
        local -a users=()
        _admg_require_dc || return 1
        mapfile -t users < <(_admg_list_users_raw)
        sgnd_print
        sgnd_print_sectionheader "Active Directory users"
        if (( ${#users[@]} == 0 )); then
            sayinfo "No users found."
            return 0
        fi
        sgnd_print_labeledmultivalue --label "Users" --items "${users[@]}"
    }

    # fn: _admg_show_user - Show one Active Directory user
        # . Purpose
        #   Display the selected user object, account state, and direct group memberships.
        #
        # . Returns
        #   0 when displayed or cancelled; non-zero on query failure.
        #
        # . Usage
        #   _admg_show_user
    _admg_show_user() {
        local user=""
        local state="Enabled"
        local -a memberships=()

        _admg_require_dc || return 1
        _admg_select_user user || return 0
        _admg_user_is_disabled "$user" && state="Disabled"
        mapfile -t memberships < <(sudo samba-tool user getgroups "$user" 2>/dev/null | LC_ALL=C sort)

        sgnd_print
        sgnd_print_sectionheader "Active Directory user: $user"
        sgnd_print_labeledvalue --label "Account state" --value "$state"
        sudo samba-tool user show "$user" || return $?
        sgnd_print
        if (( ${#memberships[@]} > 0 )); then
            sgnd_print_labeledmultivalue --label "Groups" --items "${memberships[@]}"
        else
            sgnd_print_labeledvalue --label "Groups" --value "None"
        fi
    }

    # fn: _admg_create_user - Create an Active Directory user
        # . Purpose
        #   Create directory users, optionally disable password expiry, and optionally continue creating users.
        #
        # . Returns
        #   0 on success, dry-run, or cancellation; non-zero on creation failure.
        #
        # . Usage
        #   _admg_create_user
    _admg_create_user() {
        local username=""
        local password_never_expires="No"
        local dlg_rc=0

        _admg_require_dc || return 1

        while :; do
            username=""
            password_never_expires="No"

            ask --label "User name (Q=Back)" --var username --validate _admg_validate_sam_name --back || return 0

            if _admg_list_users_raw | grep -Fxiq -- "$username"; then
                sayfail "User already exists: $username"
                return 1
            fi

            ask_decision \
                --label "Password never expires for '$username'?" \
                --choices "Yes|Y,No|N,Quit|Q" \
                --default "No" \
                --var password_never_expires || return $?
            _admg_decision_is_quit "$password_never_expires" && return 0

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "Dry run: Would create Active Directory user '$username'."
                if [[ "${password_never_expires^^}" == "YES" ]]; then
                    sayinfo "Dry run: Would set the password for '$username' to never expire."
                fi
            else
                sudo samba-tool user add "$username" </dev/tty || return $?

                if [[ "${password_never_expires^^}" == "YES" ]]; then
                    sudo samba-tool user setexpiry "$username" --noexpiry || return $?
                fi

                sayok "Active Directory user '$username' created."
            fi

            # Timeout continues the creation loop; Enter returns to the menu.
            dlg_rc=0

            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to menu; A=another; timeout=create another user" \
                || dlg_rc=$?

            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _admg_toggle_user - Enable or disable an Active Directory user
        # . Purpose
        #   Toggle the selected account between enabled and disabled states.
        #
        # . Returns
        #   0 on success, dry-run, or cancellation; non-zero on update failure.
        #
        # . Usage
        #   _admg_toggle_user
    _admg_toggle_user() {
        local user=""
        local action="disable"
        local decision="No"

        _admg_require_dc || return 1
        _admg_select_user user || return 0

        if _admg_user_is_disabled "$user"; then
            action="enable"
        elif _admg_user_is_protected "$user"; then
            saywarning "Core account '$user' cannot be disabled from SolidGroundUX."
            return 0
        fi

        ask_decision --label "${action^} user '$user'?" --choices "Yes|Y,No|N,Quit|Q" --default "No" --var decision || return $?
        _admg_decision_is_quit "$decision" && return 0
        [[ "${decision^^}" == "YES" ]] || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would $action Active Directory user '$user'."
            return 0
        fi

        if [[ "$action" == "enable" ]]; then
            sudo samba-tool user enable "$user" || return $?
        else
            sudo samba-tool user disable "$user" || return $?
        fi

        sayok "Active Directory user '$user' ${action}d."
    }

    # fn: _admg_reset_user_password - Reset an Active Directory user's password
        # . Purpose
        #   Reset the selected user's password using samba-tool's interactive secure prompt.
        #
        # . Returns
        #   0 on success, dry-run, or cancellation; non-zero on reset failure.
        #
        # . Usage
        #   _admg_reset_user_password
    _admg_reset_user_password() {
        local user=""
        local decision="No"

        _admg_require_dc || return 1
        _admg_select_user user || return 0
        ask_decision --label "Reset password for '$user'?" --choices "Yes|Y,No|N,Quit|Q" --default "No" --var decision || return $?
        _admg_decision_is_quit "$decision" && return 0
        [[ "${decision^^}" == "YES" ]] || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would reset password for '$user'."
            return 0
        fi

        sudo samba-tool user setpassword "$user" </dev/tty || return $?
        sayok "Password reset for '$user'."
    }

    # fn: _admg_set_user_password_noexpiry - Set a user's password to never expire
        # . Purpose
        #   Disable password expiry for the selected Active Directory user.
        #
        # . Returns
        #   0 on success, dry-run, or cancellation; non-zero on update failure.
        #
        # . Usage
        #   _admg_set_user_password_noexpiry
    _admg_set_user_password_noexpiry() {
        local user=""
        local decision="No"

        _admg_require_dc || return 1
        _admg_select_user user || return 0

        ask_decision             --label "Set password for '$user' to never expire?"             --choices "Yes|Y,No|N,Quit|Q"             --default "No"             --var decision || return $?
        _admg_decision_is_quit "$decision" && return 0

        [[ "${decision^^}" == "YES" ]] || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would set password for '$user' to never expire."
            return 0
        fi

        sudo samba-tool user setexpiry "$user" --noexpiry || return $?
        sayok "Password for '$user' set to never expire."
    }

    # fn: _admg_delete_user - Delete an Active Directory user
        # . Purpose
        #   Delete a selected non-protected user account after confirmation.
        #
        # . Returns
        #   0 on success, dry-run, protected-account refusal, or cancellation; non-zero on deletion failure.
        #
        # . Usage
        #   _admg_delete_user
    _admg_delete_user() {
        local user=""
        local dlg_rc=0

        _admg_require_dc || return 1

        while :; do
            user=""

            _admg_select_user user || return 0

            if _admg_user_is_protected "$user"; then
                saywarning "Core account '$user' cannot be deleted from SolidGroundUX."
                return 0
            fi

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "Dry run: Would delete Active Directory user '$user'."
            else
                sudo samba-tool user delete "$user" || return $?
                sayok "Active Directory user '$user' deleted."
            fi

            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to menu; A=another; timeout=delete another user" \
                || dlg_rc=$?

            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _admg_user_add_groups - Add a selected user to one or more AD groups
        # . Purpose
        #   Select a user and one or more groups, then add that user through the shared membership helper.
        #
        # . Returns
        #   0 after completion or cancellation; 1 when one or more membership updates fail.
        #
        # . Usage
        #   _admg_user_add_groups
    _admg_user_add_groups() {
        local user=""
        local group=""
        local failures=0
        local -a groups=()
        local -a selected_groups=()

        _admg_require_dc || return 1
        _admg_select_user user || return 0
        mapfile -t groups < <(_admg_list_groups_raw)
        (( ${#groups[@]} > 0 )) || { saywarning "No groups found."; return 0; }

        ask_selection --label "Add '$user' to groups" --var selected_groups --multi --items "${groups[@]}" || return 0
        for group in "${selected_groups[@]}"; do
            if _admg_add_member_to_group "$group" "$user"; then
                sayok "Added '$user' to '$group'."
            else
                failures=$((failures + 1))
                saywarning "Could not add '$user' to '$group'."
            fi
        done

        (( failures == 0 ))
    }

    # fn: _admg_user_remove_groups - Remove a selected user from direct group memberships
        # . Purpose
        #   Select from the user's current direct groups and remove selected memberships.
        #
        # . Returns
        #   0 after completion or cancellation; 1 when one or more removals fail.
        #
        # . Usage
        #   _admg_user_remove_groups
    _admg_user_remove_groups() {
        local user=""
        local group=""
        local failures=0
        local dlg_rc=0
        local -a groups=()
        local -a selected_groups=()

        _admg_require_dc || return 1

        while :; do
            user=""
            failures=0
            groups=()
            selected_groups=()

            _admg_select_user user || return 0
            mapfile -t groups < <(sudo samba-tool user getgroups "$user" 2>/dev/null | LC_ALL=C sort)
            (( ${#groups[@]} > 0 )) || { sayinfo "'$user' has no direct group memberships to remove."; return 0; }

            ask_selection --label "Remove '$user' from groups" --var selected_groups --multi --items "${groups[@]}" || return 0
            for group in "${selected_groups[@]}"; do
                if _admg_remove_member_from_group "$group" "$user"; then
                    sayok "Removed '$user' from '$group'."
                else
                    failures=$((failures + 1))
                    saywarning "Could not remove '$user' from '$group'."
                fi
            done

            (( failures == 0 )) || return 1

            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to menu; A=another; timeout=remove another user from groups" \
                || dlg_rc=$?

            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

# - Group actions ------------------------------------------------------------------
    # fn: _admg_list_groups - List Active Directory groups
        # . Purpose
        #   Display all directory groups.
        #
        # . Returns
        #   0 after listing groups; 1 when management is unavailable.
        #
        # . Usage
        #   _admg_list_groups
    _admg_list_groups() {
        local -a groups=()
        _admg_require_dc || return 1
        mapfile -t groups < <(_admg_list_groups_raw)
        sgnd_print
        sgnd_print_sectionheader "Active Directory groups"
        if (( ${#groups[@]} == 0 )); then
            sayinfo "No groups found."
            return 0
        fi
        sgnd_print_labeledmultivalue --label "Groups" --items "${groups[@]}"
    }

    # fn: _admg_show_group - Show one Active Directory group
        # . Purpose
        #   Display the selected group object and its direct members.
        #
        # . Returns
        #   0 when displayed or cancelled; non-zero on query failure.
        #
        # . Usage
        #   _admg_show_group
    _admg_show_group() {
        local group=""
        local -a members=()

        _admg_require_dc || return 1
        _admg_select_group group || return 0
        mapfile -t members < <(sudo samba-tool group listmembers "$group" 2>/dev/null | LC_ALL=C sort)

        sgnd_print
        sgnd_print_sectionheader "Active Directory group: $group"
        sudo samba-tool group show "$group" || return $?
        sgnd_print
        if (( ${#members[@]} > 0 )); then
            sgnd_print_labeledmultivalue --label "Members" --items "${members[@]}"
        else
            sgnd_print_labeledvalue --label "Members" --value "None"
        fi
    }

    # fn: _admg_create_group - Create an Active Directory group
        # . Purpose
        #   Create a new AD group after confirmation.
        #
        # . Returns
        #   0 on success, dry-run, or cancellation; non-zero on creation failure.
        #
        # . Usage
        #   _admg_create_group
    _admg_create_group() {
        local group=""
        local dlg_rc=0

        _admg_require_dc || return 1

        while :; do
            group=""

            ask --label "Group name (Q=Back)" --var group --validate sgnd_validate_text --back || return 0

            if _admg_list_groups_raw | grep -Fxiq -- "$group"; then
                sayfail "Group already exists: $group"
                return 1
            fi

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "Dry run: Would create Active Directory group '$group'."
            else
                sudo samba-tool group add "$group" || return $?
                sayok "Active Directory group '$group' created."
            fi

            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to menu; A=another; timeout=create another group" \
                || dlg_rc=$?

            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _admg_delete_group - Delete an Active Directory group
        # . Purpose
        #   Delete a selected non-protected AD group after confirmation.
        #
        # . Returns
        #   0 on success, dry-run, protected-group refusal, or cancellation; non-zero on deletion failure.
        #
        # . Usage
        #   _admg_delete_group
    _admg_delete_group() {
        local group=""
        local decision="No"
        local dlg_rc=0

        _admg_require_dc || return 1

        while :; do
            group=""
            decision="No"

            _admg_select_group group || return 0

            if _admg_group_is_protected "$group"; then
                saywarning "Core group '$group' cannot be deleted from SolidGroundUX."
                return 0
            fi

            ask_decision \
                --label "Delete group '$group'?" \
                --choices "Yes|Y,No|N,Quit|Q" \
                --default "No" \
                --var decision || return $?
            _admg_decision_is_quit "$decision" && return 0
            [[ "${decision^^}" == "YES" ]] || return 0

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "Dry run: Would delete Active Directory group '$group'."
            else
                sudo samba-tool group delete "$group" || return $?
                sayok "Active Directory group '$group' deleted."
            fi

            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to menu; A=another; timeout=delete another group" \
                || dlg_rc=$?

            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _admg_group_add_users - Add one or more users to a selected AD group
        # . Purpose
        #   Select a group and users, then add memberships through the shared helper.
        #
        # . Returns
        #   0 after completion or cancellation; 1 when one or more updates fail.
        #
        # . Usage
        #   _admg_group_add_users
    _admg_group_add_users() {
        local group=""
        local user=""
        local failures=0
        local dlg_rc=0
        local -a users=()
        local -a selected_users=()

        _admg_require_dc || return 1

        while :; do
            group=""
            failures=0
            users=()
            selected_users=()

            _admg_select_group group || return 0
            mapfile -t users < <(_admg_list_users_raw)
            (( ${#users[@]} > 0 )) || { saywarning "No users found."; return 0; }

            ask_selection --label "Add users to '$group'" --var selected_users --multi --items "${users[@]}" || return 0
            for user in "${selected_users[@]}"; do
                if _admg_add_member_to_group "$group" "$user"; then
                    sayok "Added '$user' to '$group'."
                else
                    failures=$((failures + 1))
                    saywarning "Could not add '$user' to '$group'."
                fi
            done

            (( failures == 0 )) || return 1

            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to menu; A=another; timeout=add users to another group" \
                || dlg_rc=$?

            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _admg_group_remove_members - Remove selected direct members from an AD group
        # . Purpose
        #   Select a group and remove one or more of its current direct members.
        #
        # . Returns
        #   0 after completion or cancellation; 1 when one or more removals fail.
        #
        # . Usage
        #   _admg_group_remove_members
    _admg_group_remove_members() {
        local group=""
        local member=""
        local failures=0
        local dlg_rc=0
        local -a members=()
        local -a selected_members=()

        _admg_require_dc || return 1

        while :; do
            group=""
            failures=0
            members=()
            selected_members=()

            _admg_select_group group || return 0
            mapfile -t members < <(sudo samba-tool group listmembers "$group" 2>/dev/null | LC_ALL=C sort)
            (( ${#members[@]} > 0 )) || { sayinfo "'$group' has no direct members."; return 0; }

            ask_selection --label "Remove members from '$group'" --var selected_members --multi --items "${members[@]}" || return 0
            for member in "${selected_members[@]}"; do
                if _admg_remove_member_from_group "$group" "$member"; then
                    sayok "Removed '$member' from '$group'."
                else
                    failures=$((failures + 1))
                    saywarning "Could not remove '$member' from '$group'."
                fi
            done

            (( failures == 0 )) || return 1

            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to menu; A=another; timeout=remove members from another group" \
                || dlg_rc=$?

            case "$dlg_rc" in
                1) continue ;;
                *) return 0 ;;
            esac
        done
    }

# - Computer actions ---------------------------------------------------------------
    # fn: _admg_list_computers - List Active Directory computer accounts
        # . Purpose
        #   Display all directory computer accounts.
        #
        # . Returns
        #   0 after listing computers; 1 when management is unavailable.
        #
        # . Usage
        #   _admg_list_computers
    _admg_list_computers() {
        local -a computers=()
        _admg_require_dc || return 1
        mapfile -t computers < <(_admg_list_computers_raw)
        sgnd_print
        sgnd_print_sectionheader "Active Directory computers"
        if (( ${#computers[@]} == 0 )); then
            sayinfo "No computer accounts found."
            return 0
        fi
        sgnd_print_labeledmultivalue --label "Computers" --items "${computers[@]}"
    }

    # fn: _admg_show_computer - Show one Active Directory computer account
        # . Purpose
        #   Display the selected computer AD object.
        #
        # . Returns
        #   0 when displayed or cancelled; non-zero on query failure.
        #
        # . Usage
        #   _admg_show_computer
    _admg_show_computer() {
        local computer=""
        _admg_require_dc || return 1
        _admg_select_computer computer || return 0
        sgnd_print
        sgnd_print_sectionheader "Active Directory computer: $computer"
        sudo samba-tool computer show "$computer"
    }

    # fn: _admg_delete_computer - Delete an Active Directory computer account
        # . Purpose
        #   Remove a selected stale computer account after confirmation.
        #
        # . Returns
        #   0 on success, dry-run, or cancellation; non-zero on deletion failure.
        #
        # . Usage
        #   _admg_delete_computer
    _admg_delete_computer() {
        local computer=""
        local decision="No"

        _admg_require_dc || return 1
        _admg_select_computer computer || return 0
        ask_decision --label "Delete computer account '$computer'?" --choices "Yes|Y,No|N,Quit|Q" --default "No" --var decision || return $?
        _admg_decision_is_quit "$decision" && return 0
        [[ "${decision^^}" == "YES" ]] || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would delete Active Directory computer '$computer'."
            return 0
        fi

        sudo samba-tool computer delete "$computer" || return $?
        sayok "Active Directory computer '$computer' deleted."
    }

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
