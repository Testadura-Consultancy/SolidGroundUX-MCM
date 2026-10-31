# ==================================================================================
# SolidGroundUX Management Console Modules - Web Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2630201
#   Shortname   : WEB_SERVER
#   Source      : 50-web-server.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Install, configure, manage, validate, and inspect an Nginx web server
#
#   Checksum : cfa3271091a0bcaaabd13b31bd838228b39f6ddc5c2dba860f6f3492e7c67e40
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
        #   ```bash
        #   _sgnd_lib_guard
        #   ```
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
    # fn: _web_run_manage - Run manage in the web server workflow.
    _web_run_manage() { local action="${1:?missing action}"; _sgnd_run_module_script "manage-web-server.sh" --action "$action"; }
    # fn: _web_run_publish - Run publish in the web server workflow.
    _web_run_publish() { local action="${1:?missing action}"; _sgnd_run_module_script "publish-web-content.sh" --action "$action"; }

    # fn: _web_record_prepare_step - Persist one child-step result in the console tracker
        # . Arguments
        #   $1 ITEM_KEY
        #   $2 RESULT_CODE
        #
        # . Returns
        #   0 always; tracking is best-effort when the console tracker is unavailable.
        #
        # . Usage
        #   ```bash
        #   _web_record_prepare_step "web-install" 0
        #   ```
    _web_record_prepare_step() {
        local item_key="${1:?missing item key}"
        local result_code="${2:-0}"

        if declare -F sgnd_console_record_action_result >/dev/null 2>&1; then
            sgnd_console_record_action_result "$item_key" "$result_code" || true
        fi
        return 0
    }

    # fn: web_prepare - Run Web Server preparation and synchronize child menu statuses
        # . Purpose
        #   Keep the compound preparation workflow inside the management executable while
        #   mapping its workflow return code onto the registered child actions.
        #
        # . Behavior
        #   - Marks Install Nginx successful when installation completes.
        #   - Marks Start web service successful when startup completes.
        #   - Marks the failing child action failed and leaves later work untouched.
        #
        # . Returns
        #   0 when preparation succeeds; otherwise the workflow failure code returned by
        #   manage-web-server.sh.
        #
        # . Usage
        #   ```bash
        #   web_prepare
        #   ```
    web_prepare() {
        local rc=0

        _web_run_manage prepare || rc=$?

        case "$rc" in
            0)
                _web_record_prepare_step "web-install" 0
                _web_record_prepare_step "web-start" 0
                return 0
                ;;
            41)
                _web_record_prepare_step "web-install" 1
                ;;
            42)
                _web_record_prepare_step "web-install" 0
                _web_record_prepare_step "web-start" 1
                ;;
            *)
                sayfail "Web Server preparation workflow returned unexpected status: $rc"
                ;;
        esac

        return "$rc"
    }
    # fn: web_install - Call `_web_run_manage` with the `install` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_install
        #   ```
    web_install()                 { _web_run_manage install; }
    # fn: web_start - Call `_web_run_manage` with the `start` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_start
        #   ```
    web_start()                   { _web_run_manage start; }
    # fn: web_configure_root - Call `_web_run_manage` with the `configure-root` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_configure_root
        #   ```
    web_configure_root()          { _web_run_manage configure-root; }
    # fn: web_manage_sites - Call `_web_run_manage` with the `manage-sites` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_manage_sites
        #   ```
    web_manage_sites()            { _web_run_manage manage-sites; }
    # fn: web_configure_default - Call `_web_run_manage` with the `configure-default` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_configure_default
        #   ```
    web_configure_default()       { _web_run_manage configure-default; }
    # fn: web_publish - Call `_web_run_publish` with the `publish-site` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_publish
        #   ```
    web_publish()                 { _web_run_publish publish-site; }
    # fn: web_doc_configure - Call `_web_run_manage` with the `configure-documentation` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_doc_configure
        #   ```
    web_doc_configure()           { _web_run_manage configure-documentation; }
    # fn: web_doc_publish - Call `_web_run_publish` with the `publish-documentation` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_doc_publish
        #   ```
    web_doc_publish()             { _web_run_publish publish-documentation; }
    # fn: web_doc_status - Call `_web_run_manage` with the `documentation-status` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_doc_status
        #   ```
    web_doc_status()              { _web_run_manage documentation-status; }
    # fn: web_service_manage - Call `_web_run_manage` with the `service` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_service_manage
        #   ```
    web_service_manage()          { _web_run_manage service; }
    # fn: web_firewall - Call `_web_run_manage` with the `firewall` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_firewall
        #   ```
    web_firewall()                { _web_run_manage firewall; }
    # fn: web_validate - Call `_web_run_manage` with the `validate` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_validate
        #   ```
    web_validate()                { _web_run_manage validate; }
    # fn: web_status - Call `_web_run_manage` with the `status` action.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_status
        #   ```
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
    # fn: validate_module_web_server - Validate the web server module and record its status for the console.
        #
        # . Returns
        #   A console validation status (0=pass, 1=fail, 2=warning, 3=skipped).
        #
        # . Usage
        #   ```bash
        #   validate_module_web_server
        #   ```
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
    sgnd_menu_register_group "web-service" "Service" "Nginx service, firewall, validation, and status" 0 1 510

    sgnd_menu_register_item "web-prepare" "$SGND_WEB_SERVER_MODULE_ID" "Prepare web server" "web_prepare" "Install, validate, enable, and start Nginx" 0 15 1 0
    sgnd_menu_register_item "web-install" "$SGND_WEB_SERVER_MODULE_ID" "Install Nginx" "web_install" "Install Nginx and basic web-server utilities" 0 0 1 1
    sgnd_menu_register_item "web-start" "$SGND_WEB_SERVER_MODULE_ID" "Start web service" "web_start" "Enable and start nginx.service" 0 0 1 1
    sgnd_menu_register_item "web-root" "$SGND_WEB_SERVER_MODULE_ID" "Configure web content root" "web_configure_root" "Select or create the storage location used for web content" 0 15 1 0
    sgnd_menu_register_item "web-default" "$SGND_WEB_SERVER_MODULE_ID" "Protect unknown hostnames" "web_configure_default" "Reject unknown HTTP hosts and HTTPS SNI without serving another site" 0 15 1 0
    sgnd_menu_register_item "web-sites" "$SGND_WEB_SERVER_MODULE_ID" "Manage sites" "web_manage_sites" "Select and manage Nginx sites, settings, content, and DNS records" 0 15 1 0

    sgnd_menu_register_item "web-service-manage" "web-service" "Manage web service" "web_service_manage" "Start, stop, restart, enable, or disable nginx.service" 0 15 1 0
    sgnd_menu_register_item "web-firewall" "web-service" "Configure web firewall" "web_firewall" "Allow HTTP and HTTPS through UFW" 0 15 1 0
    sgnd_menu_register_item "web-validate" "web-service" "Validate web server" "web_validate" "Validate package, configuration, service, listeners, and web root" 0 15 1 0
    sgnd_menu_register_item "web-status" "web-service" "Show web-server status" "web_status" "Show package, service, storage, listener, and site status" 0 15 1 0

    sayinfo "Web Server module registered with the console."
