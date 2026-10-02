# ==================================================================================
# SolidGroundUX Management Console Modules - Active Directory Client
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627501
#   Shortname   : AD_CLIENT
#   Source      : 25-active-directory-client.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Register Active Directory client management actions
#
#   Checksum : a2bb566211b87ffacbbbbeb10ddb7ee3d72809d7dd1149a062dcfa0b12cb5067
# Description:
#   Registers Active Directory client management actions with the SolidGround Management
#   Console. Persistent join, reconciliation, validation, and repair operations are
#   implemented by manage-active-directory-client.sh.
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
    SGND_AD_CLIENT_MODULE_ID="active-directory-client"
    SGND_AD_CLIENT_MODULE_NAME="Active Directory Client"
    SGND_MODULE_ID="${SGND_AD_CLIENT_MODULE_ID}"
    SGND_MODULE_NAME="$SGND_AD_CLIENT_MODULE_NAME"
# - Management dispatch -------------------------------------------------------------
    _adc_run_action() { local action="${1:?missing action}"; _sgnd_run_module_script "manage-active-directory-client.sh" --action "$action"; }

    # fn: _adc_record_join_step - Persist one child-step result in the console action tracker
        # . Arguments
        #   $1 ITEM_KEY
        #   $2 RESULT_CODE
        #
        # . Returns
        #   0 always; tracking is best-effort when the console tracker is unavailable.
        #
        # . Usage
        #   _adc_record_join_step "adc-install" 0
    _adc_record_join_step() {
        local item_key="${1:?missing item key}"
        local result_code="${2:-0}"

        if declare -F sgnd_console_record_action_result >/dev/null 2>&1; then
            sgnd_console_record_action_result "$item_key" "$result_code" || true
        fi
        return 0
    }

    # fn: _adc_join_domain - Run the composite join and synchronize child menu statuses
        # . Purpose
        #   Keep the stateful join workflow inside the management executable while mapping its
        #   distinct workflow return codes back onto the registered console child actions.
        #
        # . Behavior
        #   - Preserves the management executable's single-process join context.
        #   - Marks every completed child action successful.
        #   - Marks the failing child action failed.
        #   - Leaves steps after a failure untouched.
        #   - Treats administrator cancellation after preflight as a successful parent action.
        #   - Treats an already joined machine as a warning, not as a failed or successful join.
        #
        # . Returns
        #   0 when the join succeeds or is cancelled after preflight.
        #   2 when the machine is already joined and no join is required.
        #   Otherwise the workflow failure code.
        #
        # . Usage
        #   _adc_join_domain
    _adc_join_domain() {
        local rc=0

        _adc_run_action join-all || rc=$?

        case "$rc" in
            0)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 0
                _adc_record_join_step "adc-dns" 0
                _adc_record_join_step "adc-identity" 0
                _adc_record_join_step "adc-discover" 0
                _adc_record_join_step "adc-join-step" 0
                _adc_record_join_step "adc-sssd" 0
                _adc_record_join_step "adc-register" 0
                return 0
                ;;
            20)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 2
                return 2
                ;;
            21)
                _adc_record_join_step "adc-install" 1
                ;;
            22)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 1
                ;;
            23)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 0
                return 0
                ;;
            24)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 0
                _adc_record_join_step "adc-dns" 1
                ;;
            25)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 0
                _adc_record_join_step "adc-dns" 0
                _adc_record_join_step "adc-identity" 1
                ;;
            26)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 0
                _adc_record_join_step "adc-dns" 0
                _adc_record_join_step "adc-identity" 0
                _adc_record_join_step "adc-discover" 1
                ;;
            27)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 0
                _adc_record_join_step "adc-dns" 0
                _adc_record_join_step "adc-identity" 0
                _adc_record_join_step "adc-discover" 0
                _adc_record_join_step "adc-join-step" 1
                ;;
            28)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 0
                _adc_record_join_step "adc-dns" 0
                _adc_record_join_step "adc-identity" 0
                _adc_record_join_step "adc-discover" 0
                _adc_record_join_step "adc-join-step" 0
                _adc_record_join_step "adc-sssd" 1
                ;;
            29)
                _adc_record_join_step "adc-install" 0
                _adc_record_join_step "adc-preflight" 0
                _adc_record_join_step "adc-dns" 0
                _adc_record_join_step "adc-identity" 0
                _adc_record_join_step "adc-discover" 0
                _adc_record_join_step "adc-join-step" 0
                _adc_record_join_step "adc-sssd" 0
                _adc_record_join_step "adc-register" 1
                ;;
            *)
                sayfail "Active Directory join workflow returned unexpected status: $rc"
                ;;
        esac

        return "$rc"
    }

    _adc_step_install_packages()  { _adc_run_action install; }
    _adc_step_preflight()         { _adc_run_action preflight; }
    _adc_step_dns()               { _adc_run_action dns; }
    _adc_step_identity()          { _adc_run_action identity; }
    _adc_step_discover()          { _adc_run_action discover; }
    _adc_step_join()              { _adc_run_action join; }
    _adc_step_sssd()              { _adc_run_action sssd; }
    _adc_step_register_dns()      { _adc_run_action register; }
    _adc_reconcile()              { _adc_run_action reconcile; }
    _adc_validate()               { _adc_run_action validate; }
    _adc_status()                 { _adc_run_action status; }
    _adc_leave()                  { _adc_run_action leave; }

