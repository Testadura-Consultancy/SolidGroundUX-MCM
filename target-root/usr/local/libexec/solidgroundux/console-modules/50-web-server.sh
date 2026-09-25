# ==================================================================================
# SolidGroundUX Management Console Modules - Web Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626711
#   Source      : 50-web-server.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Install, configure, manage, validate, and inspect an Nginx web server
#
#   Checksum : e64ce7c995b4d62adce3c7959000da90b76497c67a6bfd74e6c87606a7a27723
# Description:
#   Registers Nginx host, site, publishing, documentation, service, validation, and
#   status actions with the SolidGround Management Console. Persistent operations are
#   implemented by manage-web-server.sh and publish-web-content.sh.
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
    SGND_WEB_SERVER_MODULE_ID="web-server"
    SGND_WEB_SERVER_MODULE_NAME="Web Server"
    SGND_MODULE_ID="$SGND_WEB_SERVER_MODULE_ID"
    SGND_MODULE_NAME="$SGND_WEB_SERVER_MODULE_NAME"
# - Management dispatch -------------------------------------------------------------
    _web_run_manage() { local action="${1:?missing action}"; _sgnd_run_module_script "manage-web-server.sh" --action "$action"; }
    _web_run_publish() { local action="${1:?missing action}"; _sgnd_run_module_script "publish-web-content.sh" --action "$action"; }

    web_prepare() {
        local rc=0

        if _web_run_manage install; then
            sgnd_menu_set_item_status "web-install" "success"
        else
            rc=$?
            sgnd_menu_set_item_status "web-install" "failed"
            sgnd_menu_set_item_status "web-start" "never"
            return "$rc"
        fi

        if _web_run_manage start; then
            sgnd_menu_set_item_status "web-start" "success"
        else
            rc=$?
            sgnd_menu_set_item_status "web-start" "failed"
            return "$rc"
        fi

        return 0
    }
    web_install()                 { _web_run_manage install; }
    web_start()                   { _web_run_manage start; }
    web_configure_root()          { _web_run_manage configure-root; }
    web_manage_sites()            { _web_run_manage manage-sites; }
    web_publish()                 { _web_run_publish publish-site; }
    web_doc_configure()           { _web_run_manage configure-documentation; }
    web_doc_publish()             { _web_run_publish publish-documentation; }
    web_doc_status()              { _web_run_manage documentation-status; }
    web_service_manage()          { _web_run_manage service; }
    web_firewall()                { _web_run_manage firewall; }
    web_validate()                { _web_run_manage validate; }
    web_status()                  { _web_run_manage status; }

# - Module validation contract ------------------------------------------------------
    # Return codes:
    #   0 = Passed
    #   1 = Failed
    #   2 = Warning
    #   3 = Skipped / not applicable
    #
    # Every validator sets SGND_MODULE_VALIDATION_MESSAGE to a concise result summary.
    # Detailed diagnostic output may be written by the validator or delegated action.
    validate_module_web_server() {
        if ! command -v nginx >/dev/null 2>&1; then
            SGND_MODULE_VALIDATION_MESSAGE="nginx is not installed on this host."
            return 3
        fi
        if web_validate; then
            SGND_MODULE_VALIDATION_MESSAGE="Web-server validation passed."
            return 0
        fi
        SGND_MODULE_VALIDATION_MESSAGE="Web-server validation reported one or more failures."
        return 1
    }

# - Console registration ------------------------------------------------------------
    sgnd_menu_register_group "$SGND_WEB_SERVER_MODULE_ID" "General" "General Nginx host and site management" 0 1 500
    sgnd_menu_register_group "web-documentation" "SolidGroundUX Documentation" "Configure and publish the documentation delivered with SolidGroundUX" 0 1 510
    sgnd_menu_register_group "web-service" "Service" "Nginx service, firewall, validation, and status" 0 1 520

    sgnd_menu_register_item "web-prepare" "$SGND_WEB_SERVER_MODULE_ID" "Prepare web server" "web_prepare" "Install, validate, enable, and start Nginx" 0 15 1 0
    sgnd_menu_register_item "web-install" "$SGND_WEB_SERVER_MODULE_ID" "Install Nginx" "web_install" "Install Nginx and basic web-server utilities" 0 0 1 1
    sgnd_menu_register_item "web-start" "$SGND_WEB_SERVER_MODULE_ID" "Start web service" "web_start" "Enable and start nginx.service" 0 0 1 1
    sgnd_menu_register_item "web-root" "$SGND_WEB_SERVER_MODULE_ID" "Configure web content root" "web_configure_root" "Select or create the storage location used for web content" 0 15 1 0
    sgnd_menu_register_item "web-sites" "$SGND_WEB_SERVER_MODULE_ID" "Manage sites" "web_manage_sites" "Create, enable, disable, change document roots, remove, clear content from, and list Nginx sites" 0 15 1 0
    sgnd_menu_register_item "web-publish" "$SGND_WEB_SERVER_MODULE_ID" "Publish web content" "web_publish" "Publish a local, remote, or Git repository source into an Nginx site" 0 15 1 0

    sgnd_menu_register_item "web-doc-configure" "web-documentation" "Configure documentation site" "web_doc_configure" "Create or select the Nginx site used for SolidGroundUX documentation" 0 15 1 0
    sgnd_menu_register_item "web-doc-publish" "web-documentation" "Publish SolidGroundUX documentation" "web_doc_publish" "Publish installed, local, remote, or Git repository documentation content" 0 15 1 0
    sgnd_menu_register_item "web-doc-status" "web-documentation" "Show documentation status" "web_doc_status" "Show documentation site and source configuration" 0 15 1 0

    sgnd_menu_register_item "web-service-manage" "web-service" "Manage web service" "web_service_manage" "Start, stop, restart, enable, or disable nginx.service" 0 15 1 0
    sgnd_menu_register_item "web-firewall" "web-service" "Configure web firewall" "web_firewall" "Allow HTTP and HTTPS through UFW" 0 15 1 0
    sgnd_menu_register_item "web-validate" "web-service" "Validate web server" "web_validate" "Validate package, configuration, service, listeners, and web root" 0 15 1 0
    sgnd_menu_register_item "web-status" "web-service" "Show web-server status" "web_status" "Show package, service, storage, listener, and site status" 0 15 1 0

    sayinfo "Web Server module registered with the console."
