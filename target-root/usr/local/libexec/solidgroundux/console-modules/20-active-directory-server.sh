# ==================================================================================
# SolidGroundUX Management Console Modules - Active Directory Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2629401
#   Shortname   : AD_SERVER
#   Checksum    : 93a65cd489767064bf18f1b69d4d1614ec3e4c40368f529b4a448153c82c2a72
#   Source      : 20-active-directory-server.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Register Samba Active Directory server management actions
#
# Description:
#   Registers Active Directory server management actions with the SolidGround Management
#   Console. Persistent provisioning and validation are implemented by
#   manage-active-directory-server.sh.
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
    SGND_AD_SERVER_MODULE_ID="active-directory-server"
    SGND_AD_SERVER_MODULE_NAME="Active Directory Server"
    SGND_MODULE_ID="${SGND_AD_SERVER_MODULE_ID}"
    SGND_MODULE_NAME="$SGND_AD_SERVER_MODULE_NAME"
# - Management dispatch -------------------------------------------------------------
    # fn: _adsvr_run_action - Run action in the Active Directory Server workflow.
    _adsvr_run_action() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-active-directory-server.sh" --action "$action"
    }

    # fn: _adsvr_record_provision_step - Persist one child-step result in the console tracker
        # . Arguments
        #   $1 ITEM_KEY
        #   $2 RESULT_CODE
        #
        # . Returns
        #   0 always; tracking is best-effort when the console tracker is unavailable.
        #
        # . Usage
        #   ```bash
        #   _adsvr_record_provision_step "adsvr-install" 0
        #   ```
    _adsvr_record_provision_step() {
        local item_key="${1:?missing item key}"
        local result_code="${2:-0}"

        if declare -F sgnd_console_record_action_result >/dev/null 2>&1; then
            sgnd_console_record_action_result "$item_key" "$result_code" || true
        fi
        return 0
    }

    # fn: _adsvr_provision_domain - Run the composite provision and synchronize child menu statuses
        # . Purpose
        #   Keep the stateful provisioning workflow inside the management executable while
        #   mapping its workflow return codes back onto the registered console child actions.
        #
        # . Behavior
        #   - Preserves one-process provisioning context across all Active Directory steps.
        #   - Marks every completed child action successful.
        #   - Marks the failing child action failed.
        #   - Leaves steps after a failure untouched.
        #   - Treats operator cancellation after preflight as a successful parent action.
        #
        # . Returns
        #   0 when provisioning succeeds or is cancelled after preflight.
        #   Otherwise the workflow failure code returned by the management executable.
        #
        # . Usage
        #   ```bash
        #   _adsvr_provision_domain
        #   ```
    _adsvr_provision_domain() {
        local rc=0

        _adsvr_run_action provision-all || rc=$?

        case "$rc" in
            0)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                _adsvr_record_provision_step "adsvr-identity" 0
                _adsvr_record_provision_step "adsvr-domain" 0
                _adsvr_record_provision_step "adsvr-settings" 0
                _adsvr_record_provision_step "adsvr-krb" 0
                _adsvr_record_provision_step "adsvr-resolver" 0
                _adsvr_record_provision_step "adsvr-start" 0
                _adsvr_record_provision_step "adsvr-dns" 0
                return 0
                ;;
            31)
                _adsvr_record_provision_step "adsvr-install" 1
                ;;
            32)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 1
                ;;
            33)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                return 0
                ;;
            34)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                _adsvr_record_provision_step "adsvr-identity" 1
                ;;
            35)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                _adsvr_record_provision_step "adsvr-identity" 0
                _adsvr_record_provision_step "adsvr-domain" 1
                ;;
            36)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                _adsvr_record_provision_step "adsvr-identity" 0
                _adsvr_record_provision_step "adsvr-domain" 0
                _adsvr_record_provision_step "adsvr-settings" 1
                ;;
            37)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                _adsvr_record_provision_step "adsvr-identity" 0
                _adsvr_record_provision_step "adsvr-domain" 0
                _adsvr_record_provision_step "adsvr-settings" 0
                _adsvr_record_provision_step "adsvr-krb" 1
                ;;
            38)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                _adsvr_record_provision_step "adsvr-identity" 0
                _adsvr_record_provision_step "adsvr-domain" 0
                _adsvr_record_provision_step "adsvr-settings" 0
                _adsvr_record_provision_step "adsvr-krb" 0
                _adsvr_record_provision_step "adsvr-resolver" 1
                ;;
            39)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                _adsvr_record_provision_step "adsvr-identity" 0
                _adsvr_record_provision_step "adsvr-domain" 0
                _adsvr_record_provision_step "adsvr-settings" 0
                _adsvr_record_provision_step "adsvr-krb" 0
                _adsvr_record_provision_step "adsvr-resolver" 0
                _adsvr_record_provision_step "adsvr-start" 1
                ;;
            40)
                _adsvr_record_provision_step "adsvr-install" 0
                _adsvr_record_provision_step "adsvr-preflight" 0
                _adsvr_record_provision_step "adsvr-identity" 0
                _adsvr_record_provision_step "adsvr-domain" 0
                _adsvr_record_provision_step "adsvr-settings" 0
                _adsvr_record_provision_step "adsvr-krb" 0
                _adsvr_record_provision_step "adsvr-resolver" 0
                _adsvr_record_provision_step "adsvr-start" 0
                _adsvr_record_provision_step "adsvr-dns" 1
                ;;
            *)
                sayfail "Active Directory server provisioning workflow returned unexpected status: $rc"
                ;;
        esac

        return "$rc"
    }

    # fn: _adsvr_join_additional_console - Track the distinct additional-DC workflow
        # . Purpose
        #   Map the manager's first failing stage to the corresponding nested console
        #   item, without conflating domain creation with domain join.
    _adsvr_join_additional_console() {
        local rc=0 step="" key="" status=0
        local -a steps=("adsvr-add-install" "adsvr-add-discover" "adsvr-add-join" "adsvr-add-kerberos" "adsvr-add-resolver" "adsvr-add-start" "adsvr-add-dns" "adsvr-add-repl")
        _adsvr_run_action join-additional || rc=$?
        case "$rc" in
            0) status=8 ;;
            51) status=1 ;;
            52) status=2 ;;
            53) _adsvr_record_provision_step "adsvr-add-install" 0; _adsvr_record_provision_step "adsvr-add-discover" 0; return 0 ;;
            54) status=3 ;;
            55) status=4 ;;
            56) status=5 ;;
            57) status=6 ;;
            58) status=7 ;;
            59) status=8 ;;
            *) sayfail "Additional DC workflow returned unexpected status: $rc"; return "$rc" ;;
        esac
        local index=0
        for step in "${steps[@]}"; do
            index=$((index + 1))
            (( index > status )) && break
            if (( rc != 0 && index == status )); then
                _adsvr_record_provision_step "$step" 1
            else
                _adsvr_record_provision_step "$step" 0
            fi
        done
        (( rc == 0 ))
    }

    # fn: _adsvr_add_install - Forward the `install` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_add_install
        #   ```
    _adsvr_add_install() { _adsvr_run_action install; }
    # fn: _adsvr_add_discover - Forward the `join-preflight` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_add_discover
        #   ```
    _adsvr_add_discover() { _adsvr_run_action join-preflight; }
    # fn: _adsvr_add_join - Forward the `join-domain` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_add_join
        #   ```
    _adsvr_add_join() { _adsvr_run_action join-domain; }
    # fn: _adsvr_add_replication - Forward the `join-replication` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_add_replication
        #   ```
    _adsvr_add_replication() { _adsvr_run_action join-replication; }

    # fn: _adsvr_step_install_packages - Forward the `install` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_install_packages
        #   ```
    _adsvr_step_install_packages() { _adsvr_run_action install; }
    # fn: _adsvr_step_preflight - Forward the `preflight` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_preflight
        #   ```
    _adsvr_step_preflight()        { _adsvr_run_action preflight; }
    # fn: _adsvr_step_identity - Forward the `identity` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_identity
        #   ```
    _adsvr_step_identity()         { _adsvr_run_action identity; }
    # fn: _adsvr_step_provision - Forward the `provision` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_provision
        #   ```
    _adsvr_step_provision()        { _adsvr_run_action provision; }
    # fn: _adsvr_step_domain_settings - Forward the `settings` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_domain_settings
        #   ```
    _adsvr_step_domain_settings()  { _adsvr_run_action settings; }
    # fn: _adsvr_step_kerberos - Forward the `kerberos` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_kerberos
        #   ```
    _adsvr_step_kerberos()         { _adsvr_run_action kerberos; }
    # fn: _adsvr_step_resolver - Forward the `resolver` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_resolver
        #   ```
    _adsvr_step_resolver()         { _adsvr_run_action resolver; }
    # fn: _adsvr_step_start - Forward the `start` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_start
        #   ```
    _adsvr_step_start()            { _adsvr_run_action start; }
    # fn: _adsvr_step_register_dns - Forward the `dns` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_step_register_dns
        #   ```
    _adsvr_step_register_dns()     { _adsvr_run_action dns; }
    # fn: _adsvr_validate - Forward the `validate` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_validate
        #   ```
    _adsvr_validate()              { _adsvr_run_action validate; }
    # fn: _adsvr_status - Forward the `status` action to the AD Server manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   _adsvr_status
        #   ```
    _adsvr_status()                { _adsvr_run_action status; }

