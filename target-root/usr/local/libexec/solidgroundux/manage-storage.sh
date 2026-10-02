#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Storage
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627515
#   Shortname   : MANAGE_STORAGE
#   Source      : manage-storage.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Configure, reconcile, validate, and manage local storage volumes and directories
#
#   Checksum : 074c78a6e61ff9220b3fc21c404e9291b6da2611d44c7f1dca45cf72aea40b95
# Description:
#   Implements persistent local-storage management actions exposed by the
#   15-storage Management Console module.
#
# Attribution:
#   Developers    : Mark Fieten
#   Company       : Testadura Consultancy
#   Client        : -
#   Copyright     : © 2025 - 2026 Testadura Consultancy
#   License       : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
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
# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||provision,configure,mount,unmount,expand,reconcile,reconcile-persistence,validate,status,directories,access-status,set-access,restore-defaults"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action status"
        "  $SGND_SCRIPT_NAME --action reconcile"
        "  $SGND_SCRIPT_NAME --dryrun --action reconcile"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Local declarations --------------------------------------------------------------
    SGND_STORAGE_DEFAULT_MOUNTPOINT="/srv/storage"
    SGND_STORAGE_CONFIG_FILE="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"

# - Internal helpers -------------------------------------------------------------
    # fn: _storage_validate_device
        # . Purpose
        #   Validate that a selected path is an unused whole block device.
        #
        # . Behavior
        #   - Requires an existing block device of type disk.
        #   - Rejects disks that currently contain mounted filesystems.
        #
        # Inputs:
        #   $1 - Block-device path.
        #
        # . Returns
        #   0 when the device is an unused disk, otherwise 1.
        #
        # . Usage
        #   _storage_validate_device "/dev/sdb"
    _storage_validate_device() {
        local device="${1:-}"
        local device_type=""
        local mountpoint=""

        [[ -b "$device" ]] || return 1
        device_type="$(lsblk -dn -o TYPE "$device" 2>/dev/null || true)"
        [[ "$device_type" == "disk" ]] || return 1

        while IFS= read -r mountpoint; do
            [[ -z "$mountpoint" ]] || return 1
        done < <(lsblk -nr -o MOUNTPOINTS "$device" 2>/dev/null)

        return 0
    }

    # fn: _storage_validate_mountpoint
        # . Purpose
        #   Validate an absolute mount-point path.
        #
        # Inputs:
        #   $1 - Proposed mount point.
        #
        # . Returns
        #   0 for a safe absolute path, otherwise 1.
        #
        # . Usage
        #   _storage_validate_mountpoint "/srv/storage"
    _storage_validate_mountpoint() {
        local mountpoint="${1:-}"

        [[ "$mountpoint" == /* ]] || return 1
        [[ "$mountpoint" != "/" ]] || return 1
        [[ "$mountpoint" != *$'\n'* ]] || return 1
        [[ "$mountpoint" != *[[:space:]]* ]] || return 1
    }

    # fn: _storage_list_mountpoints - List all SolidGroundUX-managed storage mount points
    _storage_list_mountpoints() {
        local source=""
        local target=""
        local filesystem=""
        local options=""

        while IFS='|' read -r source target filesystem options; do
            [[ -n "$target" ]] || continue
            _storage_validate_mountpoint "$target" || continue
            printf '%s\n' "$target"
        done < <(_storage_list_managed_fstab_entries)
    }

    # fn: _storage_mountpoint_is_managed - Validate a managed storage mount point
    _storage_mountpoint_is_managed() {
        local candidate="${1:-}"
        local mountpoint=""
        while IFS= read -r mountpoint; do
            [[ "$candidate" == "$mountpoint" ]] && return 0
        done < <(_storage_list_mountpoints)
        return 1
    }

    # fn: _storage_select_mountpoint - Select one managed storage volume
    _storage_select_mountpoint() {
        local output_var="${1:?missing output variable}"
        local label="${2:-Storage mount point}"
        local selected=""
        local choices=""
        local index=1
        local -a mountpoints=()

        mapfile -t mountpoints < <(_storage_list_mountpoints)
        (( ${#mountpoints[@]} > 0 )) || {
            sayfail "No SolidGroundUX-managed storage volumes are configured."
            return 1
        }

        if (( ${#mountpoints[@]} == 1 )); then
            selected="${mountpoints[0]}"
        else
            ask_selection \
                --label "$label" \
                --var selected \
                --items "${mountpoints[@]}" || return $?
        fi

        printf -v "$output_var" '%s' "$selected"
    }

    # fn: _storage_save_configuration - Persist the complete managed mount-point set
    _storage_save_configuration() {
        local config_dir=""
        local mountpoint=""
        local joined=""

        config_dir="$(dirname "$SGND_STORAGE_CONFIG_FILE")"
        while IFS= read -r mountpoint; do
            [[ -n "$mountpoint" ]] || continue
            [[ -z "$joined" ]] || joined+=":"
            joined+="$mountpoint"
        done < <(_storage_list_mountpoints)

        sudo install -d -m 0755 "$config_dir" || return 1
        printf '%s\n' \
            '# SolidGroundUX managed storage configuration' \
            "SGND_STORAGE_MOUNTPOINTS=$joined" | \
            sudo tee "$SGND_STORAGE_CONFIG_FILE" >/dev/null || return 1
        sudo chmod 0644 "$SGND_STORAGE_CONFIG_FILE" || return 1
    }

    # fn: _storage_get_configured_mountpoints - Read persisted managed mount points
    _storage_get_configured_mountpoints() {
        local value=""
        [[ -r "$SGND_STORAGE_CONFIG_FILE" ]] || return 1
        value="$(awk -F= '$1 == "SGND_STORAGE_MOUNTPOINTS" { print substr($0,index($0,"=")+1); exit }' "$SGND_STORAGE_CONFIG_FILE" 2>/dev/null || true)"
        [[ -n "$value" ]] || return 1
        tr ':' '\n' <<< "$value" | awk 'NF && !seen[$0]++'
    }

    # fn: _storage_list_labeled_volumes - List every filesystem labelled SGND_STORAGE
    # Output: DEVICE|UUID|FSTYPE|MOUNTPOINT|FSTAB_SOURCE
    _storage_list_labeled_volumes() {
        local device=""
        local uuid=""
        local filesystem=""
        local mountpoint=""
        local fstab_source=""

        while IFS= read -r device; do
            [[ -n "$device" ]] || continue
            device="$(readlink -f -- "$device" 2>/dev/null || printf '%s' "$device")"
            [[ -b "$device" ]] || continue
            uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
            filesystem="$(blkid -s TYPE -o value "$device" 2>/dev/null || true)"
            mountpoint="$(findmnt -rn -S "$device" -o TARGET 2>/dev/null | head -n 1 || true)"
            fstab_source=""
            if [[ -n "$uuid" ]]; then
                fstab_source="UUID=$uuid"
                [[ -n "$mountpoint" ]] || mountpoint="$(awk -v source="$fstab_source" '$0 !~ /^[[:space:]]*#/ && NF>=2 && $1==source {print $2; exit}' /etc/fstab 2>/dev/null || true)"
            fi
            _storage_validate_mountpoint "$mountpoint" || continue
            printf '%s|%s|%s|%s|%s\n' "$device" "$uuid" "$filesystem" "$mountpoint" "$fstab_source"
        done < <(blkid -t LABEL=SGND_STORAGE -o device 2>/dev/null | sort -u)
    }

    # Backward-compatible helper: return first managed mount point, or the default.
    _storage_get_mountpoint() {
        local mountpoint=""
        mountpoint="$(_storage_list_mountpoints | head -n 1)"
        printf '%s\n' "${mountpoint:-$SGND_STORAGE_DEFAULT_MOUNTPOINT}"
    }

    _storage_dryrun_complete() {
        sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
    }


    # fn: _storage_list_managed_fstab_entries - List SolidGroundUX-managed storage entries
        # . Purpose
        #   Return fstab entries that are explicitly owned by SolidGroundUX storage.
        #
        # . Behavior
        #   - Recognizes only entries immediately following the canonical
        #     '# SolidGroundUX managed storage' marker.
        #   - Ignores unrelated /etc/fstab entries.
        #
        # . Output
        #   One line per managed entry as: SOURCE|TARGET|FSTYPE|OPTIONS
    _storage_list_managed_fstab_entries() {
        awk '
            $0 == "# SolidGroundUX managed storage" {
                managed = 1
                next
            }
            managed {
                if ($0 ~ /^[[:space:]]*$/) {
                    next
                }
                if ($0 ~ /^[[:space:]]*#/) {
                    managed = 0
                    next
                }
                if (NF >= 4) {
                    printf "%s|%s|%s|%s\n", $1, $2, $3, $4
                }
                managed = 0
            }
        ' /etc/fstab 2>/dev/null
    }

    # fn: _storage_list_stale_managed_fstab_entries - List invalid/stale managed entries
    _storage_list_stale_managed_fstab_entries() {
        local source="" target="" filesystem="" options="" device="" label=""
        while IFS='|' read -r source target filesystem options; do
            [[ -n "$source" && -n "$target" ]] || continue
            case "$source" in
                UUID=*) device="$(blkid -U "${source#UUID=}" 2>/dev/null || true)" ;;
                LABEL=*) device="$(blkid -L "${source#LABEL=}" 2>/dev/null || true)" ;;
                *) device="$source" ;;
            esac
            device="$(readlink -f -- "$device" 2>/dev/null || true)"
            label=""
            [[ -b "$device" ]] && label="$(blkid -s LABEL -o value "$device" 2>/dev/null || true)"
            if [[ ! -b "$device" || "$label" != "SGND_STORAGE" ]] || ! _storage_validate_mountpoint "$target"; then
                printf '%s|%s|%s|%s\n' "$source" "$target" "$filesystem" "$options"
            fi
        done < <(_storage_list_managed_fstab_entries)
    }

    # fn: _storage_list_unused_disks
        # . Purpose
        #   List whole disks that do not currently contain mounted filesystems.
        #
        # Outputs (stdout):
        #   One device path per line.
        #
        # . Returns
        #   0 after scanning available disks.
        #
        # . Usage
        #   _storage_list_unused_disks
    _storage_list_unused_disks() {
        local disk_name=""
        local device=""

        while IFS= read -r disk_name; do
            [[ -n "$disk_name" ]] || continue
            device="/dev/$disk_name"
            _storage_validate_device "$device" && printf '%s\n' "$device"
        done < <(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" { print $1 }')
    }

    # fn: _storage_partition_path
        # . Purpose
        #   Return the first partition belonging to a disk after partitioning.
        #
        # Inputs:
        #   $1 - Whole-disk device path.
        #
        # Outputs (stdout):
        #   Partition device path.
        #
        # . Returns
        #   0 when a partition is found, otherwise 1.
        #
        # . Usage
        #   _storage_partition_path "/dev/sdb"
    _storage_partition_path() {
        local device="$1"
        local partition=""
        local attempt=0

        while (( attempt < 10 )); do
            partition="$(lsblk -nrpo NAME,TYPE "$device" 2>/dev/null | awk '$2 == "part" { print $1; exit }')"
            if [[ -n "$partition" ]]; then
                printf '%s\n' "$partition"
                return 0
            fi
            sleep 1
            attempt=$((attempt + 1))
        done

        return 1
    }

    # fn: _storage_validate_account
        # . Purpose
        #   Validate that a local or directory-backed user account can be resolved.
        #
        # Inputs:
        #   $1 - User name to validate.
        #
        # . Returns
        #   0 when the account can be resolved through getent, otherwise 1.
        #
        # . Usage
        #   _storage_validate_account "root"
    _storage_validate_account() {
        local account="${1:-}"
        [[ -n "$account" ]] || return 1
        getent passwd "$account" >/dev/null 2>&1
    }

    # fn: _storage_validate_group
        # . Purpose
        #   Validate that a local or directory-backed group can be resolved.
        #
        # Inputs:
        #   $1 - Group name to validate.
        #
        # . Returns
        #   0 when the group can be resolved through getent, otherwise 1.
        #
        # . Usage
        #   _storage_validate_group "root"
    _storage_validate_group() {
        local group="${1:-}"
        [[ -n "$group" ]] || return 1
        getent group "$group" >/dev/null 2>&1
    }

    # fn: _storage_validate_mode
        # . Purpose
        #   Validate a three- or four-digit octal filesystem mode.
        #
        # Inputs:
        #   $1 - Proposed octal mode.
        #
        # . Returns
        #   0 when the mode is valid, otherwise 1.
        #
        # . Usage
        #   _storage_validate_mode "0770"
    _storage_validate_mode() {
        [[ "${1:-}" =~ ^[0-7]{3,4}$ ]]
    }

    # fn: _storage_select_access_targets - Select one, several, or all managed storage roots
    _storage_select_access_targets() {
        local output_var="${1:?missing output variable}"
        local choice=""
        local token=""
        local count=0
        local i=0
        local index=0
        local invalid=0
        local -a mountpoints=()
        local -a selected_targets=()
        local -a tokens=()
        local -A seen=()

        mapfile -t mountpoints < <(_storage_list_mountpoints)
        count=${#mountpoints[@]}
        (( count > 0 )) || {
            sayfail "No SolidGroundUX-managed storage volumes are configured."
            return 1
        }

        sgnd_print
        sgnd_print_sectionheader "Select storage target"
        for (( i=0; i<count; i++ )); do
            sgnd_print --text "$((i + 1)). ${mountpoints[i]}" --pad 2
        done
        if (( count > 1 )); then
            sgnd_print --text "A. All storage volumes" --pad 2
        fi
        sgnd_print --text "Q. Back" --pad 2
        sgnd_print
        sgnd_print_sectionheader "Selection"

        while :; do
            choice=""
            ask --label "Selection" --var choice || return $?
            choice="${choice#"${choice%%[![:space:]]*}"}"
            choice="${choice%"${choice##*[![:space:]]}"}"

            if [[ "${choice^^}" == "Q" ]]; then
                return 1
            fi
            if (( count > 1 )) && [[ "${choice^^}" == "A" ]]; then
                selected_targets=("${mountpoints[@]}")
                break
            fi

            IFS=',' read -r -a tokens <<< "$choice"
            selected_targets=()
            seen=()
            invalid=0

            for token in "${tokens[@]}"; do
                token="${token#"${token%%[![:space:]]*}"}"
                token="${token%"${token##*[![:space:]]}"}"
                if [[ ! "$token" =~ ^[1-9][0-9]*$ ]] || (( token > count )); then
                    invalid=1
                    break
                fi
                index=$((token - 1))
                if [[ -z "${seen[$index]+x}" ]]; then
                    selected_targets+=("${mountpoints[index]}")
                    seen[$index]=1
                fi
            done

            if (( invalid == 0 && ${#selected_targets[@]} > 0 )); then
                break
            fi
            saywarning "Invalid selection: $choice"
        done

        local -n output_ref="$output_var"
        output_ref=("${selected_targets[@]}")
    }

    # fn: _storage_validate_directory_name - Validate one direct child directory name
        # . Purpose
        #   Accept a simple directory name that can safely be joined below a managed storage root.
        #
        # . Behavior
        #   - Rejects empty names, dot entries, path separators, and embedded newlines.
        #   - Allows spaces and normal filesystem punctuation in the directory name.
        #
        # Arguments:
        #   $1 - Proposed direct child directory name.
        #
        # . Returns
        #   0 when the name is safe for a direct child path; otherwise 1.
        #
        # . Usage
        #   _storage_validate_directory_name "application-data"
    _storage_validate_directory_name() {
        local directory_name="${1:-}"
        [[ -n "$directory_name" ]] || return 1
        [[ "$directory_name" != "." && "$directory_name" != ".." ]] || return 1
        [[ "$directory_name" != */* ]] || return 1
        [[ "$directory_name" != *$'\n'* ]] || return 1
    }

    # fn: _storage_list_child_directories - List direct child directories of one storage root
        # . Purpose
        #   Return only the first-level directories below a mounted SolidGroundUX storage root.
        #
        # Arguments:
        #   $1 - Mounted managed storage root.
        #
        # Output:
        #   One directory basename per line, sorted alphabetically.
        #
        # . Returns
        #   0 after scanning the root; non-zero when the root cannot be scanned.
        #
        # . Usage
        #   _storage_list_child_directories "/srv/storage"
    _storage_list_child_directories() {
        local storage_root="${1:?missing storage root}"
        sudo find "$storage_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort
    }

    # fn: _storage_select_child_directory - Select one direct child directory
        # . Purpose
        #   Present the first-level directories below a managed storage root and return the selected name.
        #
        # Arguments:
        #   $1 - Output variable name.
        #   $2 - Mounted managed storage root.
        #   $3 - Optional selector label.
        #
        # . Returns
        #   0 when a directory is selected; non-zero when none exist or selection is cancelled.
        #
        # . Usage
        #   _storage_select_child_directory selected_name "/srv/storage" "Directory"
    _storage_select_child_directory() {
        local output_var="${1:?missing output variable}"
        local storage_root="${2:?missing storage root}"
        local selector_label="${3:-Directory}"
        local selected_child=""
        local -a child_directories=()

        mapfile -t child_directories < <(_storage_list_child_directories "$storage_root")
        (( ${#child_directories[@]} > 0 )) || {
            saywarning "No directories exist below $storage_root."
            return 1
        }

        ask_selection \
            --label "$selector_label" \
            --var selected_child \
            --items "${child_directories[@]}" || return $?

        printf -v "$output_var" '%s' "$selected_child"
    }

    # fn: _storage_action_again - Offer to repeat the completed storage action
    _storage_action_again() {
        local rc=0

        sgnd_print
        sgnd_print_sectionheader "Do another"

        ask_dlg_autocontinue \
            --seconds 5 \
            --message "Repeat this storage action?" \
            --again \
            --pause \
            --legend "Enter=return to menu; A=do another; P/Space=pause"
        rc=$?

        (( rc == 3 ))
    }

# - Public module actions --------------------------------------------------------
    # fn$ storage_provision
        # . Purpose
        #   Provision an unused local disk as persistent SolidGroundUX storage, including its
        #   initial mount so the new filesystem is immediately usable.
        #
        # . Behavior
        #   - Detects and displays unused whole disks.
        #   - Asks for the target disk, filesystem, and mount point.
        #   - Requires explicit confirmation before destructive changes.
        #   - Creates one GPT partition and formats it as ext4 or XFS.
        #   - Adds the filesystem UUID to /etc/fstab, performs the initial mount, and saves the
        #     managed SolidGroundUX storage configuration.
        #   - The initial mount is part of provisioning; the standalone Mount storage action is
        #     retained for later administrative remounts and is not a compound child action.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # Outputs (files):
        #   /etc/fstab
        #
        # . Returns
        #   0 when storage is provisioned or the action is cancelled.
        #   Non-zero when validation, partitioning, formatting, or mounting fails.
        #
        # . Usage
        #   storage_provision
    storage_provision() {
        local devices=()
        local device=""
        local filesystem="EXT4"
        local mountpoint="$SGND_STORAGE_DEFAULT_MOUNTPOINT"
        local decision="No"
        local partition=""
        local uuid=""
        local fstab_backup=""

        mapfile -t devices < <(_storage_list_unused_disks)

        if (( ${#devices[@]} == 0 )); then
            saywarning "No unused whole disks were detected."
            saywarning "Existing SolidGroundUX storage can be repaired with the reconciliation options."
            return 1
        fi

        sgnd_print
        sgnd_print_sectionheader "Available storage devices"
        lsblk -d -o NAME,SIZE,TYPE,FSTYPE,MODEL "${devices[@]}" 2>/dev/null || true
        sgnd_print

        device="${devices[0]}"
        ask \
            --label "Storage device" \
            --var device \
            --default "$device" \
            --validate _storage_validate_device \
            --labelwidth 28 || return $?

        ask_decision \
            --label "Filesystem" \
            --choices "EXT4|E,XFS|X" \
            --default "EXT4" \
            --var filesystem || return $?

        ask \
            --label "Mount point" \
            --var mountpoint \
            --default "$mountpoint" \
            --validate _storage_validate_mountpoint \
            --labelwidth 28 || return $?

        sgnd_print
        sgnd_print_sectionheader "Provision storage"
        sgnd_print_labeledvalue --label "Device" --value "$device" --labelwidth 20
        sgnd_print_labeledvalue --label "Filesystem" --value "$filesystem" --labelwidth 20
        sgnd_print_labeledvalue --label "Mount point" --value "$mountpoint" --labelwidth 20
        sgnd_print
        saywarning "All existing data on $device will be destroyed."

        ask_decision \
            --label "Provision this disk?" \
            --choices "Yes|Y,No|N" \
            --default "No" \
            --var decision || return $?

        [[ "${decision^^}" == "YES" ]] || {
            sayinfo "Storage provisioning cancelled."
            return 0
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would partition $device, format it as ${filesystem,,}, and mount it at $mountpoint."
            sayinfo "DRYRUN: Would persist $mountpoint as an additional managed storage volume."
            _storage_dryrun_complete
            return 0
        fi

        sayinfo "Installing storage-management packages."
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            e2fsprogs \
            parted \
            xfsprogs || return 1

        sayinfo "Creating a GPT partition table on $device."
        sudo wipefs --all "$device" || return 1
        sudo parted --script "$device" mklabel gpt || return 1
        sudo parted --script "$device" mkpart primary 0% 100% || return 1
        sudo partprobe "$device" || true
        sudo udevadm settle || true

        partition="$(_storage_partition_path "$device")" || {
            sayfail "The new partition on $device could not be detected."
            return 1
        }

        sayinfo "Formatting $partition as ${filesystem,,}."
        case "$filesystem" in
            EXT4)
                sudo mkfs.ext4 -F -L SGND_STORAGE "$partition" || return 1
                ;;
            XFS)
                sudo mkfs.xfs -f -L SGND_STORAGE "$partition" || return 1
                ;;
            *)
                sayfail "Unsupported filesystem: $filesystem"
                return 1
                ;;
        esac

        uuid="$(sudo blkid -s UUID -o value "$partition" 2>/dev/null || true)"
        [[ -n "$uuid" ]] || {
            sayfail "The filesystem UUID could not be determined."
            return 1
        }

        sudo install -d -m 0755 "$mountpoint" || return 1

        if mountpoint -q "$mountpoint"; then
            sayfail "$mountpoint is already mounted."
            return 1
        fi

        fstab_backup="/etc/fstab.pre-storage.$(date +%Y%m%d%H%M%S)"
        sudo cp -a /etc/fstab "$fstab_backup" || return 1

        printf '%s\n' \
            '' \
            '# SolidGroundUX managed storage' \
            "UUID=$uuid $mountpoint ${filesystem,,} defaults,nofail 0 2" | \
            sudo tee -a /etc/fstab >/dev/null || return 1

        sudo systemctl daemon-reload || return 1

        if ! sudo mount "$mountpoint"; then
            sayfail "Storage could not be mounted; restoring the previous /etc/fstab."
            sudo cp -a "$fstab_backup" /etc/fstab
            return 1
        fi

        _storage_save_configuration || {
            sayfail "Storage was mounted, but the managed storage configuration could not be persisted."
            return 1
        }

        sayok "Storage provisioned and mounted successfully at $mountpoint."

        mapfile -t devices < <(_storage_list_unused_disks)
        if (( ${#devices[@]} > 0 )); then
            decision="No"
            ask_decision \
                --label "Configure another storage device?" \
                --choices "Yes|Y,No|N" \
                --default "No" \
                --var decision || return $?
            [[ "${decision^^}" == "YES" ]] && storage_provision
        fi
    }

    # fn$ storage_mount
        # . Purpose
        #   Mount the configured SolidGroundUX storage filesystem.
        #
        # . Behavior
        #   - Verifies that the default mount point has an /etc/fstab entry.
        #   - Creates the mount-point directory when needed.
        #   - Mounts the configured filesystem unless it is already mounted.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when storage is mounted or already mounted, otherwise non-zero.
        #
        # . Usage
        #   storage_mount
    storage_mount() {
        local mountpoint=""

        _storage_select_mountpoint mountpoint "Storage mount point" || return $?

        if mountpoint -q "$mountpoint"; then
            sayinfo "Storage is already mounted at $mountpoint."
            return 0
        fi

        if ! awk -v target="$mountpoint" '
            $0 !~ /^[[:space:]]*#/ && NF >= 2 && $2 == target { found = 1 }
            END { exit(found ? 0 : 1) }
        ' /etc/fstab; then
            sayfail "No persistent storage entry exists for $mountpoint."
            return 1
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would mount storage at $mountpoint."
            _storage_dryrun_complete
            return 0
        fi

        sudo install -d -m 0755 "$mountpoint" || return 1
        sudo mount "$mountpoint" || return 1
        sayok "Storage mounted at $mountpoint."
    }

    # fn$ storage_unmount
        # . Purpose
        #   Unmount the configured SolidGroundUX storage filesystem.
        #
        # . Behavior
        #   - Leaves the persistent /etc/fstab entry unchanged.
        #   - Reports when the storage is already unmounted.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when storage is unmounted or already unmounted, otherwise non-zero.
        #
        # . Usage
        #   storage_unmount
    storage_unmount() {
        local mountpoint=""

        _storage_select_mountpoint mountpoint "Storage mount point" || return $?

        if ! mountpoint -q "$mountpoint"; then
            sayinfo "Storage is already unmounted at $mountpoint."
            return 0
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would unmount storage at $mountpoint."
            _storage_dryrun_complete
            return 0
        fi

        sudo umount "$mountpoint" || {
            sayfail "Storage could not be unmounted. It may still be in use."
            return 1
        }

        sayok "Storage unmounted from $mountpoint."
    }

    # fn$ storage_expand
        # . Purpose
        #   Expand the configured storage partition and filesystem to use a larger disk.
        #
        # . Behavior
        #   - Resolves the configured storage source from the active mount or /etc/fstab.
        #   - Requires a normal disk partition created by the Storage module.
        #   - Expands the partition to fill the resized virtual or physical disk.
        #   - Grows ext4 with resize2fs or XFS with xfs_growfs.
        #   - Mounts XFS storage first when required.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when the partition and filesystem are expanded, otherwise non-zero.
        #
        # . Usage
        #   storage_expand
    storage_expand() {
        local mountpoint=""
        local source=""
        local source_spec=""
        local filesystem=""
        local parent_name=""
        local parent_device=""
        local partition_number=""

        _storage_select_mountpoint mountpoint "Storage mount point" || return $?

        if mountpoint -q "$mountpoint"; then
            source="$(findmnt -n -o SOURCE --mountpoint "$mountpoint" 2>/dev/null || true)"
            filesystem="$(findmnt -n -o FSTYPE --mountpoint "$mountpoint" 2>/dev/null || true)"
        else
            source_spec="$(awk -v target="$mountpoint" '
                $0 !~ /^[[:space:]]*#/ && NF >= 3 && $2 == target { print $1; exit }
            ' /etc/fstab)"
            filesystem="$(awk -v target="$mountpoint" '
                $0 !~ /^[[:space:]]*#/ && NF >= 3 && $2 == target { print $3; exit }
            ' /etc/fstab)"

            case "$source_spec" in
                UUID=*) source="$(blkid -U "${source_spec#UUID=}" 2>/dev/null || true)" ;;
                *) source="$source_spec" ;;
            esac
        fi

        source="$(readlink -f "$source" 2>/dev/null || true)"
        [[ -b "$source" ]] || {
            sayfail "The configured storage block device could not be resolved."
            return 1
        }

        [[ "$(lsblk -dn -o TYPE "$source" 2>/dev/null || true)" == "part" ]] || {
            sayfail "Storage expansion currently requires a normal disk partition."
            return 1
        }

        parent_name="$(lsblk -dn -o PKNAME "$source" 2>/dev/null || true)"
        partition_number="$(lsblk -dn -o PARTN "$source" 2>/dev/null || true)"
        [[ -n "$parent_name" && -n "$partition_number" ]] || {
            sayfail "The parent disk or partition number could not be determined."
            return 1
        }
        parent_device="/dev/$parent_name"

        sgnd_print
        sgnd_print_sectionheader "Expand storage"
        sgnd_print_labeledvalue --label "Disk" --value "$parent_device" --labelwidth 20
        sgnd_print_labeledvalue --label "Partition" --value "$source" --labelwidth 20
        sgnd_print_labeledvalue --label "Filesystem" --value "$filesystem" --labelwidth 20
        sgnd_print_labeledvalue --label "Mount point" --value "$mountpoint" --labelwidth 20

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would expand $source and its $filesystem filesystem."
            _storage_dryrun_complete
            return 0
        fi

        sayinfo "Installing storage expansion tools."
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            cloud-guest-utils \
            e2fsprogs \
            xfsprogs || return 1

        sayinfo "Expanding partition $partition_number on $parent_device."
        sudo growpart "$parent_device" "$partition_number" || return 1
        sudo partprobe "$parent_device" || true
        sudo udevadm settle || true

        case "${filesystem,,}" in
            ext4)
                sudo resize2fs "$source" || return 1
                ;;
            xfs)
                mountpoint -q "$mountpoint" || storage_mount || return 1
                sudo xfs_growfs "$mountpoint" || return 1
                ;;
            *)
                sayfail "Unsupported filesystem for expansion: $filesystem"
                return 1
                ;;
        esac

        sayok "Storage expansion completed successfully."
    }

    # fn$ storage_manage_directories
        # . Purpose
        #   Manage simple first-level filesystem directories below one SolidGroundUX storage root.
        #
        # . Behavior
        #   - Selects one configured storage root and requires it to be mounted before changes are allowed.
        #   - Lists only direct child directories; files are not included.
        #   - Creates new directories as root:root mode 0755.
        #   - Renames one direct child directory without crossing the selected storage-root boundary.
        #   - Removes directories only when they are empty; recursive deletion is intentionally unsupported.
        #   - Does not manage Samba shares, ACLs, AD identities, or standalone Samba identities.
        #   - Owns its interactive submenu and returns directly to the Storage menu when the user backs out.
        #   - Honors console dry-run mode for create, rename, and remove operations.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when the directory manager is exited normally; non-zero on an operation failure.
        #
        # . Usage
        #   storage_manage_directories
    storage_manage_directories() {
        local storage_root=""
        local directory_action=""
        local directory_name=""
        local selected_directory=""
        local new_directory_name=""
        local source_path=""
        local target_path=""
        local decision="No"
        local -a child_directories=()

        _storage_select_mountpoint storage_root "Storage root" || return $?

        if ! mountpoint -q "$storage_root"; then
            sayfail "Storage is not mounted at $storage_root. Mount it before managing directories."
            return 1
        fi

        while :; do
            mapfile -t child_directories < <(_storage_list_child_directories "$storage_root")

            sgnd_print
            sgnd_print_sectionheader "Storage directories"
            sgnd_print_labeledvalue --label "Storage root" --value "$storage_root" --labelwidth 20
            sgnd_print
            if (( ${#child_directories[@]} == 0 )); then
                sgnd_print --text "No directories." --pad 2
            else
                for directory_name in "${child_directories[@]}"; do
                    sgnd_print --text "$directory_name" --pad 2
                done
            fi

            directory_action=""
            ask_selection \
                --label "Action" \
                --var directory_action \
                --items "Create directory" "Rename directory" "Remove empty directory" "Refresh list" || return 0

            case "$directory_action" in
                "Create directory")
                    directory_name=""
                    ask \
                        --label "Directory name" \
                        --var directory_name \
                        --validate _storage_validate_directory_name \
                        --back || continue
                    target_path="$storage_root/$directory_name"
                    [[ ! -e "$target_path" ]] || {
                        sayfail "Directory already exists: $target_path"
                        continue
                    }
                    if (( ${FLAG_DRYRUN:-0} == 1 )); then
                        sayinfo "DRYRUN: Would create directory $target_path as root:root mode 0755."
                        continue
                    fi
                    sudo install -d -o root -g root -m 0755 "$target_path" || return 1
                    sayok "Directory created: $target_path"
                    ;;

                "Rename directory")
                    selected_directory=""
                    _storage_select_child_directory selected_directory "$storage_root" "Directory to rename" || continue
                    new_directory_name=""
                    ask \
                        --label "New directory name" \
                        --var new_directory_name \
                        --default "$selected_directory" \
                        --validate _storage_validate_directory_name \
                        --back || continue
                    [[ "$new_directory_name" != "$selected_directory" ]] || {
                        sayinfo "Directory name is unchanged."
                        continue
                    }
                    source_path="$storage_root/$selected_directory"
                    target_path="$storage_root/$new_directory_name"
                    [[ ! -e "$target_path" ]] || {
                        sayfail "Target already exists: $target_path"
                        continue
                    }
                    if (( ${FLAG_DRYRUN:-0} == 1 )); then
                        sayinfo "DRYRUN: Would rename $source_path to $target_path."
                        continue
                    fi
                    sudo mv -- "$source_path" "$target_path" || return 1
                    sayok "Directory renamed: $selected_directory -> $new_directory_name"
                    ;;

                "Remove empty directory")
                    selected_directory=""
                    _storage_select_child_directory selected_directory "$storage_root" "Directory to remove" || continue
                    target_path="$storage_root/$selected_directory"
                    if [[ -n "$(sudo find "$target_path" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
                        sayfail "Directory is not empty: $target_path"
                        continue
                    fi
                    decision="No"
                    ask_decision \
                        --label "Remove empty directory '$selected_directory'?" \
                        --choices "Yes|Y,No|N" \
                        --default "No" \
                        --var decision || continue
                    [[ "${decision^^}" == "YES" ]] || continue
                    if (( ${FLAG_DRYRUN:-0} == 1 )); then
                        sayinfo "DRYRUN: Would remove empty directory $target_path."
                        continue
                    fi
                    sudo rmdir -- "$target_path" || return 1
                    sayok "Directory removed: $target_path"
                    ;;

                "Refresh list")
                    ;;
            esac
        done
    }

    # fn$ storage_access_status
    storage_access_status() {
        local path="" owner="-" group="-" mode="-"
        sgnd_print
        sgnd_print_sectionheader "Storage access"
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            owner="-"; group="-"; mode="-"
            if [[ -e "$path" ]]; then
                owner="$(stat -c '%U' "$path" 2>/dev/null || printf '-')"
                group="$(stat -c '%G' "$path" 2>/dev/null || printf '-')"
                mode="$(stat -c '%a' "$path" 2>/dev/null || printf '-')"
            fi
            sgnd_print_labeledvalue --label "Path" --value "$path" --labelwidth 18
            sgnd_print_labeledvalue --label "Owner" --value "$owner" --labelwidth 18
            sgnd_print_labeledvalue --label "Group" --value "$group" --labelwidth 18
            sgnd_print_labeledvalue --label "Root permissions" --value "$mode" --labelwidth 18
            sgnd_print
        done < <(_storage_list_mountpoints)
        sgnd_print
        sgnd_print_sectionheader ""
    }

    storage_set_access() {
        local target="" current_owner="root" current_group="root" current_mode="755"
        local owner="" group="" mode=""
        local -a targets=()

        _storage_select_access_targets targets || return $?
        current_owner="$(stat -c '%U' "${targets[0]}" 2>/dev/null || printf 'root')"
        current_group="$(stat -c '%G' "${targets[0]}" 2>/dev/null || printf 'root')"
        current_mode="$(stat -c '%a' "${targets[0]}" 2>/dev/null || printf '755')"
        owner="$current_owner"
        group="$current_group"
        mode="$current_mode"

        sgnd_print
        sgnd_print_sectionheader "Storage access"
        ask --label "Owner" --var owner --default "$owner" --validate _storage_validate_account || return $?
        ask --label "Group" --var group --default "$group" --validate _storage_validate_group || return $?
        ask --label "Root permissions" --var mode --default "$mode" --validate _storage_validate_mode || return $?

        for target in "${targets[@]}"; do
            [[ -d "$target" ]] || { sayfail "Storage directory does not exist: $target"; return 1; }
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would set access on $target to $owner:$group $mode."
            else
                sudo chown "$owner:$group" "$target" || return 1
                sudo chmod "$mode" "$target" || return 1
                sayok "Storage access updated for $target to $owner:$group $mode."
            fi
        done
        (( ${FLAG_DRYRUN:-0} == 1 )) && _storage_dryrun_complete
        sgnd_print
        sgnd_print_sectionheader ""
    }

    storage_restore_access_defaults() {
        local target="" decision="No"
        local -a targets=()
        _storage_select_access_targets targets || return $?
        sgnd_print
        sgnd_print_sectionheader "Restore storage access defaults"
        for target in "${targets[@]}"; do
            sgnd_print_labeledvalue --label "Storage root" --value "$target" --labelwidth 20
        done
        sgnd_print_labeledvalue --label "Defaults" --value "root:root 0755" --labelwidth 20
        ask_decision --label "Restore these defaults?" --choices "Yes|Y,No|N" --default "No" --var decision || return $?
        [[ "${decision^^}" == "YES" ]] || { sayinfo "Storage access reset cancelled."; return 0; }
        for target in "${targets[@]}"; do
            [[ -d "$target" ]] || { sayfail "Storage root does not exist: $target"; return 1; }
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would restore canonical storage ownership and permissions for $target."
            else
                sudo chown root:root "$target" || return 1
                sudo chmod 0755 "$target" || return 1
                sayok "Canonical storage ownership and permissions restored for $target."
            fi
        done
        (( ${FLAG_DRYRUN:-0} == 1 )) && _storage_dryrun_complete
    }

    # fn$ storage_reconcile
    storage_reconcile() {
        local device="" uuid="" filesystem="" mountpoint="" fstab_source=""
        local detected_count=0
        local current="" detected=""

        sgnd_print
        sgnd_print_sectionheader "Reconcile storage configuration"
        while IFS='|' read -r device uuid filesystem mountpoint fstab_source; do
            [[ -n "$mountpoint" ]] || continue
            detected_count=$((detected_count + 1))
            sgnd_print_labeledvalue --label "Device" --value "$device" --labelwidth 24
            sgnd_print_labeledvalue --label "UUID" --value "${uuid:--}" --labelwidth 24
            sgnd_print_labeledvalue --label "Filesystem" --value "${filesystem:--}" --labelwidth 24
            sgnd_print_labeledvalue --label "Mount point" --value "$mountpoint" --labelwidth 24
            sgnd_print
        done < <(_storage_list_labeled_volumes)

        (( detected_count > 0 )) || { sayfail "No usable SGND_STORAGE filesystems could be detected."; return 1; }

        current="$(_storage_get_configured_mountpoints 2>/dev/null | sort -u || true)"
        detected="$(_storage_list_mountpoints | sort -u)"
        if [[ "$current" == "$detected" ]]; then
            sayok "Storage configuration already matches all managed SGND_STORAGE volumes."
            return 0
        fi
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would update $SGND_STORAGE_CONFIG_FILE with all managed storage mount points."
            _storage_dryrun_complete; return 0
        fi
        _storage_save_configuration || { sayfail "Could not update SolidGroundUX storage configuration."; return 1; }
        sayok "Storage configuration reconciled for $detected_count SGND_STORAGE volume(s)."
    }

    # fn$ storage_reconcile_persistence
        # . Purpose
        #   Repair or clean stale SolidGroundUX-managed /etc/fstab storage entries.
        #
        # . Behavior
        #   - Detects stale managed entries whose configured source no longer resolves.
        #   - Detects filesystems labelled SGND_STORAGE that are present but not referenced by
        #     a valid managed /etc/fstab entry.
        #   - When exactly one stale entry and one replacement SGND_STORAGE filesystem exist,
        #     offers to replace the stale UUID/source while preserving mount point and options.
        #   - Validates the resulting /etc/fstab before activation and restores the backup on failure.
        #   - Mounts the repaired filesystem when its target is currently unmounted.
        #   - Falls back to the previous explicit stale-entry removal workflow when repair is ambiguous.
        #   - Never formats, repartitions, or otherwise modifies filesystem contents.
        #   - Honors console dry-run mode.
        #
        # . Returns
        #   0 when persistence is already valid, repaired, removed by explicit confirmation, or cancelled.
        #   Non-zero when a requested repair/removal cannot be completed safely.
        #
        # . Usage
        #   storage_reconcile_persistence
    storage_reconcile_persistence() {
        local decision="Yes"
        local backup_file=""
        local temp_file=""
        local stale_file=""
        local source=""
        local target=""
        local filesystem=""
        local options=""
        local stale_count=0
        local candidate_count=0
        local candidate_device=""
        local candidate_uuid=""
        local candidate_filesystem=""
        local candidate_source=""
        local stale_source=""
        local stale_target=""
        local stale_filesystem=""
        local stale_options=""
        local device=""
        local uuid=""
        local detected_filesystem=""
        local mounted_target=""
        local referenced=0

        sgnd_print
        sgnd_print_sectionheader "Reconcile storage persistence"

        while IFS='|' read -r source target filesystem options; do
            [[ -n "$source" && -n "$target" ]] || continue
            sgnd_print_labeledvalue --label "Managed storage" --value "$target" --labelwidth 24
            sgnd_print_labeledvalue --label "Source" --value "$source" --labelwidth 24
            sgnd_print_labeledvalue --label "Filesystem" --value "$filesystem" --labelwidth 24
            sgnd_print
        done < <(_storage_list_managed_fstab_entries)

        while IFS='|' read -r source target filesystem options; do
            [[ -n "$source" && -n "$target" ]] || continue
            stale_count=$((stale_count + 1))
            stale_source="$source"
            stale_target="$target"
            stale_filesystem="$filesystem"
            stale_options="$options"
            saywarning "Stale managed fstab entry: $source -> $target ($filesystem, $options)"
        done < <(_storage_list_stale_managed_fstab_entries)

        if (( stale_count == 0 )); then
            sayok "All SolidGroundUX-managed storage entries are valid; no stale entries were found."
            return 0
        fi

        # A restored/re-attached storage disk commonly has a new UUID while retaining the
        # canonical SGND_STORAGE label. Repair automatically only when the mapping is unique.
        if (( stale_count == 1 )); then
            while IFS= read -r device; do
                [[ -n "$device" ]] || continue
                device="$(readlink -f -- "$device" 2>/dev/null || true)"
                [[ -b "$device" ]] || continue
                uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
                detected_filesystem="$(blkid -s TYPE -o value "$device" 2>/dev/null || true)"
                [[ -n "$uuid" && -n "$detected_filesystem" ]] || continue

                referenced=0
                if awk -v uuid_source="UUID=$uuid" -v device_source="$device" '
                    $0 !~ /^[[:space:]]*#/ && NF >= 2 && ($1 == uuid_source || $1 == device_source) { found=1 }
                    END { exit(found ? 0 : 1) }
                ' /etc/fstab 2>/dev/null; then
                    referenced=1
                fi
                (( referenced == 0 )) || continue

                mounted_target="$(findmnt -rn -S "$device" -o TARGET 2>/dev/null | head -n 1 || true)"
                [[ -z "$mounted_target" || "$mounted_target" == "$stale_target" ]] || continue
                [[ "${detected_filesystem,,}" == "${stale_filesystem,,}" ]] || continue

                candidate_count=$((candidate_count + 1))
                candidate_device="$device"
                candidate_uuid="$uuid"
                candidate_filesystem="$detected_filesystem"
            done < <(blkid -t LABEL=SGND_STORAGE -o device 2>/dev/null | sort -u)
        fi

        if (( stale_count == 1 && candidate_count == 1 )); then
            candidate_source="UUID=$candidate_uuid"
            sgnd_print_sectionheader "Repair detected storage mapping"
            sgnd_print_labeledvalue --label "Mount point" --value "$stale_target" --labelwidth 24
            sgnd_print_labeledvalue --label "Stale source" --value "$stale_source" --labelwidth 24
            sgnd_print_labeledvalue --label "Detected device" --value "$candidate_device" --labelwidth 24
            sgnd_print_labeledvalue --label "Detected UUID" --value "$candidate_uuid" --labelwidth 24
            sgnd_print_labeledvalue --label "Filesystem" --value "$candidate_filesystem" --labelwidth 24

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would replace '$stale_source' with '$candidate_source' for '$stale_target'."
                sayinfo "DRYRUN: Would validate /etc/fstab and mount '$stale_target' when currently unmounted."
                _storage_dryrun_complete
                return 0
            fi

            ask_decision \
                --label "Repair this storage mapping?" \
                --choices "Yes|Y,No|N" \
                --default "Yes" \
                --var decision || return $?
            [[ "${decision^^}" == "YES" ]] || {
                sayinfo "Storage persistence repair cancelled."
                return 0
            }

            backup_file="/etc/fstab.pre-storage-repair.$(date +%Y%m%d%H%M%S)"
            temp_file="$(mktemp)" || return 1
            sudo cp -a /etc/fstab "$backup_file" || { rm -f -- "$temp_file"; return 1; }

            awk -v old_source="$stale_source" -v target="$stale_target" -v new_source="$candidate_source" '
                BEGIN { managed=0 }
                $0 == "# SolidGroundUX managed storage" { print; managed=1; next }
                managed && NF >= 4 {
                    if ($1 == old_source && $2 == target) $1 = new_source
                    print
                    managed=0
                    next
                }
                { print }
            ' /etc/fstab > "$temp_file" || { rm -f -- "$temp_file"; return 1; }

            sudo install -m 0644 "$temp_file" /etc/fstab || { rm -f -- "$temp_file"; return 1; }
            rm -f -- "$temp_file"

            if ! findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1; then
                sayfail "Repaired /etc/fstab did not validate; restoring the previous file."
                sudo cp -a "$backup_file" /etc/fstab
                return 1
            fi

            sudo systemctl daemon-reload || {
                sayfail "systemd could not reload the repaired storage configuration; restoring /etc/fstab."
                sudo cp -a "$backup_file" /etc/fstab
                sudo systemctl daemon-reload >/dev/null 2>&1 || true
                return 1
            }

            sudo install -d -m 0755 "$stale_target" || return 1
            if ! mountpoint -q "$stale_target"; then
                if ! sudo mount "$stale_target"; then
                    sayfail "The repaired storage filesystem could not be mounted at $stale_target; restoring /etc/fstab."
                    sudo cp -a "$backup_file" /etc/fstab
                    sudo systemctl daemon-reload >/dev/null 2>&1 || true
                    return 1
                fi
            fi

            _storage_save_configuration || {
                sayfail "Storage was repaired and mounted, but the managed storage configuration could not be persisted."
                return 1
            }

            sayok "Storage persistence repaired for $stale_target."
            sayinfo "Backup retained at $backup_file."
            return 0
        fi

        saywarning "The stale storage mapping cannot be repaired automatically because the replacement is ambiguous or unavailable."
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would offer removal of $stale_count stale SolidGroundUX-managed storage entry/entries from /etc/fstab."
            _storage_dryrun_complete
            return 0
        fi

        ask_decision \
            --label "Remove stale SolidGroundUX-managed fstab entries?" \
            --choices "Yes|Y,No|N" \
            --default "No" \
            --var decision || return $?
        [[ "${decision^^}" == "YES" ]] || {
            sayinfo "Storage persistence reconciliation cancelled; stale entries were left unchanged."
            return 0
        }

        backup_file="/etc/fstab.pre-storage-reconcile.$(date +%Y%m%d%H%M%S)"
        temp_file="$(mktemp)" || return 1
        stale_file="$(mktemp)" || { rm -f -- "$temp_file"; return 1; }
        sudo cp -a /etc/fstab "$backup_file" || { rm -f -- "$temp_file" "$stale_file"; return 1; }
        _storage_list_stale_managed_fstab_entries | awk -F'|' '{print $1 "|" $2}' > "$stale_file"

        awk -v stale_file="$stale_file" '
            BEGIN {
                while ((getline k < stale_file) > 0) stale[k] = 1
                close(stale_file)
                managed = 0
                marker = ""
            }
            $0 == "# SolidGroundUX managed storage" { marker = $0; managed = 1; next }
            managed {
                if ($0 ~ /^[[:space:]]*$/) next
                if (NF >= 2) {
                    key = $1 "|" $2
                    if (!(key in stale)) { print marker; print }
                    marker = ""; managed = 0; next
                }
                print marker; marker = ""; managed = 0
            }
            { print }
        ' /etc/fstab > "$temp_file" || { rm -f -- "$stale_file" "$temp_file"; return 1; }

        rm -f -- "$stale_file"
        sudo install -m 0644 "$temp_file" /etc/fstab || { rm -f -- "$temp_file"; return 1; }
        rm -f -- "$temp_file"

        if ! findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1; then
            sayfail "Reconciled /etc/fstab did not validate; restoring backup."
            sudo cp -a "$backup_file" /etc/fstab
            return 1
        fi

        _storage_save_configuration || true
        sayok "Removed $stale_count stale SolidGroundUX-managed storage entry/entries from /etc/fstab."
        sayinfo "Backup retained at $backup_file."
    }

    # fn$ storage_status
    storage_status() {
        local source="" mountpoint="" filesystem="" options="" device="" label="" uuid="" size="-" available="-" mounted="No" rw="No"
        sgnd_print
        sgnd_print_sectionheader "Storage devices"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL
        sgnd_print
        sgnd_print_sectionheader "SolidGroundUX managed storage"
        while IFS='|' read -r source mountpoint filesystem options; do
            [[ -n "$source" && -n "$mountpoint" ]] || continue
            case "$source" in UUID=*) device="$(blkid -U "${source#UUID=}" 2>/dev/null || true)" ;; *) device="$source" ;; esac
            device="$(readlink -f -- "$device" 2>/dev/null || true)"
            label="$(blkid -s LABEL -o value "$device" 2>/dev/null || true)"
            uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
            mounted="No"; rw="No"; size="-"; available="-"
            if mountpoint -q "$mountpoint"; then
                mounted="Yes"
                findmnt -n -o OPTIONS --mountpoint "$mountpoint" 2>/dev/null | tr ',' '\n' | grep -qx rw && rw="Yes"
                size="$(df -h --output=size "$mountpoint" 2>/dev/null | awk 'NR==2{print $1}')"
                available="$(df -h --output=avail "$mountpoint" 2>/dev/null | awk 'NR==2{print $1}')"
            fi
            sgnd_print_labeledvalue --label "Mount point" --value "$mountpoint" --labelwidth 20
            sgnd_print_labeledvalue --label "Source" --value "$device" --labelwidth 20
            sgnd_print_labeledvalue --label "Filesystem" --value "$filesystem" --labelwidth 20
            sgnd_print_labeledvalue --label "Label" --value "${label:--}" --labelwidth 20
            sgnd_print_labeledvalue --label "UUID" --value "${uuid:--}" --labelwidth 20
            sgnd_print_labeledvalue --label "Mounted" --value "$mounted" --labelwidth 20
            sgnd_print_labeledvalue --label "Read/write" --value "$rw" --labelwidth 20
            sgnd_print_labeledvalue --label "Capacity" --value "$size" --labelwidth 20
            sgnd_print_labeledvalue --label "Available" --value "$available" --labelwidth 20
            sgnd_print
        done < <(_storage_list_managed_fstab_entries)
    }

    # fn$ storage_validate_provisioning
    storage_validate_provisioning() {
        local source="" mountpoint="" filesystem="" options="" device="" label="" result="" failures=0 count=0 stale_count=0
        sgnd_print
        sgnd_print_sectionheader "Validate storage provisioning"
        if findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1; then result="Passed"; else result="Failed"; failures=$((failures+1)); fi
        sgnd_print_labeledvalue --label "fstab syntax" --value "$result" --labelwidth 24
        while IFS='|' read -r source mountpoint filesystem options; do
            [[ -n "$source" && -n "$mountpoint" ]] || continue
            count=$((count+1))
            case "$source" in UUID=*) device="$(blkid -U "${source#UUID=}" 2>/dev/null || true)" ;; *) device="$source" ;; esac
            device="$(readlink -f -- "$device" 2>/dev/null || true)"
            label="$(blkid -s LABEL -o value "$device" 2>/dev/null || true)"
            sgnd_print
            sgnd_print_labeledvalue --label "Storage volume" --value "$mountpoint" --labelwidth 24
            [[ -b "$device" ]] && result="Passed" || { result="Failed"; failures=$((failures+1)); }
            sgnd_print_labeledvalue --label "Source resolves" --value "$result" --labelwidth 24
            [[ "$label" == "SGND_STORAGE" ]] && result="Passed" || { result="Failed"; failures=$((failures+1)); }
            sgnd_print_labeledvalue --label "Filesystem label" --value "$result" --labelwidth 24
            mountpoint -q "$mountpoint" && result="Passed" || { result="Failed"; failures=$((failures+1)); }
            sgnd_print_labeledvalue --label "Mounted" --value "$result" --labelwidth 24
            if mountpoint -q "$mountpoint" && findmnt -n -o OPTIONS --mountpoint "$mountpoint" 2>/dev/null | tr ',' '\n' | grep -qx rw; then result="Passed"; else result="Failed"; failures=$((failures+1)); fi
            sgnd_print_labeledvalue --label "Mounted read/write" --value "$result" --labelwidth 24
            case "${filesystem,,}" in ext4|xfs) result="Passed" ;; *) result="Failed"; failures=$((failures+1)) ;; esac
            sgnd_print_labeledvalue --label "Supported filesystem" --value "$result" --labelwidth 24
            [[ -d "$mountpoint" ]] && result="Passed" || { result="Failed"; failures=$((failures+1)); }
            sgnd_print_labeledvalue --label "Storage root" --value "$result" --labelwidth 24
        done < <(_storage_list_managed_fstab_entries)
        while IFS= read -r result; do [[ -n "$result" ]] && stale_count=$((stale_count+1)); done < <(_storage_list_stale_managed_fstab_entries)
        (( stale_count == 0 )) && result="Passed" || { result="Failed"; failures=$((failures+stale_count)); }
        sgnd_print
        sgnd_print_labeledvalue --label "Managed fstab entries" --value "$result" --labelwidth 24
        (( count > 0 )) || { sayfail "No SolidGroundUX-managed storage volumes are configured."; return 1; }
        sgnd_print
        if (( failures == 0 )); then sayok "Storage provisioning validation passed for $count volume(s)."; return 0; fi
        sayfail "$failures storage provisioning check(s) failed across $count volume(s)."; return 1
    }

# - Action dispatch -----------------------------------------------------------------
    _run_action() {
        local action="${1:?missing action}"

        case "$action" in
            provision|configure) storage_provision ;;
            mount)               storage_mount ;;
            unmount)         storage_unmount ;;
            expand)          storage_expand ;;
            reconcile)       storage_reconcile ;;
            reconcile-persistence) storage_reconcile_persistence ;;
            validate)        storage_validate_provisioning ;;
            status)          storage_status ;;
            directories)     storage_manage_directories ;;
            access-status)    storage_access_status ;;
            set-access)       storage_set_access ;;
            restore-defaults) storage_restore_access_defaults ;;
            *)
                sayfail "Unknown storage management action: $action"
                return 2
                ;;
        esac
    }

# - Main ----------------------------------------------------------------------------
    main() {
        local action=""

        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?

        action="${ACTION:-status}"

        while :; do
            _run_action "$action" || return $?

            # Compound parent workflows own progress and completion UI; child actions must not
            # add their normal auto-continue/do-another dialog in that context.
            if [[ "${SGND_STORAGE_COMPOUND_STEP:-0}" == "1" ]]; then
                break
            fi

            case "$action" in
                status|validate)
                    sgnd_print
                    ask_dlg_autocontinue \
                        --seconds 5 \
                        --pause \
                        --legend "Enter=return to menu; P/Space=pause" || true
                    break
                    ;;
                directories|access-status)
                    break
                    ;;
                *)
                    if _storage_action_again; then
                        continue
                    fi
                    break
                    ;;
            esac
        done

        return 0
    }

    main "$@"
