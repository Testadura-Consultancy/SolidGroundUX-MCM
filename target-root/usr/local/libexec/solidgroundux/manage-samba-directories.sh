#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Samba Directories
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627322
#   Source      : manage-samba-directories.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Manage directories and directory-level access beneath Samba share storage
#
#   Checksum : 23b2cf432e484a9cce87c8c4e91b02b4ec3e45f71bc16bc597f4ffcc2a11016f
# Description:
#   Provides interactive directory lifecycle and POSIX ACL management beneath the
#   SolidGroundUX Samba share root. Samba share roots are identified from the effective
#   Samba configuration and displayed with their share names. Share-level access remains
#   owned by manage-samba-shares.sh.
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

    # fn$ _load_ad_management - Load shared Active Directory discovery APIs
        # . Returns
        #   0 when the project Active Directory management library is loaded.
        # . Usage
        #   _load_ad_management || return $?
    _load_ad_management() {
        local app_root=""
        local lib_file=""
        local script_file=""
        local path_without_root=""
        local component=""
        local index=0
        local root_index=-1
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
        (( root_index >= 0 )) || { sayfail "Cannot determine Samba application root."; return 126; }

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

        [[ -r "$lib_file" ]] || { sayfail "Cannot read Active Directory management library: $lib_file"; return 126; }
        # shellcheck source=/dev/null
        source "$lib_file"
    }

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Manage Samba Directories"
    : "${SGND_SCRIPT_DESC:=Create, remove, inspect, and secure directories beneath Samba share storage.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2626712}"
    : "${SGND_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${SGND_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${SGND_SCRIPT_COPYRIGHT:=© 2025 - 2026 Testadura Consultancy}"
    : "${SGND_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.1.}"

