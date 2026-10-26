# ==================================================================================
# SolidGroundUX Management Console Modules - MariaDB
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2629401
#   Shortname   : MARIADB
#   Source      : 62-mariadb.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Install, configure, manage, validate, and inspect MariaDB
#   Checksum : 2bcc018b04113227ac5833529013a53b5638ea5a1848c2c507ce149b6aa73f49
# Description:
#   Registers host-management actions. Database administration is out of scope.
#   Live installation and integration validation are deferred to a test host.
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
    SGND_MARIADB_MODULE_ID="mariadb"
    SGND_MARIADB_MODULE_NAME="MariaDB"
    SGND_MODULE_ID="$SGND_MARIADB_MODULE_ID"
    SGND_MODULE_NAME="$SGND_MARIADB_MODULE_NAME"

# - Management dispatch -------------------------------------------------------------
    _maria_run_manage() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-mariadb.sh" --action "$action"
    }

    # Mirror SQL Server composite-child tracking, including partial failures.
    _maria_record_step() {
        if declare -F sgnd_console_record_action_result >/dev/null 2>&1; then
            sgnd_console_record_action_result "maria-$1" "$2" || true
        fi
    }
    # maria_prepare
    # Purpose:
    #   Run the installer and report completed child configuration actions.
    # Behavior:
    #   - Only records fresh-install child actions after the helper succeeds and a
    #     previously absent database instance is confirmed running.
    #   - Existing-install inspection/reconfiguration never marks all children.
    # Returns:
    #   Installer exit status (nonzero when post-install verification fails).
    # Usage:
    #   maria_prepare
    maria_prepare() {
        local rc=0
        local had_instance=0
        local actual_datadir=""

        # Package presence alone does not mean database initialization succeeded.
        # Check for a responsive local MariaDB instance before running the wizard.
        if command -v mariadb >/dev/null 2>&1 \
            && systemctl is-active --quiet mariadb \
            && sudo -n mariadb -NBe 'SELECT 1' >/dev/null 2>&1; then
            had_instance=1
        fi

        _maria_run_manage prepare || rc=$?
        (( rc == 0 )) || return "$rc"

        if (( had_instance == 0 )); then
            # Cancellation also returns success from the wizard. In that case,
            # leave the child menu indicators untouched rather than failing.
            if systemctl is-active --quiet mariadb \
                && sudo -n mariadb -NBe 'SELECT 1' >/dev/null 2>&1; then
                actual_datadir="$(sudo -n mariadb -NBe 'SELECT @@datadir' 2>/dev/null)" || actual_datadir=""
                if [[ "$actual_datadir" == /* ]]; then
                    _maria_record_step storage 0
                    _maria_record_step network 0
                    _maria_record_step memory 0
                fi
            fi
        fi
        return 0
    }
    maria_repository() { _maria_run_manage repository; }
    maria_install() { _maria_run_manage install; }
    maria_configure() { _maria_run_manage configure; }
    maria_tools() { _maria_run_manage tools; }
    maria_storage() { _maria_run_manage storage; }
    maria_network() { _maria_run_manage network; }
    maria_memory() { _maria_run_manage memory; }
    maria_access() { _maria_run_manage access; }
    maria_service() { _maria_run_manage service; }
    maria_firewall() { _maria_run_manage firewall; }
    maria_validate() { _maria_run_manage validate; }
    maria_status() { _maria_run_manage status; }
    maria_logs() { _maria_run_manage logs; }
    maria_backup() { _maria_run_manage backup; }

# - Module validation contract ------------------------------------------------------
    # 0=passed, 1=failed, 2=warning, 3=skipped/not applicable.
    validate_module_mariadb() {
        if ! dpkg-query -W -f='${Status}' mariadb-server 2>/dev/null | grep -q '^install ok installed$'; then
            SGND_MODULE_VALIDATION_MESSAGE="MariaDB is not installed on this host."
            return 3
        fi
        if maria_validate; then
            SGND_MODULE_VALIDATION_MESSAGE="MariaDB validation passed."
            return 0
        fi
        SGND_MODULE_VALIDATION_MESSAGE="MariaDB validation reported failures."
        return 1
    }

# - Console registration ------------------------------------------------------------
    # Native groups keep installation, operations and administration distinct.
    sgnd_menu_register_group "maria-installation" "Installation & Configuration" "Install and configure MariaDB" 0 1 640
    sgnd_menu_register_group "maria-server" "Server Management" "Operate and inspect MariaDB" 0 1 650
    sgnd_menu_register_group "maria-administration" "Administration" "Administrator access and data protection" 0 1 660
    sgnd_menu_register_item "maria-prepare" "maria-installation" "Prepare / Install MariaDB" "maria_prepare" "Prerequisites, configuration questions, review and installation" 0 0 1 0
    sgnd_menu_register_item "maria-storage" "maria-installation" "Configure Data Directory" "maria_storage" "Inspect data directory and filesystem; relocation not automatic" 0 15 1 1
    sgnd_menu_register_item "maria-network" "maria-installation" "Configure Network & Authentication" "maria_network" "Configure MariaDB TCP port and listening interface" 0 15 1 1
    sgnd_menu_register_item "maria-memory" "maria-installation" "Configure Memory" "maria_memory" "Configure InnoDB buffer pool" 0 15 1 1
    sgnd_menu_register_item "maria-status" "maria-server" "Show Status & Configuration" "maria_status" "Server state, storage and DBeaver connection information" 0 15 1 0
    sgnd_menu_register_item "maria-service" "maria-server" "Start / Stop / Restart" "maria_service" "Manage MariaDB service" 0 15 1 0
    sgnd_menu_register_item "maria-logs" "maria-server" "View Logs" "maria_logs" "Inspect MariaDB service journal" 0 15 1 0
    sgnd_menu_register_item "maria-access" "maria-administration" "Manage Administrator Credentials" "maria_access" "Manage dedicated remote administrator and workstation access" 0 15 1 0
    sgnd_menu_register_item "maria-backup" "maria-administration" "Backup / Restore" "maria_backup" "MariaDB backup and restore guidance, not an automated restore" 0 15 1 0
    sayinfo "MariaDB module registered with the console."
