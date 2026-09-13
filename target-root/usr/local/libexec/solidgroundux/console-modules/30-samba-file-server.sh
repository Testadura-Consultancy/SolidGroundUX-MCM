# ==================================================================================
# SolidGroundUX - Samba File Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624123
#   Checksum    : 3ef961899966fb54fede8634f4bee073d401e6e54d28d08482a13df4a7c01c9c
#   Source      : 30-samba-file-server.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Install, prepare, validate, and manage Samba file services
#
# Description:
#   Provides one orchestrated Samba file-server preparation sequence together with
#   the individually runnable steps and share-management actions used by that sequence.
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
    SGND_SAMBA_FILE_MODULE_ID="samba-file-server"
    SGND_SAMBA_FILE_MODULE_NAME="Samba File Server"
    SGND_SAMBA_FILE_MODULE_VERSION="1.0.0"
    SGND_SAMBA_FILE_MODULE_DESC="Install, prepare, validate, and manage Samba file services"

    SGND_MODULE_NAME="$SGND_SAMBA_FILE_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_SAMBA_FILE_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_SAMBA_FILE_MODULE_DESC"

    SGND_STORAGE_DEFAULT_MOUNTPOINT="/srv/storage"
    SGND_STORAGE_CONFIG_FILE="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"
    SGND_SAMBA_STORAGE_ROOT="$SGND_STORAGE_DEFAULT_MOUNTPOINT"
    SGND_SAMBA_SHARE_ROOT="$SGND_SAMBA_STORAGE_ROOT/shares"
    SGND_SAMBA_CONFIG="/etc/samba/smb.conf"

