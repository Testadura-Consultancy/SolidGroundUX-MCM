# ==================================================================================
# SolidGroundUX Management Console Modules - PostgreSQL
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2630201
#   Shortname   : POSTGRESQL
#   Source      : 61-postgresql.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Install, configure, manage, validate, and inspect PostgreSQL
#   Checksum : 983cd86192c605d1ac0b52797c1536aa5bf650fa3cfbbc4d798411bd2b36d0b2
# Description:
#   Registers host-management actions. Database administration is out of scope.
#   Installation and client connectivity have been validated on test servers;
 #   broader recovery and multi-host scenarios remain separate checks.
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
        #   ```bash
        #   _sgnd_lib_guard
        #   ```
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
    SGND_POSTGRESQL_MODULE_ID="postgresql"
    SGND_POSTGRESQL_MODULE_NAME="PostgreSQL"
    SGND_MODULE_ID="$SGND_POSTGRESQL_MODULE_ID"
    SGND_MODULE_NAME="$SGND_POSTGRESQL_MODULE_NAME"

# - Management dispatch -------------------------------------------------------------
    # fn: _pg_run_manage - Forward a PostgreSQL action to its management executable.
    _pg_run_manage() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-postgresql.sh" --action "$action"
    }

    # Mirror SQL Server composite-child tracking, including partial failures.
    # fn: _pg_record_step - Record a PostgreSQL installer child-step result if the console recorder is available.
    _pg_record_step() {
        if declare -F sgnd_console_record_action_result >/dev/null 2>&1; then
            sgnd_console_record_action_result "pg-$1" "$2" || true
        fi
    }
    # fn: pg_prepare - Prepare the PostgreSQL operation.
        # . Purpose
        #   Run installation and record completed child configuration stages.
        # . Returns
        #   Installer exit status.
        # . Usage
        #   ```bash
        #   pg_prepare
        #   ```
    pg_prepare() {
        local rc=0
        local had_cluster=0
        if command -v pg_lsclusters >/dev/null 2>&1 \
            && pg_lsclusters --no-header 2>/dev/null | grep -qE '^[[:space:]]*[0-9]+'; then
            had_cluster=1
        fi
        _pg_run_manage prepare || rc=$?
        if (( rc == 0 && had_cluster == 0 )); then
            # A fresh successful installer verifies the new cluster, including its
            # configured data directory, network and shared buffers.
            _pg_record_step storage 0
            _pg_record_step network 0
            _pg_record_step memory 0
        fi
        return "$rc"
    }
    # fn: pg_repository - Forward the `repository` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_repository
        #   ```
    pg_repository() { _pg_run_manage repository; }
    # fn: pg_install - Forward the `install` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_install
        #   ```
    pg_install() { _pg_run_manage install; }
    # fn: pg_configure - Forward the `configure` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_configure
        #   ```
    pg_configure() { _pg_run_manage configure; }
    # fn: pg_tools - Forward the `tools` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_tools
        #   ```
    pg_tools() { _pg_run_manage tools; }
    # fn: pg_storage - Forward the `storage` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_storage
        #   ```
    pg_storage() { _pg_run_manage storage; }
    # fn: pg_network - Forward the `network` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_network
        #   ```
    pg_network() { _pg_run_manage network; }
    # fn: pg_memory - Forward the `memory` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_memory
        #   ```
    pg_memory() { _pg_run_manage memory; }
    # fn: pg_access - Forward the `access` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_access
        #   ```
    pg_access() { _pg_run_manage access; }
    # fn: pg_service - Forward the `service` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_service
        #   ```
    pg_service() { _pg_run_manage service; }
    # fn: pg_firewall - Forward the `firewall` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_firewall
        #   ```
    pg_firewall() { _pg_run_manage firewall; }
    # fn: pg_validate - Forward the `validate` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_validate
        #   ```
    pg_validate() { _pg_run_manage validate; }
    # fn: pg_status - Forward the `status` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_status
        #   ```
    pg_status() { _pg_run_manage status; }
    # fn: pg_logs - Forward the `logs` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_logs
        #   ```
    pg_logs() { _pg_run_manage logs; }
    # fn: pg_backup - Forward the `backup` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_backup
        #   ```
    pg_backup() { _pg_run_manage backup; }
    # fn: pg_credentials - Forward the `credentials` action to the PostgreSQL manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   pg_credentials
        #   ```
    pg_credentials() { _pg_run_manage credentials; }

# - Module validation contract ------------------------------------------------------
    # 0=passed, 1=failed, 2=warning, 3=skipped/not applicable.
    # fn: validate_module_postgresql - Validate the PostgreSQL module and record its status for the console.
        #
        # . Returns
        #   A console validation status (0=pass, 1=fail, 2=warning, 3=skipped).
        #
        # . Usage
        #   ```bash
        #   validate_module_postgresql
        #   ```
    validate_module_postgresql() {
        if ! dpkg-query -W -f='${Status}' postgresql 2>/dev/null | grep -q '^install ok installed$'; then
            SGND_MODULE_VALIDATION_MESSAGE="PostgreSQL is not installed on this host."
            return 3
        fi
        if pg_validate; then
            SGND_MODULE_VALIDATION_MESSAGE="PostgreSQL validation passed."
            return 0
        fi
        SGND_MODULE_VALIDATION_MESSAGE="PostgreSQL validation reported failures."
        return 1
    }

# - Console registration ------------------------------------------------------------
    # Three native console groups: same module source, distinct headings.
    sgnd_menu_register_group "pg-installation" "Installation & Configuration" "Install and configure PostgreSQL" 0 1 610
    sgnd_menu_register_group "pg-server" "Server Management" "Operate and inspect PostgreSQL" 0 1 620
    sgnd_menu_register_group "pg-administration" "Administration" "Administrator access and data protection" 0 1 630
    sgnd_menu_register_item "pg-prepare" "pg-installation" "Prepare / Install PostgreSQL" "pg_prepare" "Prerequisites, configuration wizard, installation and verification" 0 0 1 0
    sgnd_menu_register_item "pg-storage" "pg-installation" "Configure Data Directory" "pg_storage" "Inspect PostgreSQL data directory; no implicit cluster migration" 0 15 1 1
    sgnd_menu_register_item "pg-network" "pg-installation" "Configure Network & Authentication" "pg_network" "Configure server listening and network connectivity" 0 15 1 1
    sgnd_menu_register_item "pg-memory" "pg-installation" "Configure Memory" "pg_memory" "Configure PostgreSQL shared buffers" 0 15 1 1
    sgnd_menu_register_item "pg-status" "pg-server" "Show Status & Configuration" "pg_status" "Server state, data storage and DBeaver connection information" 0 15 1 0
    sgnd_menu_register_item "pg-service" "pg-server" "Start / Stop / Restart" "pg_service" "Manage PostgreSQL service" 0 15 1 0
    sgnd_menu_register_item "pg-logs" "pg-server" "View Logs" "pg_logs" "Inspect database service logs" 0 15 1 0
    sgnd_menu_register_item "pg-credentials" "pg-administration" "Manage Administrator Credentials" "pg_credentials" "Set database administrator credentials and remote access" 0 15 1 0
    sgnd_menu_register_item "pg-backup" "pg-administration" "Backup / Restore" "pg_backup" "Database backup and restore guidance" 0 15 1 0
    sayinfo "PostgreSQL module registered with the console."
