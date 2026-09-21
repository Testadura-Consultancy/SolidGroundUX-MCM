# ==================================================================================
# SolidGroundUX Management Console Modules - Active Directory Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 1.2
#   Build       : 2626021
#   Checksum    : afb2d509827f17f17c5820aab89822c9686a827da1181815d1ae5dacfff6a4a2
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
    SGND_AD_SERVER_MODULE_ID="active-directory-server"
    SGND_AD_SERVER_MODULE_NAME="Active Directory Server"
    SGND_AD_SERVER_MODULE_VERSION="1.1.0"
    SGND_AD_SERVER_MODULE_DESC="Install, provision, validate, and inspect a Samba Active Directory domain controller"
    SGND_MODULE_ID="${SGND_AD_SERVER_MODULE_ID}"
    SGND_MODULE_NAME="$SGND_AD_SERVER_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_AD_SERVER_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_AD_SERVER_MODULE_DESC"

# - Management dispatch -------------------------------------------------------------
    _adsvr_run_action() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-active-directory-server.sh" --action "$action"
    }

    _adsvr_provision_domain()      { _adsvr_run_action provision-all; }
    _adsvr_step_install_packages() { _adsvr_run_action install; }
    _adsvr_step_preflight()        { _adsvr_run_action preflight; }
    _adsvr_step_identity()         { _adsvr_run_action identity; }
    _adsvr_step_provision()        { _adsvr_run_action provision; }
    _adsvr_step_domain_settings()  { _adsvr_run_action settings; }
    _adsvr_step_kerberos()         { _adsvr_run_action kerberos; }
    _adsvr_step_resolver()         { _adsvr_run_action resolver; }
    _adsvr_step_start()            { _adsvr_run_action start; }
    _adsvr_step_register_dns()     { _adsvr_run_action dns; }
    _adsvr_validate()              { _adsvr_run_action validate; }
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
    sgnd_menu_register_group "$SGND_AD_SERVER_MODULE_ID" "$SGND_AD_SERVER_MODULE_NAME" "$SGND_AD_SERVER_MODULE_DESC" 0 1 200
    sgnd_menu_register_item "adsvr-provision" "$SGND_AD_SERVER_MODULE_ID" "Provision domain" "_adsvr_provision_domain" "Run the complete Active Directory server provisioning sequence" 0 15 1 0
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