# - Helpers -----------------------------------------------------------------------
    # fn: _smb_refresh_storage_paths
        # . Purpose
        #   Resolve the persisted SolidGroundUX storage root and derived Samba share root.
        #
        # . Behavior
        #   - Reads the storage module configuration when available.
        #   - Falls back to an existing SGND_STORAGE filesystem entry in /etc/fstab.
        #   - Falls back to /srv/storage when storage is not configured yet.
        #
        # . Usage
        #   _smb_refresh_storage_paths
    _smb_refresh_storage_paths() {
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
        fi

        if [[ "$mountpoint" != /* || "$mountpoint" == "/" || "$mountpoint" == *[[:space:]]* ]]; then
            mountpoint=""
        fi

        if [[ -z "$mountpoint" ]]; then
            device="$(blkid -L SGND_STORAGE 2>/dev/null || true)"
            if [[ -n "$device" ]]; then
                uuid="$(blkid -s UUID -o value "$device" 2>/dev/null || true)"
                if [[ -n "$uuid" ]]; then
                    mountpoint="$(awk -v source="UUID=$uuid" '
                        $0 !~ /^[[:space:]]*#/ && NF >= 2 && $1 == source { print $2; exit }
                    ' /etc/fstab 2>/dev/null || true)"
                fi
            fi
        fi

        if [[ "$mountpoint" != /* || "$mountpoint" == "/" || "$mountpoint" == *[[:space:]]* ]]; then
            mountpoint="$SGND_STORAGE_DEFAULT_MOUNTPOINT"
        fi

        SGND_SAMBA_STORAGE_ROOT="$mountpoint"
        SGND_SAMBA_SHARE_ROOT="$mountpoint/shares"
    }

    # fn: _smb_validate_share_name
        # . Purpose
        #   Validate a managed Samba share name.
        #
        # . Returns
        #   0 for a supported share name; 1 otherwise.
        #
        # . Usage
        #   _smb_validate_share_name
    _smb_validate_share_name() {
        [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
    }

    # fn: _smb_share_exists
        # . Purpose
        #   Test whether a named Samba share already exists in the active configuration.
        #
        # . Returns
        #   0 when the share exists; 1 otherwise.
        #
        # . Usage
        #   _smb_share_exists
    _smb_share_exists() {
        local share_name="${1:-}"
        [[ -r "$SGND_SAMBA_CONFIG" ]] || return 1
        grep -Eqi "^[[:space:]]*\\[$share_name\\][[:space:]]*$" "$SGND_SAMBA_CONFIG"
    }

    # fn$ _smb_list_managed_shares_raw - Return SolidGroundUX-managed Samba shares
        # . Output
        #   Writes one managed share name per line.
        #
        # . Returns
        #   0 after listing.
        # . Usage
        #   _smb_list_managed_shares_raw
    _smb_list_managed_shares_raw() {
        _smb_refresh_storage_paths
        local share_name=""
        local share_path=""

        command -v testparm >/dev/null 2>&1 || return 0

        while IFS= read -r share_name; do
            [[ -n "$share_name" ]] || continue

            case "${share_name,,}" in
                global|printers|print\$) continue ;;
            esac

            share_path="$(sudo testparm -s --section-name "$share_name" --parameter-name path 2>/dev/null || true)"
            [[ "$share_path" == "$SGND_SAMBA_SHARE_ROOT/"* ]] || continue

            printf '%s\n' "$share_name"
        done < <(
            sudo testparm -s 2>/dev/null | \
                awk '/^\[[^]]+\]$/ { name=$0; gsub(/^\[|\]$/, "", name); print name }'
        )
    }

    # fn$ _smb_select_managed_share - Select one managed Samba share
        # . Arguments
        #   $1 OUTPUT_VAR - Variable receiving the selected share name.
        #
        # . Returns
        #   0 on selection; 1 when no share is available or the user returns.
        # . Usage
        #   _smb_select_managed_share "<output_var>"
    _smb_select_managed_share() {
        local output_var="${1:?missing output variable}"
        local selected=""
        local -a shares=()

        mapfile -t shares < <(_smb_list_managed_shares_raw)
        (( ${#shares[@]} > 0 )) || {
            saywarning "No managed Samba shares were found."
            return 1
        }

        ask_selection \
            --label "Select Samba share" \
            --var selected \
            --items "${shares[@]}" || return 1

        printf -v "$output_var" '%s' "$selected"
        return 0
    }

    # fn: _smb_require_storage
        # . Purpose
        #   Verify that the managed storage and share-root paths are available.
        #
        # . Returns
        #   0 when required storage exists; 1 otherwise.
        #
        # . Usage
        #   _smb_require_storage
    _smb_require_storage() {
        _smb_refresh_storage_paths
        mountpoint -q "$SGND_SAMBA_STORAGE_ROOT" || {
            sayfail "SolidGroundUX storage is not mounted at $SGND_SAMBA_STORAGE_ROOT."
            return 1
        }

        return 0
    }

    # fn: _smb_reload
        # . Purpose
        #   Validate smb.conf and reload Samba configuration.
        #
        # . Returns
        #   0 when configuration validates and reload succeeds; non-zero otherwise.
        #
        # . Usage
        #   _smb_reload
    _smb_reload() {
        sudo testparm -s >/dev/null 2>&1 || {
            sayfail "The Samba configuration is invalid."
            return 1
        }

        sudo systemctl reload smbd.service 2>/dev/null || sudo systemctl restart smbd.service
    }

# - Preparation steps -------------------------------------------------------------
    # fn: _smb_step_install_packages
        # . Purpose
        #   Install Samba file-server packages and supporting ACL tools.
        #
        # . Returns
        #   0 on success or dry-run; non-zero on package failure.
        #
        # . Usage
        #   _smb_step_install_packages
    _smb_step_install_packages() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would install Samba file-server prerequisites."
            return 0
        fi

        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            acl attr samba samba-common-bin smbclient || return 1

        command -v smbd >/dev/null 2>&1 || return 1
        command -v testparm >/dev/null 2>&1 || return 1

        sayok "Samba file-server prerequisites installed."
    }

    # fn: _smb_step_validate_storage
        # . Purpose
        #   Validate that the configured SolidGroundUX storage root is ready for file sharing.
        #
        # . Returns
        #   0 when storage requirements are met; non-zero otherwise.
        #
        # . Usage
        #   _smb_step_validate_storage
    _smb_step_validate_storage() {
        _smb_require_storage || return 1
        sayok "Storage is mounted and available for Samba file services."
    }

    # fn: _smb_step_prepare_share_root
        # . Purpose
        #   Create and apply canonical ownership and permissions to the managed Samba share root.
        #
        # . Returns
        #   0 on success or dry-run; non-zero otherwise.
        #
        # . Usage
        #   _smb_step_prepare_share_root
    _smb_step_prepare_share_root() {
        _smb_refresh_storage_paths
        _smb_require_storage || return 1

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would create $SGND_SAMBA_SHARE_ROOT."
            return 0
        fi

        sudo install -d -m 0770 "$SGND_SAMBA_SHARE_ROOT" || return 1
        [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] || return 1

        sayok "Samba share root prepared at $SGND_SAMBA_SHARE_ROOT."
    }

    # fn: _smb_step_start_service
        # . Purpose
        #   Enable, start, and validate the Samba file-server service.
        #
        # . Returns
        #   0 when the service is active; non-zero otherwise.
        #
        # . Usage
        #   _smb_step_start_service
    _smb_step_start_service() {
        command -v testparm >/dev/null 2>&1 || {
            sayfail "Samba is not installed."
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would enable and start smbd.service."
            return 0
        fi

        sudo testparm -s >/dev/null 2>&1 || {
            sayfail "Samba configuration validation failed."
            return 1
        }

        sudo systemctl enable --now smbd.service || return 1
        systemctl is-active --quiet smbd.service || {
            sayfail "smbd.service is not active."
            return 1
        }

        sayok "Samba file-server service is active."
    }

    # fn: _smb_prepare_file_server
        # . Purpose
        #   Run the tracked Samba file-server preparation sequence.
        #
        # . Returns
        #   0 when all preparation steps succeed; non-zero on a failed step.
        #
        # . Usage
        #   _smb_prepare_file_server
    _smb_prepare_file_server() {
        sgnd_console_run_tracked "smb-install" _smb_step_install_packages || return $?
        sgnd_console_run_tracked "smb-storage" _smb_step_validate_storage || return $?
        sgnd_console_run_tracked "smb-share-root" _smb_step_prepare_share_root || return $?
        sgnd_console_run_tracked "smb-service" _smb_step_start_service || return $?

        sayok "Samba file-server preparation sequence completed."
    }

# - Share management ---------------------------------------------------------------
    # Detailed share lifecycle and access management is owned by manage-samba-shares.sh.

    # fn: _smb_manage_shares
        # . Purpose
        #   Open the interactive manager for creating, listing, and removing managed Samba shares.
        #
        # . Returns
        #   0 on normal return; non-zero when a selected operation fails.
        #
        # . Usage
        #   _smb_manage_shares
    _smb_manage_shares() {
        local manager_path="${SGND_FRAMEWORK_ROOT%/}/usr/local/libexec/solidgroundux/manage-samba-shares.sh"
        local -a manager_args=()

        [[ -x "$manager_path" ]] || {
            sayfail "Samba share manager is not executable: $manager_path"
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            manager_args+=(--dryrun)
        fi

        "$manager_path" "${manager_args[@]}"
    }

# - Validation / status -----------------------------------------------------------
    # fn: _smb_validate
        # . Purpose
        #   Run active Samba file-server validation checks for packages, service, configuration, storage, and managed shares.
        #
        # . Returns
        #   0 when all checks pass; 1 when one or more checks fail.
        #
        # . Usage
        #   _smb_validate
    _smb_validate() {
        _smb_refresh_storage_paths
        local failures=0
        local result=""
        local share_name=""
        local share_path=""
        local share_count=0

        sgnd_print
        sgnd_print_sectionheader "Validate Samba File Server"

        if command -v smbd >/dev/null 2>&1 && command -v testparm >/dev/null 2>&1; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Samba tools" --value "$result" --labelwidth 24

        if command -v testparm >/dev/null 2>&1 && sudo testparm -s >/dev/null 2>&1; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Configuration" --value "$result" --labelwidth 24

        if systemctl is-active --quiet smbd.service; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "smbd service" --value "$result" --labelwidth 24

        if mountpoint -q "$SGND_SAMBA_STORAGE_ROOT"; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Storage mounted" --value "$result" --labelwidth 24

        if [[ -d "$SGND_SAMBA_SHARE_ROOT" ]]; then
            result="Passed"
        else
            result="Failed"
            failures=$((failures + 1))
        fi
        sgnd_print_labeledvalue --label "Share root" --value "$result" --labelwidth 24

        if command -v testparm >/dev/null 2>&1; then
            while IFS= read -r share_name; do
                [[ -n "$share_name" ]] || continue
                case "${share_name,,}" in
                    printers|print\$) continue ;;
                esac
                share_count=$((share_count + 1))
                share_path="$(sudo testparm -s --section-name "$share_name" --parameter-name path 2>/dev/null || true)"

                if [[ "$share_path" == "$SGND_SAMBA_SHARE_ROOT/"* && -d "$share_path" ]]; then
                    result="Passed"
                else
                    result="Failed"
                    failures=$((failures + 1))
                fi

                sgnd_print_labeledvalue --label "Share: $share_name" --value "$result" --labelwidth 24
            done < <(
                sudo testparm -s 2>/dev/null | \
                    awk '/^\[[^]]+\]$/ { name=$0; gsub(/^\[|\]$/, "", name); if (tolower(name) != "global") print name }'
            )
        fi

        sgnd_print_labeledvalue --label "Configured shares" --value "$share_count" --labelwidth 24

        if (( failures == 0 )); then
            sayok "Samba file-server validation passed."
            return 0
        fi

        sayfail "$failures Samba file-server validation check(s) failed."
        return 1
    }

    # fn: _smb_status
        # . Purpose
        #   Display Samba service, configuration, storage, and managed share-root status.
        #
        # . Returns
        #   0 after displaying available status information.
        #
        # . Usage
        #   _smb_status
    _smb_status() {
        _smb_refresh_storage_paths
        local service_state="not installed"
        local config_state="unavailable"
        local storage_state="not configured"
        local share_root_state="not available"

        if command -v smbd >/dev/null 2>&1; then
            service_state="$(systemctl is-active smbd.service 2>/dev/null || true)"
            [[ -n "$service_state" ]] || service_state="inactive"

            if testparm -s >/dev/null 2>&1; then
                config_state="valid"
            else
                config_state="invalid"
            fi
        fi

        if mountpoint -q "$SGND_SAMBA_STORAGE_ROOT"; then
            storage_state="mounted"
            [[ -d "$SGND_SAMBA_SHARE_ROOT" ]] && share_root_state="available"
        fi

        sgnd_print
        sgnd_print_sectionheader "Samba File Server"
        sgnd_print_labeledvalue --label "Service" --value "$service_state" --labelwidth 20
        sgnd_print_labeledvalue --label "Configuration" --value "$config_state" --labelwidth 20
        sgnd_print_labeledvalue --label "Storage" --value "$storage_state" --labelwidth 20
        sgnd_print_labeledvalue --label "Share root" --value "$share_root_state" --labelwidth 20
    }

# - Console registration ----------------------------------------------------------
    # Provides host-level Samba file-server preparation, validation, status, and
    # managed-share administration. Storage is consumed from the configured
    # SolidGroundUX storage root rather than being independently provisioned here.
    #
    # . Samba File Server
    # ! Prepare Samba file server
    #   > Run the complete Samba file-server preparation sequence.
    #   > Handler: _smb_prepare_file_server
    #
    # ! Install Samba prerequisites
    #   > Install Samba file-server packages and command-line utilities.
    #   > Handler: _smb_step_install_packages
    #
    # ! Validate storage
    #   > Require the configured SolidGroundUX storage mount.
    #   > Handler: _smb_step_validate_storage
    #
    # ! Prepare share root
    #   > Create and validate the configured Samba share root.
    #   > Handler: _smb_step_prepare_share_root
    #
    # ! Start Samba service
    #   > Validate the configuration and start smbd.service.
    #   > Handler: _smb_step_start_service
    #
    # ! Validate Samba file server
    #   > Validate tools, configuration, service, storage, and managed shares.
    #   > Handler: _smb_validate
    #
    # ! Show Samba file-server status
    #   > Show service, configuration, storage, and share-root status.
    #   > Handler: _smb_status
    #
    # . Samba Shares
    # ! Manage shares
    #   > Create, remove, structure, validate, and manage access to Samba shares.
    #   > Handler: _smb_manage_shares
    #   > Script: /usr/local/libexec/solidgroundux/manage-samba-shares.sh
    sgnd_menu_register_group \
        "$SGND_SAMBA_FILE_MODULE_ID" \
        "$SGND_SAMBA_FILE_MODULE_NAME" \
        "$SGND_SAMBA_FILE_MODULE_DESC" \
        0 1 300

    sgnd_menu_register_item "smb-prepare" "$SGND_SAMBA_FILE_MODULE_ID" "Prepare Samba file server" "_smb_prepare_file_server" "Run the complete Samba file-server preparation sequence" 0 15 1 0
    sgnd_menu_register_item "smb-install" "$SGND_SAMBA_FILE_MODULE_ID" "Install Samba prerequisites" "_smb_step_install_packages" "Install Samba file-server packages and command-line utilities" 0 15 1 1
    sgnd_menu_register_item "smb-storage" "$SGND_SAMBA_FILE_MODULE_ID" "Validate storage" "_smb_step_validate_storage" "Require the configured SolidGroundUX storage mount" 0 15 1 1
    sgnd_menu_register_item "smb-share-root" "$SGND_SAMBA_FILE_MODULE_ID" "Prepare share root" "_smb_step_prepare_share_root" "Create and validate the configured Samba share root" 0 20 1 1
    sgnd_menu_register_item "smb-service" "$SGND_SAMBA_FILE_MODULE_ID" "Start Samba service" "_smb_step_start_service" "Validate the configuration and start smbd.service" 0 25 1 1

    sgnd_menu_register_item "smb-validate" "$SGND_SAMBA_FILE_MODULE_ID" "Validate Samba file server" "_smb_validate" "Validate tools, configuration, service, storage, and managed shares" 0 30 1 0
    sgnd_menu_register_item "smb-status" "$SGND_SAMBA_FILE_MODULE_ID" "Show Samba file-server status" "_smb_status" "Show service, configuration, storage, and share-root status" 0 35 1 0

    sgnd_menu_register_group \
        "samba-shares" \
        "Samba Shares" \
        "Create, remove, structure, and secure managed Samba shares" \
        0 1 310

    sgnd_menu_register_item "smb-share-manage" "samba-shares" "Manage shares" "_smb_manage_shares" "Create, remove, structure, validate, and manage access to Samba shares" 0 15 1 0

    sayinfo "Samba File Server module registered with the console."
