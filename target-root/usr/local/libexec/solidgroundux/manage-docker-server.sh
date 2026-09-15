#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX - Manage Docker Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625802
#   Source      : manage-docker-server.sh
#   Type        : script
#   Group       : SolidGround Console
#   Purpose     : Install, configure, validate, and inspect a Docker host
#
# Description:
#   Provides first-version Docker host management for SolidGroundUX. The script
#   deliberately avoids migrating an existing Docker data root automatically.
# ==================================================================================
set -uo pipefail

# - Bootstrap ----------------------------------------------------------------------
    _framework_locator() {
        local script_file="" path_without_root="" component="" project_root="" exe_common=""
        local index=0 root_index=-1
        local -a path_parts=()

        if [[ -n "${SGND_FRAMEWORK_ROOT:-}" ]]; then
            if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
                exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            else
                exe_common="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            fi
            if [[ -r "$exe_common" ]]; then
                source "$exe_common"
                return 0
            fi
        fi

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || return 126
        path_without_root="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"
        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in usr|etc|var) root_index=$index ;; esac
        done

        if (( root_index >= 0 )); then
            if (( root_index == 0 )); then
                project_root="/"
            else
                project_root=""
                for (( index=0; index<root_index; index++ )); do
                    project_root+="/${path_parts[$index]}"
                done
            fi
            if [[ "$project_root" == "/" ]]; then
                exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            else
                exe_common="${project_root%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            fi
            if [[ -r "$exe_common" ]]; then
                SGND_FRAMEWORK_ROOT="$project_root"
                source "$exe_common"
                return 0
            fi
        fi

        exe_common="/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read SolidGroundUX executable common library.\n' >&2
            return 126
        }
        SGND_FRAMEWORK_ROOT="/"
        source "$exe_common"
    }

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Manage Docker Server"
    : "${SGND_SCRIPT_DESC:=Install, configure, validate, and inspect a Docker host.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2625802}"

# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||prepare,install,storage,service,validate,status"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action status"
        "  $SGND_SCRIPT_NAME --dryrun --action storage"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Local declarations --------------------------------------------------------------
    SGND_DOCKER_SERVICE="docker.service"
    SGND_DOCKER_DEFAULT_STORAGE_ROOT="/srv/storage"
    SGND_DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"

    _dryrun_complete() {
        (( ${FLAG_DRYRUN:-0} == 1 )) || return 0
        sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
    }

    _docker_package_installed() {
        dpkg-query -W -f='${Status}' docker.io 2>/dev/null | grep -q '^install ok installed$'
    }

    _docker_command_available() {
        command -v docker >/dev/null 2>&1
    }

    _docker_storage_root() {
        local configured=""
        local storage_cfg="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"

        if [[ -r "$storage_cfg" ]]; then
            configured="$(awk -F= '$1 == "SGND_STORAGE_MOUNTPOINT" {sub(/^[^=]*=/, ""); print; exit}' "$storage_cfg" 2>/dev/null || true)"
        fi
        [[ -n "$configured" ]] || configured="$SGND_DOCKER_DEFAULT_STORAGE_ROOT"
        printf '%s\n' "$configured"
    }

    _docker_current_data_root() {
        local root=""
        if _docker_command_available && systemctl is-active --quiet "$SGND_DOCKER_SERVICE" 2>/dev/null; then
            root="$(sudo docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
        fi
        if [[ -z "$root" && -r "$SGND_DOCKER_DAEMON_CONFIG" ]] && command -v python3 >/dev/null 2>&1; then
            root="$(sudo cat "$SGND_DOCKER_DAEMON_CONFIG" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("data-root", ""))' 2>/dev/null || true)"
        fi
        [[ -n "$root" ]] || root="/var/lib/docker"
        printf '%s\n' "$root"
    }

    _docker_has_workloads() {
        _docker_command_available || return 1
        sudo docker info >/dev/null 2>&1 || return 1
        [[ "$(sudo docker container ls -aq 2>/dev/null | head -n 1)" != "" ]] && return 0
        [[ "$(sudo docker image ls -q 2>/dev/null | head -n 1)" != "" ]] && return 0
        [[ "$(sudo docker volume ls -q 2>/dev/null | head -n 1)" != "" ]] && return 0
        return 1
    }

    _docker_directory_nonempty() {
        local path="$1"
        [[ -d "$path" ]] || return 1
        find "$path" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .
    }

    _docker_write_data_root() {
        local data_root="$1"
        local config_dir=""
        local temp_file=""

        config_dir="$(dirname -- "$SGND_DOCKER_DAEMON_CONFIG")"
        temp_file="$(mktemp "${TMPDIR:-/tmp}/sgnd-docker-daemon.XXXXXX")" || return 1

        if [[ -r "$SGND_DOCKER_DAEMON_CONFIG" ]]; then
            if ! sudo cat "$SGND_DOCKER_DAEMON_CONFIG" | python3 -c '
import json, sys
root = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(2)
data["data-root"] = root
json.dump(data, sys.stdout, indent=2, sort_keys=True)
print()
' "$data_root" > "$temp_file"; then
                rm -f -- "$temp_file"
                sayfail "Existing $SGND_DOCKER_DAEMON_CONFIG is not valid JSON; it was not changed."
                return 1
            fi
        else
            python3 -c '
import json, sys
json.dump({"data-root": sys.argv[1]}, sys.stdout, indent=2, sort_keys=True)
print()
' "$data_root" > "$temp_file" || { rm -f -- "$temp_file"; return 1; }
        fi

        sudo install -d -o root -g root -m 0755 "$config_dir" || { rm -f -- "$temp_file"; return 1; }
        sudo install -o root -g root -m 0644 "$temp_file" "$SGND_DOCKER_DAEMON_CONFIG" || { rm -f -- "$temp_file"; return 1; }
        rm -f -- "$temp_file"
    }

    _docker_select_service_action() {
        local output_var="${1:?missing output variable}"
        local selected=""
        sgnd_print
        sgnd_print_sectionheader "Docker service"
        ask_selection --label "Action" --var selected --items "Start" "Stop" "Restart" "Enable at boot" "Disable at boot" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

# - Host operations ----------------------------------------------------------------
    _docker_install() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would install Docker Engine from the Ubuntu docker.io package."
            return 0
        fi

        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io || return 1
        _docker_command_available || { sayfail "Docker package installed but the docker command is unavailable."; return 1; }
        sayok "Docker Engine installed."
    }

    _docker_start() {
        _docker_command_available || { sayfail "Docker is not installed."; return 1; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would enable and start $SGND_DOCKER_SERVICE."
            return 0
        fi
        sudo systemctl enable --now "$SGND_DOCKER_SERVICE" || return 1
        systemctl is-active --quiet "$SGND_DOCKER_SERVICE" || { sayfail "$SGND_DOCKER_SERVICE is not active."; return 1; }
        sayok "Docker service is active."
    }

    _docker_prepare() {
        _docker_install || return $?
        _docker_start || return $?
        sayok "Docker server preparation completed successfully."
    }

    _docker_configure_storage() {
        local storage_root=""
        local current_root=""
        local target_root=""
        local decision="YES"
        local was_active=0

        command -v python3 >/dev/null 2>&1 || { sayfail "python3 is required to update Docker daemon JSON safely."; return 1; }
        storage_root="$(_docker_storage_root)"
        current_root="$(_docker_current_data_root)"
        target_root="$storage_root/docker"

        sgnd_print
        sgnd_print_sectionheader "Docker storage"
        sgnd_print_labeledvalue --label "Current data root" --value "$current_root" --labelwidth 24
        sgnd_print_labeledvalue --label "Suggested data root" --value "$target_root" --labelwidth 24

        ask --label "Docker data root" --var target_root --default "$target_root" --back || return 0
        [[ "$target_root" == /* && "$target_root" != "/" ]] || { sayfail "Docker data root must be an absolute non-root path."; return 1; }

        if [[ "$current_root" == "$target_root" ]]; then
            sayok "Docker data root is already configured as $target_root."
            return 0
        fi

        if _docker_directory_nonempty "$current_root" && _docker_has_workloads; then
            saywarning "The current Docker data root contains images, volumes, or containers: $current_root"
            saywarning "This first-version tool does not migrate an in-use Docker installation automatically."
            sayfail "Docker storage was not changed. Remove or migrate the existing Docker workloads explicitly before retrying."
            return 1
        fi

        if _docker_directory_nonempty "$target_root"; then
            ask_decision --label "Target directory contains data. Use it anyway" --choices "YES|Y,NO|N" --default "NO" --var decision
            [[ "$decision" == "YES" ]] || return 0
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would create $target_root with root ownership."
            if _docker_directory_nonempty "$current_root"; then
                sayinfo "DRYRUN: Would move the empty-installation Docker daemon state from $current_root to $target_root."
            fi
            sayinfo "DRYRUN: Would set Docker data-root to $target_root in $SGND_DOCKER_DAEMON_CONFIG."
            systemctl is-active --quiet "$SGND_DOCKER_SERVICE" 2>/dev/null \
                && sayinfo "DRYRUN: Would restart $SGND_DOCKER_SERVICE." \
                || true
            return 0
        fi

        systemctl is-active --quiet "$SGND_DOCKER_SERVICE" 2>/dev/null && was_active=1
        (( was_active == 0 )) || sudo systemctl stop "$SGND_DOCKER_SERVICE" || return 1

        sudo install -d -o root -g root -m 0711 "$target_root" || return 1
        if _docker_directory_nonempty "$current_root"; then
            sudo cp -a "$current_root/." "$target_root/" || return 1
        fi
        _docker_write_data_root "$target_root" || return 1

        if (( was_active == 1 )); then
            sudo systemctl start "$SGND_DOCKER_SERVICE" || return 1
            [[ "$(_docker_current_data_root)" == "$target_root" ]] || {
                sayfail "Docker restarted, but the effective data root is not $target_root."
                return 1
            }
        fi

        sayok "Docker data root configured: $target_root"
    }

    _docker_manage_service() {
        local action=""
        _docker_select_service_action action || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would perform Docker service action: $action."
            return 0
        fi

        case "$action" in
            Start) sudo systemctl start "$SGND_DOCKER_SERVICE" ;;
            Stop) sudo systemctl stop "$SGND_DOCKER_SERVICE" ;;
            Restart) sudo systemctl restart "$SGND_DOCKER_SERVICE" ;;
            "Enable at boot") sudo systemctl enable "$SGND_DOCKER_SERVICE" ;;
            "Disable at boot") sudo systemctl disable "$SGND_DOCKER_SERVICE" ;;
        esac
    }

# - Status / validation -------------------------------------------------------------
    _docker_status() {
        local package_state="not installed"
        local package_version="-"
        local service_state="unavailable"
        local enabled_state="No"
        local daemon_state="Unavailable"
        local data_root="-"
        local images=0
        local containers=0
        local running=0

        if _docker_package_installed; then
            package_state="installed"
            package_version="$(dpkg-query -W -f='${Version}' docker.io 2>/dev/null || printf '-')"
        fi
        service_state="$(systemctl is-active "$SGND_DOCKER_SERVICE" 2>/dev/null || true)"
        [[ -n "$service_state" ]] || service_state="inactive"
        systemctl is-enabled --quiet "$SGND_DOCKER_SERVICE" 2>/dev/null && enabled_state="Yes"

        if _docker_command_available && sudo docker info >/dev/null 2>&1; then
            daemon_state="Available"
            data_root="$(sudo docker info --format '{{.DockerRootDir}}' 2>/dev/null || printf '-')"
            images="$(sudo docker image ls -q 2>/dev/null | sort -u | awk 'END {print NR+0}')"
            containers="$(sudo docker container ls -aq 2>/dev/null | awk 'END {print NR+0}')"
            running="$(sudo docker container ls -q 2>/dev/null | awk 'END {print NR+0}')"
        fi

        sgnd_print
        sgnd_print_sectionheader "Docker Server"
        sgnd_print_labeledvalue --label "Package" --value "$package_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Version" --value "$package_version" --labelwidth 22
        sgnd_print_labeledvalue --label "Service" --value "$service_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Enabled at boot" --value "$enabled_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Daemon" --value "$daemon_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Data root" --value "$data_root" --labelwidth 22
        sgnd_print_labeledvalue --label "Images" --value "$images" --labelwidth 22
        sgnd_print_labeledvalue --label "Containers" --value "$containers" --labelwidth 22
        sgnd_print_labeledvalue --label "Running containers" --value "$running" --labelwidth 22
    }

    _docker_validate() {
        local failures=0
        local result=""
        local data_root=""

        sgnd_print
        sgnd_print_sectionheader "Validate Docker Server"

        if _docker_package_installed && _docker_command_available; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Docker package" --value "$result" --labelwidth 24

        if systemctl is-enabled --quiet "$SGND_DOCKER_SERVICE" 2>/dev/null; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Enabled at boot" --value "$result" --labelwidth 24

        if systemctl is-active --quiet "$SGND_DOCKER_SERVICE" 2>/dev/null; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Service active" --value "$result" --labelwidth 24

        if _docker_command_available && sudo docker info >/dev/null 2>&1; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Daemon access" --value "$result" --labelwidth 24

        data_root="$(_docker_current_data_root)"
        if [[ -d "$data_root" && -x "$data_root" ]]; then result="Passed ($data_root)"; else result="Failed ($data_root)"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Docker data root" --value "$result" --labelwidth 24

        sgnd_print
        if (( failures == 0 )); then
            sayok "Docker server validation passed."
            return 0
        fi
        sayfail "$failures Docker server validation check(s) failed."
        return 1
    }

# - Action dispatch ----------------------------------------------------------------
    _run_action() {
        local action="${1:?missing action}" rc=0
        case "$action" in
            prepare)  _docker_prepare || rc=$? ;;
            install)  _docker_install || rc=$? ;;
            storage)  _docker_configure_storage || rc=$? ;;
            service)  _docker_manage_service || rc=$? ;;
            validate) _docker_validate || rc=$? ;;
            status)   _docker_status || rc=$? ;;
            *) sayfail "Unknown Docker server management action: $action"; return 2 ;;
        esac

        if (( rc == 0 )); then
            case "$action" in status|validate) ;; *) _dryrun_complete ;; esac
        fi
        return "$rc"
    }

# - Main ----------------------------------------------------------------------------
    main() {
        local action=""
        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        action="${ACTION:-status}"
        _run_action "$action"
    }

    main "$@"
