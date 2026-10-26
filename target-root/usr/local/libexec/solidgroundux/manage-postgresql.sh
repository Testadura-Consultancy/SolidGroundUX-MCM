#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - Manage PostgreSQL
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2629401
#   Shortname   : MANAGE_POSTGRESQL
#   Source      : manage-postgresql.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Install, configure, manage, validate, and inspect PostgreSQL
#
#   Checksum : 558bb945df657d46495cea1b1fa5b52744d2a4a6aab225e544aa4ddfa53631aa
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
        "action|a|enum|ACTION|Management action||prepare,repository,install,configure,storage,network,memory,access,credentials,service,firewall,tools,validate,status,logs,backup"
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

    # fn: _db_check_client - IPv4 address optionally followed by CIDR prefix
    _db_check_client() {
        local value="$1" ip="" prefix=""
        ip="${value%%/*}"
        sgnd_validate_ipv4 "$ip" || return 1
        if [[ "$value" == */* ]]; then
            prefix="${value#*/}"
            sgnd_validate_cidr "$prefix" || return 1
        fi
        return 0
    }

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
    # fn: _db_transition - Present the framework's interruptible transition countdown
    _db_transition() {
        local rc=0
        ask_dlg_autocontinue --seconds 5 --message "$1" --cancel --pause || rc=$?
        (( rc != 2 ))
    }

    # fn: _db_confirm - Require approval before changing an installation
    _db_confirm() {
        local answer="NO"
        ask_decision --label "$1" --choices "Yes|Y,No|N" --default "No" --var answer || return 1
        [[ "$answer" == YES ]]
    }

    # fn: _db_size_suggestion - Suggest 25 percent of RAM for dedicated installations
    _db_size_suggestion() {
        local total_kb=0 value=128
        total_kb="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)"
        [[ "$total_kb" =~ ^[0-9]+$ ]] || { printf '128MB\n'; return; }
        value=$(( total_kb / 4096 / 128 * 128 ))
        (( value >= 128 )) || value=128
        printf '%sMB\n' "$value"
    }

    # fn: _db_failure_pause - Keep an actionable error visible before menu redraw
    _db_failure_pause() {
        sayfail "$1"
        # Visible regardless of console log-level filtering (including SILENT).
        printf '\nERROR: %s\n' "$1" >/dev/tty 2>/dev/null || printf 'ERROR: %s\n' "$1" >&2
        if [[ -r /dev/tty && -w /dev/tty ]]; then
            local unused=""
            IFS= read -r -p 'Press Enter to return to the menu...' unused </dev/tty || true
        fi
        return 1
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
        ask_decision --label "Allow $port/tcp" --choices "Yes|Y,No|N" --default "No" --var response || return 0
        [[ "$response" == YES ]] || return 0
        _db_run_write ufw allow "${port}/tcp"
    }

    # fn: _db_storage - No automatic migration of populated database files
    _db_storage() {
        sgnd_print_sectionheader "PostgreSQL storage"
        if ! _db_installed; then
            saywarning "PostgreSQL is not installed. Choose Prepare / Install PostgreSQL to select a data directory."
            return 0
        fi
        if ! _db_cluster >/dev/null; then
            saywarning "No initialized PostgreSQL cluster found. Choose Prepare / Install to configure storage before initialization."
            return 0
        fi
        _db_storage_detail || return 1
        local version="" cluster="" dir=""
        read -r version cluster <<< "$(_db_cluster)" || return 1
        dir="$(pg_lsclusters --no-header | awk -v v="$version" -v c="$cluster" '$1==v && $2==c {print $6;exit}')"
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

    # _db_directory_inspect
    # Purpose: Inspect an installation target without provisioning or modifying disks.
    # Returns: 0 when suitable, 2 when cancelled, 3 when the choice must change.
    # Usage: _db_directory_inspect "/srv/storage/data" disposition
    _db_directory_inspect() {
        local target="$1" output_name="$2" choice="" mount="" source="" fs=""
        local target_real="" root_real="" parent=""
        printf -v "$output_name" '%s' "Keep"
        [[ "$target" == /* && "$target" != / && "$target" != *'..'* ]] || {
            saywarning "Choose a safe absolute data directory."; return 3;
        }
        if [[ -L "$target" ]]; then
            saywarning "Symbolic links are not supported as a data directory."; return 3
        fi
        parent="$target"
        while [[ ! -e "$parent" && "$parent" != / ]]; do parent="$(dirname -- "$parent")"; done
        [[ -d "$parent" ]] || { saywarning "Parent path is not a directory: $parent"; return 3; }
        # Never allow a target whose ancestor is an unmounted configured volume.
        local configured="" probe="$target"
        while [[ "$probe" != / ]]; do
            if findmnt --fstab --mountpoint "$probe" >/dev/null 2>&1 \
                && ! findmnt --mountpoint "$probe" >/dev/null 2>&1; then
                saywarning "Configured filesystem is not mounted: $probe. Mount it using Computer Setup & Storage."
                return 3
            fi
            probe="$(dirname -- "$probe")"
        done
        mount="$(findmnt -T "$parent" -n -o TARGET 2>/dev/null || true)"
        source="$(findmnt -T "$parent" -n -o SOURCE 2>/dev/null || true)"
        fs="$(findmnt -T "$parent" -n -o FSTYPE 2>/dev/null || true)"
        sgnd_print_labeledvalue --label "Filesystem mount" --value "${mount:-Unknown}" --labelwidth 22
        sgnd_print_labeledvalue --label "Source" --value "${source:-Unknown}" --labelwidth 22
        sgnd_print_labeledvalue --label "Filesystem" --value "${fs:-Unknown}" --labelwidth 22
        if [[ "$mount" == / && "$target" == /srv/* ]]; then
            saywarning "Selected storage is currently on the root filesystem. Check the dedicated disk mount."
            return 3
        fi
        if [[ -e "$target" && ! -d "$target" ]]; then
            saywarning "Data directory path exists but is not a directory."; return 3
        fi
        if [[ ! -d "$target" ]]; then
            sayinfo "Data directory does not exist; it will be created during installation."
            return 0
        fi
        if [[ -z "$(ls -A -- "$target" 2>/dev/null)" ]]; then
            sayinfo "Data directory exists and is empty."
            return 0
        fi
        saywarning "Data directory exists and is not empty: $target"
        ask_decision --label "Existing directory contents" --choices "Use|U,Clear|L,Cancel|C" --default "Cancel" --var choice || return 2
        case "${choice^^}" in
            USE)
                # Never adopt an arbitrary PGDATA into a newly registered cluster.
                if [[ -f "$target/PG_VERSION" ]]; then
                    saywarning "Existing PostgreSQL data detected. Automatic adoption is not supported; select another directory or manage the existing cluster."
                else
                    saywarning "The existing contents are not an empty PostgreSQL installation target. They cannot be used for a new cluster."
                fi
                return 3 ;;
            CLEAR)
                # The actual cleanup is deferred until AFTER the installation review.
                printf -v "$output_name" '%s' "Clear"
                saywarning "Contents will only be cleared after you confirm Install and explicitly confirm deletion."
                return 0 ;;
            CANCEL) return 2 ;;
            *) saywarning "No directory operation selected."; return 2 ;;
        esac
    }

    # _db_clear_directory
    # Purpose: Remove contents of an approved, unregistered data directory only.
    # Returns: 0 on success, 2 when cancelled, 1 on unsafe target or failure.
    # Usage: _db_clear_directory "/srv/storage/data"
    _db_clear_directory() {
        local target="$1" mount="" cluster_path="" answer=""
        [[ "$target" == /* && "$target" != / && "$target" != *'..'* && -d "$target" && ! -L "$target" ]] || return 1
        # Clear is intended only for dedicated database subdirectories.
        case "$target" in /etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/boot|/boot/*|/root|/root/*|/home|/home/*|/var|/var/log|/var/lib|/srv|/mnt|/media|/tmp|/opt) saywarning "Protected directory: $target"; return 1 ;; esac
        [[ "$(realpath -e -- "$target")" == "$target" ]] || { saywarning "Noncanonical or symlinked path: $target"; return 1; }
        # Reject a mount root and any nested mountpoint. Never traverse a mount boundary.
        mount="$(findmnt -T "$target" -n -o TARGET 2>/dev/null || true)"
        [[ -n "$mount" && "$target" != "$mount" ]] || { saywarning "Refusing to clear a filesystem mount root."; return 1; }
        if findmnt -rn -o TARGET | awk -v path="$target" 'index($0,path"/")==1 {found=1} END {exit !found}'; then
            saywarning "Refusing to clear a directory containing mounted filesystems."; return 1
        fi
        if command -v pg_lsclusters >/dev/null 2>&1; then
            while IFS= read -r cluster_path; do
                [[ -n "$cluster_path" ]] || continue
                if [[ "$target" == "$cluster_path" || "$target" == "$cluster_path"/* || "$cluster_path" == "$target"/* ]]; then
                    saywarning "Refusing to clear a registered PostgreSQL cluster path."; return 1
                fi
            done < <(pg_lsclusters --no-header 2>/dev/null | awk '{print $6}')
        fi
        saywarning "This will permanently delete all contents of $target"
        ask_decision --label "Clear directory contents permanently" --choices "Yes|Y,No|N" --default "No" --var answer || return 2
        [[ "${answer^^}" == YES ]] || return 2
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would clear contents of $target"
            return 0
        fi
        # One filesystem only, do not follow symlinks; do not remove the directory itself.
        sudo find "$target" -mindepth 1 -maxdepth 1 -xdev -exec rm -rf --one-file-system -- {} + || return 1
        [[ -z "$(ls -A -- "$target" 2>/dev/null)" ]] || return 1
        sayinfo "Data directory contents cleared: $target"
    }

    # fn: _db_fresh_install - Configure and initialize a new cluster on chosen storage
    _db_fresh_install() {
        local path="/srv/postgresql/data" cluster="main" port="5432" listen="localhost"
        local memory="" client="" version="" password_choice="NO" remote="NO" rc=0 disposition="Keep" default_client=""
        default_client="$(_db_default_client_cidr 2>/dev/null || true)"
        _db_require_ubuntu || return 1
        saystart "Phase 1: Preparing PostgreSQL prerequisites"
        sayinfo "Refreshing Ubuntu package lists"
        _db_repository || { sayfail "Unable to refresh PostgreSQL package metadata."; return 51; }
        sayinfo "Installing PostgreSQL cluster management prerequisites"
        _db_run_write env DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-common || { sayfail "Unable to install postgresql-common."; return 52; }
        sayend "PostgreSQL prerequisites prepared"
        saystart "Phase 2: Collecting installation configuration"
        memory="$(_db_size_suggestion)"
        sgnd_print_sectionheader "PostgreSQL first-install configuration"
        sayinfo "Select the data directory BEFORE creating the database cluster."
        local review_action="Install"
        # These locals are the single in-memory installation configuration state.
        while true; do
        ask --label "Data directory (absolute path)" --var path --default "$path" --back || { sayinfo "Installation cancelled."; return 0; }
        _db_directory_inspect "$path" disposition || {
            rc=$?
            if (( rc == 2 )); then sayinfo "Installation cancelled."; return 0; fi
            sayinfo "Choose another data directory."
            continue
        }
        ask --label "Cluster name" --var cluster --default "$cluster" --back || { sayinfo "Installation cancelled."; return 0; }
        [[ "$cluster" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || { sayfail "Invalid cluster name."; return 1; }
        ask --label "TCP port" --var port --default "$port" --validate _db_check_port --back || { sayinfo "Installation cancelled."; return 0; }
        ask --label "Shared buffers" --var memory --default "$memory" --back || { sayinfo "Installation cancelled."; return 0; }
        [[ "$memory" =~ ^[1-9][0-9]*(kB|MB|GB)$ ]] || { sayfail "Invalid shared_buffers size."; return 1; }
        ask_decision --label "Enable remote workstation access" --choices "Yes|Y,No|N" --default "$( [[ "$remote" == YES ]] && printf Yes || printf No )" --var remote || { sayinfo "Installation cancelled."; return 0; }
        if [[ "$remote" == YES && "$listen" == localhost ]]; then listen="*"; fi
        ask --label "Listen addresses (localhost, IP, *)" --var listen --default "$listen" --back || { sayinfo "Installation cancelled."; return 0; }
        [[ "$listen" =~ ^[a-zA-Z0-9.,:*_-]+$ ]] || { sayfail "Invalid listen addresses."; return 1; }
        if [[ "$remote" == YES ]]; then
            [[ "$listen" != localhost ]] || { sayfail "Remote access needs a non-local listen address."; return 1; }
            ask --label "Allowed workstation IPv4/CIDR" --var client --default "${client:-${default_client:-}}" --validate _db_check_client --back || { sayinfo "Installation cancelled."; return 0; }
            password_choice="YES"
        else
            ask_decision --label "Set postgres database password" --choices "Yes|Y,No|N" --default "$( [[ "$password_choice" == YES ]] && printf Yes || printf No )" --var password_choice || { sayinfo "Installation cancelled."; return 0; }
        fi
        sgnd_print_sectionheader "Review PostgreSQL installation"
        sgnd_print_labeledvalue --label "Data directory" --value "$path" --labelwidth 24
        sgnd_print_labeledvalue --label "Directory action" --value "$disposition" --labelwidth 24
        sgnd_print_labeledvalue --label "Cluster name" --value "$cluster" --labelwidth 24
        sgnd_print_labeledvalue --label "Port" --value "$port" --labelwidth 24
        sgnd_print_labeledvalue --label "Listen addresses" --value "$listen" --labelwidth 24
        sgnd_print_labeledvalue --label "Shared buffers" --value "$memory" --labelwidth 24
        sgnd_print_labeledvalue --label "Allowed client" --value "$( [[ "$remote" == YES ]] && printf %s "$client" || printf "None (local only)" )" --labelwidth 24
        sgnd_print_labeledvalue --label "Administrator password" --value "$( [[ "$password_choice" == YES ]] && printf Yes || printf No ) (prompted securely after install)" --labelwidth 24
        ask_decision --label "Review selection" --choices "Install|I,Modify|M,Cancel|C" --default "Install" --var review_action || { sayinfo "Installation cancelled."; return 0; }
        case "$review_action" in
            INSTALL) break ;;
            MODIFY) sayinfo "Revising answers; previous values are retained as defaults." ;;
            CANCEL) sayinfo "Installation cancelled. No changes made."; return 0 ;;
            *) _db_failure_pause "Unexpected review selection: $review_action"; return 1 ;;
        esac
        done
        sayend "Installation configuration approved"
        _db_transition "Starting PostgreSQL installation" || return 1
        saystart "Phase 3: Installing PostgreSQL"
        # Suppress Debian's automatic default cluster so storage is chosen before initdb.
        sayinfo "Disabling automatic default-cluster creation during package installation."
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would configure postgresql-common createcluster.conf."
        else
            # Respect an existing cluster policy instead of replacing it blindly.
            if [[ -f /etc/postgresql-common/createcluster.conf ]] && grep -Eq '^[[:space:]]*create_main_cluster[[:space:]]*=[[:space:]]*true' /etc/postgresql-common/createcluster.conf; then
                sayinfo "Temporarily disabling default cluster auto-creation."
            fi
            local policy="" restore="" 
            policy="$(mktemp)" || return 52
            restore="$(mktemp)" || { rm -f "$policy"; return 52; }
            if [[ -f /etc/postgresql-common/createcluster.conf ]]; then sudo cp /etc/postgresql-common/createcluster.conf "$restore" || { rm -f "$policy" "$restore"; return 52; }; else : > "$restore"; fi
            printf 'create_main_cluster = false\n' > "$policy"
            sudo cp "$policy" /etc/postgresql-common/createcluster.conf || { rm -f "$policy" "$restore"; return 52; }
            rm -f "$policy"
            sayinfo "Installing PostgreSQL engine."
            if ! _db_install; then
                sudo cp "$restore" /etc/postgresql-common/createcluster.conf || true
                rm -f "$restore"
                return 52
            fi
            sudo cp "$restore" /etc/postgresql-common/createcluster.conf || { rm -f "$restore"; sayfail "Cannot restore cluster policy."; return 52; }
            rm -f "$restore"
        fi
        sayend "PostgreSQL packages installed"
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would create cluster $cluster at $path, port $port."
            sayinfo "DRYRUN: Would configure network, authentication, shared buffers and firewall."
            return 0
        fi
        if pg_lsclusters --no-header 2>/dev/null | grep -qE '^[[:space:]]*[0-9]+'; then
            sayfail "A PostgreSQL cluster already exists. Refusing to initialize or overwrite data."
            return 53
        fi
        if [[ -d "$path" && -n "$(ls -A -- "$path" 2>/dev/null)" ]]; then
            if [[ "$disposition" == Clear ]]; then
                _db_clear_directory "$path" || {
                    rc=$?
                    (( rc == 2 )) && { sayinfo "Installation cancelled. Existing data was not changed."; return 0; }
                    return 53
                }
            else
                _db_failure_pause "Data directory is no longer empty: $path"
                return 53
            fi
        fi
        version="$(pg_config --version | awk '{print $2}' | cut -d. -f1)"
        [[ "$version" =~ ^[0-9]+$ ]] || { sayfail "Unable to determine PostgreSQL major version."; return 53; }
        saystart "Initializing PostgreSQL $version cluster $cluster"
        _db_run_write pg_createcluster --datadir "$path" --port "$port" "$version" "$cluster" || return 53
        sayend "PostgreSQL cluster created"
        _db_set listen_addresses "$listen" || return 54
        _db_set shared_buffers "$memory" || return 54
        if [[ "$remote" == YES ]]; then
            saystart "Configuring remote authentication"
            local hba="/etc/postgresql/$version/$cluster/pg_hba.conf"
            [[ -f "$hba" ]] || { sayfail "Authentication file missing: $hba"; return 54; }
            # IPv4 single client / CIDR validated above; appended after local entries.
            printf 'host all postgres %s scram-sha-256\n' "$client" | sudo tee -a "$hba" >/dev/null || return 54
            sayend "Workstation authentication configured"
        fi
        saystart "Starting PostgreSQL cluster"
        _db_run_write pg_ctlcluster "$version" "$cluster" start || return 55
        sayend "PostgreSQL cluster started"
        if [[ "$password_choice" == YES ]]; then
            sayinfo "Enter the postgres database password in PostgreSQL's hidden password prompt."
            sudo -u postgres psql -X -d postgres -c '\password postgres' </dev/tty || { sayfail "Administrator password setup failed."; return 56; }
        fi
        if [[ "$remote" == YES ]] && command -v ufw >/dev/null 2>&1; then
            sayinfo "Restricting UFW database access to $client on TCP $port."
            _db_run_write ufw allow from "$client" to any port "$port" proto tcp || return 57
        fi
        saystart "Verifying PostgreSQL installation"
        _db_validate || return 58
        sayend "PostgreSQL installation verified"
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

    # fn: _db_logs - Display recent service journal without another management UI
    _db_logs() {
        saystart "Reading database service log"
        journalctl -u "$DB_SERVICE" -n 80 --no-pager || { sayfail "Unable to read service log."; return 1; }
        sayend "Database service log displayed"
    }

    # fn: _db_backup - Clarify scope without implementing unsafe restore operations
    _db_backup() {
        sayinfo "Database backup and restore are intentionally managed with database-specific tooling."
        sayinfo "Use pg_dump, pg_restore and pg_basebackup, or DBeaver for interactive work."
        sayinfo "No database data has been changed."
    }

    # fn: _db_prepare - Mirror SQL Server's tracked four-step preparation
    _db_prepare() {
        local rc=0
        saystart "PostgreSQL installation workflow"
        if _db_installed && _db_cluster >/dev/null 2>&1; then
            sayinfo "PostgreSQL is already installed and an initialized cluster exists; existing data will not be changed."
            _db_status
            sayend "Existing PostgreSQL installation inspected"
            return 0
        fi
        if _db_installed; then
            saywarning "PostgreSQL package is installed but no cluster is detected; proceeding with a fresh cluster configuration without deleting any existing data."
        fi
        _db_fresh_install || rc=$?
        if (( rc != 0 )); then
            _db_failure_pause "PostgreSQL installation stopped (status $rc). See preceding messages."
            return "$rc"
        fi
        sayend "PostgreSQL installation completed and validated"
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
        local version="" cluster="" assignment="" result=""
        read -r version cluster <<< "$(_db_cluster)" || return 1
        assignment="$(pg_conftool "$version" "$cluster" show "$1" 2>/dev/null | head -n 1)" || return 1
        [[ "$assignment" == *"="* ]] || { sayfail "Cannot read PostgreSQL setting: $1"; return 1; }
        result="${assignment#*=}"
        result="${result#"${result%%[![:space:]]*}"}"
        result="${result%"${result##*[![:space:]]}"}"
        if [[ "$result" == \'*\' && ${#result} -ge 2 ]]; then result="${result:1:${#result}-2}"; fi
        printf '%s\n' "$result"
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
        local port="" address="" value="" newport="" newaddress=""
        _db_installed && _db_cluster >/dev/null || return 1
        port="$(_db_port)" || { sayfail "Cannot determine PostgreSQL TCP port."; return 1; }
        address="$(_db_conf listen_addresses)" || return 1
        sgnd_print_labeledvalue --label "TCP port" --value "$port" --labelwidth 22
        sgnd_print_labeledvalue --label "Listen addresses" --value "$address" --labelwidth 22
        ask --label "TCP port" --var newport --default "$port" --validate _db_check_port --back || return 0
        ask --label "Listen addresses" --var newaddress --default "$address" --back || return 0
        [[ "$newaddress" =~ ^[a-zA-Z0-9.,:*_-]+$ ]] || { sayfail "Invalid listening address format."; return 1; }
        _db_confirm "Apply PostgreSQL network changes" || return 0
        saystart "Configuring PostgreSQL networking"
        _db_set port "$newport" || return 1
        _db_set listen_addresses "$newaddress" || return 1
        _db_restart_active || return 1
        sayend "PostgreSQL network configured"
        sayinfo "Client authentication restrictions are controlled separately in pg_hba.conf."
    }
    # _db_memory
    # Purpose:
    #   Change PostgreSQL shared buffers only when the requested value differs.
    # Behavior:
    #   - Enter on the current value is a successful no-op.
    #   - Report configuration-write and restart failures explicitly.
    # Returns:
    #   0 for unchanged or successfully applied settings; nonzero on failure.
    # Usage:
    #   _db_memory
    _db_memory() {
        local current="" value="" normalized_current="" normalized_value=""
        _db_installed || { _db_failure_pause "PostgreSQL is not installed."; return 1; }
        _db_cluster >/dev/null || { _db_failure_pause "No PostgreSQL cluster was found."; return 1; }
        current="$(_db_conf shared_buffers)" || { _db_failure_pause "Cannot read PostgreSQL shared_buffers."; return 1; }
        sgnd_print_labeledvalue --label "Shared buffers" --value "$current" --labelwidth 22
        ask --label "Shared buffers (e.g. 512MB)" --var value --default "$current" --back || return 0
        [[ "$value" =~ ^[1-9][0-9]*(kB|MB|GB)$ ]] || {
            _db_failure_pause "Specify a positive shared buffers size in kB, MB or GB."
            return 1
        }
        normalized_current="${current,,}"
        normalized_value="${value,,}"
        if [[ "$normalized_value" == "$normalized_current" ]]; then
            sayok "Shared buffers unchanged ($current)."
            return 0
        fi
        saystart "Configuring PostgreSQL shared buffers"
        sayinfo "Changing shared_buffers from $current to $value"
        if ! _db_set shared_buffers "$value"; then
            sayfail "Could not write PostgreSQL shared_buffers."
            _db_failure_pause "PostgreSQL shared_buffers update failed. See the file log for details."
            return 1
        fi
        sayinfo "PostgreSQL shared_buffers updated to $value"
        if ! _db_restart_active; then
            sayfail "PostgreSQL restart failed after changing shared_buffers."
            _db_failure_pause "PostgreSQL could not restart after the shared buffers change. Review the service logs."
            return 1
        fi
        sayend "PostgreSQL shared buffers configured"
        return 0
    }
    # fn: _db_access - Set postgres password and authorize one workstation
    _db_access() {
        local version="" cluster="" client="" hba="" port="" listen="" answer="NO" default_client=""
        default_client="$(_db_default_client_cidr 2>/dev/null || true)"
        _db_installed || { sayfail "PostgreSQL is not installed."; return 1; }
        read -r version cluster <<< "$(_db_cluster)" || return 1
        sgnd_print_sectionheader "PostgreSQL DBeaver access"
        sayinfo "Local peer authentication remains unchanged."
        ask_decision --label "Set/change postgres database password" --choices "Yes|Y,No|N" --default "Yes" --var answer || return 0
        if [[ "$answer" == YES ]]; then
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would prompt for a postgres password."
            else
                sayinfo "PostgreSQL will securely prompt for a password (not logged)."
                sudo -u postgres psql -X -d postgres -c '\password postgres' </dev/tty || return 1
            fi
        fi
        answer="NO"
        ask_decision --label "Allow a remote DBeaver workstation" --choices "Yes|Y,No|N" --default "No" --var answer || return 0
        [[ "$answer" == YES ]] || return 0
        ask --label "Allowed IPv4/CIDR" --var client --default "${default_client:-}" --validate _db_check_client --back || return 0
        port="$(_db_port)" || return 1
        listen="$(_db_conf listen_addresses)" || return 1
        if [[ "$listen" == localhost || "$listen" == 127.0.0.1 ]]; then
            sayfail "Configure a non-local listen address in Network first."
            return 1
        fi
        _db_confirm "Allow PostgreSQL superuser from $client" || return 0
        hba="/etc/postgresql/$version/$cluster/pg_hba.conf"
        saystart "Configuring PostgreSQL workstation access"
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would add scoped scram-sha-256 rule to $hba."
        else
            [[ -f "$hba" ]] || { sayfail "Cannot find $hba"; return 1; }
            if ! grep -Fqx "host all postgres $client scram-sha-256" "$hba"; then
                printf 'host all postgres %s scram-sha-256\n' "$client" | sudo tee -a "$hba" >/dev/null || return 1
            fi
            _db_run_write pg_ctlcluster "$version" "$cluster" reload || return 1
        fi
        if command -v ufw >/dev/null 2>&1; then
            _db_run_write ufw allow from "$client" to any port "$port" proto tcp || return 1
        fi
        sayend "PostgreSQL workstation access configured"
    }

    # _db_status
    # Purpose: Show the live server configuration and workstation connection settings.
    # Returns: 0 after reporting available information.
    # Usage: _db_status
    _db_status() {
        local cluster="Unavailable" port="Unavailable" memory="Unavailable"
        local listen="Unavailable" directory="Unavailable" version="" name="" owner=""
        local host="Unavailable" service="" password="Unknown" host_cidr="" hba=""
        local -a candidate_ips=()
        if _db_installed; then
            cluster="$(_db_cluster 2>/dev/null || printf 'Ambiguous / unavailable')"
            port="$(_db_port 2>/dev/null || printf 'Unavailable')"
            memory="$(_db_conf shared_buffers 2>/dev/null || printf 'Unavailable')"
            listen="$(_db_conf listen_addresses 2>/dev/null || printf 'Unavailable')"
            if read -r version name <<< "$(_db_cluster 2>/dev/null)"; then
                directory="$(pg_lsclusters --no-header 2>/dev/null | awk -v v="$version" -v c="$name" '$1==v && $2==c {print $6;exit}')"
                hba="/etc/postgresql/$version/$name/pg_hba.conf"
            fi
        fi
        service="$(systemctl is-active "$DB_SERVICE" 2>/dev/null || true)"
        sgnd_print_sectionheader "PostgreSQL status & configuration"
        sgnd_print_labeledvalue --label "Package" --value "$(dpkg-query -W -f='${Version}' "$DB_PACKAGE" 2>/dev/null || printf 'Not installed')" --labelwidth 24
        sgnd_print_labeledvalue --label "Cluster" --value "$cluster" --labelwidth 24
        sgnd_print_labeledvalue --label "Service" --value "${service:-Unavailable}" --labelwidth 24
        sgnd_print_labeledvalue --label "Data directory" --value "${directory:-Unavailable}" --labelwidth 24
        sgnd_print_labeledvalue --label "Port" --value "$port" --labelwidth 24
        sgnd_print_labeledvalue --label "Listen addresses" --value "$listen" --labelwidth 24
        sgnd_print_labeledvalue --label "Shared buffers" --value "$memory" --labelwidth 24
        if [[ -d "$directory" ]]; then
            sgnd_print_labeledvalue --label "Disk space" --value "$(df -h --output=avail "$directory" 2>/dev/null | tail -n 1 | xargs) available" --labelwidth 24
        fi
        if [[ -n "$version" && -n "$name" ]] && command -v psql >/dev/null 2>&1; then
            local tablespaces=""
            tablespaces="$(sudo -n -u postgres psql -X -A -t -d postgres -c 'SELECT spcname FROM pg_tablespace ORDER BY spcname;' 2>/dev/null | paste -sd ', ' -)" || true
            [[ -z "$tablespaces" ]] || sgnd_print_labeledvalue --label "Tablespaces" --value "$tablespaces" --labelwidth 24
        fi
        sgnd_print_sectionheader "DBeaver connection information"
        if [[ "$listen" == localhost || "$listen" == 127.0.0.1 || "$listen" == Unavailable ]]; then
            sayinfo "PostgreSQL does not appear configured for external TCP connections."
            sgnd_print_labeledvalue --label "Host" --value "localhost (server only)" --labelwidth 24
        else
            if [[ "$listen" != '*' && "$listen" != '0.0.0.0' ]]; then
                host="${listen%%,*}"
            else
                host="$(hostname -I 2>/dev/null | awk '{print $1}')"
            fi
            sgnd_print_labeledvalue --label "Host (candidate)" --value "${host:-Unavailable}" --labelwidth 24
            sayinfo "Remote access also requires a matching pg_hba.conf rule and firewall permission."
        fi
        sgnd_print_labeledvalue --label "Port" --value "$port" --labelwidth 24
        sgnd_print_labeledvalue --label "Database" --value "postgres" --labelwidth 24
        sgnd_print_labeledvalue --label "Username" --value "postgres" --labelwidth 24
        sgnd_print_labeledvalue --label "Password" --value "Enter the configured administrator password" --labelwidth 24
        if [[ -n "$host" && "$host" != Unavailable && "$port" != Unavailable ]]; then
            sgnd_print_labeledvalue --label "JDBC URL" --value "jdbc:postgresql://$host:$port/postgres" --labelwidth 24
        fi
        sayinfo "In DBeaver: New Connection > PostgreSQL, enter the displayed host, port, database and username."
        sayinfo "The connection details are derived from this server, not a verified test from your workstation."
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
            install) _db_prepare || rc=$? ;;
            configure) _db_configure || rc=$? ;;
            tools) _db_tools || rc=$? ;;
            storage) _db_storage || rc=$? ;;
            network) _db_network || rc=$? ;;
            memory) _db_memory || rc=$? ;;
            access|credentials) _db_access || rc=$? ;;
            service) _db_service || rc=$? ;;
            firewall) _db_firewall || rc=$? ;;
            validate) _db_validate || rc=$? ;;
            status) _db_status || rc=$? ;;
            logs) _db_logs || rc=$? ;;
            backup) _db_backup || rc=$? ;;
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
