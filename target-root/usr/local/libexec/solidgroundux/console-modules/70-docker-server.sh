# ==================================================================================
# SolidGroundUX Management Console Modules - Docker Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625802
#   Source      : 70-docker-server.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Install, configure, manage, validate, and inspect a Docker host and its containers
#
# Description:
#   Registers Docker host and container-management actions with the SolidGround
#   Management Console. Persistent host operations are implemented by
#   manage-docker-server.sh; container lifecycle operations are implemented by
#   manage-docker-containers.sh.
# ==================================================================================
set -uo pipefail

# - Library guard ------------------------------------------------------------------
    _sgnd_lib_guard() {
        local lib_base="" guard=""
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
    SGND_DOCKER_MODULE_ID="docker-server"
    SGND_DOCKER_MODULE_NAME="Docker Server"
    SGND_DOCKER_MODULE_VERSION="0.1.0"
    SGND_DOCKER_MODULE_DESC="Install, configure, manage, validate, and inspect Docker and its containers"

    SGND_MODULE_ID="$SGND_DOCKER_MODULE_ID"
    SGND_MODULE_NAME="$SGND_DOCKER_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_DOCKER_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_DOCKER_MODULE_DESC"

# - Management dispatch -------------------------------------------------------------
    _docker_run_host() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-docker-server.sh" --action "$action"
    }

    _docker_run_containers() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-docker-containers.sh" --action "$action"
    }

    docker_prepare()             { _docker_run_host prepare; }
    docker_install()             { _docker_run_host install; }
    docker_storage()             { _docker_run_host storage; }
    docker_service()             { _docker_run_host service; }
    docker_validate()            { _docker_run_host validate; }
    docker_status()              { _docker_run_host status; }

    docker_container_list()      { _docker_run_containers list; }
    docker_container_create()    { _docker_run_containers create; }
    docker_container_start()     { _docker_run_containers start; }
    docker_container_stop()      { _docker_run_containers stop; }
    docker_container_restart()   { _docker_run_containers restart; }
    docker_container_remove()    { _docker_run_containers remove; }
    docker_container_inspect()   { _docker_run_containers inspect; }
    docker_container_logs()      { _docker_run_containers logs; }
    docker_image_list()          { _docker_run_containers images; }
    docker_image_pull()          { _docker_run_containers pull; }

# - Console registration ------------------------------------------------------------
    sgnd_menu_register_group \
        "$SGND_DOCKER_MODULE_ID" \
        "Docker Host" \
        "Install, configure, validate, and inspect the Docker host" \
        0 1 700

    sgnd_menu_register_item "docker-prepare" "$SGND_DOCKER_MODULE_ID" "Prepare Docker server" "docker_prepare" "Install Docker, enable the service, and validate the host" 0 15 1 0
    sgnd_menu_register_item "docker-install" "$SGND_DOCKER_MODULE_ID" "Install Docker" "docker_install" "Install the Docker Engine packages" 0 15 1 1
    sgnd_menu_register_item "docker-storage" "$SGND_DOCKER_MODULE_ID" "Configure Docker storage" "docker_storage" "Configure the Docker data root using SolidGroundUX storage" 0 15 1 0
    sgnd_menu_register_item "docker-service" "$SGND_DOCKER_MODULE_ID" "Manage Docker service" "docker_service" "Start, stop, restart, enable, or disable Docker" 0 15 1 0
    sgnd_menu_register_item "docker-validate" "$SGND_DOCKER_MODULE_ID" "Validate Docker server" "docker_validate" "Validate Docker installation, service, daemon access, and storage" 0 15 1 0
    sgnd_menu_register_item "docker-status" "$SGND_DOCKER_MODULE_ID" "Show Docker status" "docker_status" "Show Docker package, service, daemon, storage, image, and container status" 0 15 1 0

    sgnd_menu_register_group \
        "docker-containers" \
        "Containers" \
        "Create and manage Docker containers and images" \
        0 1 710

    sgnd_menu_register_item "docker-container-list" "docker-containers" "List containers" "docker_container_list" "List Docker containers and their current state" 0 15 1 0
    sgnd_menu_register_item "docker-container-create" "docker-containers" "Create container" "docker_container_create" "Create a Docker container from an image" 0 15 1 0
    sgnd_menu_register_item "docker-container-start" "docker-containers" "Start container" "docker_container_start" "Start an existing Docker container" 0 15 1 0
    sgnd_menu_register_item "docker-container-stop" "docker-containers" "Stop container" "docker_container_stop" "Stop a running Docker container" 0 15 1 0
    sgnd_menu_register_item "docker-container-restart" "docker-containers" "Restart container" "docker_container_restart" "Restart a Docker container" 0 15 1 0
    sgnd_menu_register_item "docker-container-remove" "docker-containers" "Remove container" "docker_container_remove" "Remove a stopped Docker container" 0 15 1 0
    sgnd_menu_register_item "docker-container-inspect" "docker-containers" "Inspect container" "docker_container_inspect" "Show Docker container configuration and runtime details" 0 15 1 0
    sgnd_menu_register_item "docker-container-logs" "docker-containers" "Show container logs" "docker_container_logs" "Show recent Docker container logs" 0 15 1 0
    sgnd_menu_register_item "docker-image-list" "docker-containers" "List images" "docker_image_list" "List locally available Docker images" 0 15 1 0
    sgnd_menu_register_item "docker-image-pull" "docker-containers" "Pull image" "docker_image_pull" "Pull a Docker image from a registry" 0 15 1 0

    sayinfo "Docker Server module registered with the console."
