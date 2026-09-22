#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Active Directory
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626501
#   Source      : manage-active-directory.sh
#   Type        : script
#   Group       : Subject manager
#   Purpose     : Manage Samba Active Directory users, groups, memberships, and computers
#
#   Checksum : 5e122f184b10b5eeade6cddce78039d350869a884a712770e575b8e81165a34d
# Description:
#   Implements day-to-day directory administration exposed by the
#   27-active-directory-management Management Console module.
# =====================================================================================
set -uo pipefail

# - Bootstrap ----------------------------------------------------------------------
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
        #   - Loads sgnd-exe-common.sh from the resolved framework root.
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
        fi

        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read executable common library: %s\n' "$exe_common" >&2
            return 126
        }

        # shellcheck source=/dev/null
        source "$exe_common"
    }
    _load_ad_management_library() {
        local script_file="" path_without_root="" component="" app_root="" lib_file=""
        local index=0 root_index=-1
        local -a path_parts=()

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || return 126
        path_without_root="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"

        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in
                usr|etc|var) root_index=$index ;;
            esac
        done

        (( root_index >= 0 )) || {
            sayfail "Cannot determine Active Directory application root."
            return 126
        }

        if (( root_index == 0 )); then
            app_root="/"
        else
            app_root=""
            for (( index=0; index<root_index; index++ )); do
                app_root+="/${path_parts[$index]}"
            done
        fi

        if [[ "$app_root" == "/" ]]; then
            lib_file="/usr/local/lib/solidgroundux/common/active-directory-management.sh"
        else
            lib_file="${app_root%/}/usr/local/lib/solidgroundux/common/active-directory-management.sh"
        fi

        [[ -r "$lib_file" ]] || {
            sayfail "Cannot read Active Directory management library: $lib_file"
            return 126
        }

        # shellcheck source=/dev/null
        source "$lib_file"
    }

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Manage Active Directory"
    : "${SGND_SCRIPT_DESC:=Manage Active Directory users, groups, memberships, and computers.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2625721}"

# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||status,validate,user-list,user-show,user-create,user-toggle,user-password,user-noexpiry,user-addgroups,user-removegroups,user-delete,group-list,group-show,group-create,group-addusers,group-removemembers,group-delete,computer-list,computer-show,computer-delete"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Internal helpers ---------------------------------------------------------------
    _admg_require_dc() { sgnd_ad_require_dc; }

    _admg_validate_sam_name() { sgnd_ad_validate_account "$@"; }

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

        _admg_ask_selection --label "Select Active Directory user" --var selected --items "${users[@]}" || return 1
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

        _admg_ask_selection --label "Select Active Directory group" --var selected --items "${groups[@]}" || return 1
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

        _admg_ask_selection --label "Select Active Directory computer" --var selected --items "${computers[@]}" || return 1
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
            sayinfo "DRYRUN: Would add '$member' to '$group'."
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
            sayinfo "DRYRUN: Would remove '$member' from '$group'."
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

    # fn: _admg_ask_selection - Render AD selections with manager-owned presentation
    _admg_ask_selection() {
        local label="Select an option" var_name="selection" multi=0 input="" token="" start=0 end=0 index=0 i=0 invalid=0
        local -a items=() tokens=() selected_values=()
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
        for (( i=0; i<${#items[@]}; i++ )); do sgnd_print --text "$((i + 1)). ${items[i]}" --pad 2; done
        sgnd_print --text "Q. Back" --pad 2
        sgnd_print
        while :; do
            input=""
            if (( multi )); then ask --label "Selection (comma/range)" --var input; else ask --label "Selection" --var input; fi
            input="${input#"${input%%[![:space:]]*}"}"; input="${input%"${input##*[![:space:]]}"}"
            [[ "${input^^}" == "Q" ]] && return 1
            if (( ! multi )); then
                if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input <= ${#items[@]} )); then printf -v "$var_name" '%s' "${items[input - 1]}"; return 0; fi
                saywarning "Invalid selection: $input"; continue
            fi
            selected_values=(); selected_indexes=(); invalid=0; IFS=',' read -r -a tokens <<< "$input"
            for token in "${tokens[@]}"; do
                token="${token#"${token%%[![:space:]]*}"}"; token="${token%"${token##*[![:space:]]}"}"
                if [[ "$token" =~ ^([1-9][0-9]*)-([1-9][0-9]*)$ ]]; then
                    start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"; (( start <= end && end <= ${#items[@]} )) || { invalid=1; break; }
                    for (( index=start; index<=end; index++ )); do selected_indexes["$index"]=1; done
                elif [[ "$token" =~ ^[1-9][0-9]*$ ]] && (( token <= ${#items[@]} )); then selected_indexes["$token"]=1
                else invalid=1; break; fi
            done
            if (( invalid || ${#selected_indexes[@]} == 0 )); then saywarning "Invalid selection: $input"; continue; fi
            for (( index=1; index<=${#items[@]}; index++ )); do [[ -n "${selected_indexes[$index]-}" ]] && selected_values+=("${items[index - 1]}"); done
            local -n output_ref="$var_name"; output_ref=("${selected_values[@]}"); return 0
        done
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

    # fn: _admg_validate - Validate local Active Directory administration readiness
    _admg_validate() {
        local failures=0 realm=""
        sgnd_print
        sgnd_print_sectionheader "Active Directory management validation"
        command -v samba-tool >/dev/null 2>&1 && sgnd_print_labeledvalue --label "samba-tool" --value "Passed" || { sgnd_print_labeledvalue --label "samba-tool" --value "Failed"; failures=$((failures+1)); }
        sgnd_ad_is_domain_controller && sgnd_print_labeledvalue --label "Domain controller" --value "Passed" || { sgnd_print_labeledvalue --label "Domain controller" --value "Failed"; failures=$((failures+1)); }
        systemctl is-active --quiet samba-ad-dc.service && sgnd_print_labeledvalue --label "AD/DC service" --value "Passed" || { sgnd_print_labeledvalue --label "AD/DC service" --value "Failed"; failures=$((failures+1)); }
        realm="$(sgnd_ad_current_realm 2>/dev/null || true)"
        [[ -n "$realm" ]] && sgnd_print_labeledvalue --label "Realm" --value "Passed ($realm)" || { sgnd_print_labeledvalue --label "Realm" --value "Failed"; failures=$((failures+1)); }
        sudo samba-tool user list >/dev/null 2>&1 && sgnd_print_labeledvalue --label "User enumeration" --value "Passed" || { sgnd_print_labeledvalue --label "User enumeration" --value "Failed"; failures=$((failures+1)); }
        sudo samba-tool group list >/dev/null 2>&1 && sgnd_print_labeledvalue --label "Group enumeration" --value "Passed" || { sgnd_print_labeledvalue --label "Group enumeration" --value "Failed"; failures=$((failures+1)); }
        sudo samba-tool computer list >/dev/null 2>&1 && sgnd_print_labeledvalue --label "Computer enumeration" --value "Passed" || { sgnd_print_labeledvalue --label "Computer enumeration" --value "Failed"; failures=$((failures+1)); }
        (( failures == 0 )) && { sayok "Active Directory management validation passed."; return 0; }
        sayfail "$failures Active Directory management validation check(s) failed."
        return 1
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
                sayinfo "DRYRUN: Would create Active Directory user '$username'."
                if [[ "${password_never_expires^^}" == "YES" ]]; then
                    sayinfo "DRYRUN: Would set the password for '$username' to never expire."
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
            sayinfo "DRYRUN: Would $action Active Directory user '$user'."
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
            sayinfo "DRYRUN: Would reset password for '$user'."
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
            sayinfo "DRYRUN: Would set password for '$user' to never expire."
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
                sayinfo "DRYRUN: Would delete Active Directory user '$user'."
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

        _admg_ask_selection --label "Add '$user' to groups" --var selected_groups --multi --items "${groups[@]}" || return 0
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

            _admg_ask_selection --label "Remove '$user' from groups" --var selected_groups --multi --items "${groups[@]}" || return 0
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
                sayinfo "DRYRUN: Would create Active Directory group '$group'."
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
                sayinfo "DRYRUN: Would delete Active Directory group '$group'."
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

            _admg_ask_selection --label "Add users to '$group'" --var selected_users --multi --items "${users[@]}" || return 0
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

            _admg_ask_selection --label "Remove members from '$group'" --var selected_members --multi --items "${members[@]}" || return 0
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
            sayinfo "DRYRUN: Would delete Active Directory computer '$computer'."
            return 0
        fi

        sudo samba-tool computer delete "$computer" || return $?
        sayok "Active Directory computer '$computer' deleted."
    }


# - Action dispatch -----------------------------------------------------------------
    _admg_action_is_mutating() {
        case "${1:-}" in user-create|user-toggle|user-password|user-noexpiry|user-addgroups|user-removegroups|user-delete|group-create|group-addusers|group-removemembers|group-delete|computer-delete) return 0 ;; *) return 1 ;; esac
    }
    _admg_run_action() {
        local action="${1:?missing action}" rc=0
        case "$action" in
            status) _admg_status || rc=$? ;;
            validate) _admg_validate || rc=$? ;;
            user-list) _admg_list_users || rc=$? ;;
            user-show) _admg_show_user || rc=$? ;;
            user-create) _admg_create_user || rc=$? ;;
            user-toggle) _admg_toggle_user || rc=$? ;;
            user-password) _admg_reset_user_password || rc=$? ;;
            user-noexpiry) _admg_set_user_password_noexpiry || rc=$? ;;
            user-addgroups) _admg_user_add_groups || rc=$? ;;
            user-removegroups) _admg_user_remove_groups || rc=$? ;;
            user-delete) _admg_delete_user || rc=$? ;;
            group-list) _admg_list_groups || rc=$? ;;
            group-show) _admg_show_group || rc=$? ;;
            group-create) _admg_create_group || rc=$? ;;
            group-addusers) _admg_group_add_users || rc=$? ;;
            group-removemembers) _admg_group_remove_members || rc=$? ;;
            group-delete) _admg_delete_group || rc=$? ;;
            computer-list) _admg_list_computers || rc=$? ;;
            computer-show) _admg_show_computer || rc=$? ;;
            computer-delete) _admg_delete_computer || rc=$? ;;
            *) sayfail "Unknown Active Directory management action: $action"; return 2 ;;
        esac
        if (( rc == 0 )) && (( ${FLAG_DRYRUN:-0} == 1 )) && _admg_action_is_mutating "$action"; then sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."; fi
        return "$rc"
    }
# - Main ---------------------------------------------------------------------------
    main() {
        local action=""
        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        _load_ad_management_library || return $?
        action="${ACTION:-}"
        [[ -n "$action" ]] || { sayfail "No management action supplied. Use --action <action>."; return 2; }
        _admg_run_action "$action"
    }
    main "$@"
