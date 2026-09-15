#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX - Manage Storage
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625721
#   Source      : manage-storage.sh
#   Type        : script
#   Group       : SolidGround Console
#   Purpose     : Configure, reconcile, validate, and inspect local storage volumes
#
# Description:
#   Implements persistent local-storage management actions exposed by the
#   15-storage Management Console module.
# =====================================================================================
set -uo pipefail

# - Bootstrap ----------------------------------------------------------------------
    # fn$ _framework_locator - Resolve and load the active SolidGroundUX framework
    _framework_locator() {
        local script_file=""
        local path_without_root=""
        local component=""
        local project_root=""
        local exe_common=""
        local index=0
        local root_index=-1
        local -a path_parts=()

        # A Management Modules executable may live in a separate application tree.
        # Prefer an explicitly supplied framework root when the console provides one.
        if [[ -n "${SGND_FRAMEWORK_ROOT:-}" ]]; then
            if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
                exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            else
                exe_common="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            fi
            if [[ -r "$exe_common" ]]; then
                # shellcheck source=/dev/null
                source "$exe_common"
                return 0
            fi
        fi

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || return 126
        path_without_root="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"
        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in usr|etc|var) root_index=$index ;; esac
        done

        if (( root_index >= 0 )); then
            if (( root_index == 0 )); then
                project_root="/"
            else
                project_root=""
                for (( index=0; index<root_index; index++ )); do
                    project_root+="/${path_parts[$index]}"
                done
            fi
            if [[ "$project_root" == "/" ]]; then
                exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            else
                exe_common="${project_root%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            fi
            if [[ -r "$exe_common" ]]; then
                SGND_FRAMEWORK_ROOT="$project_root"
                # shellcheck source=/dev/null
                source "$exe_common"
                return 0
            fi
        fi

        exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read SolidGroundUX executable common library.\n' >&2
            return 126
        }
        SGND_FRAMEWORK_ROOT="/"
        # shellcheck source=/dev/null
        source "$exe_common"
    }

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Manage Storage"
    : "${SGND_SCRIPT_DESC:=Configure, reconcile, validate, and inspect local storage volumes.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2625721}"

# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||configure,mount,unmount,expand,reconcile,reconcile-persistence,validate,status,access-status,set-owner,set-group,set-permissions,restore-defaults"
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

    # fn: _storage_get_mountpoint
        # . Purpose
        #   Resolve the configured SolidGroundUX storage mount point.
        #
        # . Behavior
        #   - Uses the persisted storage configuration when available.
        #   - Falls back to an existing SGND_STORAGE filesystem entry in /etc/fstab.
        #   - Falls back to /srv/storage when storage has not yet been configured.
        #
        # Outputs (stdout):
        #   Effective storage mount point.
        #
        # . Usage
        #   mountpoint="$(_storage_get_mountpoint)"
    _storage_get_mountpoint() {
        local mountpoint=""
        local device=""
        local uuid=""

        if [[ -r "$SGND_STORAGE_CONFIG_FILE" ]]; then
            mountpoint="$(awk -F= '
                $1 == "SGND_STORAGE_MOUNTPOINT" {
                    print substr($0, index($0, "=") + 1)
                    exit
                }
            ' "$SGND_STORAGE_CONFIG_FILE" 2>/dev/null || true)"

            if _storage_validate_mountpoint "$mountpoint"; then
                printf '%s\n' "$mountpoint"
                return 0
            fi
        fi

        device="$(blkid -L SGND_STORAGE 2>/dev/null || true)"
        if [[ -n "$device" ]]; then
            uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
            if [[ -n "$uuid" ]]; then
                mountpoint="$(awk -v source="UUID=$uuid" '
                    $0 !~ /^[[:space:]]*#/ && NF >= 2 && $1 == source { print $2; exit }
                ' /etc/fstab 2>/dev/null || true)"

                if _storage_validate_mountpoint "$mountpoint"; then
                    printf '%s\n' "$mountpoint"
                    return 0
                fi
            fi
        fi

        printf '%s\n' "$SGND_STORAGE_DEFAULT_MOUNTPOINT"
    }

    # fn: _storage_get_share_root
        # . Purpose
        #   Return the managed Samba share root beneath the configured storage mount point.
        #
        # Outputs (stdout):
        #   Effective share-root path.
        #
        # . Usage
        #   share_root="$(_storage_get_share_root)"
    _storage_get_share_root() {
        printf '%s/shares\n' "$(_storage_get_mountpoint)"
    }

    # fn: _storage_save_mountpoint
        # . Purpose
        #   Persist the configured SolidGroundUX storage mount point.
        #
        # Inputs:
        #   $1 - Validated absolute mount point.
        #
        # . Returns
        #   0 when configuration is written, otherwise non-zero.
        #
        # . Usage
        #   _storage_save_mountpoint "/srv/storage"
    _storage_save_mountpoint() {
        local mountpoint="${1:-}"
        local config_dir=""

        _storage_validate_mountpoint "$mountpoint" || return 1
        config_dir="$(dirname "$SGND_STORAGE_CONFIG_FILE")"

        sudo install -d -m 0755 "$config_dir" || return 1
        printf '%s\n' \
            '# SolidGroundUX managed storage configuration' \
            "SGND_STORAGE_MOUNTPOINT=$mountpoint" | \
            sudo tee "$SGND_STORAGE_CONFIG_FILE" >/dev/null || return 1
        sudo chmod 0644 "$SGND_STORAGE_CONFIG_FILE" || return 1
    }


    # fn: _storage_get_configured_mountpoint - Read only the persisted storage mount point
    _storage_get_configured_mountpoint() {
        local mountpoint=""

        [[ -r "$SGND_STORAGE_CONFIG_FILE" ]] || return 1
        mountpoint="$(awk -F= '
            $1 == "SGND_STORAGE_MOUNTPOINT" {
                print substr($0, index($0, "=") + 1)
                exit
            }
        ' "$SGND_STORAGE_CONFIG_FILE" 2>/dev/null || true)"

        _storage_validate_mountpoint "$mountpoint" || return 1
        printf '%s\n' "$mountpoint"
    }

    # fn: _storage_detect_labeled_volume - Resolve the existing SGND_STORAGE filesystem
    # Outputs globals:
    #   STORAGE_DETECTED_DEVICE, STORAGE_DETECTED_UUID, STORAGE_DETECTED_FILESYSTEM,
    #   STORAGE_DETECTED_MOUNTPOINT, STORAGE_DETECTED_FSTAB_SOURCE
    _storage_detect_labeled_volume() {
        local device=""
        local uuid=""
        local filesystem=""
        local mountpoint=""
        local fstab_source=""

        STORAGE_DETECTED_DEVICE=""
        STORAGE_DETECTED_UUID=""
        STORAGE_DETECTED_FILESYSTEM=""
        STORAGE_DETECTED_MOUNTPOINT=""
        STORAGE_DETECTED_FSTAB_SOURCE=""

        device="$(blkid -L SGND_STORAGE 2>/dev/null || true)"
        [[ -n "$device" ]] || return 1
        device="$(readlink -f -- "$device" 2>/dev/null || printf '%s' "$device")"
        [[ -b "$device" ]] || return 1

        uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
        filesystem="$(blkid -s TYPE -o value "$device" 2>/dev/null || true)"

        mountpoint="$(findmnt -rn -S "$device" -o TARGET 2>/dev/null | head -n 1 || true)"

        if [[ -n "$uuid" ]]; then
            fstab_source="UUID=$uuid"
            if [[ -z "$mountpoint" ]]; then
                mountpoint="$(awk -v source="$fstab_source" '
                    $0 !~ /^[[:space:]]*#/ && NF >= 2 && $1 == source { print $2; exit }
                ' /etc/fstab 2>/dev/null || true)"
            fi
        fi

        if [[ -z "$mountpoint" ]]; then
            mountpoint="$(awk -v dev="$device" '
                $0 !~ /^[[:space:]]*#/ && NF >= 2 && $1 == dev { print $2; exit }
            ' /etc/fstab 2>/dev/null || true)"
        fi

        _storage_validate_mountpoint "$mountpoint" || return 1

        STORAGE_DETECTED_DEVICE="$device"
        STORAGE_DETECTED_UUID="$uuid"
        STORAGE_DETECTED_FILESYSTEM="$filesystem"
        STORAGE_DETECTED_MOUNTPOINT="$mountpoint"
        STORAGE_DETECTED_FSTAB_SOURCE="$fstab_source"
        return 0
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

    # fn: _storage_list_stale_managed_fstab_entries - List stale SolidGroundUX-managed entries
        # . Purpose
        #   Identify SolidGroundUX-managed fstab entries that do not describe the
        #   currently detected SGND_STORAGE volume.
        #
        # . Prerequisite
        #   _storage_detect_labeled_volume must have completed successfully.
        #
        # . Output
        #   One stale managed entry per line as SOURCE|TARGET|FSTYPE|OPTIONS.
    _storage_list_stale_managed_fstab_entries() {
        local expected_source=""
        local source=""
        local target=""
        local filesystem=""
        local options=""

        [[ -n "${STORAGE_DETECTED_MOUNTPOINT:-}" ]] || return 1

        if [[ -n "${STORAGE_DETECTED_UUID:-}" ]]; then
            expected_source="UUID=${STORAGE_DETECTED_UUID}"
        else
            expected_source="${STORAGE_DETECTED_DEVICE:-}"
        fi

        while IFS='|' read -r source target filesystem options; do
            [[ -n "$source" && -n "$target" ]] || continue
            if [[ "$source" != "$expected_source" || "$target" != "$STORAGE_DETECTED_MOUNTPOINT" ]]; then
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

    # fn: _storage_select_access_target
        # . Purpose
        #   Ask which managed storage directory should be changed.
        #
        # Outputs (globals):
        #   Variable named by $1 receives either the storage root or shares root path.
        #
        # Inputs:
        #   $1 - Output variable name.
        #
        # . Returns
        #   0 when a target was selected, otherwise non-zero.
        #
        # . Usage
        #   _storage_select_access_target target
    _storage_select_access_target() {
        local output_var="$1"
        local selection="STORAGE"
        local target=""

        ask_decision \
            --label "Storage access target" \
            --choices "STORAGE|S,SHARES|H" \
            --default "STORAGE" \
            --var selection || return $?

        case "$selection" in
            STORAGE) target="$(_storage_get_mountpoint)" ;;
            SHARES)  target="$(_storage_get_share_root)" ;;
            *)       return 1 ;;
        esac

        printf -v "$output_var" '%s' "$target"
    }

