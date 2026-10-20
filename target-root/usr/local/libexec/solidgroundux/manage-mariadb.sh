#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - Manage MariaDB
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627515
#   Shortname   : MANAGE_MARIADB
#   Source      : manage-mariadb.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Install, configure, manage, validate, and inspect MariaDB
#
#   Checksum : 3abb07a7182c6e3653857224a974d2b9b0a020b6d0f85d794ded9977767b1538
# Description:
#   Install, configure, manage, validate, and inspect MariaDB.
#
# Attribution:
#   Developers    : Mark Fieten
#   Company       : Testadura Consultancy
#   Client        : -
#   Copyright     : © 2025 - 2026 Testadura Consultancy
#   License       : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
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
        "action|a|enum|ACTION|Management action||prepare,repository,install,configure,storage,network,memory,service,firewall,tools,validate,status"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action status"
        "  $SGND_SCRIPT_NAME --dryrun --action storage"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0


# - Role constants and helpers ------------------------------------------------------
    DB_SERVICE="mariadb.service"
    DB_PACKAGE="mariadb-server"
    DB_PORT_DEFAULT="3306"

    # fn: _db_require_ubuntu - Require supported platform before package writes
    _db_require_ubuntu() {
        local os_id="" os_version=""
        source /etc/os-release
        os_id="${ID:-}"; os_version="${VERSION_ID:-}"
        [[ "$os_id" == ubuntu && ( "$os_version" == 24.04 || "$os_version" == 26.04 ) ]] || {
            sayfail "Only Ubuntu 24.04 and 26.04 are supported."
            return 1
        }
    }

    # fn: _db_installed - Check package state
    _db_installed() {
        dpkg-query -W -f='${Status}' "$DB_PACKAGE" 2>/dev/null | grep -q '^install ok installed$'
    }

    # fn: _db_run_write - Honor SolidGroundUX dryrun before changing host
    _db_run_write() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: $(printf '%q ' "$@")"
            return 0
        fi
        sudo "$@"
    }

    # fn: _db_restart_active - Only restart when currently active
    _db_restart_active() {
        if systemctl is-active --quiet "$DB_SERVICE"; then
            _db_run_write systemctl restart "$DB_SERVICE"
        fi
    }

    # fn: _db_check_port - Validate TCP port argument
    _db_check_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }

    # fn: _db_choose_service_action - Apply an explicitly selected systemd operation
    _db_service() {
        local choice="" operation=""
        sgnd_print_sectionheader "MariaDB service management"
        ask --label "Start, Stop, Restart, Enable or Disable" --var choice --back || return 0
        case "${choice,,}" in
            start|stop|restart|enable|disable) operation="${choice,,}" ;;
            *) saywarning "No service action selected."; return 0 ;;
        esac
        _db_run_write systemctl "$operation" "$DB_SERVICE"
    }

    # fn: _db_firewall - Open the configured TCP port (not the database auth rules)
    _db_firewall() {
        local port=""
        command -v ufw >/dev/null 2>&1 || { saywarning "UFW is not installed."; return 0; }
        port="$(_db_port)" || return 1
        sayinfo "UFW will allow TCP port $port; restrict source networks separately."
        local response="NO"
        ask_decision --label "Allow $port/tcp" --choices "YES|Y,NO|N" --default "NO" --var response || return 0
        [[ "$response" == YES ]] || return 0
        _db_run_write ufw allow "${port}/tcp"
    }

    # fn: _db_storage - No automatic migration of populated database files
    _db_storage() {
        sgnd_print_sectionheader "MariaDB storage"
        _db_storage_detail
        saywarning "Moving an initialized database directory requires an engine-specific, offline migration."
        sayinfo "No storage files or configuration have been changed."
    }

    # fn: _db_repository - Stock Ubuntu repos, no external keys or pinned versions
    _db_repository() {
        _db_require_ubuntu || return $?
        _db_run_write apt-get update
    }

    # fn: _db_install - Install engine using the selected Ubuntu packages
    _db_install() {
        _db_require_ubuntu || return $?
        _db_run_write env DEBIAN_FRONTEND=noninteractive apt-get install -y "$DB_PACKAGE"
    }

    # fn: _db_tools - Install standard engine command-line client
    _db_tools() {
        _db_run_write env DEBIAN_FRONTEND=noninteractive apt-get install -y "mariadb-client"
    }

    # fn: _db_prepare - Mirror SQL Server's tracked four-step preparation
    _db_prepare() {
        _db_repository || return 51
        _db_install || return 52
        _db_configure || return 53
        _db_tools || return 54
        sayok "MariaDB preparation completed."
    }

