#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Samba Users
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627412
#   Shortname   : MANAGE_SAMBA_USERS
#   Source      : manage-samba-users.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Manage standalone Samba users, local access groups, and memberships
#
#   Checksum : cc27364a43c77a875f7f0206cf645a3b6729164318da61a7a969f9fd6b98e67e
# Description:
#   Provides interactive management for local Samba users and the local groups used for
#   standalone Samba share access. The overview shows Samba users together with their
#   local group memberships so identity configuration can be reviewed at a glance.
#
# Attribution:
#   Developers    : Mark Fieten
#   Company       : Testadura Consultancy
#   Client        : -
#   Copyright     : © 2025 - 2026 Testadura Consultancy
#   License       : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail

# - Bootstrap -----------------------------------------------------------------------
    # fn$ _framework_locator - Resolve and load the active SolidGroundUX framework
        # . Purpose
        #   Determine the filesystem root of the currently executing SolidGroundUX tree
        #   from the script's physical path, then load the executable runtime library.
        #
        # . Behavior
        #   - Resolves the physical path of the executing script.
        #   - Treats usr, etc, and var as the canonical top-level SolidGroundUX tree roots.
        #   - Uses the last occurrence of one of those path components to determine the
        #     active filesystem root.
        #   - Resolves production scripts beneath /usr, /etc, or /var to root (/).
        #   - Resolves staged/development trees to the path prefix preceding the detected
        #     usr, etc, or var component.
        #   - Loads sgnd-exe-common.sh from the resolved framework root when available.
        #   - For staged/development trees where the executable common library is not
        #     present, falls back to the installed framework copy without changing
        #     SGND_FRAMEWORK_ROOT.
        #
        # . Globals (write)
        #   SGND_FRAMEWORK_ROOT
        #
        # . Output
        #   Writes fatal bootstrap errors to stderr using printf because framework UI
        #   helpers are not available until sgnd-exe-common.sh has been loaded.
        #
        # . Returns
        #   0 when the framework root was resolved and executable common library loaded.
        #   126 when the script path cannot be resolved, no canonical root component can
        #   be found, or the executable common library is unreadable.
        #
        # . Usage
        #   _framework_locator || return $?
    _framework_locator() {
        local script_file=""
        local path_without_root=""
        local component=""
        local framework_root=""
        local exe_common=""
        local index=0
        local root_index=-1
        local -a path_parts=()

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || {
            printf 'FATAL: Cannot resolve executable path: %s\n' "${BASH_SOURCE[0]}" >&2
            return 126
        }

        path_without_root="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"

        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in
                usr|etc|var)
                    root_index=$index
                    ;;
            esac
        done

        if (( root_index < 0 )); then
            printf 'FATAL: Cannot determine SolidGroundUX framework root from: %s\n' "$script_file" >&2
            return 126
        fi

        if (( root_index == 0 )); then
            framework_root="/"
        else
            framework_root=""
            for (( index=0; index<root_index; index++ )); do
                framework_root+="/${path_parts[$index]}"
            done
        fi

        SGND_FRAMEWORK_ROOT="$framework_root"

        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
        else
            exe_common="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"

            if [[ ! -r "$exe_common" ]]; then
                exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            fi
        fi

        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read executable common library: %s\n' "$exe_common" >&2
            return 126
        }

        # shellcheck source=/dev/null
        source "$exe_common"
    }

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
# - Framework integration ----------------------------------------------------------
    SGND_USING=(
        sgnd-datatable.sh
        sgnd-menu.sh
    )
    SGND_ARGS_SPEC=()
    SGND_SCRIPT_EXAMPLES=(
        "Run Samba user/group management:"
        "  $SGND_SCRIPT_NAME"
        ""
        "Preview framework-supported changes:"
        "  $SGND_SCRIPT_NAME --dryrun"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Helpers -------------------------------------------------------------------------
    # fn: _smb_runtime_auth_mode - Return the configured Samba authentication mode
        # . Output
        #   Writes "ad" for ADS security and "standalone" otherwise.
        # . Returns
        #   0 always.
        # . Usage
        #   mode="$(_smb_runtime_auth_mode)"
    _smb_runtime_auth_mode() {
        local security=""
        security="$(sudo testparm -s --parameter-name security 2>/dev/null || true)"
        [[ "${security^^}" == "ADS" ]] && printf 'ad\n' || printf 'standalone\n'
    }

    # fn: _validate_identity_name - Validate a local Samba user/group name
        # . Arguments
        #   $1  Candidate identity name.
        # . Returns
        #   0 for a supported name; 1 otherwise.
        # . Usage
        #   _validate_identity_name "SambaUsers"
    _validate_identity_name() {
        [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
    }

    # fn: _smb_ask_selection - Render a numbered single/multi-select prompt
        # . Arguments
        #   --label TEXT, --var NAME, optional --multi, then --items ITEM...
        # . Returns
        #   0 on selection; 1 on Q/back; 2 for invalid invocation.
        # . Usage
        #   _smb_ask_selection --label "Select users" --var selected --multi --items "user1" "user2"
    _smb_ask_selection() {
        local label="Select an option"
        local var_name="selection"
        local multi=0
        local input=""
        local token=""
        local start=0
        local end=0
        local index=0
        local i=0
        local invalid=0
        local -a items=()
        local -a tokens=()
        local -a selected_values=()
        local -A selected_indexes=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --label) label="$2"; shift 2 ;;
                --var) var_name="$2"; shift 2 ;;
                --multi) multi=1; shift ;;
                --items) shift; items=("$@"); break ;;
                --) shift; break ;;
                *) items+=("$1"); shift ;;
            esac
        done

        [[ "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
        (( ${#items[@]} > 0 )) || return 2

        sgnd_print
        sgnd_print_sectionheader --text "$label"
        for (( i=0; i<${#items[@]}; i++ )); do
            sgnd_print --text "$((i + 1)). ${items[i]}" --pad 2
        done
        sgnd_print --text "Q. Back" --pad 2
        sgnd_print
        sgnd_print_sectionheader ""

        while :; do
            input=""
            if (( multi )); then
                ask --label "Selection (comma/range)" --var input
            else
                ask --label "Selection" --var input
            fi

            input="${input#"${input%%[![:space:]]*}"}"
            input="${input%"${input##*[![:space:]]}"}"
            [[ "${input^^}" == "Q" ]] && return 1

            if (( ! multi )); then
                if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input <= ${#items[@]} )); then
                    printf -v "$var_name" '%s' "${items[input - 1]}"
                    return 0
                fi
                saywarning "Invalid selection: $input"
                continue
            fi

            selected_values=()
            selected_indexes=()
            invalid=0
            IFS=',' read -r -a tokens <<< "$input"

            for token in "${tokens[@]}"; do
                token="${token#"${token%%[![:space:]]*}"}"
                token="${token%"${token##*[![:space:]]}"}"
                if [[ "$token" =~ ^([1-9][0-9]*)-([1-9][0-9]*)$ ]]; then
                    start="${BASH_REMATCH[1]}"
                    end="${BASH_REMATCH[2]}"
                    if (( start > end || end > ${#items[@]} )); then
                        invalid=1
                        break
                    fi
                    for (( index=start; index<=end; index++ )); do
                        selected_indexes["$index"]=1
                    done
                elif [[ "$token" =~ ^[1-9][0-9]*$ ]] && (( token <= ${#items[@]} )); then
                    selected_indexes["$token"]=1
                else
                    invalid=1
                    break
                fi
            done

            if (( invalid || ${#selected_indexes[@]} == 0 )); then
                saywarning "Invalid selection: $input"
                continue
            fi

            for (( index=1; index<=${#items[@]}; index++ )); do
                [[ -n "${selected_indexes[$index]-}" ]] || continue
                selected_values+=("${items[index - 1]}")
            done

            local -n output_ref="$var_name"
            output_ref=("${selected_values[@]}")
            return 0
        done
    }

    # fn: _list_local_samba_users_raw - List enabled local Samba users
        # . Output
        #   Writes one Samba user name per line.
        # . Returns
        #   pdbedit status.
        # . Usage
        #   mapfile -t users < <(_list_local_samba_users_raw)
    _list_local_samba_users_raw() {
        sudo pdbedit -L 2>/dev/null | cut -d: -f1 | LC_ALL=C sort -fu
    }

    # fn: _list_local_groups_raw - List deliberate local access groups
        # . Behavior
        #   - Uses only the local files NSS source.
        #   - Includes groups with GID >= 1000.
        #   - Excludes nogroup and user-private primary groups.
        # . Output
        #   Writes one group name per line.
        # . Returns
        #   0 after enumeration.
        # . Usage
        #   mapfile -t groups < <(_list_local_groups_raw)
    _list_local_groups_raw() {
        local group=""
        local gid=""

        while IFS=: read -r group _ gid _; do
            [[ -n "$group" && "$gid" =~ ^[0-9]+$ ]] || continue
            (( gid >= 1000 )) || continue
            [[ "$group" != "nogroup" ]] || continue

            if getent -s files passwd | awk -F: -v name="$group" -v gid="$gid" '
                $1 == name && $4 == gid { found=1; exit }
                END { exit(found ? 0 : 1) }
            '; then
                continue
            fi

            printf '%s\n' "$group"
        done < <(getent -s files group)
    }

    # fn: _user_group_memberships - Return local group memberships for one user
        # . Arguments
        #   $1  Local user name.
        # . Output
        #   Writes a comma-separated group list, or "None" when no groups resolve.
        # . Returns
        #   0 always.
        # . Usage
        #   groups="$(_user_group_memberships user1)"
    _user_group_memberships() {
        local user="${1:?missing user}"
        local group_line=""
        local group=""
        local result=""
        local -a groups=()

        group_line="$(id -nG "$user" 2>/dev/null || true)"
        read -r -a groups <<< "$group_line"
        for group in "${groups[@]}"; do
            [[ -n "$group" ]] || continue
            if [[ -z "$result" ]]; then
                result="$group"
            else
                result+=", $group"
            fi
        done

        printf '%s\n' "${result:-None}"
    }

    # fn: _select_local_samba_user - Select one enabled local Samba user
        # . Arguments
        #   $1  Output variable name.
        # . Returns
        #   0 on selection; 1 on back/no users.
        # . Usage
        #   _select_local_samba_user user || return 0
    _select_local_samba_user() {
        local output_var="${1:?missing output variable}"
        local selected=""
        local -a users=()

        mapfile -t users < <(_list_local_samba_users_raw)
        (( ${#users[@]} > 0 )) || { saywarning "No local Samba users are available."; return 1; }
        _smb_ask_selection --label "Select local Samba user" --var selected --items "${users[@]}" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    # fn: _select_local_groups - Select one or more local access groups
        # . Arguments
        #   $1  Output array variable name.
        # . Returns
        #   0 on selection; 1 on back/no groups.
        # . Usage
        #   _select_local_groups selected_groups || return 0
    _select_local_groups() {
        local output_var="${1:?missing output array variable}"
        local -a available_groups=()
        local -a chosen_groups=()

        mapfile -t available_groups < <(_list_local_groups_raw)
        (( ${#available_groups[@]} > 0 )) || { saywarning "No local groups are available."; return 1; }
        _smb_ask_selection --label "Select local group(s)" --var chosen_groups --multi --items "${available_groups[@]}" || return 1

        local -n output_ref="$output_var"
        output_ref=("${chosen_groups[@]}")
    }

    # fn: _select_local_group - Select exactly one local access group
        # . Arguments
        #   $1  Output variable name.
        # . Returns
        #   0 on selection; 1 on back/no groups.
        # . Usage
        #   _select_local_group group || return 0
    _select_local_group() {
        local output_var="${1:?missing output variable}"
        local selected=""
        local -a available_groups=()

        mapfile -t available_groups < <(_list_local_groups_raw)
        (( ${#available_groups[@]} > 0 )) || { saywarning "No local groups are available."; return 1; }
        _smb_ask_selection --label "Select local group" --var selected --items "${available_groups[@]}" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    # fn: _pause_return - Keep terminal action results visible
        # . Arguments
        #   $1  Optional return message.
        # . Returns
        #   0 always.
        # . Usage
        #   _pause_return
    _pause_return() {
        local message="${1:-Press Enter to return to Samba user management.}"
        sgnd_print_sectionheader ""
        ask_dlg_autocontinue --seconds 15 --message "$message" --pause || true
        return 0
    }

# - Overview ------------------------------------------------------------------------
    # fn: _show_identity_overview - Show Samba users and their local group memberships
        # . Behavior
        #   - Lists every enabled local Samba user.
        #   - Shows all groups reported by the local identity system for each user.
        #   - Lists deliberate local access groups and their supplementary members.
        # . Returns
        #   0 after rendering the overview.
        # . Usage
        #   _show_identity_overview
    _show_identity_overview() {
        local user=""
        local group=""
        local members=""
        local memberships=""
        local -a users=()
        local -a groups=()

        sgnd_print
        sgnd_print_sectionheader --text "Samba users and group memberships"
        mapfile -t users < <(_list_local_samba_users_raw)
        if (( ${#users[@]} == 0 )); then
            sgnd_print --text "No local Samba users found." --pad 2
        else
            for user in "${users[@]}"; do
                memberships="$(_user_group_memberships "$user")"
                sgnd_print_labeledvalue --label "$user" --value "$memberships" --labelwidth 20
            done
        fi

        sgnd_print
        sgnd_print_sectionheader --text "Local access groups"
        mapfile -t groups < <(_list_local_groups_raw)
        if (( ${#groups[@]} == 0 )); then
            sgnd_print --text "No local access groups found." --pad 2
        else
            for group in "${groups[@]}"; do
                members="$(getent -s files group "$group" 2>/dev/null | cut -d: -f4)"
                sgnd_print_labeledvalue --label "$group" --value "${members:-No supplementary members}" --labelwidth 20
            done
        fi

        _pause_return
    }

# - Samba users ---------------------------------------------------------------------
    # fn: _create_samba_user - Create/enable a local Samba user
        # . Behavior
        #   - Creates the matching Linux account when it does not exist.
        #   - Enables the account in Samba and prompts for its Samba password.
        # . Returns
        #   0 after normal completion; non-zero on account-management failure.
        # . Usage
        #   _create_samba_user
    _create_samba_user() {
        local user=""
        local dlg_rc=0

        while :; do
            user=""
            ask --label "Local user (Q=Back)" --var user --validate _validate_identity_name --back || return 0
            if ! getent -s files passwd "$user" >/dev/null 2>&1; then
                sudo useradd -m -s /bin/bash "$user" || { sayfail "Local Linux user '$user' could not be created."; return 1; }
                sayok "Local Linux user '$user' created."
            fi

            sayinfo "Enter the Samba password for '$user'."
            sudo smbpasswd -a "$user" </dev/tty || { sayfail "Samba account '$user' could not be enabled."; return 1; }
            sayok "Local Samba user '$user' is enabled."

            dlg_rc=0
            sgnd_print_sectionheader ""
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=create/enable another Samba user" \
                || dlg_rc=$?
            case "$dlg_rc" in
                1|3) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _change_samba_password - Change the password for one local Samba user
        # . Returns
        #   0 on success/back; non-zero on smbpasswd failure.
        # . Usage
        #   _change_samba_password
    _change_samba_password() {
        local user=""
        _select_local_samba_user user || return 0
        sudo smbpasswd "$user" </dev/tty || { sayfail "Samba password for '$user' could not be changed."; return 1; }
        sayok "Samba password for '$user' changed."
        _pause_return
    }

    # fn: _remove_samba_users - Remove one or more Samba identities while preserving Linux users
        # . Returns
        #   0 when all selected identities are removed/back; 1 when one or more removals fail.
        # . Usage
        #   _remove_samba_users
    _remove_samba_users() {
        local user=""
        local failures=0
        local -a users=()
        local -a selected_users=()

        mapfile -t users < <(_list_local_samba_users_raw)
        (( ${#users[@]} > 0 )) || { saywarning "No local Samba users are available."; _pause_return; return 0; }
        _smb_ask_selection --label "Select Samba user(s) to remove" --var selected_users --multi --items "${users[@]}" || return 0

        for user in "${selected_users[@]}"; do
            if sudo smbpasswd -x "$user" >/dev/null 2>&1; then
                sayok "Samba user '$user' removed; the Linux account was preserved."
            else
                failures=$((failures + 1))
                saywarning "Samba user '$user' could not be removed."
            fi
        done

        _pause_return
        (( failures == 0 ))
    }

# - Local groups --------------------------------------------------------------------
    # fn: _create_local_group - Create a local standalone access group
        # . Returns
        #   0 after normal completion; non-zero on groupadd failure.
        # . Usage
        #   _create_local_group
    _create_local_group() {
        local group=""
        local dlg_rc=0

        while :; do
            group=""
            ask --label "Group name (Q=Back)" --var group --validate _validate_identity_name --back || return 0
            if getent -s files group "$group" >/dev/null 2>&1; then
                saywarning "Group '$group' already exists."
            else
                sudo groupadd "$group" || { sayfail "Local group '$group' could not be created."; return 1; }
                sayok "Local group '$group' created."
            fi

            dlg_rc=0
            sgnd_print_sectionheader ""
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=create another local group" \
                || dlg_rc=$?
            case "$dlg_rc" in
                1|3) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _add_users_to_group - Add selected Samba users to one selected local group
        # . Returns
        #   0 after success/back; 1 when one or more usermod operations fail.
        # . Usage
        #   _add_users_to_group
    _add_users_to_group() {
        local group=""
        local user=""
        local dlg_rc=0
        local failures=0
        local -a users=()
        local -a selected_users=()

        while :; do
            group=""
            failures=0
            users=()
            selected_users=()

            _select_local_group group || return 0
            mapfile -t users < <(_list_local_samba_users_raw)
            (( ${#users[@]} > 0 )) || { saywarning "No local Samba users are available."; return 0; }

            _smb_ask_selection --label "Add users to '$group'" --var selected_users --multi --items "${users[@]}" || return 0
            for user in "${selected_users[@]}"; do
                if sudo usermod -aG "$group" "$user"; then
                    sayok "User '$user' added to '$group'."
                else
                    failures=$((failures + 1))
                    saywarning "User '$user' could not be added to '$group'."
                fi
            done
            (( failures == 0 )) || return 1

            dlg_rc=0
            sgnd_print_sectionheader ""
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=add users to another local group" \
                || dlg_rc=$?
            case "$dlg_rc" in
                1|3) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _remove_users_from_group - Remove selected supplementary members from one local group
        # . Returns
        #   0 after success/back; 1 when one or more gpasswd operations fail.
        # . Usage
        #   _remove_users_from_group
    _remove_users_from_group() {
        local group=""
        local member=""
        local user=""
        local dlg_rc=0
        local failures=0
        local -a members=()
        local -a filtered_members=()
        local -a selected_members=()

        while :; do
            group=""
            failures=0
            members=()
            filtered_members=()
            selected_members=()

            _select_local_group group || return 0
            IFS=',' read -r -a members <<< "$(getent -s files group "$group" 2>/dev/null | cut -d: -f4)"
            for member in "${members[@]}"; do
                [[ -n "$member" ]] && filtered_members+=("$member")
            done

            (( ${#filtered_members[@]} > 0 )) || { sayinfo "'$group' has no supplementary members to remove."; _pause_return; return 0; }
            _smb_ask_selection --label "Remove users from '$group'" --var selected_members --multi --items "${filtered_members[@]}" || return 0

            for user in "${selected_members[@]}"; do
                if sudo gpasswd -d "$user" "$group" >/dev/null 2>&1; then
                    sayok "User '$user' removed from '$group'."
                else
                    failures=$((failures + 1))
                    saywarning "User '$user' could not be removed from '$group'."
                fi
            done
            (( failures == 0 )) || return 1

            dlg_rc=0
            sgnd_print_sectionheader ""
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=remove users from another local group" \
                || dlg_rc=$?
            case "$dlg_rc" in
                1|3) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _remove_local_groups - Remove one or more selected local access groups
        # . Returns
        #   0 when all selected groups are removed/back; 1 when one or more removals fail.
        # . Usage
        #   _remove_local_groups
    _remove_local_groups() {
        local group=""
        local failures=0
        local -a selected_groups=()

        _select_local_groups selected_groups || return 0
        for group in "${selected_groups[@]}"; do
            if sudo groupdel "$group"; then
                sayok "Local group '$group' removed."
            else
                failures=$((failures + 1))
                saywarning "Local group '$group' could not be removed."
            fi
        done

        _pause_return
        (( failures == 0 ))
    }

# - Menu ----------------------------------------------------------------------------
    _smb_user_menu_overview()       { _show_identity_overview; }
    _smb_user_menu_create_user()    { _create_samba_user; }
    _smb_user_menu_password()       { _change_samba_password; }
    _smb_user_menu_remove_user()    { _remove_samba_users; }
    _smb_user_menu_create_group()   { _create_local_group; }
    _smb_user_menu_add_members()    { _add_users_to_group; }
    _smb_user_menu_remove_members() { _remove_users_from_group; }
    _smb_user_menu_remove_group()   { _remove_local_groups; }

    # fn: _build_menu - Build the standalone Samba identity-management menu
        # . Returns
        #   0 when menu registration succeeds.
        # . Usage
        #   _build_menu
    _build_menu() {
        sgnd_menu_create "Manage Samba Users" "Standalone Samba users, groups, and memberships"
        SGND_MENU_SHOW_TOGGLEBAR=0
        SGND_CURRENT_MODULE_SOURCE="manage-samba-users"
        SGND_MENU_ACTIVE_SOURCE="$SGND_CURRENT_MODULE_SOURCE"

        sgnd_menu_register_group "identity-overview" "Overview" "" 0 1 10
        sgnd_menu_register_item "overview" "identity-overview" "Show users and group memberships" "_smb_user_menu_overview" "" 0 0 1 0

        sgnd_menu_register_group "samba-users" "Samba users" "" 0 1 20
        sgnd_menu_register_item "create-user" "samba-users" "Create/enable Samba user" "_smb_user_menu_create_user" "" 0 0 1 0
        sgnd_menu_register_item "password" "samba-users" "Change Samba password" "_smb_user_menu_password" "" 0 0 1 0
        sgnd_menu_register_item "remove-user" "samba-users" "Remove Samba user(s)" "_smb_user_menu_remove_user" "" 0 0 1 0

        sgnd_menu_register_group "local-groups" "Local access groups" "" 0 1 30
        sgnd_menu_register_item "create-group" "local-groups" "Create local group" "_smb_user_menu_create_group" "" 0 0 1 0
        sgnd_menu_register_item "add-members" "local-groups" "Add user(s) to local group" "_smb_user_menu_add_members" "" 0 0 1 0
        sgnd_menu_register_item "remove-members" "local-groups" "Remove user(s) from local group" "_smb_user_menu_remove_members" "" 0 0 1 0
        sgnd_menu_register_item "remove-group" "local-groups" "Remove local group(s)" "_smb_user_menu_remove_group" "" 0 0 1 0
    }

# - Main ----------------------------------------------------------------------------
    # fn: main - Run interactive standalone Samba identity management
        # . Arguments
        #   $@  Framework and script-specific arguments.
        # . Returns
        #   0 after normal exit; non-zero on bootstrap/action failure.
        # . Usage
        #   main "$@"
    main() {
        local choice=""
        local dispatch_rc=0

        _framework_locator || exit $?
        sgnd_exe_start "$@" || return $?

        command -v pdbedit >/dev/null 2>&1 || { sayfail "pdbedit is not installed."; return 1; }
        command -v smbpasswd >/dev/null 2>&1 || { sayfail "smbpasswd is not installed."; return 1; }
        command -v testparm >/dev/null 2>&1 || { sayfail "testparm is not installed."; return 1; }

        if [[ "$(_smb_runtime_auth_mode)" != "standalone" ]]; then
            saywarning "Local Samba user/group management is only applicable in standalone mode."
            return 0
        fi

        while :; do
            _build_menu || return $?
            sgnd_menu_show_menu

            choice=""
            sgnd_print
            sgnd_print_sectionheader ""
            printf 'Selection : ' >/dev/tty
            sgnd_menu_read_choice choice || return $?

            case "$choice" in
                EXIT|ESC) return 0 ;;
                RESET|REDRAW) continue ;;
            esac

            dispatch_rc=0
            sgnd_menu_dispatch "$choice" || dispatch_rc=$?
            sgnd_print
            sgnd_print_sectionheader ""
            (( dispatch_rc == 0 )) || sleep 1
        done
    }

    main "$@"
