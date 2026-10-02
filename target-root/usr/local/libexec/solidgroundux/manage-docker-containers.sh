#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - Manage Docker Containers
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627515
#   Shortname   : MANAGE_DOCKER_CONTAINERS
#   Source      : manage-docker-containers.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Create and manage Docker containers and images
#
#   Checksum : 61d4d99666b4f81ba0af9e17c3c94d3f04d2ab6130fdde58fea53778b8df4b09
# Description:
#   Provides guided Docker image discovery, image pulling, container creation, and
#   common lifecycle operations without attempting to replace Docker Compose or a
#   full container-management product. Docker Hub search/tag discovery is offered
#   as the friendly default, with manual image references retained as a fallback.
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
        "action|a|enum|ACTION|Management action||list,create,start,stop,restart,shell,remove,inspect,logs,images,pull"
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
        local quoted=""
        local rendered="DRYRUN: Would run:"
        for part in "$@"; do
            printf -v quoted '%q' "$part"
            rendered+=" $quoted"
        done
        sayinfo "$rendered"
    }

    _docker_validate_port() {
        local value="${1-}"
        [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 65535 ))
    }

    _docker_validate_absolute_path() {
        local value="${1-}"
        [[ "$value" == /* && "$value" != "/" && "$value" != *$'\n'* ]]
    }

    _docker_validate_env_name() {
        [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
    }

    # Select a value while presenting a richer display label for each choice.
    # When a details array is supplied, render each choice as a labeled multi-value row so
    # long descriptive text wraps in the value column instead of being clipped.
    _docker_select_labeled_value() {
        local output_var="${1:?missing output variable}"
        local label="${2:-Select an option}"
        local values_name="${3:?missing values array}"
        local labels_name="${4:?missing labels array}"
        local details_name="${5-}"
        local input=""
        local i=0
        local -n values_ref="$values_name"
        local -n labels_ref="$labels_name"

        (( ${#values_ref[@]} > 0 && ${#values_ref[@]} == ${#labels_ref[@]} )) || return 2

        sgnd_print
        sgnd_print_sectionheader --text "$label"
        if [[ -n "$details_name" ]]; then
            local -n details_ref="$details_name"
            (( ${#details_ref[@]} == ${#values_ref[@]} )) || return 2
            for (( i=0; i<${#labels_ref[@]}; i++ )); do
                sgnd_print_labeledmultivalue \
                    --label "$((i + 1)). ${labels_ref[i]}" \
                    --value "${details_ref[i]}" \
                    --labelwidth 36 \
                    --pad 2
            done
        else
            for (( i=0; i<${#labels_ref[@]}; i++ )); do
                sgnd_print --text "$((i + 1)). ${labels_ref[i]}" --pad 2
            done
        fi
        sgnd_print --text "Q. Back" --pad 2
        sgnd_print
        sgnd_print_sectionheader ""

        while :; do
            input=""
            ask --label "Selection" --var input
            input="${input#"${input%%[![:space:]]*}"}"
            input="${input%"${input##*[![:space:]]}"}"
            [[ "${input^^}" == "Q" ]] && return 1
            if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input <= ${#values_ref[@]} )); then
                printf -v "$output_var" '%s' "${values_ref[input - 1]}"
                return 0
            fi
            saywarning "Select 1-${#values_ref[@]} or Q."
        done
    }

    _docker_select_container() {
        local output_var="${1:?missing output variable}"
        local scope="${2:-all}"
        local label="${3:-Select Docker container}"
        local name=""
        local image=""
        local status=""
        local -a docker_args=(container ls -a)
        local -a values=()
        local -a labels=()

        case "$scope" in
            running) docker_args+=(--filter status=running) ;;
            stopped) docker_args+=(--filter status=exited --filter status=created) ;;
        esac
        docker_args+=(--format $'{{.Names}}\t{{.Image}}\t{{.Status}}')

        while IFS=$'\t' read -r name image status; do
            [[ -n "$name" ]] || continue
            values+=("$name")
            labels+=("$name  |  $image  |  $status")
        done < <(sudo docker "${docker_args[@]}" 2>/dev/null | LC_ALL=C sort)

        (( ${#values[@]} > 0 )) || { saywarning "No matching Docker containers were found."; return 1; }
        _docker_select_labeled_value "$output_var" "$label" values labels
    }

    # Select a locally available image without reusing the caller's output variable name
    # locally; Bash dynamic scoping would otherwise swallow the selected image value.
    _docker_select_local_image() {
        local output_var="${1:?missing output variable}"
        local image_ref=""
        local id=""
        local size=""
        local -a values=()
        local -a labels=()

        while IFS=$'\t' read -r image_ref id size; do
            [[ -n "$image_ref" && "$image_ref" != *'<none>'* ]] || continue
            values+=("$image_ref")
            labels+=("$image_ref  |  ${id:0:12}  |  $size")
        done < <(sudo docker image ls --format $'{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' 2>/dev/null | LC_ALL=C sort -u)

        if (( ${#values[@]} == 0 )); then
            saywarning "No local Docker images are available. Pull an image before creating a container."
            return 1
        fi

        _docker_select_labeled_value "$output_var" "Select Docker image" values labels
    }

    _docker_search_hub_repository() {
        local output_var="${1:?missing output variable}"
        local search_term=""
        local name=""
        local description=""
        local stars=""
        local official=""
        local official_label=""
        local -a values=()
        local -a labels=()
        local -a details=()

        ask --label "Docker Hub search" --var search_term --back || return 1
        search_term="$(_docker_trim "$search_term")"
        [[ -n "$search_term" ]] || { saywarning "Enter a search term."; return 1; }

        while IFS=$'\t' read -r name description stars official; do
            [[ -n "$name" ]] || continue
            official_label=""
            case "${official,,}" in
                true|yes|ok|"[ok]"|"[official]") official_label=" [Official]" ;;
            esac
            description="$(_docker_trim "$description")"
            values+=("$name")
            labels+=("$name$official_label")
            details+=("${stars:-0} stars | $description")
        done < <(sudo docker search --limit 25 --format $'{{.Name}}\t{{.Description}}\t{{.StarCount}}\t{{.IsOfficial}}' "$search_term" 2>/dev/null)

        if (( ${#values[@]} == 0 )); then
            saywarning "Docker Hub returned no repositories for '$search_term'."
            return 1
        fi

        _docker_select_labeled_value "$output_var" "Select Docker Hub repository" values labels details
    }

    _docker_list_hub_tags() {
        local repository="${1:?missing repository}"
        command -v python3 >/dev/null 2>&1 || return 1

        # Docker Hub's registry requires a repository-scoped bearer token even for
        # public repositories. Obtain the anonymous pull token, then enumerate tags
        # through the Registry HTTP API V2 rather than relying on undocumented Hub URLs.
        python3 - "$repository" <<'PYTAG'
import json
import sys
import urllib.parse
import urllib.request

repository = sys.argv[1]
if "/" not in repository:
    repository = "library/" + repository

token_query = urllib.parse.urlencode({
    "service": "registry.docker.io",
    "scope": f"repository:{repository}:pull",
})
token_request = urllib.request.Request(
    "https://auth.docker.io/token?" + token_query,
    headers={"User-Agent": "SolidGroundUX/2.1"},
)
with urllib.request.urlopen(token_request, timeout=12) as response:
    token_payload = json.load(response)
token = token_payload.get("token") or token_payload.get("access_token")
if not token:
    raise SystemExit(1)

tags_request = urllib.request.Request(
    "https://registry-1.docker.io/v2/"
    + urllib.parse.quote(repository, safe="/")
    + "/tags/list?n=1000",
    headers={
        "Authorization": "Bearer " + token,
        "User-Agent": "SolidGroundUX/2.1",
    },
)
with urllib.request.urlopen(tags_request, timeout=12) as response:
    payload = json.load(response)

tags = sorted({str(tag).strip() for tag in (payload.get("tags") or []) if str(tag).strip()}, reverse=True)
if "latest" in tags:
    print("latest")
    tags.remove("latest")
for tag in tags[:49]:
    print(tag)
PYTAG
    }

    _docker_select_hub_tag() {
        local output_var="${1:?missing output variable}"
        local repository="${2:?missing repository}"
        local selected_tag=""
        local fallback="latest"
        local -a tags=()
        local -a labels=()

        mapfile -t tags < <(_docker_list_hub_tags "$repository" 2>/dev/null || true)
        if (( ${#tags[@]} > 0 )); then
            labels=("${tags[@]}")
            tags+=("__MANUAL__")
            labels+=("Enter tag manually")
            _docker_select_labeled_value selected_tag "Select image tag" tags labels || return 1
            if [[ "$selected_tag" != "__MANUAL__" ]]; then
                printf -v "$output_var" '%s' "$selected_tag"
                return 0
            fi
        else
            saywarning "Docker Hub tags could not be retrieved for $repository."
        fi

        ask --label "Image tag" --var fallback --default "$fallback" --back || return 1
        fallback="$(_docker_trim "$fallback")"
        [[ -n "$fallback" ]] || { sayfail "An image tag is required."; return 1; }
        printf -v "$output_var" '%s' "$fallback"
    }

    _docker_select_restart_policy() {
        local output_var="${1:?missing output variable}"
        local selected=""
        _docker_ask_selection --label "Container restart policy" --var selected --items "no" "unless-stopped" "always" "on-failure" || return 1
        printf -v "$output_var" '%s' "$selected"
    }

    _docker_collect_port_mappings() {
        local array_name="${1:?missing command array}"
        local summary_var="${2:?missing summary variable}"
        local decision="No"
        local host_port=""
        local container_port=""
        local protocol="TCP"
        local mapping=""
        local summary=""
        local -n command_ref="$array_name"

        ask_decision --label "Publish container ports" --choices "Yes|Y,No|N" --default "No" --var decision || return $?
        while [[ "${decision^^}" == "YES" ]]; do
            ask --label "Host port" --var host_port --validate _docker_validate_port --back || return 1
            ask --label "Container port" --var container_port --validate _docker_validate_port --back || return 1
            ask_decision --label "Protocol" --choices "TCP|T,UDP|U" --default "TCP" --var protocol || return $?
            mapping="$host_port:$container_port/${protocol,,}"
            command_ref+=(-p "$mapping")
            [[ -z "$summary" ]] || summary+=", "
            summary+="$mapping"
            ask_decision --label "Add another port mapping" --choices "Yes|Y,No|N" --default "No" --var decision || return $?
        done
        printf -v "$summary_var" '%s' "${summary:-None}"
    }

    _docker_collect_volume_mappings() {
        local array_name="${1:?missing command array}"
        local summary_var="${2:?missing summary variable}"
        local decision="No"
        local host_path=""
        local container_path=""
        local read_only="No"
        local mapping=""
        local summary=""
        local -n command_ref="$array_name"

        ask_decision --label "Add persistent host storage" --choices "Yes|Y,No|N" --default "No" --var decision || return $?
        while [[ "${decision^^}" == "YES" ]]; do
            ask --label "Host path" --var host_path --validate _docker_validate_absolute_path --back || return 1
            ask --label "Container path" --var container_path --validate _docker_validate_absolute_path --back || return 1
            ask_decision --label "Read-only inside container" --choices "Yes|Y,No|N" --default "No" --var read_only || return $?
            mapping="$host_path:$container_path"
            [[ "${read_only^^}" == "YES" ]] && mapping+=":ro"
            command_ref+=(-v "$mapping")
            [[ -z "$summary" ]] || summary+=", "
            summary+="$mapping"
            ask_decision --label "Add another persistent volume" --choices "Yes|Y,No|N" --default "No" --var decision || return $?
        done
        printf -v "$summary_var" '%s' "${summary:-None}"
    }

    # Collect one or more user-defined container environment variables.
    # Keep the prompt receiver names distinct from generic framework-local names so
    # Bash dynamic scoping cannot swallow values before they are added to docker -e.
    _docker_collect_environment() {
        local array_name="${1:?missing command array}"
        local summary_var="${2:?missing summary variable}"
        local decision="No"
        local env_name=""
        local env_value=""
        local summary=""
        local -n command_ref="$array_name"

        ask_decision --label "Add environment variables" --choices "Yes|Y,No|N" --default "No" --var decision || return $?
        while [[ "${decision^^}" == "YES" ]]; do
            env_name=""
            env_value=""
            ask --label "Variable name" --var env_name --validate _docker_validate_env_name --back || return 1
            ask --label "Variable value" --var env_value --default "" --back || return 1
            command_ref+=(-e "$env_name=$env_value")
            [[ -z "$summary" ]] || summary+=", "
            summary+="$env_name=<set>"
            ask_decision --label "Add another environment variable" --choices "Yes|Y,No|N" --default "No" --var decision || return $?
        done
        printf -v "$summary_var" '%s' "${summary:-None}"
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
        local mode=""
        local repository=""
        local tag=""
        local image=""

        _docker_require_daemon || return 1
        _docker_ask_selection \
            --label "Pull Docker image" \
            --var mode \
            --items "Search Docker Hub" "Enter image reference manually" || return 0

        case "$mode" in
            "Search Docker Hub")
                _docker_search_hub_repository repository || return 0
                _docker_select_hub_tag tag "$repository" || return 0
                image="$repository:$tag"
                ;;
            "Enter image reference manually")
                ask --label "Image reference" --var image --default "ubuntu:latest" --back || return 0
                image="$(_docker_trim "$image")"
                [[ -n "$image" ]] || { sayfail "An image reference is required."; return 1; }
                ;;
        esac

        sgnd_print
        sgnd_print_sectionheader "Pull Docker image"
        sgnd_print_labeledvalue --label "Image" --value "$image" --labelwidth 20

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            _docker_print_command docker pull "$image"
            return 0
        fi
        sudo docker pull "$image" || return 1
        sayok "Docker image available locally: $image"
    }

    _docker_create_container() {
        local name=""
        local image=""
        local suggested_name=""
        local ports_summary="None"
        local volumes_summary="None"
        local environment_summary="None"
        local restart_policy="no"
        local start_now="Yes"
        local decision="Yes"
        local container_command=""
        local -a command_args=()
        local -a options=()
        local -a command=()

        _docker_require_daemon || return 1
        _docker_select_local_image image || return 0

        suggested_name="${image##*/}"
        suggested_name="${suggested_name%%:*}"
        suggested_name="${suggested_name//[^A-Za-z0-9_.-]/-}"
        [[ -n "$suggested_name" ]] || suggested_name="container"

        ask --label "Container name" --var name --default "$suggested_name" --validate _docker_validate_name --back || return 0
        sudo docker container inspect "$name" >/dev/null 2>&1 && { sayfail "Container already exists: $name"; return 1; }

        options+=(--name "$name")
        _docker_collect_port_mappings options ports_summary || return 0
        _docker_collect_volume_mappings options volumes_summary || return 0
        _docker_collect_environment options environment_summary || return 0
        _docker_select_restart_policy restart_policy || return 0

        # An image may define its own default command (for example nginx), while a
        # general-purpose image such as Ubuntu normally needs an explicit long-running
        # process when it is intended to remain active. Leave this empty to use the
        # image default. Arguments are entered as a simple space-separated command.
        ask --label "Container command (optional)" --var container_command --default "" --back || return 0
        container_command="$(_docker_trim "$container_command")"
        if [[ -n "$container_command" ]]; then
            read -r -a command_args <<< "$container_command"
        fi

        ask_decision --label "Start container after creation" --choices "Yes|Y,No|N" --default "Yes" --var start_now || return 0
        options+=(--restart "$restart_policy")

        if [[ "${start_now^^}" == "YES" ]]; then
            command=(docker run -d "${options[@]}" "$image" "${command_args[@]}")
        else
            command=(docker create "${options[@]}" "$image" "${command_args[@]}")
        fi

        sgnd_print
        sgnd_print_sectionheader "Create Docker container"
        sgnd_print_labeledvalue --label "Name" --value "$name" --labelwidth 22
        sgnd_print_labeledvalue --label "Image" --value "$image" --labelwidth 22
        sgnd_print_labeledvalue --label "Ports" --value "$ports_summary" --labelwidth 22
        sgnd_print_labeledvalue --label "Volumes" --value "$volumes_summary" --labelwidth 22
        sgnd_print_labeledvalue --label "Environment" --value "$environment_summary" --labelwidth 22
        sgnd_print_labeledvalue --label "Restart policy" --value "$restart_policy" --labelwidth 22
        sgnd_print_labeledvalue --label "Command" --value "${container_command:-Image default}" --labelwidth 22
        sgnd_print_labeledvalue --label "Start now" --value "$start_now" --labelwidth 22

        ask_decision --label "Create container '$name'" --choices "Yes|Y,No|N" --default "Yes" --var decision || return 0
        [[ "${decision^^}" == "YES" ]] || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            _docker_print_command "${command[@]}"
            return 0
        fi
        sudo "${command[@]}" || return 1
        sayok "Container created: $name"
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

    # fn: _docker_open_container_shell - Open an interactive shell in a running container
        # . Purpose
        #   Let an operator enter a running container without having to remember docker exec syntax.
        #
        # . Behavior
        #   - Selects only running containers.
        #   - Prefers /bin/bash when present and falls back to /bin/sh.
        #   - Reports a clear failure when the container image provides neither shell.
        #   - Honors console dry-run mode.
    _docker_open_container_shell() {
        local container=""
        local shell_path=""

        _docker_require_daemon || return 1
        _docker_select_container container running "Open Docker container shell" || return 0

        if sudo docker exec "$container" /bin/bash -c 'exit 0' >/dev/null 2>&1; then
            shell_path="/bin/bash"
        elif sudo docker exec "$container" /bin/sh -c 'exit 0' >/dev/null 2>&1; then
            shell_path="/bin/sh"
        else
            sayfail "Container '$container' does not provide /bin/bash or /bin/sh."
            return 1
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            _docker_print_command docker exec -it "$container" "$shell_path"
            return 0
        fi

        sayinfo "Opening $shell_path in container: $container"
        sudo docker exec -it "$container" "$shell_path"
    }

    _docker_remove_container() {
        local container=""
        local decision="No"
        _docker_require_daemon || return 1
        _docker_select_container container stopped "Remove Docker container" || return 0
        ask_decision --label "Remove container '$container'" --choices "Yes|Y,No|N" --default "No" --var decision
        [[ "${decision^^}" == "YES" ]] || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then _docker_print_command docker rm "$container"; return 0; fi
        sudo docker rm "$container" >/dev/null || return 1
        sayok "Container removed: $container"
    }

    # fn: _docker_action_again - Offer to repeat a completed interactive Docker action
        # . Purpose
        #   Give repeatable Docker management actions the standard SolidGroundUX
        #   do-another/return interaction instead of ending at the generic executable pause.
        #
        # . Behavior
        #   - Enter returns to the Management Console and is the automatic/default path.
        #   - A repeats the same Docker action.
        #   - P/Space pauses the automatic return countdown.
        #
        # . Returns
        #   0 only when the operator selected A (do another); otherwise non-zero.
    _docker_action_again() {
        local rc=0

        sgnd_print
        sgnd_print_sectionheader "Do another"

        ask_dlg_autocontinue \
            --seconds 5 \
            --message "Repeat this Docker action?" \
            --again \
            --pause \
            --legend "Enter=return to menu; A=do another; P/Space=pause"
        rc=$?

        (( rc == 3 ))
    }

    # fn: _docker_return_to_menu - Offer the standard automatic return for read-only actions
        # . Purpose
        #   Let read-only Docker actions end naturally without offering a redundant repeat option.
        #
        # . Behavior
        #   - Enter returns to the Management Console immediately.
        #   - P/Space pauses the automatic return countdown.
    _docker_return_to_menu() {
        sgnd_print
        ask_dlg_autocontinue \
            --seconds 5 \
            --pause \
            --legend "Enter=return to menu; P/Space=pause" || true
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
            shell)   _docker_open_container_shell || rc=$? ;;
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
        local rc=0

        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        action="${ACTION:-list}"

        while :; do
            rc=0
            _run_action "$action" || rc=$?
            (( rc == 0 )) || return "$rc"

            case "$action" in
                list|images)
                    _docker_return_to_menu
                    break
                    ;;
                *)
                    if _docker_action_again; then
                        continue
                    fi
                    break
                    ;;
            esac
        done

        return 0
    }

    main "$@"