# - Module validation contract ------------------------------------------------------
    # Return codes:
    #   0 = Passed
    #   1 = Failed
    #   2 = Warning
    #   3 = Skipped / not applicable
    #
    # Every validator sets SGND_MODULE_VALIDATION_MESSAGE to a concise result summary.
    # Detailed diagnostic output may be written by the validator or delegated action.
    # fn: validate_module_active_directory_server - Validate the Active Directory module and record its status for the console.
        #
        # . Returns
        #   A console validation status (0=pass, 1=fail, 2=warning, 3=skipped).
        #
        # . Usage
        #   ```bash
        #   validate_module_active_directory_server
        #   ```
    validate_module_active_directory_server() {
        if ! grep -Eiq '^[[:space:]]*server[[:space:]]+role[[:space:]]*=[[:space:]]*active[[:space:]]+directory[[:space:]]+domain[[:space:]]+controller' /etc/samba/smb.conf 2>/dev/null; then
            SGND_MODULE_VALIDATION_MESSAGE="Host is not configured as an Active Directory domain controller."
            return 3
        fi
        if _adsvr_validate; then
            SGND_MODULE_VALIDATION_MESSAGE="Active Directory server validation passed."
            return 0
        fi
        SGND_MODULE_VALIDATION_MESSAGE="Active Directory server validation reported one or more failures."
        return 1
    }