# - Framework integration ----------------------------------------------------------
    SGND_USING=(
        sgnd-datatable.sh
        sgnd-menu.sh
    )
    SGND_ARGS_SPEC=()
    SGND_SCRIPT_EXAMPLES=(
        "Run directory management:"
        "  $SGND_SCRIPT_NAME"
        ""
        "Preview changes:"
        "  $SGND_SCRIPT_NAME --dryrun"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Local declarations -------------------------------------------------------------
    SGND_SAMBA_CONFIG="/etc/samba/smb.conf"
    SGND_STORAGE_DEFAULT_MOUNTPOINT="/srv/storage"
    SGND_STORAGE_CONFIG_FILE="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"
    SGND_SAMBA_SHARE_ROOT="/srv/storage/shares"
    DIRECTORY_PATHS=()
    DIRECTORY_LABELS=()
    SELECTED_DIRECTORIES=()
    DISCOVERED_USERS=()
    DISCOVERED_GROUPS=()

# - Storage and Samba discovery ----------------------------------------------------
    # fn: _refresh_storage_paths - Resolve the configured SolidGroundUX share root
        # . Returns
        #   0 after SGND_SAMBA_SHARE_ROOT is refreshed.
        # . Usage
        #   _refresh_storage_paths
    _refresh_storage_paths() {
        local mountpoint=""
        local device=""
        local uuid=""

        if [[ -r "$SGND_STORAGE_CONFIG_FILE" ]]; then
            mountpoint="$(awk -F= '
                $1 == "SGND_STORAGE_MOUNTPOINTS" {
                    value=substr($0, index($0, "=") + 1)
                    split(value, parts, ":")
                    print parts[1]
                    exit
                }
                $1 == "SGND_STORAGE_MOUNTPOINT" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$SGND_STORAGE_CONFIG_FILE" 2>/dev/null || true)"
        fi

        if [[ "$mountpoint" != /* || "$mountpoint" == "/" || "$mountpoint" == *[[:space:]]* ]]; then
            mountpoint=""
        fi
        if [[ -z "$mountpoint" ]]; then
            device="$(blkid -L SGND_STORAGE 2>/dev/null || true)"
            if [[ -n "$device" ]]; then
                uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
                if [[ -n "$uuid" ]]; then
                    mountpoint="$(awk -v source="UUID=$uuid" '$0 !~ /^[[:space:]]*#/ && NF >= 2 && $1 == source { print $2; exit }' /etc/fstab 2>/dev/null || true)"
                fi
            fi
        fi
        if [[ "$mountpoint" != /* || "$mountpoint" == "/" || "$mountpoint" == *[[:space:]]* ]]; then
            mountpoint="$SGND_STORAGE_DEFAULT_MOUNTPOINT"
        fi
        SGND_SAMBA_SHARE_ROOT="$mountpoint/shares"
    }

    # fn: _share_name_for_path - Return the Samba share name exported from one exact directory path
        # . Arguments
        #   $1  Absolute directory path.
        # . Output
        #   Writes the share name when the path is an effective Samba share root.
        # . Returns
        #   0 when a matching share exists; 1 otherwise.
        # . Usage
        #   share="$(_share_name_for_path "$path")"
    _share_name_for_path() {
        local candidate="${1:?missing directory path}"
        local share=""
        local path=""

        command -v testparm >/dev/null 2>&1 || return 1
        while IFS= read -r share; do
            [[ -n "$share" ]] || continue
            case "${share,,}" in
                global|printers|print\$) continue ;;
            esac
            path="$(sudo testparm -s --section-name "$share" --parameter-name path 2>/dev/null || true)"
            [[ "$path" == "$candidate" ]] || continue
            printf '%s\n' "$share"
            return 0
        done < <(sudo testparm -s 2>/dev/null | awk '/^\[[^]]+\]$/ { name=$0; gsub(/^\[|\]$/, "", name); print name }')
        return 1
    }

    # fn: _refresh_directory_catalog - Enumerate directories beneath the Samba share root
        # . Purpose
        #   Build selectable directory paths and labels, marking effective Samba share roots.
        # . Outputs (globals)
        #   DIRECTORY_PATHS, DIRECTORY_LABELS
        # . Returns
        #   0 when one or more directories exist; 1 otherwise.
        # . Usage
        #   _refresh_directory_catalog || return 0
    _refresh_directory_catalog() {
        local path=""
        local relative=""
        local share=""

        DIRECTORY_PATHS=()
        DIRECTORY_LABELS=()
        _refresh_storage_paths
        [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] || { saywarning "Samba share root is unavailable: $SGND_SAMBA_SHARE_ROOT"; return 1; }

        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            relative="${path#"$SGND_SAMBA_SHARE_ROOT"/}"
            share="$(_share_name_for_path "$path" 2>/dev/null || true)"
            DIRECTORY_PATHS+=("$path")
            if [[ -n "$share" ]]; then
                DIRECTORY_LABELS+=("* [$share] $relative")
            else
                DIRECTORY_LABELS+=("  $relative")
            fi
        done < <(sudo find "$SGND_SAMBA_SHARE_ROOT" -mindepth 1 -type d -printf '%p\n' 2>/dev/null | LC_ALL=C sort)

        (( ${#DIRECTORY_PATHS[@]} > 0 )) || { saywarning "No directories found beneath $SGND_SAMBA_SHARE_ROOT."; return 1; }
        return 0
    }

    # fn: _selected_directory_text - Format current directory selection for the menu subtitle
        # . Output
        #   Writes a comma-separated relative path list.
        # . Returns
        #   0 always.
        # . Usage
        #   selected_text="$(_selected_directory_text)"
    _selected_directory_text() {
        local path=""
        local text=""
        for path in "${SELECTED_DIRECTORIES[@]}"; do
            [[ -n "$text" ]] && text+=", "
            text+="${path#"$SGND_SAMBA_SHARE_ROOT"/}"
        done
        printf '%s\n' "${text:-None selected}"
    }

    # fn: _select_directories - Select one or more directories from the current catalog
        # . Outputs (globals)
        #   SELECTED_DIRECTORIES
        # . Returns
        #   0 on selection; 1 on cancel or empty catalog.
        # . Usage
        #   _select_directories || return 0
    _select_directories() {
        local selected_label=""
        local index=0
        local -a selected_labels=()

        _refresh_directory_catalog || return 1
        sgnd_print --text "* = directory is exported as a Samba share; share name appears in brackets." --pad 2
        ask_selection --label "Select directory/directories" --var selected_labels --multi --items "${DIRECTORY_LABELS[@]}" || return 1

        SELECTED_DIRECTORIES=()
        for selected_label in "${selected_labels[@]}"; do
            for index in "${!DIRECTORY_LABELS[@]}"; do
                [[ "$selected_label" == "${DIRECTORY_LABELS[$index]}" ]] || continue
                SELECTED_DIRECTORIES+=("${DIRECTORY_PATHS[$index]}")
                break
            done
        done
        (( ${#SELECTED_DIRECTORIES[@]} > 0 ))
    }

    # fn: _require_directory_selection - Require one or more selected directories
        # . Returns
        #   0 when selected; 1 otherwise.
        # . Usage
        #   _require_directory_selection || return $?
    _require_directory_selection() {
        (( ${#SELECTED_DIRECTORIES[@]} > 0 )) || { saywarning "Select one or more directories first."; return 1; }
    }

    # fn: _directory_is_share_root - Test whether a directory is itself exported as a Samba share
        # . Arguments
        #   $1  Absolute directory path.
        # . Returns
        #   0 when exported; 1 otherwise.
        # . Usage
        #   _directory_is_share_root "$path"
    _directory_is_share_root() {
        _share_name_for_path "${1:?missing directory path}" >/dev/null 2>&1
    }

# - Identity discovery -------------------------------------------------------------
    # fn: _runtime_auth_mode - Return Samba's configured authentication mode
        # . Output
        #   Writes ad for ADS security, otherwise standalone.
        # . Returns
        #   0 always.
        # . Usage
        #   mode="$(_runtime_auth_mode)"
    _runtime_auth_mode() {
        local security=""
        security="$(sudo testparm -s --parameter-name security 2>/dev/null || true)"
        [[ "${security^^}" == "ADS" ]] && printf 'ad\n' || printf 'standalone\n'
    }

    # fn: _ensure_kerberos_ticket - Ensure a TGT is available for direct AD discovery
        # . Returns
        #   0 when a usable ticket exists; 1 otherwise.
        # . Usage
        #   _ensure_kerberos_ticket
    _ensure_kerberos_ticket() {
        local realm=""
        local username="Administrator"
        local principal=""

        klist -s 2>/dev/null && return 0
        realm="$(realm list --name-only 2>/dev/null | head -n 1 || true)"
        realm="${realm^^}"
        [[ -n "$realm" ]] || { saywarning "No joined Active Directory realm was found."; return 1; }
        saywarning "No valid Kerberos ticket is available."
        (( ${FLAG_DRYRUN:-0} == 0 )) || return 1
        sgnd_print --text "AD Admin rights are needed to query Active Directory. Please enter the AD administrator account."
        ask --label "AD user (Q=Back)" --var username --default "Administrator" --back || return 1
        [[ "$username" == *"@"* ]] && username="${username%@*}"
        principal="${username}@${realm}"
        sayinfo "Authenticate as $principal."
        kinit "$principal" || { sayfail "Kerberos authentication failed for $principal."; return 1; }
        klist -s 2>/dev/null || { sayfail "Kerberos authentication completed without a usable ticket."; return 1; }
        sayok "Kerberos authentication succeeded."
    }

    # fn: _discover_ad_identities - Discover AD users or groups through LDAP/GSSAPI
        # . Arguments
        #   $1  Identity type: user or group.
        #   $2  Output array variable name.
        # . Returns
        #   0 with one or more identities; 1 on discovery failure.
        # . Usage
        #   _discover_ad_identities group DISCOVERED_GROUPS
    _discover_ad_identities() {
        local type="${1:?missing identity type}"
        local output_var="${2:?missing output array variable}"
        local realm=""
        local realm_lower=""
        local dc=""
        local base_dn=""
        local filter=""
        local identity=""
        local -a discovered=()

        realm="$(realm list --name-only 2>/dev/null | head -n 1 || true)"
        [[ -n "$realm" ]] || { saywarning "No joined Active Directory realm was found."; return 1; }
        realm_lower="${realm,,}"
        dc="$(host -t SRV "_ldap._tcp.${realm_lower}" 2>/dev/null | awk '{ print $NF }' | sed 's/\.$//' | head -n 1)"
        [[ -n "$dc" ]] || { saywarning "No LDAP domain controller could be discovered for $realm."; return 1; }
        base_dn="$(awk -v realm="$realm_lower" 'BEGIN { n=split(realm,p,"."); for(i=1;i<=n;i++){ if(i>1)printf ","; printf "DC=%s",p[i] } printf "\n" }')"
        _ensure_kerberos_ticket || return 1
        command -v ldapsearch >/dev/null 2>&1 || { saywarning "ldapsearch is not installed."; return 1; }

        case "$type" in
            user) filter='(&(objectClass=user)(objectCategory=person))' ;;
            group) filter='(objectClass=group)' ;;
            *) sayfail "Unsupported identity type: $type"; return 1 ;;
        esac

        while IFS= read -r identity; do
            [[ -n "$identity" ]] && discovered+=("$identity")
        done < <(
            ldapsearch -N -Y GSSAPI -H "ldap://$dc" -b "$base_dn" "$filter" sAMAccountName 2>/dev/null |
                awk -F': ' '/^sAMAccountName: / { print $2 }' |
                LC_ALL=C sort -fu
        )

        (( ${#discovered[@]} > 0 )) || { saywarning "No Active Directory ${type}s could be discovered."; return 1; }
        local -n output_ref="$output_var"
        output_ref=("${discovered[@]}")
    }

    # fn: _list_local_access_groups_raw - List deliberate local access groups
        # . Purpose
        #   Return local groups suitable for explicit directory ACL management without
        #   cluttering selectors with automatic user-private primary groups.
        # . Behavior
        #   - Uses only the local files NSS source.
        #   - Includes groups with GID >= 1000.
        #   - Excludes nogroup.
        #   - Excludes a group when a same-named local user has that group as its primary GID.
        # . Output
        #   Writes one local access-group name per line.
        # . Returns
        #   0 after enumeration.
        # . Usage
        #   mapfile -t groups < <(_list_local_access_groups_raw)
    _list_local_access_groups_raw() {
        local group=""
        local gid=""

        while IFS=: read -r group _ gid _; do
            [[ -n "$group" && "$gid" =~ ^[0-9]+$ ]] || continue
            (( gid >= 1000 )) || continue
            [[ "$group" != "nogroup" ]] || continue

            if getent -s files passwd | awk -F: -v name="$group" -v gid="$gid" '''
                $1 == name && $4 == gid { found=1; exit }
                END { exit(found ? 0 : 1) }
            '''; then
                continue
            fi

            printf '%s\n' "$group"
        done < <(getent -s files group)
    }

    # fn: _select_identities - Select one or more users/groups appropriate to the active Samba mode
        # . Arguments
        #   $1  Identity type: user or group.
        #   $2  Output array variable name.
        # . Returns
        #   0 on selection; 1 on cancel/discovery failure.
        # . Usage
        #   _select_identities user users || return 0
    _select_identities() {
        local type="${1:?missing identity type}"
        local output_var="${2:?missing output array variable}"
        local mode=""
        local realm=""
        local value=""
        local -a values=()
        local -a selected=()
        local -a resolved=()

        mode="$(_runtime_auth_mode)"
        if [[ "$mode" == "ad" ]]; then
            _discover_ad_identities "$type" values || return 1
            ask_selection --label "Select Active Directory ${type}(s)" --var selected --multi --items "${values[@]}" || return 1
            realm="$(realm list --name-only 2>/dev/null | head -n 1 || true)"
            for value in "${selected[@]}"; do
                resolved+=("${value}@${realm,,}")
            done
        elif [[ "$type" == "user" ]]; then
            mapfile -t values < <(sudo pdbedit -L 2>/dev/null | cut -d: -f1 | LC_ALL=C sort -fu)
            (( ${#values[@]} > 0 )) || { saywarning "No local Samba users are available."; return 1; }
            ask_selection --label "Select local Samba user(s)" --var selected --multi --items "${values[@]}" || return 1
            resolved=("${selected[@]}")
        else
            mapfile -t values < <(_list_local_access_groups_raw)
            (( ${#values[@]} > 0 )) || { saywarning "No local groups are available."; return 1; }
            ask_selection --label "Select local group(s)" --var selected --multi --items "${values[@]}" || return 1
            resolved=("${selected[@]}")
        fi

        local -n output_ref="$output_var"
        output_ref=("${resolved[@]}")
    }

# - Directory ACL helpers -----------------------------------------------------------
    # fn: _select_permissions - Select directory ACL permissions and return an rwx mask
        # . Arguments
        #   $1  Output variable name.
        # . Returns
        #   0 with a three-character permission mask; 1 on cancel.
        # . Usage
        #   _select_permissions perms || return 0
    _select_permissions() {
        local output_var="${1:?missing output variable}"
        local item=""
        local perms="---"
        local -a selected=()

        ask_selection \
            --label "Select directory permissions" \
            --var selected \
            --multi \
            --items "Read (r)" "Write (w)" "Traverse (x)" || return 1

        for item in "${selected[@]}"; do
            case "$item" in
                "Read (r)") perms="r${perms:1}" ;;
                "Write (w)") perms="${perms:0:1}w${perms:2}" ;;
                "Traverse (x)") perms="${perms:0:2}x" ;;
            esac
        done
        printf -v "$output_var" '%s' "$perms"
    }

    # fn: _grant_directory_access - Grant selected users/groups ACL access to selected directories
        # . Arguments
        #   $1  Identity type: user or group.
        # . Behavior
        #   Applies both immediate and default ACL entries. Share-root directories are skipped
        #   because share-level access is owned by Manage shares.
        # . Returns
        #   0 after updates; non-zero on ACL failure.
        # . Usage
        #   _grant_directory_access group
    _grant_directory_access() {
        local type="${1:?missing identity type}"
        local identity=""
        local path=""
        local perms=""
        local acl_prefix="u"
        local failures=0
        local -a identities=()

        _require_directory_selection || return $?
        _select_identities "$type" identities || return $?
        (( ${#identities[@]} > 0 )) || { saywarning "No $type identities were selected."; return 1; }
        _select_permissions perms || return 0
        [[ "$type" == "group" ]] && acl_prefix="g"

        for path in "${SELECTED_DIRECTORIES[@]}"; do
            if _directory_is_share_root "$path"; then
                saywarning "Share-root access is managed in Manage shares; skipped: ${path#"$SGND_SAMBA_SHARE_ROOT"/}"
                continue
            fi
            for identity in "${identities[@]}"; do
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "DRYRUN: Would grant $perms to $type '$identity' on '$path' and its default ACL."
                    continue
                fi
                sudo setfacl -m "$acl_prefix:$identity:$perms" -m "m::rwx" -- "$path" || { failures=$((failures + 1)); continue; }
                sudo setfacl -m "d:$acl_prefix:$identity:$perms" -m "d:m::rwx" -- "$path" || { failures=$((failures + 1)); continue; }
                sayok "Granted $perms to $type '$identity' on '${path#"$SGND_SAMBA_SHARE_ROOT"/}'."
            done
        done

        (( ${FLAG_DRYRUN:-0} == 0 )) || sayok "DRYRUN directory access preview completed."
        (( failures == 0 ))
    }

    # fn: _assigned_identities - Return named ACL identities across selected directories
        # . Arguments
        #   $1  Identity type: user or group.
        # . Output
        #   Writes one resolved identity per line.
        # . Returns
        #   0 always.
        # . Usage
        #   mapfile -t identities < <(_assigned_identities group)
    _assigned_identities() {
        local type="${1:?missing identity type}"
        local path=""
        local id=""
        local name=""
        local acl_type="user"
        local -A seen=()

        [[ "$type" == "group" ]] && acl_type="group"
        for path in "${SELECTED_DIRECTORIES[@]}"; do
            while IFS= read -r id; do
                [[ -n "$id" ]] || continue
                if [[ "$type" == "group" ]]; then
                    name="$(getent group "$id" 2>/dev/null | cut -d: -f1)"
                else
                    name="$(getent passwd "$id" 2>/dev/null | cut -d: -f1)"
                fi
                [[ -n "$name" ]] || name="${type}-id:$id"
                [[ -n "${seen[$name]-}" ]] && continue
                seen["$name"]=1
                printf '%s\n' "$name"
            done < <(sudo getfacl -cpn -- "$path" 2>/dev/null | awk -F: -v t="$acl_type" '$1 == t && $2 != "" { print $2 }')
        done
    }

    # fn: _remove_directory_access - Remove selected named user/group ACL entries
        # . Arguments
        #   $1  Identity type: user or group.
        # . Returns
        #   0 after updates; non-zero on ACL failure.
        # . Usage
        #   _remove_directory_access user
    _remove_directory_access() {
        local type="${1:?missing identity type}"
        local identity=""
        local path=""
        local acl_prefix="u"
        local failures=0
        local -a identities=()
        local -a selected=()

        _require_directory_selection || return $?
        mapfile -t identities < <(_assigned_identities "$type" | LC_ALL=C sort -fu)
        (( ${#identities[@]} > 0 )) || { saywarning "No named $type ACL entries are assigned to the selected directories."; return 0; }
        ask_selection --label "Select ${type}(s) to remove" --var selected --multi --items "${identities[@]}" || return 0
        [[ "$type" == "group" ]] && acl_prefix="g"

        for path in "${SELECTED_DIRECTORIES[@]}"; do
            if _directory_is_share_root "$path"; then
                saywarning "Share-root access is managed in Manage shares; skipped: ${path#"$SGND_SAMBA_SHARE_ROOT"/}"
                continue
            fi
            for identity in "${selected[@]}"; do
                [[ "$identity" == *-id:* ]] && { saywarning "Unresolved identity '$identity' cannot be removed by name."; continue; }
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "DRYRUN: Would remove $type '$identity' from '$path' and its default ACL."
                    continue
                fi
                sudo setfacl -x "$acl_prefix:$identity" -- "$path" 2>/dev/null || true
                sudo setfacl -x "d:$acl_prefix:$identity" -- "$path" 2>/dev/null || true
                sayok "Removed $type '$identity' access from '${path#"$SGND_SAMBA_SHARE_ROOT"/}'."
            done
        done
        (( failures == 0 ))
    }

    # fn: _show_directory_access - Display ownership and named ACLs for selected directories
        # . Returns
        #   0 after display.
        # . Usage
        #   _show_directory_access
    _show_directory_access() {
        local path=""
        local share=""
        local record=""
        local type=""
        local id=""
        local perms=""
        local name=""

        _require_directory_selection || return $?
        for path in "${SELECTED_DIRECTORIES[@]}"; do
            share="$(_share_name_for_path "$path" 2>/dev/null || true)"
            sgnd_print
            sgnd_print_sectionheader --text "${path#"$SGND_SAMBA_SHARE_ROOT"/}"
            sgnd_print_labeledvalue --label "Path" --value "$path" --labelwidth 22
            sgnd_print_labeledvalue --label "Samba share" --value "${share:-No}" --labelwidth 22
            sgnd_print_labeledvalue --label "Owner" --value "$(stat -c '%U' "$path" 2>/dev/null || printf 'Unavailable')" --labelwidth 22
            sgnd_print_labeledvalue --label "Group" --value "$(stat -c '%G' "$path" 2>/dev/null || printf 'Unavailable')" --labelwidth 22

            while IFS='|' read -r type id perms; do
                [[ -n "$id" ]] || continue
                if [[ "$type" == "user" ]]; then
                    name="$(getent passwd "$id" 2>/dev/null | cut -d: -f1)"
                else
                    name="$(getent group "$id" 2>/dev/null | cut -d: -f1)"
                fi
                [[ -n "$name" ]] || name="${type}-id:$id"
                sgnd_print_labeledvalue --label "${type^} $name" --value "$perms" --labelwidth 32
            done < <(sudo getfacl -cpn -- "$path" 2>/dev/null | awk -F: '($1=="user" || $1=="group") && $2!="" { print $1 "|" $2 "|" $3 }')

            while IFS='|' read -r type id perms; do
                [[ -n "$id" ]] || continue
                if [[ "$type" == "user" ]]; then
                    name="$(getent passwd "$id" 2>/dev/null | cut -d: -f1)"
                else
                    name="$(getent group "$id" 2>/dev/null | cut -d: -f1)"
                fi
                [[ -n "$name" ]] || name="${type}-id:$id"
                sgnd_print_labeledvalue --label "Default ${type} $name" --value "$perms" --labelwidth 32
            done < <(sudo getfacl -cpn -- "$path" 2>/dev/null | awk -F: '$1=="default" && ($2=="user" || $2=="group") && $3!="" { print $2 "|" $3 "|" $4 }')
        done
        sgnd_print_sectionheader ""
        ask_dlg_autocontinue --seconds 15 --message "Press Enter to return to directory management." --pause || true
    }

# - Directory lifecycle ------------------------------------------------------------
    # fn: _inherit_directory_access - Copy ownership, mode, and ACL model from parent to child
        # . Arguments
        #   $1  Parent directory.
        #   $2  Child directory.
        # . Returns
        #   0 on success; non-zero on filesystem/ACL failure.
        # . Usage
        #   _inherit_directory_access "$parent" "$child"
    _inherit_directory_access() {
        local parent="${1:?missing parent directory}"
        local child="${2:?missing child directory}"
        sudo chown --reference="$parent" -- "$child" || return 1
        sudo chmod --reference="$parent" -- "$child" || return 1
        sudo getfacl -cp -- "$parent" 2>/dev/null | sudo setfacl --set-file=- -- "$child" || return 1
    }

    # fn: _validate_relative_path - Validate a safe relative directory path
        # . Arguments
        #   $1  Relative path.
        # . Returns
        #   0 when safe; 1 otherwise.
        # . Usage
        #   _validate_relative_path "Files/Mark"
    _validate_relative_path() {
        local relative_path="${1:-}"
        local part=""
        local -a parts=()
        [[ -n "$relative_path" && "$relative_path" != /* && "$relative_path" != *$'\n'* ]] || return 1
        IFS='/' read -r -a parts <<< "$relative_path"
        for part in "${parts[@]}"; do
            [[ -n "$part" && "$part" != "." && "$part" != ".." ]] || return 1
        done
    }

    # fn: _create_directory_tree - Create a relative tree beneath one parent with inherited ACLs
        # . Arguments
        #   $1  Parent directory.
        #   $2  Relative path.
        # . Returns
        #   0 when the tree exists and newly created components inherited access.
        # . Usage
        #   _create_directory_tree "$parent" "Files/Mark"
    _create_directory_tree() {
        local parent="${1:?missing parent directory}"
        local relative="${2:?missing relative path}"
        local current="$parent"
        local child=""
        local part=""
        local -a parts=()

        IFS='/' read -r -a parts <<< "$relative"
        for part in "${parts[@]}"; do
            child="$current/$part"
            if ! sudo test -d "$child"; then
                sudo mkdir -- "$child" || return 1
                _inherit_directory_access "$current" "$child" || return 1
            fi
            current="$child"
        done
        sudo test -d "$current"
    }

    # fn: _select_parent_directory - Select the share root or one existing directory as parent
        # . Arguments
        #   $1  Output variable name.
        # . Returns
        #   0 on selection; 1 on cancel.
        # . Usage
        #   _select_parent_directory parent || return 0
    _select_parent_directory() {
        local output_var="${1:?missing output variable}"
        local selected=""
        local index=0
        local -a labels=("[Share root] $SGND_SAMBA_SHARE_ROOT")
        local -a paths=("$SGND_SAMBA_SHARE_ROOT")

        if _refresh_directory_catalog; then
            labels+=("${DIRECTORY_LABELS[@]}")
            paths+=("${DIRECTORY_PATHS[@]}")
        fi
        ask_selection --label "Select parent directory" --var selected --items "${labels[@]}" || return 1
        for index in "${!labels[@]}"; do
            [[ "$selected" == "${labels[$index]}" ]] || continue
            printf -v "$output_var" '%s' "${paths[$index]}"
            return 0
        done
        return 1
    }

    # fn: _create_directory - Create one directory tree beneath a selected parent
        # . Returns
        #   0 after returning to manager; non-zero on creation failure.
        # . Usage
        #   _create_directory
    _create_directory() {
        local parent=""
        local relative=""
        local full_path=""
        local dlg_rc=0

        while :; do
            parent=""
            relative=""
            _select_parent_directory parent || return 0
            ask --label "Relative directory path (Q=Back)" --var relative --validate _validate_relative_path --back || return 0
            full_path="$parent/$relative"
            [[ "$full_path" == "$SGND_SAMBA_SHARE_ROOT/"* ]] || { sayfail "Directory path escapes the Samba share root."; return 1; }

            if sudo test -d "$full_path"; then
                saywarning "Directory already exists: $full_path"
            elif (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would create '$full_path' and inherit access from '$parent'."
            else
                _create_directory_tree "$parent" "$relative" || { sayfail "Could not create directory tree: $full_path"; return 1; }
                sayok "Created '${full_path#"$SGND_SAMBA_SHARE_ROOT"/}'."
            fi

            dlg_rc=0
            sgnd_print_sectionheader ""
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to manager; A=another; timeout=create another directory" \
                || dlg_rc=$?
            case "$dlg_rc" in
                1|3) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _remove_directories - Remove selected non-share-root directories
        # . Returns
        #   0 after returning to manager; non-zero on removal failure.
        # . Usage
        #   _remove_directories
    _remove_directories() {
        local path=""
        local decision="No"
        local failures=0

        _require_directory_selection || return $?
        ask_decision \
            --label "Remove selected directories and all contents" \
            --choices "Yes|Y,No|N,Quit|Q" \
            --default "No" \
            --var decision || return $?
        [[ "${decision^^}" == "QUIT" || "${decision^^}" == "Q" || "${decision^^}" == "NO" || "${decision^^}" == "N" ]] && return 0

        for path in "${SELECTED_DIRECTORIES[@]}"; do
            if _directory_is_share_root "$path"; then
                saywarning "Cannot remove Samba share root from Directory Management: ${path#"$SGND_SAMBA_SHARE_ROOT"/}"
                continue
            fi
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would recursively remove '$path'."
                continue
            fi
            if sudo rm -rf -- "$path"; then
                sayok "Removed '${path#"$SGND_SAMBA_SHARE_ROOT"/}'."
            else
                failures=$((failures + 1))
                saywarning "Could not remove '$path'."
            fi
        done
        SELECTED_DIRECTORIES=()
        sgnd_print_sectionheader ""
        ask_dlg_autocontinue --seconds 15 --message "Press Enter to return to directory management." --pause || true
        (( failures == 0 ))
    }

    # fn: _show_directories - Display all directories and share-root markers
        # . Returns
        #   0 after display; 1 when no directories exist.
        # . Usage
        #   _show_directories
    _show_directories() {
        local label=""
        _refresh_directory_catalog || return 1
        sgnd_print
        sgnd_print_sectionheader --text "Samba directories"
        sgnd_print --text "* = directory is exported as a Samba share; share name appears in brackets." --pad 2
        sgnd_print
        for label in "${DIRECTORY_LABELS[@]}"; do
            sgnd_print --text "$label" --pad 2
        done
        sgnd_print_sectionheader ""
        ask_dlg_autocontinue --seconds 15 --message "Press Enter to return to directory management." --pause || true
    }

    # fn: _validate_selected_directories - Validate selected directory paths and ACL readability
        # . Returns
        #   0 when selected directories validate; 1 otherwise.
        # . Usage
        #   _validate_selected_directories
    _validate_selected_directories() {
        local path=""
        local result=""
        local failures=0
        _require_directory_selection || return $?

        sgnd_print
        sgnd_print_sectionheader --text "Validate selected directories"
        for path in "${SELECTED_DIRECTORIES[@]}"; do
            result="Passed"
            [[ "$path" == "$SGND_SAMBA_SHARE_ROOT/"* && -d "$path" ]] || { result="Failed"; failures=$((failures + 1)); }
            sgnd_print_labeledvalue --label "${path#"$SGND_SAMBA_SHARE_ROOT"/}" --value "$result" --labelwidth 32
            if ! sudo getfacl -cp -- "$path" >/dev/null 2>&1; then
                sgnd_print_labeledvalue --label "ACL readable" --value "Failed" --labelwidth 32
                failures=$((failures + 1))
            fi
        done
        sgnd_print_sectionheader ""
        ask_dlg_autocontinue --seconds 15 --message "Press Enter to return to directory management." --pause || true
        (( failures == 0 ))
    }

# - Menu ---------------------------------------------------------------------------
    _dir_menu_show()          { _show_directories; }
    _dir_menu_select()        { _select_directories; }
    _dir_menu_create()        { _create_directory; }
    _dir_menu_remove()        { _remove_directories; }
    _dir_menu_show_access()   { _show_directory_access; }
    _dir_menu_grant_users()   { _grant_directory_access user; }
    _dir_menu_grant_groups()  { _grant_directory_access group; }
    _dir_menu_remove_users()  { _remove_directory_access user; }
    _dir_menu_remove_groups() { _remove_directory_access group; }
    _dir_menu_validate()      { _validate_selected_directories; }

    # fn: _build_menu - Build the directory-management menu for the current selection state
        # . Returns
        #   0 when menu registration succeeds.
        # . Usage
        #   _build_menu
    _build_menu() {
        local selection_state=2
        local selected_text=""
        (( ${#SELECTED_DIRECTORIES[@]} > 0 )) && selection_state=1
        selected_text="$(_selected_directory_text)"

        sgnd_menu_create "Manage Samba Directories" "Selected directories: $selected_text"
        SGND_MENU_SHOW_TOGGLEBAR=0
        SGND_CURRENT_MODULE_SOURCE="manage-samba-directories"
        SGND_MENU_ACTIVE_SOURCE="$SGND_CURRENT_MODULE_SOURCE"

        sgnd_menu_register_group "directory-browse" "Directories" "" 0 1 10
        sgnd_menu_register_item "show"   "directory-browse" "Show directories"   "_dir_menu_show"   "" 0 0 1 0
        sgnd_menu_register_item "select" "directory-browse" "Select directories" "_dir_menu_select" "" 0 0 1 0
        sgnd_menu_register_item "create" "directory-browse" "Create directory"   "_dir_menu_create" "" 0 0 1 0
        sgnd_menu_register_item "remove" "directory-browse" "Remove directories" "_dir_menu_remove" "" 0 0 "$selection_state" 0

        sgnd_menu_register_group "directory-access" "Directory access" "" 0 1 20
        sgnd_menu_register_item "show-access"    "directory-access" "Show access"              "_dir_menu_show_access"   "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "grant-users"    "directory-access" "Grant access to user(s)"  "_dir_menu_grant_users"   "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "grant-groups"   "directory-access" "Grant access to group(s)" "_dir_menu_grant_groups"  "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "remove-users"   "directory-access" "Remove user access"       "_dir_menu_remove_users"  "" 0 0 "$selection_state" 0
        sgnd_menu_register_item "remove-groups"  "directory-access" "Remove group access"      "_dir_menu_remove_groups" "" 0 0 "$selection_state" 0

        sgnd_menu_register_group "directory-validation" "Validation" "" 0 1 30
        sgnd_menu_register_item "validate" "directory-validation" "Validate selected directories" "_dir_menu_validate" "" 0 0 "$selection_state" 0
    }

# - Main ---------------------------------------------------------------------------
    # fn: main - Run interactive Samba directory management
        # . Arguments
        #   $@  Framework and script-specific arguments.
        # . Returns
        #   0 after normal exit; non-zero on bootstrap or action failure.
        # . Usage
        #   main "$@"
    main() {
        local choice=""
        local dispatch_rc=0

        _framework_locator || exit $?
        _load_ad_management || return $?
        sgnd_exe_start "$@" || return $?

        command -v setfacl >/dev/null 2>&1 || { sayfail "setfacl is not installed."; return 1; }
        command -v getfacl >/dev/null 2>&1 || { sayfail "getfacl is not installed."; return 1; }
        [[ -r "$SGND_SAMBA_CONFIG" ]] || { sayfail "Samba configuration not found: $SGND_SAMBA_CONFIG"; return 1; }
        _refresh_storage_paths
        [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] || { sayfail "Share root not found: $SGND_SAMBA_SHARE_ROOT"; return 1; }

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
