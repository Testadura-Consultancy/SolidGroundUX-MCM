# ==================================================================================
# SolidGroundUX - SQL Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625621
#   Source      : 60-sqlserver.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Install, configure, manage, validate, and inspect Microsoft SQL Server
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
    SGND_SQLSERVER_MODULE_ID="sql-server"
    SGND_SQLSERVER_MODULE_NAME="SQL Server"
    SGND_SQLSERVER_MODULE_VERSION="1.1.6"
    SGND_SQLSERVER_MODULE_DESC="Install, configure, manage, validate, and inspect Microsoft SQL Server"

    SGND_MODULE_ID="$SGND_SQLSERVER_MODULE_ID"
    SGND_MODULE_NAME="$SGND_SQLSERVER_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_SQLSERVER_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_SQLSERVER_MODULE_DESC"

    SGND_SQLSERVER_MAJOR="2025"
    SGND_SQLSERVER_SERVICE="mssql-server.service"
    SGND_SQLSERVER_DEFAULT_STORAGE_ROOT="/srv/storage"

# - Internal helpers ---------------------------------------------------------------
    # fn: _sqlserver_ubuntu_version - Return the supported Ubuntu version
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_ubuntu_version
    _sqlserver_ubuntu_version() {
        local os_id=""
        local version_id=""
        [[ -r /etc/os-release ]] || return 1
        source /etc/os-release
        os_id="${ID:-}"
        version_id="${VERSION_ID:-}"
        [[ "$os_id" == "ubuntu" ]] || return 1
        case "$version_id" in 22.04|24.04) printf '%s\n' "$version_id"; return 0 ;; esac
        return 1
    }

    # fn: _sqlserver_validate_port - Validate a TCP port number
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_validate_port
    _sqlserver_validate_port() {
        [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
    }

    # fn: _sqlserver_engine_installed - Test whether SQL Server is installed
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_engine_installed
    _sqlserver_engine_installed() {
        dpkg-query -W -f='${Status}' mssql-server 2>/dev/null | grep -q '^install ok installed$'
    }

    # fn: _sqlserver_tools_installed - Test whether sqlcmd tools are installed
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_tools_installed
    _sqlserver_tools_installed() {
        [[ -x /opt/mssql-tools18/bin/sqlcmd ]]
    }

    # fn: _sqlserver_conf_get - Read one persisted SQL Server setting
        # . Returns
        #   0 on success; non-zero when the setting cannot be read or is not configured.
        # . Usage
        #   _sqlserver_conf_get
    _sqlserver_conf_get() {
        local key="$1"
        local section=""
        local option=""
        local value=""
        local config_file="/var/opt/mssql/mssql.conf"

        section="${key%%.*}"
        option="${key#*.}"
        [[ -n "$section" && -n "$option" && "$section" != "$option" ]] || return 1

        # /var/opt/mssql/mssql.conf is the authoritative persisted configuration.
        # Read only the protected file with privilege; parse the stream as the
        # current user. Do not rely on a non-portable mssql-conf get subcommand.
        if (( EUID == 0 )); then
            value="$(cat "$config_file" 2>/dev/null | awk -v section="$section" -v option="$option" '
                BEGIN { in_section=0 }
                /^[[:space:]]*\[/ {
                    line=$0
                    gsub(/^[[:space:]]*\[/, "", line)
                    gsub(/\][[:space:]]*$/, "", line)
                    in_section=(line == section)
                    next
                }
                in_section {
                    line=$0
                    sub(/^[[:space:]]*/, "", line)
                    if (line ~ "^" option "[[:space:]]*=") {
                        sub("^" option "[[:space:]]*=[[:space:]]*", "", line)
                        sub(/[[:space:]]*$/, "", line)
                        print line
                        exit
                    }
                }
            ' || true)"
        else
            value="$(sudo cat "$config_file" 2>/dev/null | awk -v section="$section" -v option="$option" '
                BEGIN { in_section=0 }
                /^[[:space:]]*\[/ {
                    line=$0
                    gsub(/^[[:space:]]*\[/, "", line)
                    gsub(/\][[:space:]]*$/, "", line)
                    in_section=(line == section)
                    next
                }
                in_section {
                    line=$0
                    sub(/^[[:space:]]*/, "", line)
                    if (line ~ "^" option "[[:space:]]*=") {
                        sub("^" option "[[:space:]]*=[[:space:]]*", "", line)
                        sub(/[[:space:]]*$/, "", line)
                        print line
                        exit
                    }
                }
            ' || true)"
        fi

        [[ -n "$value" ]] || return 1
        printf '%s
' "$value"
    }

    # fn: _sqlserver_tcp_port - Return the effective SQL Server TCP port
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_tcp_port
    _sqlserver_tcp_port() {
        local port=""
        port="$(_sqlserver_conf_get network.tcpport 2>/dev/null || true)"
        [[ "$port" =~ ^[0-9]+$ ]] || port=1433
        printf '%s\n' "$port"
    }

    # fn: _sqlserver_storage_root - Resolve the configured SolidGroundUX storage root
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_storage_root
    _sqlserver_storage_root() {
        local configured=""
        local storage_cfg="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"
        if [[ -r "$storage_cfg" ]]; then
            configured="$(awk -F= '$1 == "SGND_STORAGE_MOUNTPOINT" {sub(/^[^=]*=/, ""); print; exit}' "$storage_cfg" 2>/dev/null || true)"
        fi
        [[ -n "$configured" ]] || configured="$SGND_SQLSERVER_DEFAULT_STORAGE_ROOT"
        printf '%s\n' "$configured"
    }

    # fn: _sqlserver_select_directory - Select or enter a SQL Server storage directory
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_select_directory
    _sqlserver_select_directory() {
        local label="$1"
        local default_path="$2"
        local output_var="${3:?missing output variable}"
        local storage_root=""
        local selected=""
        local manual=""
        local path=""
        local -a options=()

        storage_root="$(_sqlserver_storage_root)"
        options+=("$default_path")
        if [[ -d "$storage_root" ]]; then
            while IFS= read -r path; do
                [[ -n "$path" && "$path" != "$default_path" ]] && options+=("$path")
            done < <(find "$storage_root" -mindepth 1 -maxdepth 3 -type d 2>/dev/null | sort)
        fi
        options+=("Enter path manually")

        sgnd_print
        sgnd_print_sectionheader "$label"
        ask_selection --label "Selection" --var selected --items "${options[@]}" || return 1
        if [[ "$selected" == "Enter path manually" ]]; then
            ask --label "$label" --var manual --default "$default_path" --back || return 1
            selected="$manual"
        fi
        [[ "$selected" == /* ]] || selected="$storage_root/$selected"
        printf -v "$output_var" '%s' "$selected"
    }

    # fn: _sqlserver_ensure_directory - Create and prepare a SQL Server storage directory
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_ensure_directory
    _sqlserver_ensure_directory() {
        local path="$1"
        local decision="YES"
        if [[ ! -d "$path" ]]; then
            ask_decision --label "Create directory $path" --choices "YES|Y,NO|N" --default "YES" --var decision
            [[ "$decision" == "YES" ]] || return 1
            if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would create $path."; return 0; fi
            sudo mkdir -p "$path" || return 1
        fi
        if (( ${FLAG_DRYRUN:-0} == 0 )); then
            sudo chown mssql:mssql "$path" || return 1
            sudo chmod 0750 "$path" || return 1
        fi
    }

    # fn: _sqlserver_apply_conf - Set one mssql-conf value
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_apply_conf
    _sqlserver_apply_conf() {
        local key="$1"
        local value="$2"
        local quiet="${3:-0}"
        local output=""

        [[ -x /opt/mssql/bin/mssql-conf ]] || { sayfail "mssql-conf is unavailable."; return 1; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would set $key=$value."
            return 0
        fi

        if (( quiet )); then
            if ! output="$(sudo /opt/mssql/bin/mssql-conf set "$key" "$value" 2>&1)"; then
                [[ -n "$output" ]] && printf '%s\n' "$output"
                return 1
            fi
            return 0
        fi

        sudo /opt/mssql/bin/mssql-conf set "$key" "$value" || return 1
    }

    # fn: _sqlserver_restart_if_active - Restart SQL Server when it is currently active
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_restart_if_active
    _sqlserver_restart_if_active() {
        systemctl is-active --quiet "$SGND_SQLSERVER_SERVICE" 2>/dev/null || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would restart $SGND_SQLSERVER_SERVICE."; return 0; fi
        sudo systemctl restart "$SGND_SQLSERVER_SERVICE"
    }

# - Role preparation ---------------------------------------------------------------
    # fn: _sqlserver_step_repository - Configure Microsoft SQL Server repositories
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_step_repository
    _sqlserver_step_repository() {
        local ubuntu_version=""
        local engine_list="/etc/apt/sources.list.d/mssql-server-2025.list"
        local keyring="/usr/share/keyrings/microsoft-prod.gpg"
        local repo_url=""
        local tools_deb=""
        local temp_deb=""

        ubuntu_version="$(_sqlserver_ubuntu_version)" || { sayfail "SQL Server 2025 role supports Ubuntu 22.04 and 24.04 only."; return 1; }
        repo_url="https://packages.microsoft.com/config/ubuntu/${ubuntu_version}/mssql-server-2025.list"
        tools_deb="https://packages.microsoft.com/config/ubuntu/${ubuntu_version}/packages-microsoft-prod.deb"

        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would configure Microsoft SQL Server 2025 repositories for Ubuntu $ubuntu_version."; return 0; fi
        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg || return 1
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee "$keyring" >/dev/null || return 1
        curl -fsSL "$repo_url" | sudo tee "$engine_list" >/dev/null || return 1
        temp_deb="$(mktemp "${TMPDIR:-/tmp}/packages-microsoft-prod.XXXXXX.deb")" || return 1
        curl -fsSL "$tools_deb" -o "$temp_deb" || { rm -f -- "$temp_deb"; return 1; }
        sudo dpkg -i "$temp_deb" >/dev/null || { rm -f -- "$temp_deb"; return 1; }
        rm -f -- "$temp_deb"
        sudo apt-get update || return 1
        sayok "Microsoft SQL Server repositories configured for Ubuntu $ubuntu_version."
    }

    # fn: _sqlserver_step_install_engine - Install Microsoft SQL Server 2025
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_step_install_engine
    _sqlserver_step_install_engine() {
        _sqlserver_ubuntu_version >/dev/null || { sayfail "SQL Server 2025 role supports Ubuntu 22.04 and 24.04 only."; return 1; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would install Microsoft SQL Server 2025."; return 0; fi
        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y mssql-server || return 1
        [[ -x /opt/mssql/bin/mssql-conf ]] || { sayfail "SQL Server package installed but mssql-conf is unavailable."; return 1; }
        sayok "Microsoft SQL Server engine installed."
    }

    # fn: _sqlserver_step_configure - Run the canonical mssql-conf setup workflow
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_step_configure
    _sqlserver_step_configure() {
        [[ -x /opt/mssql/bin/mssql-conf ]] || { sayfail "SQL Server is not installed."; return 1; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would run mssql-conf setup."; return 0; fi
        sudo /opt/mssql/bin/mssql-conf setup || return $?
        systemctl is-active --quiet "$SGND_SQLSERVER_SERVICE" || { sayfail "$SGND_SQLSERVER_SERVICE is not active after setup."; return 1; }
        sayok "Microsoft SQL Server configured and running."
    }

    # fn: _sqlserver_step_install_tools - Install sqlcmd and bcp tools
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_step_install_tools
    _sqlserver_step_install_tools() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would install mssql-tools18 and unixODBC development libraries."; return 0; fi
        sudo apt-get update || return 1
        sudo env ACCEPT_EULA=Y DEBIAN_FRONTEND=noninteractive apt-get install -y mssql-tools18 unixodbc-dev || return 1
        _sqlserver_tools_installed || { sayfail "mssql-tools18 installed but sqlcmd is unavailable."; return 1; }
        sayok "SQL Server command-line tools installed."
    }

    # fn: _sqlserver_prepare - Run the tracked SQL Server preparation workflow
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_prepare
    _sqlserver_prepare() {
        sgnd_console_run_tracked "sql-repo" _sqlserver_step_repository || return $?
        sgnd_console_run_tracked "sql-install" _sqlserver_step_install_engine || return $?
        sgnd_console_run_tracked "sql-configure" _sqlserver_step_configure || return $?
        sgnd_console_run_tracked "sql-tools" _sqlserver_step_install_tools || return $?
        sayok "SQL Server preparation completed successfully."
    }

# - Configuration ------------------------------------------------------------------
    # fn: _sqlserver_configure_storage - Configure SQL data, log, and backup directories
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_configure_storage
    _sqlserver_configure_storage() {
        local storage_root=""
        local data_dir=""
        local log_dir=""
        local backup_dir=""

        _sqlserver_engine_installed || { sayfail "SQL Server is not installed."; return 1; }
        storage_root="$(_sqlserver_storage_root)"
        data_dir="$(_sqlserver_conf_get filelocation.defaultdatadir 2>/dev/null || printf '%s/mssql/data' "$storage_root")"
        log_dir="$(_sqlserver_conf_get filelocation.defaultlogdir 2>/dev/null || printf '%s/mssql/log' "$storage_root")"
        backup_dir="$(_sqlserver_conf_get filelocation.defaultbackupdir 2>/dev/null || printf '%s/mssql/backup' "$storage_root")"

        _sqlserver_select_directory "Select SQL data directory" "$data_dir" data_dir || return 0
        _sqlserver_select_directory "Select SQL log directory" "$log_dir" log_dir || return 0
        _sqlserver_select_directory "Select SQL backup directory" "$backup_dir" backup_dir || return 0

        _sqlserver_ensure_directory "$data_dir" || return 1
        _sqlserver_ensure_directory "$log_dir" || return 1
        _sqlserver_ensure_directory "$backup_dir" || return 1

        _sqlserver_apply_conf filelocation.defaultdatadir "$data_dir" 1 || return 1
        _sqlserver_apply_conf filelocation.defaultlogdir "$log_dir" 1 || return 1
        _sqlserver_apply_conf filelocation.defaultbackupdir "$backup_dir" 1 || return 1

        local restart="YES"
        if systemctl is-active --quiet "$SGND_SQLSERVER_SERVICE" 2>/dev/null; then
            sgnd_print
            sayinfo "SQL Server must be restarted to apply the storage changes."
            ask_decision --label "Restart SQL Server now" --choices "YES|Y,NO|N" --default "YES" --var restart

            if [[ "$restart" == "YES" ]]; then
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "Dry run: Would restart $SGND_SQLSERVER_SERVICE."
                else
                    sudo systemctl restart "$SGND_SQLSERVER_SERVICE" || {
                        sayfail "Could not restart $SGND_SQLSERVER_SERVICE."
                        return 1
                    }
                    systemctl is-active --quiet "$SGND_SQLSERVER_SERVICE" 2>/dev/null || {
                        sayfail "$SGND_SQLSERVER_SERVICE did not become active after restart."
                        return 1
                    }
                    sayok "SQL Server restarted successfully."
                fi
            else
                saywarning "Storage configuration was updated. Restart $SGND_SQLSERVER_SERVICE before using the new paths."
            fi
        else
            saywarning "SQL Server is not running. The storage changes will apply the next time $SGND_SQLSERVER_SERVICE starts."
        fi

        sayok "SQL Server storage locations configured."
    }

    # fn: _sqlserver_configure_network - Configure the SQL Server TCP port
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_configure_network
    _sqlserver_configure_network() {
        local port=""
        port="$(_sqlserver_tcp_port)"
        ask --label "TCP port" --var port --default "$port" --validate _sqlserver_validate_port --back || return 0
        _sqlserver_apply_conf network.tcpport "$port" || return 1
        _sqlserver_restart_if_active || return 1
        sayok "SQL Server TCP port configured: $port"
    }

    # fn: _sqlserver_configure_memory - Configure the SQL Server memory limit
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_configure_memory
    _sqlserver_configure_memory() {
        local memory_mb=""
        memory_mb="$(_sqlserver_conf_get memory.memorylimitmb 2>/dev/null || true)"
        [[ "$memory_mb" =~ ^[0-9]+$ ]] || memory_mb="2048"
        ask --label "Memory limit (MB)" --var memory_mb --default "$memory_mb" --back || return 0
        [[ "$memory_mb" =~ ^[1-9][0-9]*$ ]] || { sayfail "Memory limit must be a positive integer."; return 1; }
        _sqlserver_apply_conf memory.memorylimitmb "$memory_mb" || return 1
        _sqlserver_restart_if_active || return 1
        sayok "SQL Server memory limit configured: ${memory_mb} MB"
    }

    # fn: _sqlserver_manage_service - Manage SQL Server service state and startup behavior
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_manage_service
    _sqlserver_manage_service() {
        local action=""
        ask_selection --label "SQL Server service action" --var action --items "Start" "Stop" "Restart" "Enable at boot" "Disable at boot" || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would perform SQL Server service action: $action."; return 0; fi
        case "$action" in
            Start) sudo systemctl start "$SGND_SQLSERVER_SERVICE" ;;
            Stop) sudo systemctl stop "$SGND_SQLSERVER_SERVICE" ;;
            Restart) sudo systemctl restart "$SGND_SQLSERVER_SERVICE" ;;
            "Enable at boot") sudo systemctl enable "$SGND_SQLSERVER_SERVICE" ;;
            "Disable at boot") sudo systemctl disable "$SGND_SQLSERVER_SERVICE" ;;
        esac
    }

    # fn: _sqlserver_configure_firewall - Allow the configured SQL Server port through UFW
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_configure_firewall
    _sqlserver_configure_firewall() {
        local port=""
        command -v ufw >/dev/null 2>&1 || { saywarning "UFW is not installed."; return 0; }
        port="$(_sqlserver_tcp_port)"
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would allow ${port}/tcp through UFW."; return 0; fi
        sudo ufw allow "${port}/tcp" || return 1
        sayok "SQL Server TCP port $port allowed through UFW."
    }

# - Status / validation ------------------------------------------------------------
    # fn: _sqlserver_status - Show SQL Server status and effective configuration
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_status
    _sqlserver_status() {
        local ubuntu_version="unsupported"
        local package_state="not installed"
        local package_version="-"
        local service_state="unavailable"
        local enabled_state="No"
        local tools_state="not installed"
        local port=1433
        local listener_state="No"
        local memory_mb="default"
        local data_dir="default"
        local log_dir="default"
        local backup_dir="default"

        ubuntu_version="$(_sqlserver_ubuntu_version 2>/dev/null || printf 'unsupported')"
        if _sqlserver_engine_installed; then
            package_state="installed"
            package_version="$(dpkg-query -W -f='${Version}' mssql-server 2>/dev/null || printf '-')"
            service_state="$(systemctl is-active "$SGND_SQLSERVER_SERVICE" 2>/dev/null || true)"
            [[ -n "$service_state" ]] || service_state="inactive"
            systemctl is-enabled --quiet "$SGND_SQLSERVER_SERVICE" 2>/dev/null && enabled_state="Yes"
            memory_mb="$(_sqlserver_conf_get memory.memorylimitmb 2>/dev/null || printf 'default')"
            data_dir="$(_sqlserver_conf_get filelocation.defaultdatadir 2>/dev/null || printf 'default')"
            log_dir="$(_sqlserver_conf_get filelocation.defaultlogdir 2>/dev/null || printf 'default')"
            backup_dir="$(_sqlserver_conf_get filelocation.defaultbackupdir 2>/dev/null || printf 'default')"
        fi

        _sqlserver_tools_installed && tools_state="installed"
        port="$(_sqlserver_tcp_port)"
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$" && listener_state="Yes"

        sgnd_print
        sgnd_print_sectionheader "Microsoft SQL Server"
        sgnd_print_labeledvalue --label "Ubuntu" --value "$ubuntu_version" --labelwidth 22
        sgnd_print_labeledvalue --label "SQL Server" --value "$package_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Package version" --value "$package_version" --labelwidth 22
        sgnd_print_labeledvalue --label "Service" --value "$service_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Enabled at boot" --value "$enabled_state" --labelwidth 22
        sgnd_print_labeledvalue --label "TCP port" --value "$port" --labelwidth 22
        sgnd_print_labeledvalue --label "TCP listener" --value "$listener_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Memory limit MB" --value "$memory_mb" --labelwidth 22
        sgnd_print_labeledvalue --label "Data directory" --value "$data_dir" --labelwidth 22
        sgnd_print_labeledvalue --label "Log directory" --value "$log_dir" --labelwidth 22
        sgnd_print_labeledvalue --label "Backup directory" --value "$backup_dir" --labelwidth 22
        sgnd_print_labeledvalue --label "sqlcmd tools" --value "$tools_state" --labelwidth 22
    }

    # fn: _sqlserver_validate - Validate the SQL Server role
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _sqlserver_validate
    _sqlserver_validate() {
        local failures=0
        local result=""
        local port=1433
        local path=""

        sgnd_print
        sgnd_print_sectionheader "Validate Microsoft SQL Server"

        if _sqlserver_ubuntu_version >/dev/null; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Supported Ubuntu" --value "$result" --labelwidth 24

        if _sqlserver_engine_installed && [[ -x /opt/mssql/bin/sqlservr ]]; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Database engine" --value "$result" --labelwidth 24

        if systemctl is-enabled --quiet "$SGND_SQLSERVER_SERVICE" 2>/dev/null; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Enabled at boot" --value "$result" --labelwidth 24

        if systemctl is-active --quiet "$SGND_SQLSERVER_SERVICE" 2>/dev/null; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Service active" --value "$result" --labelwidth 24

        port="$(_sqlserver_tcp_port)"
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "TCP listener" --value "$result ($port)" --labelwidth 24

        for path in \
            "$(_sqlserver_conf_get filelocation.defaultdatadir 2>/dev/null || true)" \
            "$(_sqlserver_conf_get filelocation.defaultlogdir 2>/dev/null || true)" \
            "$(_sqlserver_conf_get filelocation.defaultbackupdir 2>/dev/null || true)"; do
            [[ -z "$path" ]] && continue
            if [[ -d "$path" ]] && sudo -u mssql test -r "$path" && sudo -u mssql test -w "$path" && sudo -u mssql test -x "$path"; then
                result="Passed ($path)"
            else
                result="Failed ($path)"
                failures=$((failures + 1))
            fi
            sgnd_print_labeledvalue --label "Storage access" --value "$result" --labelwidth 24
        done

        if _sqlserver_tools_installed; then result="Passed"; else result="Warning (optional tools missing)"; fi
        sgnd_print_labeledvalue --label "sqlcmd tools" --value "$result" --labelwidth 24

        sgnd_print
        if (( failures == 0 )); then sayok "SQL Server validation passed."; return 0; fi
        sayfail "$failures SQL Server validation check(s) failed."
        return 1
    }

# - Console registration -----------------------------------------------------------
    # Provides basic Microsoft SQL Server host management: repositories, engine and
    # tools installation, storage, network, memory, service and firewall settings,
    # status, and validation. Database-specific administration remains out of scope.
    #
    # . Menu items
    # ! Prepare SQL Server
    #   > Configure repositories, install and configure SQL Server, and install tools.
    #   > Handler: _sqlserver_prepare
    #
    # ! Configure Microsoft repositories
    #   > Configure SQL Server 2025 and Microsoft package repositories.
    #   > Handler: _sqlserver_step_repository
    #
    # ! Install SQL Server engine
    #   > Install the Microsoft SQL Server 2025 database engine.
    #   > Handler: _sqlserver_step_install_engine
    #
    # ! Configure SQL Server
    #   > Run the interactive mssql-conf setup workflow.
    #   > Handler: _sqlserver_step_configure
    #
    # ! Configure SQL storage
    #   > Configure SQL Server data, log, and backup locations.
    #   > Handler: _sqlserver_configure_storage
    #
    # ! Configure SQL network
    #   > Configure the SQL Server TCP port.
    #   > Handler: _sqlserver_configure_network
    #
    # ! Configure SQL memory
    #   > Configure the SQL Server memory limit.
    #   > Handler: _sqlserver_configure_memory
    #
    # ! Manage SQL service
    #   > Start, stop, restart, enable, or disable SQL Server.
    #   > Handler: _sqlserver_manage_service
    #
    # ! Configure SQL firewall
    #   > Allow the configured SQL Server TCP port through UFW.
    #   > Handler: _sqlserver_configure_firewall
    #
    # ! Install SQL Server tools
    #   > Install sqlcmd, bcp, and unixODBC development libraries.
    #   > Handler: _sqlserver_step_install_tools
    #
    # ! Validate SQL Server
    #   > Validate platform, engine, service, listener, storage, and tools.
    #   > Handler: _sqlserver_validate
    #
    # ! Show SQL Server status
    #   > Show service, network, memory, storage, and sqlcmd status.
    #   > Handler: _sqlserver_status
    sgnd_menu_register_group \
        "$SGND_SQLSERVER_MODULE_ID" \
        "$SGND_SQLSERVER_MODULE_NAME" \
        "$SGND_SQLSERVER_MODULE_DESC" \
        0 1 600

    sgnd_menu_register_item "sql-prepare" "$SGND_SQLSERVER_MODULE_ID" "Prepare SQL Server" "_sqlserver_prepare" "Configure repositories, install and configure SQL Server, and install tools" 0 15 1 0
    sgnd_menu_register_item "sql-repo" "$SGND_SQLSERVER_MODULE_ID" "Configure Microsoft repositories" "_sqlserver_step_repository" "Configure SQL Server 2025 and Microsoft package repositories" 0 15 1 1
    sgnd_menu_register_item "sql-install" "$SGND_SQLSERVER_MODULE_ID" "Install SQL Server engine" "_sqlserver_step_install_engine" "Install the Microsoft SQL Server 2025 database engine" 0 15 1 1
    sgnd_menu_register_item "sql-configure" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL Server" "_sqlserver_step_configure" "Run the interactive mssql-conf setup workflow" 0 15 1 1
    sgnd_menu_register_item "sql-storage" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL storage" "_sqlserver_configure_storage" "Configure SQL Server data, log, and backup locations" 0 15 1 0
    sgnd_menu_register_item "sql-network" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL network" "_sqlserver_configure_network" "Configure the SQL Server TCP port" 0 15 1 0
    sgnd_menu_register_item "sql-memory" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL memory" "_sqlserver_configure_memory" "Configure the SQL Server memory limit" 0 15 1 0
    sgnd_menu_register_item "sql-service" "$SGND_SQLSERVER_MODULE_ID" "Manage SQL service" "_sqlserver_manage_service" "Start, stop, restart, enable, or disable SQL Server" 0 15 1 0
    sgnd_menu_register_item "sql-firewall" "$SGND_SQLSERVER_MODULE_ID" "Configure SQL firewall" "_sqlserver_configure_firewall" "Allow the configured SQL Server TCP port through UFW" 0 15 1 0
    sgnd_menu_register_item "sql-tools" "$SGND_SQLSERVER_MODULE_ID" "Install SQL Server tools" "_sqlserver_step_install_tools" "Install sqlcmd, bcp, and unixODBC development libraries" 0 15 1 1
    sgnd_menu_register_item "sql-validate" "$SGND_SQLSERVER_MODULE_ID" "Validate SQL Server" "_sqlserver_validate" "Validate platform, engine, service, listener, storage, and tools" 0 15 1 0
    sgnd_menu_register_item "sql-status" "$SGND_SQLSERVER_MODULE_ID" "Show SQL Server status" "_sqlserver_status" "Show service, network, memory, storage, and sqlcmd status" 0 15 1 0

    sayinfo "SQL Server module registered with the console."
#   Checksum : 4eff94020b76983c569f671268d1ab64de64f73d97136fa20900c2ff5edbff8c