# - Module validation contract ------------------------------------------------------
    # Return codes:
    #   0 = Passed
    #   1 = Failed
    #   2 = Warning
    #   3 = Skipped / not applicable
    #
    # Every validator sets SGND_MODULE_VALIDATION_MESSAGE to a concise result summary.
    # Detailed diagnostic output may be written by the validator or delegated action.
    validate_module_active_directory_client() {
        if ! command -v realm >/dev/null 2>&1 || [[ -z "$(realm list 2>/dev/null)" ]]; then
            SGND_MODULE_VALIDATION_MESSAGE="Host is not joined to an Active Directory realm through realmd."
            return 3
        fi
        if _adc_validate; then
            SGND_MODULE_VALIDATION_MESSAGE="Active Directory client validation passed."
            return 0
        fi
        SGND_MODULE_VALIDATION_MESSAGE="Active Directory client validation reported one or more failures."
        return 1
    }

# - Console registration ---------------------------------------------------------
    # Provides Active Directory client preparation and domain membership management.
    # The complete join workflow is exposed together with its individual steps for
    # diagnosis, validation, status inspection, DNS registration, and domain leave.
    #
    # . Menu items
    # ! Join domain
    #   > Run the complete Active Directory client join sequence.
    #   > Handler: _adc_join_domain
    #
    # ! Install AD client prerequisites
    #   > Install realmd, SSSD, Kerberos, and Active Directory client utilities.
    #   > Handler: _adc_step_install_packages
    #
    # ! Validate join inputs
    #   > Collect realm, DNS, account, and machine identity settings.
    #   > Handler: _adc_step_preflight
    #
    # ! Configure Active Directory DNS
    #   > Point the client at the authoritative Active Directory DNS server.
    #   > Handler: _adc_step_dns
    #
    # ! Prepare client identity
    #   > Set and validate the machine FQDN before joining.
    #   > Handler: _adc_step_identity
    #
    # ! Discover Active Directory services
    #   > Validate realm, Kerberos, and LDAP service discovery.
    #   > Handler: _adc_step_discover
    #
    # ! Join Active Directory realm
    #   > Join the machine to the selected realm.
    #   > Handler: _adc_step_join
    #
    # ! Start SSSD
    #   > Start and validate the SSSD client service.
    #   > Handler: _adc_step_sssd
    #
    # ! Register client DNS
    #   > Register and verify the client IPv4 host record.
    #   > Handler: _adc_step_register_dns
    #
    # ! Reconcile AD client
    #   > Repair safe local AD client drift without rejoining the realm.
    #   > Handler: _adc_reconcile
    #
    # ! Validate AD client
    #   > Validate membership, service discovery, and SSSD.
    #   > Handler: _adc_validate
    #
    # ! Show AD client status
    #   > Show machine identity and current realm membership.
    #   > Handler: _adc_status
    #
    # ! Leave domain
    #   > Leave the currently joined Active Directory realm.
    #   > Handler: _adc_leave
    sgnd_menu_register_group "$SGND_AD_CLIENT_MODULE_ID" "$SGND_AD_CLIENT_MODULE_NAME" "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" 0 1 250
    sgnd_menu_register_item "adc-join" "$SGND_AD_CLIENT_MODULE_ID" "Join domain" "_adc_join_domain" "Run the complete Active Directory client join sequence" 0 15 1 0
    sgnd_menu_register_item "adc-install" "$SGND_AD_CLIENT_MODULE_ID" "Install AD client prerequisites" "_adc_step_install_packages" "Install realmd, SSSD, Kerberos, and AD client utilities" 0 15 1 1
    sgnd_menu_register_item "adc-preflight" "$SGND_AD_CLIENT_MODULE_ID" "Validate join inputs" "_adc_step_preflight" "Collect realm, DNS, account, and machine identity settings" 0 15 1 1
    sgnd_menu_register_item "adc-dns" "$SGND_AD_CLIENT_MODULE_ID" "Configure Active Directory DNS" "_adc_step_dns" "Point the client at the authoritative Active Directory DNS server" 0 15 1 1
    sgnd_menu_register_item "adc-identity" "$SGND_AD_CLIENT_MODULE_ID" "Prepare client identity" "_adc_step_identity" "Set and validate the machine FQDN before joining" 0 15 1 1
    sgnd_menu_register_item "adc-discover" "$SGND_AD_CLIENT_MODULE_ID" "Discover Active Directory services" "_adc_step_discover" "Validate realm, Kerberos, and LDAP service discovery" 0 15 1 1
    sgnd_menu_register_item "adc-join-step" "$SGND_AD_CLIENT_MODULE_ID" "Join Active Directory realm" "_adc_step_join" "Join the machine to the selected realm" 0 15 1 1
    sgnd_menu_register_item "adc-sssd" "$SGND_AD_CLIENT_MODULE_ID" "Start SSSD" "_adc_step_sssd" "Start and validate the SSSD client service" 0 15 1 1
    sgnd_menu_register_item "adc-register" "$SGND_AD_CLIENT_MODULE_ID" "Register client DNS" "_adc_step_register_dns" "Register and verify the client IPv4 host record" 0 15 1 1
    sgnd_menu_register_item "adc-reconcile" "$SGND_AD_CLIENT_MODULE_ID" "Reconcile AD client" "_adc_reconcile" "Repair safe local AD client drift without rejoining the realm" 0 20 1 0
    sgnd_menu_register_item "adc-validate" "$SGND_AD_CLIENT_MODULE_ID" "Validate AD client" "_adc_validate" "Validate membership, service discovery, and SSSD" 0 15 1 0
    sgnd_menu_register_item "adc-status" "$SGND_AD_CLIENT_MODULE_ID" "Show AD client status" "_adc_status" "Show machine identity and current realm membership" 0 15 1 0
    sgnd_menu_register_item "adc-leave" "$SGND_AD_CLIENT_MODULE_ID" "Leave domain" "_adc_leave" "Leave the currently joined Active Directory realm" 0 15 1 0