# - Public module actions --------------------------------------------------------
    # fn$ storage_configure
        # . Purpose
        #   Provision an unused local disk as persistent SolidGroundUX storage.
        #
        # . Behavior
        #   - Detects and displays unused whole disks.
        #   - Asks for the target disk, filesystem, and mount point.
        #   - Requires explicit confirmation before destructive changes.
        #   - Creates one GPT partition and formats it as ext4 or XFS.
        #   - Adds the filesystem UUID to /etc/fstab and mounts it.
        #   - Creates a shares directory for file-service consumers.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # Outputs (files):
        #   /etc/fstab
        #   <mount point>/shares
        #
        # . Returns
        #   0 when storage is configured or the action is cancelled.
        #   Non-zero when validation, partitioning, formatting, or mounting fails.
        #
        # . Usage
        #   storage_configure
    storage_configure() {
        local devices=()
        local device=""
        local filesystem="EXT4"
        local mountpoint="$(_storage_get_mountpoint)"
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
        sgnd_print_sectionheader "Configure storage"
        sgnd_print_labeledvalue --label "Device" --value "$device" --labelwidth 20
        sgnd_print_labeledvalue --label "Filesystem" --value "$filesystem" --labelwidth 20
        sgnd_print_labeledvalue --label "Mount point" --value "$mountpoint" --labelwidth 20
        sgnd_print
        saywarning "All existing data on $device will be destroyed."

        ask_decision \
            --label "Configure this disk?" \
            --choices "Yes|Y,No|N" \
            --default "No" \
            --var decision || return $?

        [[ "${decision^^}" == "YES" ]] || {
            sayinfo "Storage configuration cancelled."
            return 0
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would partition $device, format it as ${filesystem,,}, and mount it at $mountpoint."
            sayinfo "DRYRUN: Would create $mountpoint/shares and persist SGND_STORAGE_MOUNTPOINT=$mountpoint."
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

        sudo install -d -m 0770 "$mountpoint/shares" || return 1
        _storage_save_mountpoint "$mountpoint" || {
            sayfail "Storage was mounted, but its mount point could not be persisted."
            return 1
        }

        sayok "Storage configured successfully at $mountpoint."
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
        local mountpoint="$(_storage_get_mountpoint)"

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
        local mountpoint="$(_storage_get_mountpoint)"

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
        local mountpoint="$(_storage_get_mountpoint)"
        local source=""
        local source_spec=""
        local filesystem=""
        local parent_name=""
        local parent_device=""
        local partition_number=""

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

    # fn$ storage_access_status
        # . Purpose
        #   Display ownership and Unix permissions for the managed storage directories.
        #
        # . Behavior
        #   - Reports owner, group, and octal mode for the configured storage root.
        #   - Reports owner, group, and octal mode for the configured shares root.
        #   - Reports missing directories without changing the filesystem.
        #
        # . Returns
        #   0 after displaying the available ownership information.
        #
        # . Usage
        #   storage_access_status
    storage_access_status() {
        local path=""
        local owner="-"
        local group="-"
        local mode="-"

        sgnd_print
        sgnd_print_sectionheader "Storage access"

        for path in "$(_storage_get_mountpoint)" "$(_storage_get_share_root)"; do
            owner="-"
            group="-"
            mode="-"

            if [[ -e "$path" ]]; then
                owner="$(stat -c '%U' "$path" 2>/dev/null || printf '-')"
                group="$(stat -c '%G' "$path" 2>/dev/null || printf '-')"
                mode="$(stat -c '%a' "$path" 2>/dev/null || printf '-')"
            fi

            sgnd_print_labeledvalue --label "Path" --value "$path" --labelwidth 18
            sgnd_print_labeledvalue --label "Owner" --value "$owner" --labelwidth 18
            sgnd_print_labeledvalue --label "Group" --value "$group" --labelwidth 18
            sgnd_print_labeledvalue --label "Permissions" --value "$mode" --labelwidth 18
            sgnd_print
        done

        return 0
    }

    # fn$ storage_set_owner
        # . Purpose
        #   Set the Unix owner of a managed storage directory.
        #
        # . Behavior
        #   - Lets the administrator select the storage root or shares root.
        #   - Validates the requested account through getent.
        #   - Changes only the selected directory, not its descendants.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when ownership is updated, otherwise non-zero.
        #
        # . Usage
        #   storage_set_owner
    storage_set_owner() {
        local target=""
        local current_owner="root"
        local owner=""

        _storage_select_access_target target || return $?
        [[ -d "$target" ]] || { sayfail "Storage directory does not exist: $target"; return 1; }

        current_owner="$(stat -c '%U' "$target" 2>/dev/null || printf 'root')"
        owner="$current_owner"

        ask \
            --label "Storage owner" \
            --var owner \
            --default "$owner" \
            --validate _storage_validate_account || return $?

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would set owner of $target to $owner."
            _storage_dryrun_complete
            return 0
        fi

        sudo chown "$owner" "$target" || return 1
        sayok "Storage owner updated for $target."
    }

    # fn$ storage_set_group
        # . Purpose
        #   Set the Unix group of a managed storage directory.
        #
        # . Behavior
        #   - Lets the administrator select the storage root or shares root.
        #   - Validates the requested group through getent.
        #   - Changes only the selected directory, not its descendants.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when the group is updated, otherwise non-zero.
        #
        # . Usage
        #   storage_set_group
    storage_set_group() {
        local target=""
        local current_group="root"
        local group=""

        _storage_select_access_target target || return $?
        [[ -d "$target" ]] || { sayfail "Storage directory does not exist: $target"; return 1; }

        current_group="$(stat -c '%G' "$target" 2>/dev/null || printf 'root')"
        group="$current_group"

        ask \
            --label "Storage group" \
            --var group \
            --default "$group" \
            --validate _storage_validate_group || return $?

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would set group of $target to $group."
            _storage_dryrun_complete
            return 0
        fi

        sudo chgrp "$group" "$target" || return 1
        sayok "Storage group updated for $target."
    }

    # fn$ storage_set_permissions
        # . Purpose
        #   Set Unix permissions on a managed storage directory.
        #
        # . Behavior
        #   - Lets the administrator select the storage root or shares root.
        #   - Uses the current mode as the editable default.
        #   - Accepts a three- or four-digit octal mode.
        #   - Changes only the selected directory, not its descendants.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when permissions are updated, otherwise non-zero.
        #
        # . Usage
        #   storage_set_permissions
    storage_set_permissions() {
        local target=""
        local mode=""

        _storage_select_access_target target || return $?
        [[ -d "$target" ]] || { sayfail "Storage directory does not exist: $target"; return 1; }

        mode="$(stat -c '%a' "$target" 2>/dev/null || true)"
        ask \
            --label "Storage permissions" \
            --var mode \
            --default "$mode" \
            --validate _storage_validate_mode || return $?

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would set permissions on $target to $mode."
            _storage_dryrun_complete
            return 0
        fi

        sudo chmod "$mode" "$target" || return 1
        sayok "Storage permissions updated for $target."
    }

    # fn$ storage_restore_access_defaults
        # . Purpose
        #   Restore canonical ownership and permissions for the managed storage roots.
        #
        # . Behavior
        #   - Restores the configured storage root to root:root with mode 0755.
        #   - Restores the configured shares root to root:root with mode 0770.
        #   - Requires confirmation before changing either directory.
        #   - Does not alter share directories beneath the configured shares root.
        #   - Honors console dry-run mode.
        #
        # Inputs (globals):
        #   FLAG_DRYRUN
        #
        # . Returns
        #   0 when defaults are restored or the action is cancelled.
        #   Non-zero when a required directory or filesystem operation fails.
        #
        # . Usage
        #   storage_restore_access_defaults
    storage_restore_access_defaults() {
        local decision="No"
        local mountpoint="$(_storage_get_mountpoint)"
        local share_root="$(_storage_get_share_root)"

        [[ -d "$mountpoint" ]] || {
            sayfail "Storage root does not exist: $mountpoint"
            return 1
        }
        [[ -d "$share_root" ]] || {
            sayfail "Shares root does not exist: $share_root"
            return 1
        }

        sgnd_print
        sgnd_print_sectionheader "Restore storage access defaults"
        sgnd_print_labeledvalue --label "Storage root" --value "root:root 0755" --labelwidth 20
        sgnd_print_labeledvalue --label "Shares root" --value "root:root 0770" --labelwidth 20

        ask_decision \
            --label "Restore these defaults?" \
            --choices "Yes|Y,No|N" \
            --default "No" \
            --var decision || return $?

        [[ "${decision^^}" == "YES" ]] || {
            sayinfo "Storage access reset cancelled."
            return 0
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would restore canonical storage ownership and permissions."
            _storage_dryrun_complete
            return 0
        fi

        sudo chown root:root "$mountpoint" || return 1
        sudo chmod 0755 "$mountpoint" || return 1
        sudo chown root:root "$share_root" || return 1
        sudo chmod 0770 "$share_root" || return 1

        sayok "Canonical storage ownership and permissions restored."
    }

    # fn$ storage_reconcile
        # . Purpose
        #   Reconcile SolidGroundUX storage configuration with an existing SGND_STORAGE volume.
        #
        # . Behavior
        #   - Detects the existing filesystem labeled SGND_STORAGE.
        #   - Resolves its current or persistent mount point.
        #   - Compares that mount point with /etc/solidgroundux/storage.cfg.
        #   - Rewrites only the SolidGroundUX storage configuration when they differ.
        #   - Never partitions, formats, mounts, unmounts, or changes /etc/fstab.
        #   - Honors console dry-run mode.
    storage_reconcile() {
        local configured_mountpoint=""
        local decision="Yes"

        _storage_detect_labeled_volume || {
            sayfail "No usable SGND_STORAGE filesystem could be detected."
            return 1
        }

        configured_mountpoint="$(_storage_get_configured_mountpoint 2>/dev/null || true)"

        sgnd_print
        sgnd_print_sectionheader "Reconcile storage configuration"
        sgnd_print_labeledvalue --label "Device" --value "$STORAGE_DETECTED_DEVICE" --labelwidth 24
        sgnd_print_labeledvalue --label "UUID" --value "${STORAGE_DETECTED_UUID:--}" --labelwidth 24
        sgnd_print_labeledvalue --label "Filesystem" --value "${STORAGE_DETECTED_FILESYSTEM:--}" --labelwidth 24
        sgnd_print_labeledvalue --label "Detected mount point" --value "$STORAGE_DETECTED_MOUNTPOINT" --labelwidth 24
        sgnd_print_labeledvalue --label "Configured mount point" --value "${configured_mountpoint:-Not configured}" --labelwidth 24
        sgnd_print

        if [[ "$configured_mountpoint" == "$STORAGE_DETECTED_MOUNTPOINT" ]]; then
            sayok "Storage configuration already matches the detected SGND_STORAGE volume."
            return 0
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would update $SGND_STORAGE_CONFIG_FILE to use '$STORAGE_DETECTED_MOUNTPOINT'."
            _storage_dryrun_complete
            return 0
        fi

        ask_decision \
            --label "Update SolidGroundUX storage configuration?" \
            --choices "Yes|Y,No|N" \
            --default "Yes" \
            --var decision || return $?

        [[ "${decision^^}" == "YES" ]] || {
            sayinfo "Storage reconciliation cancelled."
            return 0
        }

        _storage_save_mountpoint "$STORAGE_DETECTED_MOUNTPOINT" || {
            sayfail "Could not update SolidGroundUX storage configuration."
            return 1
        }

        sayok "Storage configuration reconciled to $STORAGE_DETECTED_MOUNTPOINT."
        return 0
    }


    # fn$ storage_reconcile_persistence
        # . Purpose
        #   Remove stale SolidGroundUX-managed storage entries from /etc/fstab.
        #
        # . Behavior
        #   - Detects the active filesystem labeled SGND_STORAGE.
        #   - Considers only fstab entries explicitly preceded by the canonical
        #     '# SolidGroundUX managed storage' marker.
        #   - Keeps the managed entry that matches the detected SGND_STORAGE UUID and mount point.
        #   - Removes stale managed storage blocks only; unrelated fstab entries are untouched.
        #   - Creates a timestamped backup before changing /etc/fstab.
        #   - Honors console dry-run mode.
    storage_reconcile_persistence() {
        local expected_source=""
        local decision="Yes"
        local backup_file=""
        local temp_file=""
        local source=""
        local target=""
        local filesystem=""
        local options=""
        local stale_count=0

        _storage_detect_labeled_volume || {
            sayfail "No usable SGND_STORAGE filesystem could be detected."
            return 1
        }

        if [[ -n "${STORAGE_DETECTED_UUID:-}" ]]; then
            expected_source="UUID=${STORAGE_DETECTED_UUID}"
        else
            expected_source="$STORAGE_DETECTED_DEVICE"
        fi

        sgnd_print
        sgnd_print_sectionheader "Reconcile storage persistence"
        sgnd_print_labeledvalue --label "Expected source" --value "$expected_source" --labelwidth 24
        sgnd_print_labeledvalue --label "Expected mount point" --value "$STORAGE_DETECTED_MOUNTPOINT" --labelwidth 24
        sgnd_print

        while IFS='|' read -r source target filesystem options; do
            [[ -n "$source" && -n "$target" ]] || continue
            stale_count=$((stale_count + 1))
            saywarning "Stale managed fstab entry: $source -> $target ($filesystem, $options)"
        done < <(_storage_list_stale_managed_fstab_entries)

        if (( stale_count == 0 )); then
            sayok "No stale SolidGroundUX-managed storage entries were found in /etc/fstab."
            return 0
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would remove $stale_count stale SolidGroundUX-managed storage entr$([[ $stale_count -eq 1 ]] && printf 'y' || printf 'ies') from /etc/fstab."
            sayinfo "DRYRUN: Would keep the managed entry for '$expected_source' at '$STORAGE_DETECTED_MOUNTPOINT'."
            _storage_dryrun_complete
            return 0
        fi

        ask_decision \
            --label "Remove stale SolidGroundUX-managed fstab entries?" \
            --choices "Yes|Y,No|N" \
            --default "Yes" \
            --var decision || return $?

        [[ "${decision^^}" == "YES" ]] || {
            sayinfo "Storage persistence reconciliation cancelled."
            return 0
        }

        backup_file="/etc/fstab.pre-storage-reconcile.$(date +%Y%m%d%H%M%S)"
        temp_file="$(mktemp)" || return 1

        sudo cp -a /etc/fstab "$backup_file" || {
            rm -f -- "$temp_file"
            return 1
        }

        awk -v expected_source="$expected_source" -v expected_target="$STORAGE_DETECTED_MOUNTPOINT" '
            function flush_marker() {
                if (marker != "") {
                    print marker
                    marker = ""
                }
            }
            $0 == "# SolidGroundUX managed storage" {
                flush_marker()
                marker = $0
                managed = 1
                next
            }
            managed {
                if ($0 ~ /^[[:space:]]*$/) {
                    # Keep waiting for the managed entry; do not emit the marker yet.
                    next
                }
                if ($0 ~ /^[[:space:]]*#/) {
                    flush_marker()
                    managed = 0
                    print
                    next
                }
                if (NF >= 2) {
                    if ($1 == expected_source && $2 == expected_target) {
                        flush_marker()
                        print
                    }
                    marker = ""
                    managed = 0
                    next
                }
                flush_marker()
                managed = 0
            }
            {
                print
            }
            END {
                flush_marker()
            }
        ' /etc/fstab > "$temp_file" || {
            rm -f -- "$temp_file"
            return 1
        }

        sudo install -m 0644 "$temp_file" /etc/fstab || {
            rm -f -- "$temp_file"
            return 1
        }
        rm -f -- "$temp_file"

        if ! findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1; then
            sayfail "Reconciled /etc/fstab did not validate; restoring backup."
            sudo cp -a "$backup_file" /etc/fstab
            return 1
        fi

        sayok "Removed $stale_count stale SolidGroundUX-managed storage entr$([[ $stale_count -eq 1 ]] && printf 'y' || printf 'ies') from /etc/fstab."
        sayinfo "Backup retained at $backup_file."
        return 0
    }

    # fn$ storage_status
        # . Purpose
        #   Display local block devices and the configured SolidGroundUX storage state.
        #
        # . Behavior
        #   - Displays a concise block-device overview.
        #   - Reports filesystem, source, capacity, availability, and persistence for
        #     the configured storage mount point.
        #
        # Outputs (console):
        #   Local disk and storage-mount status.
        #
        # . Returns
        #   0 after displaying available status information.
        #
        # . Usage
        #   storage_status
    storage_status() {
        local mountpoint="$(_storage_get_mountpoint)"
        local share_root="$mountpoint/shares"
        local source="Not configured"
        local filesystem="-"
        local filesystem_label="-"
        local filesystem_uuid="-"
        local size="-"
        local available="-"
        local mounted="No"
        local persistent="No"
        local root_exists="No"
        local mounted_readwrite="No"
        local share_root_exists="No"
        local mount_matches="No"
        local fstab_valid="Not checked"
        local detected_mountpoint="Not detected"
        local config_reconciled="No"

        if _storage_detect_labeled_volume; then
            detected_mountpoint="$STORAGE_DETECTED_MOUNTPOINT"
            [[ "$mountpoint" == "$detected_mountpoint" ]] && config_reconciled="Yes"
        fi

        [[ -d "$mountpoint" ]] && root_exists="Yes"
        [[ -d "$share_root" ]] && share_root_exists="Yes"

        if mountpoint -q "$mountpoint"; then
            mounted="Yes"
            source="$(findmnt -n -o SOURCE --mountpoint "$mountpoint" 2>/dev/null || true)"
            filesystem="$(findmnt -n -o FSTYPE --mountpoint "$mountpoint" 2>/dev/null || true)"
            size="$(df -h --output=size "$mountpoint" 2>/dev/null | awk 'NR == 2 { print $1 }')"
            available="$(df -h --output=avail "$mountpoint" 2>/dev/null | awk 'NR == 2 { print $1 }')"

            if [[ -n "$source" ]]; then
                filesystem_label="$(blkid -s LABEL -o value "$source" 2>/dev/null || true)"
                filesystem_uuid="$(blkid -s UUID -o value "$source" 2>/dev/null || true)"
                [[ -n "$filesystem_label" ]] || filesystem_label="-"
                [[ -n "$filesystem_uuid" ]] || filesystem_uuid="-"
            fi

            if findmnt -n -o OPTIONS --mountpoint "$mountpoint" 2>/dev/null | tr "," "\n" | grep -qx "rw"; then
                mounted_readwrite="Yes"
            fi

            if [[ "$(findmnt -n -o TARGET --source "$source" 2>/dev/null || true)" == "$mountpoint" ]]; then
                mount_matches="Yes"
            fi
        fi

        if awk -v target="$mountpoint" '
            $0 !~ /^[[:space:]]*#/ && NF >= 2 && $2 == target { found = 1 }
            END { exit(found ? 0 : 1) }
        ' /etc/fstab; then
            persistent="Yes"
        fi

        if findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1; then
            fstab_valid="Yes"
        else
            fstab_valid="No"
        fi

        sgnd_print
        sgnd_print_sectionheader "Storage devices"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL

        sgnd_print
        sgnd_print_sectionheader "SolidGroundUX storage"
        sgnd_print_labeledvalue --label "Configured mount point" --value "$mountpoint" --labelwidth 24
        sgnd_print_labeledvalue --label "Detected SGND_STORAGE" --value "$detected_mountpoint" --labelwidth 24
        sgnd_print_labeledvalue --label "Config reconciled" --value "$config_reconciled" --labelwidth 24
        sgnd_print_labeledvalue --label "Source" --value "$source" --labelwidth 24
        sgnd_print_labeledvalue --label "Filesystem" --value "$filesystem" --labelwidth 24
        sgnd_print_labeledvalue --label "Label" --value "$filesystem_label" --labelwidth 24
        sgnd_print_labeledvalue --label "UUID" --value "$filesystem_uuid" --labelwidth 24
        sgnd_print_labeledvalue --label "Mounted" --value "$mounted" --labelwidth 24
        sgnd_print_labeledvalue --label "Persistent" --value "$persistent" --labelwidth 24
        sgnd_print_labeledvalue --label "fstab valid" --value "$fstab_valid" --labelwidth 24
        sgnd_print_labeledvalue --label "Mount source matches" --value "$mount_matches" --labelwidth 24
        sgnd_print_labeledvalue --label "Storage root exists" --value "$root_exists" --labelwidth 24
        sgnd_print_labeledvalue --label "Mounted read/write" --value "$mounted_readwrite" --labelwidth 24
        sgnd_print_labeledvalue --label "Shares root exists" --value "$share_root_exists" --labelwidth 24
        sgnd_print_labeledvalue --label "Capacity" --value "$size" --labelwidth 24
        sgnd_print_labeledvalue --label "Available" --value "$available" --labelwidth 24
    }


    # fn$ storage_validate_provisioning
        # . Purpose
        #   Actively validate the SolidGroundUX storage provisioning state.
        #
        # . Behavior
        #   - Verifies that /etc/fstab is syntactically valid.
        #   - Verifies that the configured storage mount point has a persistent entry.
        #   - Verifies that the storage filesystem is mounted read/write.
        #   - Resolves the active source and compares it with the configured fstab source.
        #   - Verifies the expected filesystem label and storage directory structure.
        #   - Displays each check as Passed or Failed and returns failure when any
        #     required provisioning check fails.
        #
        # Outputs (console):
        #   Validation results for fstab, mount state, source, filesystem, and directories.
        #
        # . Returns
        #   0 when all storage provisioning checks pass.
        #   1 when one or more checks fail.
        #
        # . Usage
        #   storage_validate_provisioning
    storage_validate_provisioning() {
        local mountpoint="$(_storage_get_mountpoint)"
        local share_root="$mountpoint/shares"
        local fstab_source=""
        local resolved_fstab_source=""
        local active_source=""
        local filesystem=""
        local filesystem_label=""
        local configured_mountpoint=""
        local detected_mountpoint=""
        local result=""
        local stale_managed_count=0
        local stale_entry=""
        local failures=0

        sgnd_print
        sgnd_print_sectionheader "Validate storage provisioning"

        if findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "fstab syntax" --value "$result" --labelwidth 24

        configured_mountpoint="$(_storage_get_configured_mountpoint 2>/dev/null || true)"
        if _storage_detect_labeled_volume; then
            detected_mountpoint="$STORAGE_DETECTED_MOUNTPOINT"
        fi

        if [[ -n "$configured_mountpoint" && -n "$detected_mountpoint" && "$configured_mountpoint" == "$detected_mountpoint" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Config reconciliation" --value "$result" --labelwidth 24
        if [[ "$result" == "Failed" && -n "$detected_mountpoint" ]]; then
            saywarning "Configured mount point '${configured_mountpoint:-Not configured}' differs from detected SGND_STORAGE mount point '$detected_mountpoint'."
        fi

        if [[ -n "$detected_mountpoint" ]]; then
            while IFS= read -r stale_entry; do
                [[ -n "$stale_entry" ]] || continue
                stale_managed_count=$((stale_managed_count + 1))
            done < <(_storage_list_stale_managed_fstab_entries)
        fi

        if (( stale_managed_count == 0 )); then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Managed fstab entries" --value "$result" --labelwidth 24
        if (( stale_managed_count > 0 )); then
            saywarning "$stale_managed_count stale SolidGroundUX-managed fstab entr$([[ $stale_managed_count -eq 1 ]] && printf 'y' || printf 'ies') detected; run Reconcile storage persistence."
        fi

        fstab_source="$(awk -v target="$mountpoint" '
            $0 !~ /^[[:space:]]*#/ && NF >= 3 && $2 == target { print $1; exit }
        ' /etc/fstab)"

        if [[ -n "$fstab_source" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Persistent entry" --value "$result" --labelwidth 24

        if mountpoint -q "$mountpoint"; then
            result="Passed"
            active_source="$(findmnt -n -o SOURCE --mountpoint "$mountpoint" 2>/dev/null || true)"
            filesystem="$(findmnt -n -o FSTYPE --mountpoint "$mountpoint" 2>/dev/null || true)"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Mounted" --value "$result" --labelwidth 24

        if mountpoint -q "$mountpoint" && \
           findmnt -n -o OPTIONS --mountpoint "$mountpoint" 2>/dev/null | tr ',' '\n' | grep -qx 'rw'; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Mounted read/write" --value "$result" --labelwidth 24

        case "$fstab_source" in
            UUID=*)
                resolved_fstab_source="$(blkid -U "${fstab_source#UUID=}" 2>/dev/null || true)"
                ;;
            LABEL=*)
                resolved_fstab_source="$(blkid -L "${fstab_source#LABEL=}" 2>/dev/null || true)"
                ;;
            *)
                resolved_fstab_source="$fstab_source"
                ;;
        esac

        active_source="$(readlink -f "$active_source" 2>/dev/null || true)"
        resolved_fstab_source="$(readlink -f "$resolved_fstab_source" 2>/dev/null || true)"

        if [[ -n "$active_source" && -n "$resolved_fstab_source" && "$active_source" == "$resolved_fstab_source" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Mount source matches" --value "$result" --labelwidth 24

        case "${filesystem,,}" in
            ext4|xfs) result="Passed" ;;
            *)
                result="Failed"
                failures=$((failures + 1))
                ;;
        esac
        sgnd_print_labeledvalue --label "Supported filesystem" --value "$result" --labelwidth 24

        filesystem_label="$(blkid -s LABEL -o value "$active_source" 2>/dev/null || true)"
        if [[ "$filesystem_label" == "SGND_STORAGE" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Filesystem label" --value "$result" --labelwidth 24

        if [[ -d "$mountpoint" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Storage root" --value "$result" --labelwidth 24

        if [[ -d "$share_root" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Shares root" --value "$result" --labelwidth 24

        sgnd_print
        if (( failures == 0 )); then
            sayok "Storage provisioning validation passed."
            return 0
        fi

        sayfail "$failures storage provisioning check(s) failed."
        return 1
    }


# - Action dispatch -----------------------------------------------------------------
    _run_action() {
        local action="${1:?missing action}"

        case "$action" in
            configure)       storage_configure ;;
            mount)           storage_mount ;;
            unmount)         storage_unmount ;;
            expand)          storage_expand ;;
            reconcile)       storage_reconcile ;;
            reconcile-persistence) storage_reconcile_persistence ;;
            validate)        storage_validate_provisioning ;;
            status)          storage_status ;;
            access-status)   storage_access_status ;;
            set-owner)       storage_set_owner ;;
            set-group)       storage_set_group ;;
            set-permissions) storage_set_permissions ;;
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
        _run_action "$action"
    }

    main "$@"
