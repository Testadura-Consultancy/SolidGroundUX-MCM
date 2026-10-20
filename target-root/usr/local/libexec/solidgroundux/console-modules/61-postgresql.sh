# ==================================================================================
# SolidGroundUX Management Console Modules - PostgreSQL
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2629400
#   Shortname   : POSTGRESQL
#   Source      : 61-postgresql.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Install, configure, manage, validate, and inspect PostgreSQL
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
    SGND_POSTGRESQL_MODULE_ID="postgresql"
    SGND_POSTGRESQL_MODULE_NAME="PostgreSQL"
    SGND_MODULE_ID="$SGND_POSTGRESQL_MODULE_ID"
    SGND_MODULE_NAME="$SGND_POSTGRESQL_MODULE_NAME"

# - Management dispatch -------------------------------------------------------------
    _pg_run_manage() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-postgresql.sh" --action "$action"
    }

    # Mirror SQL Server composite-child tracking, including partial failures.
    _pg_record_step() {
        if declare -F sgnd_console_record_action_result >/dev/null 2>&1; then
            sgnd_console_record_action_result "pg-$1" "$2" || true
        fi
    }
    pg_prepare() {
        local rc=0
        local -a steps=(repository install configure tools)
        local index=0
        _pg_run_manage prepare || rc=$?
        if (( rc == 0 )); then
            for index in "${!steps[@]}"; do _pg_record_step "${steps[index]}" 0; done
            return 0
        fi
        if (( rc >= 51 && rc <= 54 )); then
            for (( index=0; index<rc-51; index++ )); do _pg_record_step "${steps[index]}" 0; done
            _pg_record_step "${steps[rc-51]}" 1
        fi
        return "$rc"
    }
    pg_repository() { _pg_run_manage repository; }
    pg_install() { _pg_run_manage install; }
    pg_configure() { _pg_run_manage configure; }
    pg_tools() { _pg_run_manage tools; }
    pg_storage() { _pg_run_manage storage; }
    pg_network() { _pg_run_manage network; }
    pg_memory() { _pg_run_manage memory; }
    pg_service() { _pg_run_manage service; }
    pg_firewall() { _pg_run_manage firewall; }
    pg_validate() { _pg_run_manage validate; }
    pg_status() { _pg_run_manage status; }

# - Module validation contract ------------------------------------------------------
    # 0=passed, 1=failed, 2=warning, 3=skipped/not applicable.
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
    sgnd_menu_register_group "$SGND_POSTGRESQL_MODULE_ID" "$SGND_POSTGRESQL_MODULE_NAME" \
        "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" 0 1 610
    sgnd_menu_register_item "pg-prepare" "$SGND_POSTGRESQL_MODULE_ID" "Prepare PostgreSQL" "pg_prepare" "Install and prepare PostgreSQL" 0 15 1 0
    sgnd_menu_register_item "pg-repository" "$SGND_POSTGRESQL_MODULE_ID" "Repository PostgreSQL" "pg_repository" "Use supported Ubuntu repositories" 0 15 1 1
    sgnd_menu_register_item "pg-install" "$SGND_POSTGRESQL_MODULE_ID" "Install PostgreSQL" "pg_install" "Install PostgreSQL engine" 0 15 1 1
    sgnd_menu_register_item "pg-configure" "$SGND_POSTGRESQL_MODULE_ID" "Configure PostgreSQL" "pg_configure" "Configure initial PostgreSQL installation" 0 15 1 1
    sgnd_menu_register_item "pg-tools" "$SGND_POSTGRESQL_MODULE_ID" "Tools PostgreSQL" "pg_tools" "Install database command-line tools" 0 15 1 1
    sgnd_menu_register_item "pg-storage" "$SGND_POSTGRESQL_MODULE_ID" "Storage PostgreSQL" "pg_storage" "Inspect storage and relocation guidance (no automatic moves)" 0 15 1 0
    sgnd_menu_register_item "pg-network" "$SGND_POSTGRESQL_MODULE_ID" "Network PostgreSQL" "pg_network" "Configure network listening and port" 0 15 1 0
    sgnd_menu_register_item "pg-memory" "$SGND_POSTGRESQL_MODULE_ID" "Memory PostgreSQL" "pg_memory" "Configure engine memory parameters" 0 15 1 0
    sgnd_menu_register_item "pg-service" "$SGND_POSTGRESQL_MODULE_ID" "Service PostgreSQL" "pg_service" "Start, stop, restart or manage boot enablement" 0 15 1 0
    sgnd_menu_register_item "pg-firewall" "$SGND_POSTGRESQL_MODULE_ID" "Firewall PostgreSQL" "pg_firewall" "Allow configured TCP port through UFW" 0 15 1 0
    sgnd_menu_register_item "pg-validate" "$SGND_POSTGRESQL_MODULE_ID" "Validate PostgreSQL" "pg_validate" "Validate installed database server" 0 15 1 0
    sgnd_menu_register_item "pg-status" "$SGND_POSTGRESQL_MODULE_ID" "Status PostgreSQL" "pg_status" "Show current database server status" 0 15 1 0
    sayinfo "PostgreSQL module registered with the console."
