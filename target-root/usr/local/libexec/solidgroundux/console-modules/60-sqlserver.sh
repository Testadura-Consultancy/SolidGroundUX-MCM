# ==================================================================================
# SolidGroundUX - SQL Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625801
#   Source      : 60-sqlserver.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Install, configure, manage, validate, and inspect Microsoft SQL Server
#
# Description:
#   Registers Microsoft SQL Server host-management actions with the SolidGround
#   Management Console. Persistent operations are implemented by manage-sqlserver.sh.
#   Database-specific administration remains out of scope.
# ==================================================================================
set -uo pipefail

# - Library guard ------------------------------------------------------------------
    _sgnd_lib_guard() {
        local lib_base="" guard=""
        lib_base="$(basename "${BASH_SOURCE[0]}" .sh)"
        lib_base="${lib_base//-/_}"
        guard="SGND_${lib_base^^}_LOADED"
        [[ "${BASH_SOURCE[0]}" != "$0" ]] || { printf 'This is a library; source it, do not execute it: %s\n' "${BASH_SOURCE[0]}" >&2; exit 2; }
        [[ -n "${!guard-}" ]] && return 0
        printf -v "$guard" '1'
    }
    _sgnd_lib_guard
    unset -f _sgnd_lib_guard

    if declare -F sgnd_module_init_metadata >/dev/null 2>&1 && declare -F sgnd_header_buffer_load >/dev/null 2>&1; then
        sgnd_module_init_metadata "${BASH_SOURCE[0]}"
    fi

# - Module metadata ----------------------------------------------------------------
    SGND_SQLSERVER_MODULE_ID="sql-server"
    SGND_SQLSERVER_MODULE_NAME="SQL Server"
    SGND_SQLSERVER_MODULE_VERSION="1.2.0"
    SGND_SQLSERVER_MODULE_DESC="Install, configure, manage, validate, and inspect Microsoft SQL Server"

    SGND_MODULE_ID="$SGND_SQLSERVER_MODULE_ID"
    SGND_MODULE_NAME="$SGND_SQLSERVER_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_SQLSERVER_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_SQLSERVER_MODULE_DESC"

# - Management dispatch -------------------------------------------------------------
    _sqlserver_run_manage() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-sqlserver.sh" --action "$action"
    }

    sqlserver_prepare()           { _sqlserver_run_manage prepare; }
    sqlserver_repository()        { _sqlserver_run_manage repository; }
    sqlserver_install()           { _sqlserver_run_manage install; }
    sqlserver_configure()         { _sqlserver_run_manage configure; }
    sqlserver_storage()           { _sqlserver_run_manage storage; }
    sqlserver_network()           { _sqlserver_run_manage network; }
    sqlserver_memory()            { _sqlserver_run_manage memory; }
    sqlserver_service()           { _sqlserver_run_manage service; }
    sqlserver_firewall()          { _sqlserver_run_manage firewall; }
    sqlserver_tools()             { _sqlserver_run_manage tools; }
    sqlserver_validate()          { _sqlserver_run_manage validate; }
    sqlserver_status()            { _sqlserver_run_manage status; }

# - Console registration ------------------------------------------------------------
    sgnd_menu_register_group \
        "$SGND_SQLSERVER_MODULE_ID" \
        "$SGND_SQLSERVER_MODULE_NAME" \
        "$SGND_SQLSERVER_MODULE_DESC" \
        0 1 600

    sgnd_menu_register_item "sql-prepare" "$SGND_SQLSERVER_MODULE_ID" "Prepare SQL Server" "sqlserver_prepare" "Configure repositories, install and configure SQL Server, and install tools" 0 15 1 0
    sgnd_menu_register_item "sql-repo" "$SGND_SQLSERVER_MODULE_ID" "Configure Microsoft repositories" "sqlserver_repository" "Configure SQL Server 2025 and Microsoft package repositories" 0 15 1 1
    sgnd_menu_register_item "sql-install" "$SGND_SQLSERVER_MODULE_ID" "Install SQL Server engine" "sqlserver_install" "Install the Microsoft SQL Server 2025 database engine" 0 15 1 1
    sgnd_menu_register_item "sql-configure" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL Server" "sqlserver_configure" "Run the interactive mssql-conf setup workflow" 0 15 1 1
    sgnd_menu_register_item "sql-storage" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL storage" "sqlserver_storage" "Configure SQL Server data, log, and backup locations" 0 15 1 0
    sgnd_menu_register_item "sql-network" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL network" "sqlserver_network" "Configure the SQL Server TCP port" 0 15 1 0
    sgnd_menu_register_item "sql-memory" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL memory" "sqlserver_memory" "Configure the SQL Server memory limit" 0 15 1 0
    sgnd_menu_register_item "sql-service" "$SGND_SQLSERVER_MODULE_ID" "Manage SQL service" "sqlserver_service" "Start, stop, restart, enable, or disable SQL Server" 0 15 1 0
    sgnd_menu_register_item "sql-firewall" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL firewall" "sqlserver_firewall" "Allow the configured SQL Server TCP port through UFW" 0 15 1 0
    sgnd_menu_register_item "sql-tools" "$SGND_SQLSERVER_MODULE_ID" "Install SQL Server tools" "sqlserver_tools" "Install sqlcmd, bcp, and unixODBC development libraries" 0 15 1 1
    sgnd_menu_register_item "sql-validate" "$SGND_SQLSERVER_MODULE_ID" "Validate SQL Server" "sqlserver_validate" "Validate platform, engine, service, listener, storage, and tools" 0 15 1 0
    sgnd_menu_register_item "sql-status" "$SGND_SQLSERVER_MODULE_ID" "Show SQL Server status" "sqlserver_status" "Show service, network, memory, storage, and sqlcmd status" 0 15 1 0

    sayinfo "SQL Server module registered with the console."
