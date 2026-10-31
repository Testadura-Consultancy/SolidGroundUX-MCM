#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - Manage MariaDB
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2630201
#   Shortname   : MANAGE_MARIADB
#   Source      : manage-mariadb.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Install, configure, manage, validate, and inspect MariaDB
#
#   Checksum : de9f3fe64205a5cabde58db6983026802346552c309ae8325221b59c0ab63010
# Description:
#   Install, configure, manage, validate, and inspect MariaDB.
#
# Usage:
#   Run the executable from its shell command (or installed wrapper):
#   ```bash
#   manage-mariadb --action status
#   manage-mariadb --dryrun --action storage
#   ```
#
#   Script-specific options:
#   - `--action NAME`, `-a`: Management action (supported actions: `prepare`, `repository`, `install`, `configure`, `storage`, `network`, `memory`, `access`, `service`, `firewall`, `tools`, `validate`, `status`, `logs`, `backup`).
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
        #   ```bash
        #   _framework_locator || return $?
        #   ```
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
        "action|a|enum|ACTION|Management action||prepare,repository,install,configure,storage,network,memory,access,service,firewall,tools,validate,status,logs,backup"
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

    # fn: _db_default_client_cidr - Determine the subnet of the default-route IPv4 interface.
    # Returns: Network/prefix, or empty when no usable routed IPv4 address exists.
    # Usage: _db_default_client_cidr
    _db_default_client_cidr() {
        local interface="" address=""
        interface="$(ip -4 route show default 2>/dev/null | awk '$1 == "default" { for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')"
        [[ -n "$interface" ]] || return 1
        address="$(ip -o -4 addr show dev "$interface" scope global 2>/dev/null | awk '{print $4; exit}')"
        [[ -n "$address" ]] || return 1
        python3 - "$address" <<'CIDR_PY'
import ipaddress
import sys
try:
    print(ipaddress.ip_interface(sys.argv[1]).network)
except ValueError:
    sys.exit(1)
CIDR_PY
    }
    # fn: _db_check_client_cidr - Validate a single IPv4 address or a routed CIDR.
    # Returns: 0 for a valid IPv4 host/network, nonzero for invalid input.
    # Usage: _db_check_client_cidr "192.168.0.0/24"
    _db_check_client_cidr() {
        python3 - "$1" <<'CIDR_PY'
import ipaddress
import sys
try:
    ipaddress.IPv4Network(sys.argv[1], strict=False)
except (ValueError, TypeError):
    sys.exit(1)
CIDR_PY
    }
    # fn: _db_account_host - Convert CIDR to MariaDB's IPv4/netmask host format.
    # Returns: The host specification for CREATE USER; no wildcard expansion.
    # Usage: _db_account_host "192.168.0.0/24"
    _db_account_host() {
        python3 - "$1" <<'CIDR_PY'
import ipaddress
import sys
try:
    network = ipaddress.IPv4Network(sys.argv[1], strict=False)
    print(f"{network.network_address}/{network.netmask}" if network.prefixlen != 32 else str(network.network_address))
except (ValueError, TypeError):
    sys.exit(1)
CIDR_PY
    }
    # fn: _db_transition - Framework countdown before installation work
    _db_transition() {
        local rc=0
        ask_dlg_autocontinue --seconds 5 --message "$1" --cancel --pause || rc=$?
        (( rc != 2 ))
    }
    # fn: _db_confirm - Ask for explicit installation approval
    _db_confirm() {
        local answer="NO"
        ask_decision --label "$1" --choices "Yes|Y,No|N" --default "No" --var answer || return 1
        [[ "$answer" == YES ]]
    }
    # fn: _db_failure_pause - Keep failures visible before the console redraws
    _db_failure_pause() {
        sayfail "$1"
        if [[ -r /dev/tty && -w /dev/tty ]]; then
            local unused=""
            IFS= read -r -p 'Press Enter to return to the menu...' unused </dev/tty || true
        fi
        return 1
    }
    # fn: _db_suggest_pool - Suggest a quarter of physical RAM in megabytes
    _db_suggest_pool() {
        local kb="" mb=128
        kb="$(awk '/^MemTotal:/ {print $2;exit}' /proc/meminfo)"
        [[ "$kb" =~ ^[0-9]+$ ]] && mb=$((kb / 4096 / 128 * 128))
        (( mb >= 128 )) || mb=128
        printf '%sM\n' "$mb"
    }

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
    # fn: _db_service - Manage the service for db in the MariaDB workflow.
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
        ask_decision --label "Allow $port/tcp" --choices "Yes|Y,No|N" --default "No" --var response || return 0
        [[ "$response" == YES ]] || return 0
        _db_run_write ufw allow "${port}/tcp"
    }

    # fn: _db_storage - No automatic migration of populated database files
    _db_storage() {
        sgnd_print_sectionheader "MariaDB storage"
        _db_storage_detail || return 1
        local dir=""
        dir="$(_db_option datadir 2>/dev/null || printf '/var/lib/mysql')"
        if [[ -d "$dir" ]]; then
            sayinfo "Data directory exists: $dir"
            sgnd_print_labeledvalue --label "Filesystem" --value "$(findmnt -T "$dir" -n -o TARGET,FSTYPE 2>/dev/null || printf 'Unknown')" --labelwidth 22
            sgnd_print_labeledvalue --label "Owner" --value "$(stat -c '%U:%G' "$dir" 2>/dev/null || printf 'Unknown')" --labelwidth 22
        else
            saywarning "Configured data directory does not exist: $dir"
        fi
        saywarning "Moving an initialized database directory requires an engine-specific, offline migration."
        sayinfo "No storage files or configuration have been changed."
    }

    # fn: _db_storage_check - Validate selected directory before installing packages
    # Purpose: Reject unsafe filesystem roots, unmounted fstab targets and existing data.
    # Returns: 0 if directory is safe for fresh initialization; 1 otherwise.
    # Usage: _db_storage_check "/srv/storage/data/mysql"
    _db_storage_check() {
        local path="$1" parent="" mount="" existing=""
        [[ "$path" == /* && "$path" != / ]] || { sayfail "Select an absolute data directory below a filesystem root."; return 1; }
        [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || { sayfail "Invalid newline in data directory."; return 1; }
        path="$(realpath -m -- "$path")" || return 1
        case "$path" in
            /|/etc|/usr|/bin|/sbin|/boot|/proc|/sys|/dev|/run|/root|/home|/var|/var/lib|/srv|/mnt|/media)
                sayfail "Cannot initialize a MariaDB cluster in a system directory or mount root: $path"
                return 1 ;;
        esac
        if [[ "$path" != /var/lib/mysql ]] && findmnt -M "$path" -n >/dev/null 2>&1; then
            sayfail "The data directory is itself a filesystem mount root: $path. Select a subdirectory instead."
            return 1
        fi
        # Detect unmounted fstab mounts at the directory or any of its ancestors.
        parent="$path"
        while [[ "$parent" != / ]]; do
            if findmnt --fstab --mountpoint "$parent" -n >/dev/null 2>&1 && ! findmnt -M "$parent" -n >/dev/null 2>&1; then
                sayfail "Expected filesystem is not mounted: $parent"
                return 1
            fi
            parent="$(dirname -- "$parent")"
        done
        if [[ -L "$path" ]]; then
            sayfail "A symbolic-link data directory is not supported: $path"
            return 1
        fi
        if [[ -e "$path" && ! -d "$path" ]]; then
            sayfail "Data directory path exists but is not a directory: $path"
            return 1
        fi
        if [[ -d "$path" ]]; then
            mount="$(findmnt -T "$path" -n -o TARGET,SOURCE,FSTYPE 2>/dev/null || true)"
            sgnd_print_labeledvalue --label "Filesystem" --value "${mount:-Unknown}" --labelwidth 23
            if [[ -n "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
                if [[ "$path" == /var/lib/mysql ]] && [[ -d "$path/mysql" ]]; then
                    sayfail "Default MariaDB directory already contains a database. Existing installations must not be reinitialized."
                else
                    sayfail "Data directory is not empty: $path. Choose an empty directory; existing data will not be deleted."
                fi
                return 1
            fi
        else
            parent="$(dirname -- "$path")"
            while [[ ! -d "$parent" && "$parent" != / ]]; do parent="$(dirname -- "$parent")"; done
            mount="$(findmnt -T "$parent" -n -o TARGET,SOURCE,FSTYPE 2>/dev/null || true)"
            sgnd_print_labeledvalue --label "Filesystem" --value "${mount:-Unknown}" --labelwidth 23
        fi
        return 0
    }

    # fn: _db_package_datadir - Identify MariaDB’s active data directory or configured package default.
        # . Purpose
        #   Discover the initialized package directory rather than assuming its path.
        # . Returns
        #   0 and one absolute path, or 1 when no trustworthy location is known.
        # . Usage
        #   ```bash
        #   _db_package_datadir
        #   ```
    _db_package_datadir() {
        local found="" option="" candidate=""
        if systemctl is-active --quiet "$DB_SERVICE"; then
            found="$(sudo mariadb --batch --skip-column-names -e 'SELECT @@datadir' 2>/dev/null)" || {
                sayfail "MariaDB is running, but its actual data directory cannot be queried."
                return 1
            }
        else
            # Read packaged configuration when the service is stopped.
            if command -v my_print_defaults >/dev/null 2>&1; then
                while IFS= read -r option; do
                    case "$option" in --datadir=*) found="${option#--datadir=}" ;; esac
                done < <(my_print_defaults mysqld server mariadb mariadbd 2>/dev/null)
            fi
            if [[ -z "$found" ]]; then
                for candidate in /var/lib/mariadb /var/lib/mysql; do
                    if [[ -d "$candidate/mysql" ]]; then
                        [[ -z "$found" ]] || { sayfail "Multiple initialized MariaDB directories found; unable to select one safely."; return 1; }
                        found="$candidate"
                    fi
                done
            fi
        fi
        [[ "$found" == /* ]] || { sayfail "Could not determine MariaDB's package data directory."; return 1; }
        found="$(realpath -m -- "$found")" || return 1
        [[ -d "$found/mysql" ]] || {
            sayfail "MariaDB reports $found but no system tables were found there."
            return 1
        }
        printf '%s\n' "$found"
    }

    # fn: _db_ensure_initialized - Check whether MariaDB data storage has been initialized and initialize it when appropriate.
        # . Purpose
        #   Initialize only an empty and stopped package data directory.
        # . Returns
        #   0 if initialized, nonzero if state is ambiguous or unsafe.
        # . Usage
        #   ```bash
        #   _db_ensure_initialized
        #   ```
    _db_ensure_initialized() {
        local data="" candidate="" count=0
        if systemctl is-active --quiet "$DB_SERVICE"; then
            _db_package_datadir >/dev/null || return 1
            return 0
        fi
        for candidate in /var/lib/mariadb /var/lib/mysql; do
            if [[ -d "$candidate/mysql" ]]; then
                ((count+=1))
                data="$candidate"
            fi
        done
        if (( count == 1 )); then return 0; fi
        if (( count > 1 )); then
            sayfail "Multiple initialized MariaDB directories exist; initialization is unsafe."
            return 1
        fi
        # If the package has not initialized anything, discover its configured default.
        data="$(my_print_defaults mysqld server mariadb mariadbd 2>/dev/null | sed -n 's/^--datadir=//p' | tail -n 1)"
        [[ -n "$data" ]] || data="/var/lib/mariadb"
        [[ "$data" == /* ]] || { sayfail "MariaDB package data directory is not absolute."; return 1; }
        data="$(realpath -m -- "$data")" || return 1
        if [[ -d "$data" ]] && [[ -n "$(find "$data" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
            sayfail "Unexpected files in $data; refusing to initialize over existing data."
            return 1
        fi
        command -v mariadb-install-db >/dev/null 2>&1 || {
            sayfail "MariaDB initialization utility mariadb-install-db is unavailable."
            return 1
        }
        saystart "Initializing missing MariaDB system tables"
        _db_run_write install -d -o mysql -g mysql -m 0750 "$data" || return 1
        _db_run_write mariadb-install-db --user=mysql --datadir="$data" --auth-root-authentication-method=socket || {
            sayfail "MariaDB system table initialization failed."
            return 1
        }
        [[ -d "$data/mysql" ]] || { sayfail "MariaDB initialization did not create system tables at $data."; return 1; }
        sayend "MariaDB system tables initialized"
    }

    # fn: _db_apparmor_profile - Find an installed AppArmor profile for the MariaDB daemon.
        # . Purpose
        #   Discover the distro-installed MariaDB AppArmor profile.
        # . Returns
        #   0 with the path, or 1 if none exists.
        # . Usage
        #   ```bash
        #   _db_apparmor_profile
        #   ```
    _db_apparmor_profile() {
        local candidate=""
        for candidate in /etc/apparmor.d/mariadbd /etc/apparmor.d/usr.sbin.mariadbd /etc/apparmor.d/usr.sbin.mysqld; do
            if [[ -f "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
        done
        return 1
    }

    # fn: _db_apparmor_prepare - Prepare db apparmor in the MariaDB workflow.
        # . Purpose
        #   Allow MariaDB to access a custom datadir in its active profile.
        # . Returns
        #   Nonzero if an installed profile cannot be safely configured.
        # . Usage
        #   ```bash
        #   _db_apparmor_prepare "/path/to/data" "/path/to/profile"
        #   ```
    _db_apparmor_prepare() {
        local target="$1" profile="$2" local_file="" rule="" alias_entry="" old="$3"
        [[ -f "$profile" ]] || return 1
        command -v apparmor_parser >/dev/null 2>&1 || { sayfail "AppArmor parser is not installed."; return 1; }
        case "$profile" in
            /etc/apparmor.d/mariadbd)
                local_file=/etc/apparmor.d/local/mariadbd
                grep -Eq 'local/mariadbd' "$profile" || { sayfail "MariaDB AppArmor profile has no local override include."; return 1; }
                ;;
            /etc/apparmor.d/usr.sbin.mariadbd)
                local_file=/etc/apparmor.d/local/usr.sbin.mariadbd
                grep -Eq 'local/usr.sbin.mariadbd' "$profile" || { sayfail "MariaDB AppArmor profile has no local override include."; return 1; }
                ;;
            /etc/apparmor.d/usr.sbin.mysqld)
                local_file=/etc/apparmor.d/local/usr.sbin.mysqld
                grep -Eq 'local/usr.sbin.mysqld' "$profile" || { sayfail "MariaDB AppArmor profile has no local override include."; return 1; }
                ;;
            *) return 1 ;;
        esac
        # AppArmor path syntax is special; reject wildcard/escape characters rather than generate an unsafe rule.
        [[ "$target" =~ ^/[A-Za-z0-9_./-]+$ ]] || { sayfail "Cannot safely express this data path in AppArmor policy: $target"; return 1; }
        _db_run_write install -d -m 0755 "$(dirname "$local_file")" || return 1
        [[ -e "$local_file" ]] || _db_run_write touch "$local_file" || return 1
        for rule in "$target/ rw," "$target/** rwk,"; do
            if ! grep -Fxq -- "$rule" "$local_file"; then
                printf '%s\n' "$rule" | sudo tee -a "$local_file" >/dev/null || return 1
            fi
        done
        # Keep legacy alias behavior only where the distro ships and uses that mechanism.
        if [[ "$profile" != /etc/apparmor.d/mariadbd && -f /etc/apparmor.d/tunables/alias ]]; then
            alias_entry="alias ${old%/}/ -> ${target%/}/,"
            if ! grep -Fxq -- "$alias_entry" /etc/apparmor.d/tunables/alias; then
                printf '%s\n' "$alias_entry" | sudo tee -a /etc/apparmor.d/tunables/alias >/dev/null || return 1
            fi
        fi
        sayinfo "Reloading MariaDB AppArmor profile: $profile"
        _db_run_write apparmor_parser -r "$profile"
    }

    # fn: _db_apparmor_known_denial - Detect the known MariaDB AppArmor mknod denial in recent kernel messages.
        # . Purpose
        #   Identify the tested Ubuntu mknod/c AppArmor denial since a start attempt.
        # . Returns
        #   0 only for a matching denial.
        # . Usage
        #   ```bash
        #   _db_apparmor_known_denial "<unix seconds>"
        #   ```
    _db_apparmor_known_denial() {
        local since="$1" messages=""
        messages="$(journalctl -k --since "@$since" --no-pager 2>/dev/null)" || return 1
        printf '%s\n' "$messages" | grep -E 'apparmor="DENIED".*operation="mknod".*profile="mariadbd".*denied_mask="c"' >/dev/null
    }

    # fn: _db_apparmor_recover - Offer a targeted recovery for the recognized MariaDB AppArmor denial.
        # . Purpose
        #   Offer explicit, profile-only complain mode as a tested compatibility workaround.
        # . Returns
        #   0 only if approved and MariaDB passes datadir verification.
        # . Usage
        #   ```bash
        #   _db_apparmor_recover "/path/to/profile" "/selected/datadir" "<start timestamp>"
        #   ```
    _db_apparmor_recover() {
        local profile="$1" target="$2" since="$3" answer="NO" actual=""
        _db_apparmor_known_denial "$since" || return 1
        command -v aa-complain >/dev/null 2>&1 || { sayfail "AppArmor denial detected but apparmor-utils is unavailable."; return 1; }
        saywarning "Known MariaDB AppArmor file-creation denial detected (mknod/c)."
        saywarning "Complain mode reduces AppArmor enforcement for mariadbd only."
        ask_decision --label "Use temporary MariaDB AppArmor compatibility mode" --choices "Yes|Y,No|N" --default "No" --var answer || return 1
        [[ "${answer^^}" == YES ]] || { sayinfo "AppArmor workaround declined; enforcement unchanged."; return 1; }
        _db_run_write aa-complain "$profile" || { sayfail "Could not change MariaDB AppArmor mode."; return 1; }
        if ! _db_run_write systemctl start "$DB_SERVICE"; then
            sayfail "MariaDB still failed to start in AppArmor complain mode."
            _db_run_write aa-enforce "$profile" || saywarning "Could not restore AppArmor enforce mode automatically."
            return 1
        fi
        actual="$(_db_option datadir)" || return 1
        [[ "${actual%/}" == "${target%/}" ]] || { sayfail "MariaDB started but data directory differs from selected location: $actual"; return 1; }
        saywarning "MariaDB is running with AppArmor in complain mode; restore enforcement after the distro issue is fixed."
        return 0
    }

    # fn: _db_custom_datadir - Configure a custom MariaDB data directory and required service/security settings.
        # . Purpose
        #   Relocate only freshly initialized package data to validated destination.
        # . Returns
        #   0 after live datadir verification, nonzero otherwise.
        # . Usage
        #   ```bash
        #   _db_custom_datadir "/srv/storage/data/mysql"
        #   ```
    _db_custom_datadir() {
        local target="$1" old="" override="/etc/mysql/mariadb.conf.d/99-solidgroundux.cnf"
        local dropin="/etc/systemd/system/mariadb.service.d/90-solidgroundux-storage.conf"
        local profile="" real_target="" value="" start_timestamp=""
        old="$(_db_package_datadir)" || return 1
        real_target="$(realpath -m -- "$target")" || return 1
        [[ "$real_target" != "$old" ]] || { sayinfo "MariaDB already uses selected data directory: $old"; return 0; }
        _db_storage_check "$real_target" || return 1
        [[ -d "$old/mysql" ]] || { sayfail "Source $old has no MariaDB system tables; refusing transfer."; return 1; }
        saystart "Configuring MariaDB data directory: $real_target"
        sayinfo "Package data source: $old"
        sayinfo "Selected data destination: $real_target"
        _db_run_write systemctl stop "$DB_SERVICE" || { sayfail "Could not stop MariaDB for offline data transfer."; return 1; }
        _db_run_write install -d -o mysql -g mysql -m 0750 "$real_target" || return 1
        _db_run_write cp -a -- "$old/." "$real_target/" || { sayfail "Copy to the chosen data directory failed; original remains intact."; return 1; }
        _db_run_write chown -R mysql:mysql "$real_target" || return 1
        _db_set datadir "$real_target" || { sayfail "Could not write MariaDB datadir override."; return 1; }
        local unit_tmp=""
        unit_tmp="$(mktemp)" || return 1
        printf '[Service]\nReadWritePaths=%s\n' "$real_target" > "$unit_tmp"
        case "$real_target" in /home/*|/root/*|/run/user/*) printf 'ProtectHome=false\n' >> "$unit_tmp" ;; esac
        _db_run_write install -d -m 0755 "$(dirname "$dropin")" || { rm -f "$unit_tmp"; return 1; }
        _db_run_write install -m 0644 "$unit_tmp" "$dropin" || { rm -f "$unit_tmp"; return 1; }
        rm -f "$unit_tmp"
        _db_run_write systemctl daemon-reload || return 1
        profile="$(_db_apparmor_profile 2>/dev/null || true)"
        if [[ -n "$profile" ]]; then
            _db_apparmor_prepare "$real_target" "$profile" "$old" || { sayfail "MariaDB AppArmor configuration failed."; return 1; }
            # Installations previously placed in complain mode should first retry enforcement.
            if command -v aa-enforce >/dev/null 2>&1; then
                _db_run_write aa-enforce "$profile" || { sayfail "Could not enable MariaDB AppArmor enforcement."; return 1; }
            fi
        fi
        start_timestamp="$(date +%s)"
        if ! _db_run_write systemctl start "$DB_SERVICE"; then
            saywarning "MariaDB failed to start from the selected data directory. Checking AppArmor diagnostics."
            if [[ -z "$profile" ]] || ! _db_apparmor_recover "$profile" "$real_target" "$start_timestamp"; then
                sayfail "MariaDB could not start using $real_target; original data remains at $old. Check systemd and AppArmor logs."
                return 1
            fi
        fi
        value="$(_db_option datadir)" || return 1
        [[ "${value%/}" == "$real_target" ]] || { sayfail "Running MariaDB datadir mismatch: $value (expected $real_target)"; return 1; }
        sayinfo "MariaDB now uses: $real_target"
        sayinfo "Original package data retained at $old for recovery; do not remove until verified."
        sayend "Custom MariaDB data directory activated"
    }

    # fn: _db_fresh_install - Collect all settings before package installation
    # Purpose: Initialize a fresh MariaDB service using an arbitrary validated directory.
    # Returns: 0 on completion or cancellation; nonzero on failure.
    # Usage: _db_fresh_install
    _db_fresh_install() {
        local path="/var/lib/mysql" port="3306" bind="127.0.0.1" memory="" remote="NO"
        local client="" admin="sgnd_admin" password="" confirm_password="" escaped=""
        local sql="" review_action="INSTALL" account_host="" default_client=""
        default_client="$(_db_default_client_cidr 2>/dev/null || true)"
        _db_require_ubuntu || return 1
        memory="$(_db_suggest_pool)"
        while true; do
            sgnd_print_sectionheader "MariaDB first-install configuration"
            ask --label "Data directory (absolute path)" --var path --default "$path" --back || return 0
            path="$(realpath -m -- "$path")" || return 1
            _db_storage_check "$path" || return 1
            ask --label "TCP port" --var port --default "$port" --validate _db_check_port --back || return 0
            ask --label "InnoDB buffer pool (e.g. 512M)" --var memory --default "$memory" --back || return 0
            [[ "$memory" =~ ^[1-9][0-9]*[MG]$ ]] || { sayfail "Invalid InnoDB buffer pool value."; return 1; }
            ask_decision --label "Enable DBeaver remote access" --choices "Yes|Y,No|N" --default "$( [[ "$remote" == YES ]] && printf Yes || printf No )" --var remote || return 0
            [[ "$remote" != YES || "$bind" != 127.0.0.1 ]] || bind=0.0.0.0
            ask --label "Bind IPv4 address" --var bind --default "$bind" --validate sgnd_validate_ipv4 --back || return 0
            if [[ "$remote" == YES ]]; then
                [[ "$bind" != 127.0.0.1 ]] || { sayfail "Remote access requires a non-loopback bind address."; return 1; }
                ask --label "Allowed workstation IPv4/CIDR" --var client --default "${client:-${default_client:-}}" --validate _db_check_client_cidr --back || return 0
                ask --label "Remote administrator username" --var admin --default "$admin" --back || return 0
                [[ "$admin" =~ ^[a-zA-Z][a-zA-Z0-9_]{0,31}$ && "$admin" != root ]] || { sayfail "Invalid remote administrator name."; return 1; }
            fi
            sgnd_print_sectionheader "Review MariaDB installation"
            sgnd_print_labeledvalue --label "Data directory" --value "$path" --labelwidth 25
            sgnd_print_labeledvalue --label "TCP port" --value "$port" --labelwidth 25
            sgnd_print_labeledvalue --label "Bind IPv4" --value "$bind" --labelwidth 25
            sgnd_print_labeledvalue --label "InnoDB buffer pool" --value "$memory" --labelwidth 25
            sgnd_print_labeledvalue --label "Remote administrator" --value "$( [[ "$remote" == YES ]] && printf '%s (%s)' "$admin" "$client" || printf Disabled )" --labelwidth 25
            ask_decision --label "Review selection" --choices "Install|I,Modify|M,Cancel|C" --default "Install" --var review_action || return 0
            case "$review_action" in
                INSTALL) break ;;
                MODIFY) sayinfo "Revising answers; previous values remain defaults." ;;
                CANCEL) sayinfo "Installation cancelled."; return 0 ;;
                *) sayfail "Invalid review selection."; return 1 ;;
            esac
        done
        _db_transition "Starting MariaDB installation" || { sayinfo "Installation cancelled."; return 0; }
        if [[ "$remote" == YES && ${FLAG_DRYRUN:-0} != 1 ]]; then
            sayinfo "Enter a password for $admin. Input is hidden and not logged."
            IFS= read -r -s -p 'New database password: ' password </dev/tty || return 1
            printf '\n' >/dev/tty
            IFS= read -r -s -p 'Confirm password: ' confirm_password </dev/tty || return 1
            printf '\n' >/dev/tty
            [[ -n "$password" && "$password" == "$confirm_password" ]] || { sayfail "Password confirmation failed."; return 1; }
        fi
        # A recheck immediately before package changes catches newly mounted/modified paths.
        _db_storage_check "$path" || return 1
        saystart "Preparing MariaDB repository"
        _db_repository || { sayfail "MariaDB repository preparation failed."; return 51; }
        sayinfo "Installing AppArmor administration utilities"
        _db_run_write env DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-utils || { sayfail "Could not install apparmor-utils."; return 51; }
        sayend "MariaDB repository ready"
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would install MariaDB and configure data directory $path."
            return 0
        fi
        saystart "Installing MariaDB engine"
        _db_install || { sayfail "MariaDB package installation failed."; return 52; }
        sayend "MariaDB packages installed"
        _db_ensure_initialized || { sayfail "MariaDB package data is not initialized."; return 53; }
        _db_custom_datadir "$path" || { sayfail "Custom data-directory activation failed."; return 53; }
        saystart "Configuring MariaDB settings"
        _db_set port "$port" || return 54
        _db_set bind-address "$bind" || return 54
        _db_set innodb_buffer_pool_size "$memory" || return 54
        _db_run_write systemctl restart "$DB_SERVICE" || { sayfail "Could not restart MariaDB after configuring the server."; return 54; }
        sayend "MariaDB settings applied"
        if [[ "$remote" == YES ]]; then
            saystart "Creating remote database administrator"
            account_host="$(_db_account_host "$client")" || { sayfail "Invalid allowed client network."; return 55; }
            escaped="$(printf '%s' "$password" | sed "s/'/''/g")"
            sql="SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; CREATE USER IF NOT EXISTS '$admin'@'$account_host' IDENTIFIED BY '$escaped'; ALTER USER '$admin'@'$account_host' IDENTIFIED BY '$escaped'; GRANT ALL PRIVILEGES ON *.* TO '$admin'@'$account_host' WITH GRANT OPTION;"
            if ! printf '%s\n' "$sql" | sudo mariadb --batch >/dev/null; then
                unset password confirm_password escaped sql
                sayfail "Could not configure remote administrator."
                return 55
            fi
            unset password confirm_password escaped sql
            sayend "Remote administrator configured"
            if command -v ufw >/dev/null 2>&1; then
                _db_run_write ufw allow from "$client" to any port "$port" proto tcp || return 56
            fi
        fi
        saystart "Verifying MariaDB installation"
        _db_validate || { sayfail "MariaDB failed post-install validation."; return 57; }
        local actual=""
        actual="$(_db_option datadir)" || return 57
        [[ "${actual%/}" == "${path%/}" ]] || { sayfail "MariaDB uses $actual instead of requested $path"; return 57; }
        sayend "MariaDB installation verified"
        return 0
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

    # fn: _db_logs - Display recent service journal without another management UI
    _db_logs() {
        saystart "Reading database service log"
        journalctl -u "$DB_SERVICE" -n 80 --no-pager || { sayfail "Unable to read service log."; return 1; }
        sayend "Database service log displayed"
    }

    # fn: _db_backup - Clarify scope without implementing unsafe restore operations
    _db_backup() {
        sayinfo "Database backup and restore are intentionally managed with database-specific tooling."
        sayinfo "Use mariadb-dump/mariadb-backup or DBeaver for interactive work."
        sayinfo "No database data has been changed."
    }

    # _db_existing_install - Explicit choices for an initialized MariaDB instance.
    # Purpose:
    #   Inspect or deliberately reconfigure an existing server without touching data files.
    # Returns:
    #   0 on inspection, cancellation or successful configuration; nonzero on failure.
    # Usage:
    # fn: _db_existing_install - Install db existing in the MariaDB workflow.
    _db_existing_install() {
        local choice="" port="" bind="" memory="" current_port="" current_bind=""
        local current_memory="" review="" access="No" rc=0
        while true; do
            sgnd_print_sectionheader "Existing MariaDB installation"
            _db_status || { sayfail "Cannot inspect the installed MariaDB server."; return 1; }
            ask_decision --label "Existing installation" --choices "Inspect|I,Reconfigure|R,Cancel|C" --default "Inspect" --var choice || return 0
            case "${choice^^}" in
                INSPECT)
                    sayinfo "Existing MariaDB installation inspected; no settings changed."
                    return 0 ;;
                CANCEL)
                    sayinfo "MariaDB management cancelled; no settings changed."
                    return 0 ;;
                RECONFIGURE) break ;;
                *) sayfail "Unexpected existing-installation selection: $choice"; return 1 ;;
            esac
        done

        current_port="$(_db_option port)" || { sayfail "Cannot read current MariaDB port."; return 1; }
        current_bind="$(_db_option bind-address)" || { sayfail "Cannot read current MariaDB bind address."; return 1; }
        current_memory="$(_db_option innodb_buffer_pool_size)" || { sayfail "Cannot read current InnoDB buffer pool."; return 1; }
        [[ "$current_memory" =~ ^[0-9]+$ ]] || { sayfail "Unexpected InnoDB memory setting: $current_memory"; return 1; }
        port="$current_port"
        bind="$current_bind"
        memory="$((current_memory / 1048576))"
        (( memory >= 1 )) || memory=1
        while true; do
            sgnd_print_sectionheader "Reconfigure MariaDB"
            sayinfo "Existing database files and data directory will not be modified."
            ask --label "TCP port" --var port --default "$port" --validate _db_check_port --back || return 0
            ask --label "Bind IPv4 address" --var bind --default "$bind" --validate sgnd_validate_ipv4 --back || return 0
            ask --label "InnoDB buffer pool (MB)" --var memory --default "$memory" --back || return 0
            [[ "$memory" =~ ^[1-9][0-9]*$ ]] || { sayfail "Specify a positive InnoDB buffer pool size in MB."; return 1; }
            sgnd_print_sectionheader "Review MariaDB reconfiguration"
            sgnd_print_labeledvalue --label "Port" --value "$current_port -> $port" --labelwidth 24
            sgnd_print_labeledvalue --label "Bind IPv4" --value "$current_bind -> $bind" --labelwidth 24
            sgnd_print_labeledvalue --label "InnoDB buffer pool" --value "$current_memory bytes -> ${memory}MB" --labelwidth 24
            sgnd_print_labeledvalue --label "Data directory" --value "$(_db_option datadir 2>/dev/null || printf Unknown) (unchanged)" --labelwidth 24
            ask_decision --label "Review selection" --choices "Apply|A,Modify|M,Cancel|C" --default "Cancel" --var review || return 0
            case "${review^^}" in
                APPLY) break ;;
                MODIFY) sayinfo "Revising settings; previously entered values retained." ;;
                CANCEL) sayinfo "Reconfiguration cancelled; no settings changed."; return 0 ;;
                *) sayfail "Unexpected review selection: $review"; return 1 ;;
            esac
        done
        if [[ "$port" == "$current_port" && "$bind" == "$current_bind" ]] &&
           (( memory * 1048576 == current_memory )); then
            sayinfo "MariaDB configuration unchanged."
            return 0
        fi
        _db_transition "Applying MariaDB reconfiguration" || { sayinfo "Reconfiguration cancelled."; return 0; }
        saystart "Applying MariaDB configuration"
        if [[ "$port" != "$current_port" ]]; then
            _db_set port "$port" || rc=1
        fi
        if (( rc == 0 )) && [[ "$bind" != "$current_bind" ]]; then
            _db_set bind-address "$bind" || rc=1
        fi
        if (( rc == 0 )) && (( memory * 1048576 != current_memory )); then
            _db_set innodb_buffer_pool_size "${memory}M" || rc=1
        fi
        if (( rc == 0 )); then
            _db_restart_active || rc=1
        fi
        if (( rc != 0 )); then
            _db_failure_pause "MariaDB reconfiguration failed; inspect the service and configuration before retrying."
            return 1
        fi
        sayend "MariaDB configuration applied"
        _db_validate || { _db_failure_pause "MariaDB configuration applied but service validation failed."; return 1; }
        sayinfo "Administrator access can be managed separately under Manage Administrator Credentials."
        return 0
    }

    # fn: _db_prepare - Mirror SQL Server's tracked four-step preparation
    _db_prepare() {
        local rc=0
        saystart "MariaDB installation workflow"
        if _db_installed && systemctl is-active --quiet "$DB_SERVICE" && _db_package_datadir >/dev/null 2>&1; then
            sayinfo "MariaDB is already installed; choose whether to inspect or reconfigure it."
            _db_existing_install || rc=$?
            if (( rc != 0 )); then
                _db_failure_pause "MariaDB existing-installation workflow stopped (status $rc)."
                return "$rc"
            fi
            sayend "Existing MariaDB workflow completed"
            return 0
        fi
        _db_fresh_install || rc=$?
        if (( rc != 0 )); then
            _db_failure_pause "MariaDB installation stopped (status $rc). Review preceding output."
            return "$rc"
        fi
        sayend "MariaDB installation completed and validated"
    }

# - MariaDB-specific operations -----------------------------------------------------
    # SolidGroundUX writes a dedicated override rather than patching distro files.
    DB_OVERRIDE="/etc/mysql/mariadb.conf.d/99-solidgroundux.cnf"
    # fn: _db_option - Read a selected MariaDB server setting from the active service or configuration.
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
    # fn: _db_port - Call `_db_option` with the `port` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _db_port
        #   ```
    _db_port() { _db_option port; }
    # fn: _db_set - Set db in the MariaDB workflow.
    _db_set() {
        local key="$1" value="$2" old="" tmp=""
        # Restrict keys and value syntax before an elevated file write.
        case "$key" in port|bind-address|innodb_buffer_pool_size|datadir) ;; *) return 1;; esac
        if [[ "$key" == datadir ]]; then
            [[ "$value" == /* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *'#'* && "$value" != *';'* ]] || return 1
        else
            [[ "$value" =~ ^[a-zA-Z0-9._:]+$ ]] || return 1
        fi
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
    # fn: _db_configure - Configure db in the MariaDB workflow.
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
    # fn: _db_storage_detail - Display the configured database data directory.
    _db_storage_detail() {
        local path=""
        path="$(_db_option datadir 2>/dev/null || printf '/var/lib/mysql')"
        sgnd_print_labeledvalue --label "Data directory" --value "$path" --labelwidth 22
    }
    # fn: _db_network - Review or configure the MariaDB TCP port and bind address.
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
    # fn: _db_memory - Review or configure the MariaDB InnoDB buffer-pool size.
    _db_memory() {
        local current="" value=""
        _db_installed || return 1
        current="$(_db_option innodb_buffer_pool_size 2>/dev/null || printf '134217728')"
        sgnd_print_labeledvalue --label "InnoDB buffer pool bytes" --value "$current" --labelwidth 22
        local mb=0
        if [[ "$current" =~ ^[0-9]+$ ]]; then mb=$((current / 1048576)); else mb=512; fi
        (( mb > 0 )) || mb=512
        ask --label "InnoDB buffer pool MB" --var value --default "$mb" --back || return 0
        [[ "$value" =~ ^[1-9][0-9]*$ ]] || { sayfail "Enter a positive integer MB value."; return 1; }
        if [[ "$current" =~ ^[0-9]+$ ]] && (( current == value * 1048576 )); then
            sayinfo "InnoDB buffer pool unchanged (${value}MB)."
            return 0
        fi
        _db_set innodb_buffer_pool_size "${value}M" || { sayfail "Could not update InnoDB buffer pool."; return 1; }
        _db_restart_active || { sayfail "Could not restart MariaDB after changing memory configuration."; return 1; }
        sayinfo "InnoDB buffer pool configured (${value}MB)."
    }
    # fn: _db_access - Configure one workstation-scoped DBeaver administrator
    _db_access() {
        local client="" admin="sgnd_admin" password="" confirm_password="" escaped="" sql="" bind="" port="" account_host="" default_client=""
        default_client="$(_db_default_client_cidr 2>/dev/null || true)"
        _db_installed || { sayfail "MariaDB is not installed."; return 1; }
        sgnd_print_sectionheader "MariaDB DBeaver access"
        bind="$(_db_option bind-address)" || return 1
        port="$(_db_port)" || return 1
        [[ "$bind" != 127.0.0.1 && "$bind" != localhost ]] || {
            sayfail "Configure a non-loopback bind address in Network first."
            return 1
        }
        ask --label "Allowed workstation IPv4/CIDR" --var client --default "${default_client:-}" --validate _db_check_client_cidr --back || return 0
        ask --label "Remote administrator username" --var admin --default "$admin" --back || return 0
        [[ "$admin" =~ ^[a-zA-Z][a-zA-Z0-9_]{0,31}$ && "$admin" != root ]] || { sayfail "Invalid administrator name."; return 1; }
        _db_confirm "Grant administrator privileges to $admin from $client" || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would securely prompt for credentials and configure $admin from $client."
            return 0
        fi
        IFS= read -r -s -p 'New administrator password: ' password </dev/tty || return 1
        printf '\n' >/dev/tty
        IFS= read -r -s -p 'Confirm password: ' confirm_password </dev/tty || return 1
        printf '\n' >/dev/tty
        [[ -n "$password" && "$password" == "$confirm_password" ]] || { sayfail "Password confirmation failed."; return 1; }
        account_host="$(_db_account_host "$client")" || { sayfail "Invalid allowed client network."; return 1; }
        escaped="$(printf '%s' "$password" | sed "s/'/''/g")"
        sql="SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; CREATE USER IF NOT EXISTS '$admin'@'$account_host' IDENTIFIED BY '$escaped'; ALTER USER '$admin'@'$account_host' IDENTIFIED BY '$escaped'; GRANT ALL PRIVILEGES ON *.* TO '$admin'@'$account_host' WITH GRANT OPTION;"
        saystart "Configuring MariaDB administrator access"
        if ! printf '%s\n' "$sql" | sudo mariadb --batch >/dev/null; then
            unset password confirm_password escaped sql
            sayfail "MariaDB administrator configuration failed."
            return 1
        fi
        unset password confirm_password escaped sql
        if command -v ufw >/dev/null 2>&1; then
            _db_run_write ufw allow from "$client" to any port "$port" proto tcp || return 1
        fi
        sayend "MariaDB DBeaver access configured"
    }

    # fn: _db_status - Inspect status for db in the MariaDB workflow.
    _db_status() {
        local bind="" port="" host="" addr=""
        port="$(_db_port 2>/dev/null || printf '3306')"
        bind="$(_db_option bind-address 2>/dev/null || printf '127.0.0.1')"
        addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
        host="${addr:-$(hostname -f 2>/dev/null || hostname)}"
        sgnd_print_sectionheader "MariaDB"
        sgnd_print_labeledvalue --label "Package" --value "$(dpkg-query -W -f='${Version}' "$DB_PACKAGE" 2>/dev/null || printf 'Not installed')" --labelwidth 23
        sgnd_print_labeledvalue --label "Service" --value "$(systemctl is-active "$DB_SERVICE" 2>/dev/null || true)" --labelwidth 23
        sgnd_print_labeledvalue --label "Port" --value "$port" --labelwidth 23
        sgnd_print_labeledvalue --label "Bind address" --value "$bind" --labelwidth 23
        _db_storage_detail
        local aa_profile="" aa_mode="Not installed"
        aa_profile="$(_db_apparmor_profile 2>/dev/null || true)"
        if [[ -n "$aa_profile" ]]; then
            if command -v aa-status >/dev/null 2>&1; then
                if aa-status --complaining 2>/dev/null | grep -Eq '(^|/)mariadbd([[:space:]]|$)'; then aa_mode="Complain";
                elif aa-status --enforced 2>/dev/null | grep -Eq '(^|/)mariadbd([[:space:]]|$)'; then aa_mode="Enforce";
                else aa_mode="Unknown (check aa-status)"; fi
            else aa_mode="Profile installed (status unavailable)"; fi
        fi
        sgnd_print_labeledvalue --label "AppArmor" --value "$aa_mode" --labelwidth 23
        sgnd_print_labeledvalue --label "InnoDB buffer pool" --value "$(_db_option innodb_buffer_pool_size 2>/dev/null || printf 'Unavailable')" --labelwidth 23
        sgnd_print_sectionheader "DBeaver connection information"
        sgnd_print_labeledvalue --label "Host candidate" --value "$host" --labelwidth 23
        sgnd_print_labeledvalue --label "Port" --value "$port" --labelwidth 23
        sgnd_print_labeledvalue --label "Database" --value "mysql" --labelwidth 23
        sgnd_print_labeledvalue --label "User" --value "The remote administrator configured during installation" --labelwidth 23
        sgnd_print_labeledvalue --label "JDBC URL" --value "jdbc:mariadb://${host}:${port}/mysql" --labelwidth 23
        if [[ "$bind" == 127.0.0.1 || "$bind" == localhost ]]; then
            saywarning "MariaDB currently listens only on localhost; remote DBeaver connections are unavailable."
        else
            sayinfo "Remote connectivity also requires a matching MariaDB account host, valid password and firewall access."
        fi
    }
    # fn: _db_validate - Validate db in the MariaDB workflow.
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
            install) _db_prepare || rc=$? ;;
            configure) _db_configure || rc=$? ;;
            tools) _db_tools || rc=$? ;;
            storage) _db_storage || rc=$? ;;
            network) _db_network || rc=$? ;;
            memory) _db_memory || rc=$? ;;
            access) _db_access || rc=$? ;;
            service) _db_service || rc=$? ;;
            firewall) _db_firewall || rc=$? ;;
            validate) _db_validate || rc=$? ;;
            status) _db_status || rc=$? ;;
            logs) _db_logs || rc=$? ;;
            backup) _db_backup || rc=$? ;;
            *) sayfail "Unknown MariaDB action: $action"; return 2 ;;
        esac
        return "$rc"
    }

# - Main ----------------------------------------------------------------------------
    # fn: main - Dispatch command-line options to the appropriate management workflow.
    main() {
        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        _run_action "${ACTION:-status}"
    }
    main "$@"
