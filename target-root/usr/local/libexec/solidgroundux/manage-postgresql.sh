#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - Manage PostgreSQL
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627515
#   Shortname   : MANAGE_POSTGRESQL
#   Source      : manage-postgresql.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Install, configure, manage, validate, and inspect PostgreSQL
#
#   Checksum : 3abb07a7182c6e3653857224a974d2b9b0a020b6d0f85d794ded9977767b1538
# Description:
#   Install, configure, manage, validate, and inspect PostgreSQL.
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
    DB_SERVICE="postgresql.service"
    DB_PACKAGE="postgresql"
    DB_PORT_DEFAULT="5432"

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
        sgnd_print_sectionheader "PostgreSQL service management"
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
        sgnd_print_sectionheader "PostgreSQL storage"
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
        _db_run_write env DEBIAN_FRONTEND=noninteractive apt-get install -y "postgresql-client"
    }

    # fn: _db_prepare - Mirror SQL Server's tracked four-step preparation
    _db_prepare() {
        _db_repository || return 51
        _db_install || return 52
        _db_configure || return 53
        _db_tools || return 54
        sayok "PostgreSQL preparation completed."
    }

# - PostgreSQL-specific operations -------------------------------------------------
    # Debian/Ubuntu support multiple clusters; refuse ambiguous selections.
    _db_cluster() {
        local -a clusters=()
        local version="" name="" port="" status="" owner="" directory="" logfile=""
        command -v pg_lsclusters >/dev/null 2>&1 || { sayfail "pg_lsclusters is unavailable."; return 1; }
        while read -r version name port status owner directory logfile; do
            [[ "$version" =~ ^[0-9]+$ ]] && clusters+=("$version $name")
        done < <(pg_lsclusters --no-header 2>/dev/null)
        (( ${#clusters[@]} == 1 )) || { sayfail "Expected exactly one PostgreSQL cluster; found ${#clusters[@]}. Manage multi-cluster hosts manually."; return 1; }
        printf '%s\n' "${clusters[0]}"
    }
    _db_conf() {
        local version="" cluster=""
        read -r version cluster <<< "$(_db_cluster)" || return 1
        pg_conftool "$version" "$cluster" show "$1" 2>/dev/null | head -n 1
    }
    _db_set() {
        local version="" cluster="" setting="$1" value="$2"
        read -r version cluster <<< "$(_db_cluster)" || return 1
        _db_run_write pg_conftool "$version" "$cluster" set "$setting" "$value"
    }
    _db_port() {
        local port=""
        port="$(_db_conf port)" || return 1
        [[ "$port" =~ ^[0-9]+$ ]] || return 1
        printf '%s\n' "$port"
    }
    _db_configure() {
        _db_installed || { sayfail "PostgreSQL is not installed."; return 1; }
        _db_cluster >/dev/null || return 1
        sayok "PostgreSQL cluster detected. Authentication and database roles remain unchanged."
    }
    _db_storage_detail() {
        local version="" cluster="" dir=""
        read -r version cluster <<< "$(_db_cluster)" || return 1
        dir="$(pg_lsclusters --no-header | awk -v v="$version" -v c="$cluster" '$1==v && $2==c {print $6;exit}')"
        sgnd_print_labeledvalue --label "Data directory" --value "$dir" --labelwidth 22
    }
    _db_network() {
        local port="" address="" current="" value="" current_address=""
        _db_installed && _db_cluster >/dev/null || return 1
        port="$(_db_port)" || return 1
        current_address="$(_db_conf listen_addresses)" || return 1
        sgnd_print_labeledvalue --label "TCP port" --value "$port" --labelwidth 22
        sgnd_print_labeledvalue --label "Listen addresses" --value "$current_address" --labelwidth 22
        ask --label "TCP port" --var value --default "$port" --validate _db_check_port --back || return 0
        _db_set port "$value" || return 1
        ask --label "Listen addresses (localhost, IP or *)" --var address --default "$current_address" --back || return 0
        [[ "$address" =~ ^[a-zA-Z0-9.,:*_-]+$ ]] || { sayfail "Invalid listen address format."; return 1; }
        _db_set listen_addresses "$address" || return 1
        saywarning "Remote access additionally requires pg_hba.conf rules; these were not changed."
        _db_restart_active
    }
    _db_memory() {
        local current="" value=""
        _db_installed && _db_cluster >/dev/null || return 1
        current="$(_db_conf shared_buffers)" || return 1
        sgnd_print_labeledvalue --label "Shared buffers" --value "$current" --labelwidth 22
        ask --label "shared_buffers (e.g. 512MB)" --var value --default "$current" --back || return 0
        [[ "$value" =~ ^[1-9][0-9]*(kB|MB|GB)$ ]] || { sayfail "Specify positive kB, MB or GB."; return 1; }
        _db_set shared_buffers "$value" || return 1
        _db_restart_active
    }
    _db_status() {
        local cluster="Unavailable" port="Unavailable" memory="Unavailable"
        if _db_installed; then
            cluster="$(_db_cluster 2>/dev/null || printf 'Ambiguous / unavailable')"
            port="$(_db_port 2>/dev/null || printf 'Unavailable')"
            memory="$(_db_conf shared_buffers 2>/dev/null || printf 'Unavailable')"
        fi
        sgnd_print_sectionheader "PostgreSQL"
        sgnd_print_labeledvalue --label "Package" --value "$(dpkg-query -W -f='${Version}' "$DB_PACKAGE" 2>/dev/null || printf 'Not installed')" --labelwidth 23
        sgnd_print_labeledvalue --label "Cluster" --value "$cluster" --labelwidth 23
        sgnd_print_labeledvalue --label "Service" --value "$(systemctl is-active "$DB_SERVICE" 2>/dev/null || true)" --labelwidth 23
        sgnd_print_labeledvalue --label "Port" --value "$port" --labelwidth 23
        sgnd_print_labeledvalue --label "Shared buffers" --value "$memory" --labelwidth 23
    }
    _db_validate() {
        local failures=0 port=""
        _db_installed || { sayfail "PostgreSQL engine not installed."; return 1; }
        _db_cluster >/dev/null || failures=$((failures+1))
        port="$(_db_port)" || failures=$((failures+1))
        if [[ -n "$port" ]]; then
            ss -ltn | awk '{print $4}' | grep -Eq "(^|:)${port}$" || failures=$((failures+1))
        fi
        command -v psql >/dev/null 2>&1 || failures=$((failures+1))
        if (( failures == 0 )); then sayok "PostgreSQL validation passed."; else sayfail "$failures validation check(s) failed."; fi
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
            *) sayfail "Unknown PostgreSQL action: $action"; return 2 ;;
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