# - MariaDB-specific operations -----------------------------------------------------
    # SolidGroundUX writes a dedicated override rather than patching distro files.
    DB_OVERRIDE="/etc/mysql/mariadb.conf.d/99-solidgroundux.cnf"
    _db_option() {
        local key="$1" value=""
        if command -v mariadb >/dev/null 2>&1 && systemctl is-active --quiet "$DB_SERVICE"; then
            case "$key" in
                port) value="$(sudo mariadb -NBe 'SELECT @@port' 2>/dev/null || true)" ;;
                bind-address) value="$(sudo mariadb -NBe 'SELECT @@bind_address' 2>/dev/null || true)" ;;
                innodb_buffer_pool_size) value="$(sudo mariadb -NBe 'SELECT @@innodb_buffer_pool_size' 2>/dev/null || true)" ;;
                datadir) value="$(sudo mariadb -NBe 'SELECT @@datadir' 2>/dev/null || true)" ;;
            esac
        fi
        [[ -n "$value" ]] || value="$(my_print_defaults mysqld 2>/dev/null | sed -n "s/^--${key}=//p" | tail -n 1)"
        [[ -n "$value" ]] || case "$key" in port) value=3306;; bind-address) value=127.0.0.1;; *) return 1;; esac
        printf '%s\n' "$value"
    }
    _db_port() { _db_option port; }
    _db_set() {
        local key="$1" value="$2" old="" tmp=""
        # Restrict keys and value syntax before an elevated file write.
        case "$key" in port|bind-address|innodb_buffer_pool_size) ;; *) return 1;; esac
        [[ "$value" =~ ^[a-zA-Z0-9._:]+$ ]] || return 1
        old="$(sudo cat "$DB_OVERRIDE" 2>/dev/null || true)"
        tmp="$(mktemp)" || return 1
        if [[ -z "$old" ]]; then printf '[mariadb]\n' > "$tmp"; else printf '%s\n' "$old" > "$tmp"; fi
        sed -i "/^[[:space:]]*${key}[[:space:]]*=/d" "$tmp"
        printf '%s = %s\n' "$key" "$value" >> "$tmp"
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would write $key=$value to $DB_OVERRIDE"; rm -f "$tmp"; return 0
        fi
        sudo install -o root -g root -m 0644 "$tmp" "$DB_OVERRIDE"
        local rc=$?
        rm -f "$tmp"
        return "$rc"
    }
    _db_configure() {
        _db_installed || { sayfail "MariaDB not installed."; return 1; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would run MariaDB security setup."; return 0
        fi
        sayinfo "Ubuntu packages typically configure Unix socket authentication for root."
        if command -v mariadb-secure-installation >/dev/null 2>&1; then
            sayinfo "Launching MariaDB security setup."
            sudo mariadb-secure-installation
        else
            saywarning "mariadb-secure-installation unavailable; review user security manually."
        fi
    }
    _db_storage_detail() {
        local path=""
        path="$(_db_option datadir 2>/dev/null || printf '/var/lib/mysql')"
        sgnd_print_labeledvalue --label "Data directory" --value "$path" --labelwidth 22
    }
    _db_network() {
        local port="" address="" value=""
        _db_installed || return 1
        port="$(_db_port)" || return 1
        address="$(_db_option bind-address)" || return 1
        sgnd_print_labeledvalue --label "Port" --value "$port" --labelwidth 22
        sgnd_print_labeledvalue --label "Bind address" --value "$address" --labelwidth 22
        ask --label "TCP port" --var value --default "$port" --validate _db_check_port --back || return 0
        _db_set port "$value" || return 1
        ask --label "Bind IPv4 address (e.g. 127.0.0.1 or 0.0.0.0)" --var value --default "$address" --back || return 0
        [[ "$value" =~ ^[0-9.]+$ ]] || { sayfail "Enter an IPv4 address."; return 1; }
        _db_set bind-address "$value" || return 1
        saywarning "Database accounts and host grants are not modified."
        _db_restart_active
    }
    _db_memory() {
        local current="" value=""
        _db_installed || return 1
        current="$(_db_option innodb_buffer_pool_size 2>/dev/null || printf '134217728')"
        sgnd_print_labeledvalue --label "InnoDB buffer pool bytes" --value "$current" --labelwidth 22
        ask --label "InnoDB buffer pool MB" --var value --default "512" --back || return 0
        [[ "$value" =~ ^[1-9][0-9]*$ ]] || { sayfail "Enter a positive integer MB value."; return 1; }
        _db_set innodb_buffer_pool_size "${value}M" || return 1
        _db_restart_active
    }
    _db_status() {
        sgnd_print_sectionheader "MariaDB"
        sgnd_print_labeledvalue --label "Package" --value "$(dpkg-query -W -f='${Version}' "$DB_PACKAGE" 2>/dev/null || printf 'Not installed')" --labelwidth 23
        sgnd_print_labeledvalue --label "Service" --value "$(systemctl is-active "$DB_SERVICE" 2>/dev/null || true)" --labelwidth 23
        sgnd_print_labeledvalue --label "Port" --value "$(_db_port)" --labelwidth 23
        _db_storage_detail
        sgnd_print_labeledvalue --label "InnoDB buffer pool" --value "$(_db_option innodb_buffer_pool_size 2>/dev/null || printf 'Unavailable')" --labelwidth 23
    }
    _db_validate() {
        local failures=0 port=""
        _db_installed || { sayfail "MariaDB engine not installed."; return 1; }
        systemctl is-active --quiet "$DB_SERVICE" || failures=$((failures+1))
        command -v mariadb >/dev/null 2>&1 || failures=$((failures+1))
        port="$(_db_port)" || failures=$((failures+1))
        [[ -n "$port" ]] && ss -ltn | awk '{print $4}' | grep -Eq "(^|:)${port}$" || failures=$((failures+1))
        if (( failures == 0 )); then sayok "MariaDB validation passed."; else sayfail "$failures validation check(s) failed."; fi
        (( failures == 0 ))
    }

# - Action dispatch ----------------------------------------------------------------
    # fn: _run_action - Execute management action and retain its exit status
    _run_action() {
        local action="${1:?missing action}" rc=0
        case "$action" in
            prepare) _db_prepare || rc=$? ;;
            repository) _db_repository || rc=$? ;;
            install) _db_install || rc=$? ;;
            configure) _db_configure || rc=$? ;;
            tools) _db_tools || rc=$? ;;
            storage) _db_storage || rc=$? ;;
            network) _db_network || rc=$? ;;
            memory) _db_memory || rc=$? ;;
            service) _db_service || rc=$? ;;
            firewall) _db_firewall || rc=$? ;;
            validate) _db_validate || rc=$? ;;
            status) _db_status || rc=$? ;;
            *) sayfail "Unknown MariaDB action: $action"; return 2 ;;
        esac
        return "$rc"
    }

# - Main ----------------------------------------------------------------------------
    main() {
        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        _run_action "${ACTION:-status}"
    }
    main "$@"
