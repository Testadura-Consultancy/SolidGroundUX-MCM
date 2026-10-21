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
    maria_prepare() {
        local rc=0
        local -a steps=(repository install configure tools)
        local index=0
        _maria_run_manage prepare || rc=$?
        if (( rc == 0 )); then
            for index in "${!steps[@]}"; do _maria_record_step "${steps[index]}" 0; done
            return 0
        fi
        if (( rc >= 51 && rc <= 54 )); then
            for (( index=0; index<rc-51; index++ )); do _maria_record_step "${steps[index]}" 0; done
            _maria_record_step "${steps[rc-51]}" 1
        fi
        return "$rc"
    }
    maria_repository() { _maria_run_manage repository; }
    maria_install() { _maria_run_manage install; }
    maria_configure() { _maria_run_manage configure; }
    maria_tools() { _maria_run_manage tools; }
    maria_storage() { _maria_run_manage storage; }
    maria_network() { _maria_run_manage network; }
    maria_memory() { _maria_run_manage memory; }
    maria_service() { _maria_run_manage service; }
    maria_firewall() { _maria_run_manage firewall; }
    maria_validate() { _maria_run_manage validate; }
    maria_status() { _maria_run_manage status; }

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
    sgnd_menu_register_group "$SGND_MARIADB_MODULE_ID" "$SGND_MARIADB_MODULE_NAME" \
        "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" 0 1 620
    sgnd_menu_register_item "maria-prepare" "$SGND_MARIADB_MODULE_ID" "Prepare MariaDB" "maria_prepare" "Install and prepare MariaDB" 0 15 1 0
    sgnd_menu_register_item "maria-repository" "$SGND_MARIADB_MODULE_ID" "Repository MariaDB" "maria_repository" "Use supported Ubuntu repositories" 0 15 1 1
    sgnd_menu_register_item "maria-install" "$SGND_MARIADB_MODULE_ID" "Install MariaDB" "maria_install" "Install MariaDB engine" 0 15 1 1
    sgnd_menu_register_item "maria-configure" "$SGND_MARIADB_MODULE_ID" "Configure MariaDB" "maria_configure" "Configure initial MariaDB installation" 0 15 1 1
    sgnd_menu_register_item "maria-tools" "$SGND_MARIADB_MODULE_ID" "Tools MariaDB" "maria_tools" "Install database command-line tools" 0 15 1 1
    sgnd_menu_register_item "maria-storage" "$SGND_MARIADB_MODULE_ID" "Storage MariaDB" "maria_storage" "Inspect storage and relocation guidance (no automatic moves)" 0 15 1 0
    sgnd_menu_register_item "maria-network" "$SGND_MARIADB_MODULE_ID" "Network MariaDB" "maria_network" "Configure network listening and port" 0 15 1 0
    sgnd_menu_register_item "maria-memory" "$SGND_MARIADB_MODULE_ID" "Memory MariaDB" "maria_memory" "Configure engine memory parameters" 0 15 1 0
    sgnd_menu_register_item "maria-service" "$SGND_MARIADB_MODULE_ID" "Service MariaDB" "maria_service" "Start, stop, restart or manage boot enablement" 0 15 1 0
    sgnd_menu_register_item "maria-firewall" "$SGND_MARIADB_MODULE_ID" "Firewall MariaDB" "maria_firewall" "Allow configured TCP port through UFW" 0 15 1 0
    sgnd_menu_register_item "maria-validate" "$SGND_MARIADB_MODULE_ID" "Validate MariaDB" "maria_validate" "Validate installed database server" 0 15 1 0
    sgnd_menu_register_item "maria-status" "$SGND_MARIADB_MODULE_ID" "Status MariaDB" "maria_status" "Show current database server status" 0 15 1 0
    sayinfo "MariaDB module registered with the console."
