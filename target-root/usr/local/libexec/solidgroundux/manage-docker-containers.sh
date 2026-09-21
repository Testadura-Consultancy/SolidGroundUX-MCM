#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - Manage Docker Containers
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626414
#   Source      : manage-docker-containers.sh
#   Type        : script
#   Group       : Console Actions
#   Purpose     : Create and manage Docker containers and images
#
#   Checksum : ad40d436938609f068babde8a6bacf66651da4c13b4252beda916176bf658064
# Description:
#   Provides a deliberately small first-version Docker container manager. It covers
#   the common lifecycle and creation options without attempting to replace Docker
#   Compose or a full container-management product.
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
        #   - Loads sgnd-exe-common.sh from the resolved framework root.
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
    SGND_SCRIPT_TITLE="Manage Docker Containers"
    : "${SGND_SCRIPT_DESC:=Create and manage Docker containers and images.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2625802}"

# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||list,create,start,stop,restart,remove,inspect,logs,images,pull"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action list"
        "  $SGND_SCRIPT_NAME --dryrun --action create"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Helpers ------------------------------------------------------------------------
    _dryrun_complete() {
        (( ${FLAG_DRYRUN:-0} == 1 )) || return 0
        sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
    }

    _docker_require_daemon() {
        command -v docker >/dev/null 2>&1 || { sayfail "Docker is not installed."; return 1; }
        sudo docker info >/dev/null 2>&1 || { sayfail "Docker daemon is unavailable."; return 1; }
    }

    _docker_validate_name() {
        [[ "${1-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
    }

    _docker_trim() {
        local value="${1-}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        printf '%s' "$value"
    }

    _docker_print_command() {
        local part=""
        printf 'DRYRUN: Would run:'
        for part in "$@"; do printf ' %q' "$part"; done
        printf '\n'
    }

    _docker_select_container() {
        local output_var="${1:?missing output variable}"
        local scope="${2:-all}"
        local label="${3:-Select Docker container}"
        local selected=""
        local -a containers=()

        if [[ "$scope" == "running" ]]; then
            mapfile -t containers < <(sudo docker container ls --format '{{.Names}}' 2>/dev/null | LC_ALL=C sort)
        elif [[ "$scope" == "stopped" ]]; then
            mapfile -t containers < <(sudo docker container ls -a --filter status=exited --filter status=created --format '{{.Names}}' 2>/dev/null | LC_ALL=C sort)
        else
            mapfile -t containers < <(sudo docker container ls -a --format '{{.Names}}' 2>/dev/null | LC_ALL=C sort)
        fi

        (( ${#containers[@]} > 0 )) || { saywarning "No matching Docker containers were found."; return 1; }
        sgnd_print
        sgnd_print_sectionheader "$label"
        _docker_ask_selection --label "Container" --var selected --items "${containers[@]}" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    _docker_select_restart_policy() {
        local output_var="${1:?missing output variable}"
        local selected=""
        sgnd_print
        sgnd_print_sectionheader "Container restart policy"
        _docker_ask_selection --label "Policy" --var selected --items "no" "unless-stopped" "always" "on-failure" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    _docker_append_csv_options() {
        local option="$1"
        local csv="$2"
        local array_name="$3"
        local item=""
        local -a parts=()
        local -n target="$array_name"

        [[ -n "$csv" ]] || return 0
        IFS=',' read -r -a parts <<< "$csv"
        for item in "${parts[@]}"; do
            item="$(_docker_trim "$item")"
            [[ -n "$item" ]] || continue
            target+=("$option" "$item")
        done
    }

    # Render a local numbered selector using the Docker action layout.
    # The framework ask_selection API is intentionally left unchanged.
    _docker_ask_selection() {
        local label="Select an option"
        local var_name="selection"
        local input=""
        local i=0
        local -a items=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --label) label="$2"; shift 2 ;;
                --var) var_name="$2"; shift 2 ;;
                --items) shift; items=("$@"); break ;;
                *) return 2 ;;
            esac
        done

        [[ "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
        (( ${#items[@]} > 0 )) || return 2

        sgnd_print
        sgnd_print_sectionheader --text "$label"
        for (( i=0; i<${#items[@]}; i++ )); do
            sgnd_print --text "$((i + 1)). ${items[i]}" --pad 2
        done
        sgnd_print --text "Q. Back" --pad 2
        sgnd_print
        sgnd_print_sectionheader ""

        while :; do
            input=""
            ask --label "Selection" --var input
            input="${input#"${input%%[![:space:]]*}"}"
            input="${input%"${input##*[![:space:]]}"}"
            [[ "${input^^}" == "Q" ]] && return 1
            if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input <= ${#items[@]} )); then
                printf -v "$var_name" '%s' "${items[input - 1]}"
                return 0
            fi
            saywarning "Select 1-${#items[@]} or Q."
        done
    }

# - Read-only actions ---------------------------------------------------------------
    _docker_list_containers() {
        _docker_require_daemon || return 1
        sgnd_print
        sgnd_print_sectionheader "Docker containers"
        sudo docker container ls -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    }

    _docker_list_images() {
        _docker_require_daemon || return 1
        sgnd_print
        sgnd_print_sectionheader "Docker images"
        sudo docker image ls
    }

    _docker_inspect_container() {
        local container=""
        _docker_require_daemon || return 1
        _docker_select_container container all "Inspect Docker container" || return 0
        sudo docker inspect "$container"
    }

    _docker_show_logs() {
        local container=""
        local lines="100"
        _docker_require_daemon || return 1
        _docker_select_container container all "Docker container logs" || return 0
        ask --label "Number of log lines" --var lines --default "$lines" --back || return 0
        [[ "$lines" =~ ^[1-9][0-9]*$ ]] || { sayfail "Log line count must be a positive integer."; return 1; }
        sudo docker logs --tail "$lines" "$container"
    }

# - Mutating actions ---------------------------------------------------------------
    _docker_pull_image() {
        local image=""
        _docker_require_daemon || return 1
        ask --label "Docker image" --var image --default "ubuntu:latest" --back || return 0
        [[ -n "$image" ]] || { sayfail "An image name is required."; return 1; }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            _docker_print_command docker pull "$image"
            return 0
        fi
        sudo docker pull "$image"
    }

    _docker_create_container() {
        local name=""
        local image=""
        local ports=""
        local volumes=""
        local environment=""
        local restart_policy="no"
        local start_now="YES"
        local item=""
        local -a command=(docker)

        _docker_require_daemon || return 1
        ask --label "Container name" --var name --validate _docker_validate_name --back || return 0
        ask --label "Image" --var image --default "ubuntu:latest" --back || return 0
        [[ -n "$image" ]] || { sayfail "An image name is required."; return 1; }

        sudo docker container inspect "$name" >/dev/null 2>&1 && { sayfail "Container already exists: $name"; return 1; }

        ask --label "Published ports (comma separated, e.g. 8080:80)" --var ports --default "" --back || return 0
        ask --label "Volumes (comma separated, e.g. /srv/data:/data)" --var volumes --default "" --back || return 0
        ask --label "Environment variables (comma separated, e.g. MODE=prod)" --var environment --default "" --back || return 0
        _docker_select_restart_policy restart_policy || return 0
        ask_decision --label "Start container after creation" --choices "YES|Y,NO|N" --default "YES" --var start_now

        if [[ "$start_now" == "YES" ]]; then
            command+=(run -d)
        else
            command+=(create)
        fi
        command+=(--name "$name" --restart "$restart_policy")
        _docker_append_csv_options -p "$ports" command
        _docker_append_csv_options -v "$volumes" command
        _docker_append_csv_options -e "$environment" command
        command+=("$image")

        sgnd_print
        sgnd_print_sectionheader "Create Docker container"
        sgnd_print_labeledvalue --label "Name" --value "$name" --labelwidth 22
        sgnd_print_labeledvalue --label "Image" --value "$image" --labelwidth 22
        sgnd_print_labeledvalue --label "Ports" --value "${ports:-None}" --labelwidth 22
        sgnd_print_labeledvalue --label "Volumes" --value "${volumes:-None}" --labelwidth 22
        sgnd_print_labeledvalue --label "Environment" --value "${environment:-None}" --labelwidth 22
        sgnd_print_labeledvalue --label "Restart policy" --value "$restart_policy" --labelwidth 22
        sgnd_print_labeledvalue --label "Start now" --value "$start_now" --labelwidth 22

        ask_decision --label "Create container '$name'" --choices "YES|Y,NO|N" --default "YES" --var start_now
        [[ "$start_now" == "YES" ]] || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            _docker_print_command "${command[@]}"
            return 0
        fi
        sudo "${command[@]}"
    }

    _docker_start_container() {
        local container=""
        _docker_require_daemon || return 1
        _docker_select_container container stopped "Start Docker container" || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then _docker_print_command docker start "$container"; return 0; fi
        sudo docker start "$container" >/dev/null || return 1
        sayok "Container started: $container"
    }

    _docker_stop_container() {
        local container=""
        _docker_require_daemon || return 1
        _docker_select_container container running "Stop Docker container" || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then _docker_print_command docker stop "$container"; return 0; fi
        sudo docker stop "$container" >/dev/null || return 1
        sayok "Container stopped: $container"
    }

    _docker_restart_container() {
        local container=""
        _docker_require_daemon || return 1
        _docker_select_container container running "Restart Docker container" || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then _docker_print_command docker restart "$container"; return 0; fi
        sudo docker restart "$container" >/dev/null || return 1
        sayok "Container restarted: $container"
    }

    _docker_remove_container() {
        local container=""
        local decision="NO"
        _docker_require_daemon || return 1
        _docker_select_container container stopped "Remove Docker container" || return 0
        ask_decision --label "Remove container '$container'" --choices "YES|Y,NO|N" --default "NO" --var decision
        [[ "$decision" == "YES" ]] || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then _docker_print_command docker rm "$container"; return 0; fi
        sudo docker rm "$container" >/dev/null || return 1
        sayok "Container removed: $container"
    }

# - Action dispatch ----------------------------------------------------------------
    _run_action() {
        local action="${1:?missing action}" rc=0
        case "$action" in
            list)    _docker_list_containers || rc=$? ;;
            create)  _docker_create_container || rc=$? ;;
            start)   _docker_start_container || rc=$? ;;
            stop)    _docker_stop_container || rc=$? ;;
            restart) _docker_restart_container || rc=$? ;;
            remove)  _docker_remove_container || rc=$? ;;
            inspect) _docker_inspect_container || rc=$? ;;
            logs)    _docker_show_logs || rc=$? ;;
            images)  _docker_list_images || rc=$? ;;
            pull)    _docker_pull_image || rc=$? ;;
            *) sayfail "Unknown Docker container management action: $action"; return 2 ;;
        esac

        if (( rc == 0 )); then
            case "$action" in list|inspect|logs|images) ;; *) _dryrun_complete ;; esac
        fi
        sgnd_print
        sgnd_print_sectionheader ""
        return "$rc"
    }

# - Main ----------------------------------------------------------------------------
    main() {
        local action=""
        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        action="${ACTION:-list}"
        _run_action "$action"
    }

    main "$@"