# - Console registration ---------------------------------------------------------
    # Registers Samba Active Directory domain-controller management actions.
    # Persistent implementation is delegated to manage-active-directory-server.sh;
    # individual steps remain exposed for diagnosis and recovery.
    #
    # . Menu items
    # ! Provision domain
    #   > Run the complete Active Directory server provisioning sequence.
    #   > Handler: _adsvr_provision_domain
    #
    # ! Join existing domain as additional DC
    #   > Discover the existing domain and join as a writable Samba controller.
    #   > Handler: _adsvr_join_additional_console
    #   > Child steps: installation, discovery, join, Kerberos, resolver, service, DNS, replication.
    #
    # ! Install AD server prerequisites
    #   > Install Samba AD/DC, Kerberos, and DNS utilities.
    #   > Handler: _adsvr_step_install_packages
    #
    # ! Validate provisioning inputs
    #   > Collect realm settings and validate the machine before changes.
    #   > Handler: _adsvr_step_preflight
    #
    # ! Prepare domain controller identity
    #   > Prepare and validate the domain controller FQDN.
    #   > Handler: _adsvr_step_identity
    #
    # ! Provision Samba domain
    #   > Create the Samba directory database and Active Directory configuration.
    #   > Handler: _adsvr_step_provision
    #
    # ! Apply initial domain settings
    #   > Set Administrator policy and the upstream DNS forwarder.
    #   > Handler: _adsvr_step_domain_settings
    #
    # ! Install Kerberos configuration
    #   > Install and validate Samba's generated krb5.conf.
    #   > Handler: _adsvr_step_kerberos
    #
    # ! Configure AD resolver
    #   > Point the domain controller at Samba DNS and free IPv4 port 53.
    #   > Handler: _adsvr_step_resolver
    #
    # ! Start AD/DC service
    #   > Start Samba AD/DC and validate Samba-owned IPv4 DNS.
    #   > Handler: _adsvr_step_start
    #
    # ! Register domain controller DNS
    #   > Register and validate the DC A, SOA, Kerberos, and LDAP records.
    #   > Handler: _adsvr_step_register_dns
    #
    # ! Validate AD server
    #   > Validate service, DNS, directory, and Kerberos discovery.
    #   > Handler: _adsvr_validate
    #
    # ! Show AD server status
    #   > Show the configured Samba role, realm, and service state.
    #   > Handler: _adsvr_status
    sgnd_menu_register_group "$SGND_AD_SERVER_MODULE_ID" "$SGND_AD_SERVER_MODULE_NAME" "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" 0 1 200
    sgnd_menu_register_item "adsvr-provision" "$SGND_AD_SERVER_MODULE_ID" "Provision domain" "_adsvr_provision_domain" "Run the complete Active Directory server provisioning sequence" 0 15 1 0
    sgnd_menu_register_item "adsvr-additional" "$SGND_AD_SERVER_MODULE_ID" "Join existing domain as additional DC" "_adsvr_join_additional_console" "Join as a writable controller; retain the existing domain" 0 15 1 0
    sgnd_menu_register_item "adsvr-add-install" "$SGND_AD_SERVER_MODULE_ID" "Install prerequisites (additional DC)" "_adsvr_add_install" "Install Samba AD/DC prerequisites" 0 15 1 1
    sgnd_menu_register_item "adsvr-add-discover" "$SGND_AD_SERVER_MODULE_ID" "Discover existing domain" "_adsvr_add_discover" "Validate remote DC, DNS and system resolver" 0 15 1 1
    sgnd_menu_register_item "adsvr-add-join" "$SGND_AD_SERVER_MODULE_ID" "Join existing domain" "_adsvr_add_join" "Interactive writable DC join; requires prior discovery" 0 15 1 1
    sgnd_menu_register_item "adsvr-add-kerberos" "$SGND_AD_SERVER_MODULE_ID" "Install joined DC Kerberos" "_adsvr_step_kerberos" "Install joined Samba Kerberos settings" 0 15 1 1
    sgnd_menu_register_item "adsvr-add-resolver" "$SGND_AD_SERVER_MODULE_ID" "Configure joined DC DNS resolver" "_adsvr_step_resolver" "Switch from existing DC DNS to own DNS" 0 15 1 1
    sgnd_menu_register_item "adsvr-add-start" "$SGND_AD_SERVER_MODULE_ID" "Start additional DC" "_adsvr_step_start" "Start and validate Samba AD/DC" 0 15 1 1
    sgnd_menu_register_item "adsvr-add-dns" "$SGND_AD_SERVER_MODULE_ID" "Register additional DC DNS" "_adsvr_step_register_dns" "Register AD records on joined controller" 0 15 1 1
    sgnd_menu_register_item "adsvr-add-repl" "$SGND_AD_SERVER_MODULE_ID" "Inspect AD replication" "_adsvr_add_replication" "Check DRS replication with existing controllers" 0 15 1 1
    sgnd_menu_register_item "adsvr-install" "$SGND_AD_SERVER_MODULE_ID" "Install AD server prerequisites" "_adsvr_step_install_packages" "Install Samba AD/DC, Kerberos, and DNS utilities" 0 15 1 1
    sgnd_menu_register_item "adsvr-preflight" "$SGND_AD_SERVER_MODULE_ID" "Validate provisioning inputs" "_adsvr_step_preflight" "Collect realm settings and validate the machine before changes" 0 15 1 1
    sgnd_menu_register_item "adsvr-identity" "$SGND_AD_SERVER_MODULE_ID" "Prepare domain controller identity" "_adsvr_step_identity" "Prepare and validate the domain controller FQDN" 0 15 1 1
    sgnd_menu_register_item "adsvr-domain" "$SGND_AD_SERVER_MODULE_ID" "Provision Samba domain" "_adsvr_step_provision" "Create the Samba directory database and AD configuration" 0 15 1 1
    sgnd_menu_register_item "adsvr-settings" "$SGND_AD_SERVER_MODULE_ID" "Apply initial domain settings" "_adsvr_step_domain_settings" "Set Administrator policy and the upstream DNS forwarder" 0 15 1 1
    sgnd_menu_register_item "adsvr-krb" "$SGND_AD_SERVER_MODULE_ID" "Install Kerberos configuration" "_adsvr_step_kerberos" "Install and validate Samba's generated krb5.conf" 0 15 1 1
    sgnd_menu_register_item "adsvr-resolver" "$SGND_AD_SERVER_MODULE_ID" "Configure AD resolver" "_adsvr_step_resolver" "Point the DC at Samba DNS and free IPv4 port 53" 0 15 1 1
    sgnd_menu_register_item "adsvr-start" "$SGND_AD_SERVER_MODULE_ID" "Start AD/DC service" "_adsvr_step_start" "Start Samba AD/DC and validate Samba-owned IPv4 DNS" 0 15 1 1
    sgnd_menu_register_item "adsvr-dns" "$SGND_AD_SERVER_MODULE_ID" "Register domain controller DNS" "_adsvr_step_register_dns" "Register and validate the DC A, SOA, Kerberos, and LDAP records" 0 15 1 1
    sgnd_menu_register_item "adsvr-validate" "$SGND_AD_SERVER_MODULE_ID" "Validate AD server" "_adsvr_validate" "Validate service, DNS, directory, and Kerberos discovery" 0 15 1 0
    sgnd_menu_register_item "adsvr-status" "$SGND_AD_SERVER_MODULE_ID" "Show AD server status" "_adsvr_status" "Show the configured Samba role, realm, and service state" 0 15 1 0

    sayinfo "Active Directory Server module registered with the console."
