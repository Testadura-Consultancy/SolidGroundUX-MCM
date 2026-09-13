# ==================================================================================
# SolidGroundUX - Active Directory Client
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624102
#   Checksum    : 9c729b5902f4146dad2b4d43eadbbc1eaa660b958b803106ce9ac78253bbe1b7
#   Source      : 25-active-directory-client.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Install, join, validate, and inspect an Active Directory client
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
    SGND_AD_CLIENT_MODULE_VERSION="1.0.0"
    SGND_AD_CLIENT_MODULE_DESC="Install, join, validate, and inspect Active Directory client membership"
    SGND_MODULE_NAME="$SGND_AD_CLIENT_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_AD_CLIENT_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_AD_CLIENT_MODULE_DESC"

    SGND_ADC_REALM=""
    SGND_ADC_ACCOUNT="Administrator"
    SGND_ADC_DNS_SERVER=""
    SGND_ADC_IP=""
    SGND_ADC_HOSTNAME_SHORT=""
    SGND_ADC_FQDN=""

# - Internal helpers ---------------------------------------------------------------
    # fn: _adc_validate_realm
        # . Purpose
        #   Validate an Active Directory realm name.
        #
        # . Returns
        #   0 for a valid dotted realm name; 1 otherwise.
        #
        # . Usage
        #   _adc_validate_realm
    _adc_validate_realm() { [[ "${1-}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; }
    # fn: _adc_validate_account
        # . Purpose
        #   Validate the account name used for the domain join.
        #
        # . Returns
        #   0 for a supported account name; 1 otherwise.
        #
        # . Usage
        #   _adc_validate_account
    _adc_validate_account() { [[ "${1-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; }
    # fn: _adc_primary_ipv4
        # . Purpose
        #   Resolve the machine primary routed IPv4 address.
        #
        # . Returns
        #   Prints the primary IPv4 address when available.
        #
        # . Usage
        #   _adc_primary_ipv4
    _adc_primary_ipv4() { ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit} }'; }
    # fn: _adc_current_dns
        # . Purpose
        #   Resolve the first non-loopback DNS server reported by systemd-resolved.
        #
        # . Returns
        #   Prints the first matching IPv4 DNS server when available.
        #
        # . Usage
        #   _adc_current_dns
    _adc_current_dns() { resolvectl dns 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '^127\.' | head -n 1; }

    # fn: _adc_collect_context
        # . Purpose
        #   Collect and validate client realm, DNS server, join account, host, and IPv4 context.
        #
        # . Returns
        #   0 when a complete join context is available; non-zero on validation or cancellation.
        #
        # . Usage
        #   _adc_collect_context
    _adc_collect_context() {
        local current_domain=""
        SGND_ADC_HOSTNAME_SHORT="$(hostname -s 2>/dev/null || true)"
        SGND_ADC_IP="$(_adc_primary_ipv4)"
        current_domain="$(hostname -d 2>/dev/null || true)"
        [[ -n "$current_domain" ]] || current_domain="testadura.hq"
        [[ -n "$SGND_ADC_REALM" ]] || SGND_ADC_REALM="$current_domain"
        [[ -n "$SGND_ADC_DNS_SERVER" ]] || SGND_ADC_DNS_SERVER="$(_adc_current_dns)"

        [[ -n "$SGND_ADC_HOSTNAME_SHORT" && "$SGND_ADC_HOSTNAME_SHORT" != localhost ]] || { sayfail "A valid hostname is required."; return 1; }
        [[ -n "$SGND_ADC_IP" ]] || { sayfail "A primary IPv4 address is required."; return 1; }
        ask --label "AD realm" --var SGND_ADC_REALM --default "$SGND_ADC_REALM" --validate _adc_validate_realm || return $?
        SGND_ADC_REALM="${SGND_ADC_REALM,,}"
        ask --label "AD DNS server" --var SGND_ADC_DNS_SERVER --default "$SGND_ADC_DNS_SERVER" --validate sgnd_validate_ipv4 || return $?
        ask --label "Join account" --var SGND_ADC_ACCOUNT --default "$SGND_ADC_ACCOUNT" --validate _adc_validate_account || return $?
        SGND_ADC_FQDN="${SGND_ADC_HOSTNAME_SHORT}.${SGND_ADC_REALM}"
        sgnd_print
        sgnd_print_labeledvalue --label "Machine FQDN" --value "$SGND_ADC_FQDN"
        sgnd_print_labeledvalue --label "Machine IPv4" --value "$SGND_ADC_IP"
        sgnd_print_labeledvalue --label "AD realm" --value "$SGND_ADC_REALM"
        sgnd_print_labeledvalue --label "AD DNS server" --value "$SGND_ADC_DNS_SERVER"
        sgnd_print_labeledvalue --label "Join account" --value "$SGND_ADC_ACCOUNT"
    }

    # fn: _adc_require_context
        # . Purpose
        #   Ensure Active Directory client join context is available.
        #
        # . Returns
        #   0 when context exists or can be collected; non-zero otherwise.
        #
        # . Usage
        #   _adc_require_context
    _adc_require_context() {
        [[ -n "$SGND_ADC_REALM" && -n "$SGND_ADC_DNS_SERVER" && -n "$SGND_ADC_IP" ]] && return 0
        _adc_collect_context
    }

    # fn: _adc_step_install_packages
        # . Purpose
        #   Install and validate realmd, SSSD, Kerberos, and Active Directory client prerequisites.
        #
        # . Returns
        #   0 on success or dry-run; non-zero on package or command validation failure.
        #
        # . Usage
        #   _adc_step_install_packages
    _adc_step_install_packages() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would install Active Directory client prerequisites."; return 0; fi
        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y adcli krb5-user libnss-sss libpam-sss packagekit realmd samba-common-bin sssd-ad sssd-tools || return 1
        command -v realm >/dev/null && command -v adcli >/dev/null && command -v kinit >/dev/null || return 1
        sayok "Active Directory client prerequisites installed."
    }

    # fn: _adc_step_preflight
        # . Purpose
        #   Collect join inputs and reject a machine that is already joined to a realm.
        #
        # . Returns
        #   0 when the join may continue; non-zero otherwise.
        #
        # . Usage
        #   _adc_step_preflight
    _adc_step_preflight() {
        _adc_collect_context || return 1
        if realm list --name-only 2>/dev/null | grep -q .; then sayfail "This machine is already joined to an Active Directory realm."; return 1; fi
        sayok "Active Directory client inputs validated."
    }

    # fn: _adc_step_dns
        # . Purpose
        #   Point the client resolver at the authoritative Active Directory DNS server and verify its SOA.
        #
        # . Returns
        #   0 when DNS is configured and authoritative; non-zero otherwise.
        #
        # . Usage
        #   _adc_step_dns
    _adc_step_dns() {
        _adc_require_context || return 1
        declare -F sgnd_console_set_dns_server >/dev/null 2>&1 || { sayfail "Console DNS helper is unavailable."; return 1; }
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would set DNS to $SGND_ADC_DNS_SERVER."; return 0; }
        sgnd_console_set_dns_server "$SGND_ADC_DNS_SERVER" || return 1
        sudo resolvectl flush-caches 2>/dev/null || true
        host -t SOA "$SGND_ADC_REALM" "$SGND_ADC_DNS_SERVER" >/dev/null 2>&1 || { sayfail "$SGND_ADC_DNS_SERVER is not authoritative for $SGND_ADC_REALM."; return 1; }
        sayok "Client DNS points to the Active Directory DNS server."
    }

    # fn: _adc_step_identity
        # . Purpose
        #   Set the client FQDN and maintain the matching /etc/hosts entry.
        #
        # . Returns
        #   0 when hostname -f matches the expected client FQDN; non-zero otherwise.
        #
        # . Usage
        #   _adc_step_identity
    _adc_step_identity() {
        local tmp_file=""
        _adc_require_context || return 1
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would set hostname/FQDN to $SGND_ADC_FQDN."; return 0; }
        sudo hostnamectl set-hostname "$SGND_ADC_FQDN" || return 1
        tmp_file="$(mktemp)" || return 1
        awk -v short_name="$SGND_ADC_HOSTNAME_SHORT" '
            function contains_host(line,host,n,f,i){n=split(line,f,/[[:space:]]+/);for(i=2;i<=n;i++)if(tolower(f[i])==tolower(host))return 1;return 0}
            /^[[:space:]]*#/ || /^[[:space:]]*$/ {print;next}
            {if(!contains_host($0,short_name))print}
        ' /etc/hosts > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
        printf '%s\t%s %s\n' "$SGND_ADC_IP" "$SGND_ADC_FQDN" "$SGND_ADC_HOSTNAME_SHORT" >> "$tmp_file"
        sudo install -o root -g root -m 0644 "$tmp_file" /etc/hosts || { rm -f "$tmp_file"; return 1; }
        rm -f "$tmp_file"
        [[ "$(hostname -f 2>/dev/null || true)" == "$SGND_ADC_FQDN" ]] || return 1
        sayok "Active Directory client identity prepared."
    }

    # fn: _adc_step_discover
        # . Purpose
        #   Validate realm, Kerberos, and LDAP service discovery before joining.
        #
        # . Returns
        #   0 when all required services are discoverable; non-zero otherwise.
        #
        # . Usage
        #   _adc_step_discover
    _adc_step_discover() {
        _adc_require_context || return 1
        realm discover "$SGND_ADC_REALM" >/dev/null 2>&1 || { sayfail "The realm could not be discovered."; return 1; }
        host -t SRV "_kerberos._tcp.$SGND_ADC_REALM" >/dev/null 2>&1 || { sayfail "Kerberos service discovery failed."; return 1; }
        host -t SRV "_ldap._tcp.$SGND_ADC_REALM" >/dev/null 2>&1 || { sayfail "LDAP service discovery failed."; return 1; }
        sayok "Active Directory services discovered."
    }

    # fn: _adc_step_join
        # . Purpose
        #   Join the machine to the selected Active Directory realm.
        #
        # . Returns
        #   0 when realm membership validates; non-zero or the realm command status otherwise.
        #
        # . Usage
        #   _adc_step_join
    _adc_step_join() {
        _adc_require_context || return 1
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would join $SGND_ADC_REALM as $SGND_ADC_ACCOUNT."; return 0; }
        sudo realm join --user="$SGND_ADC_ACCOUNT" "$SGND_ADC_REALM" </dev/tty || return $?
        realm list --name-only 2>/dev/null | grep -Fqi "$SGND_ADC_REALM" || { sayfail "Realm membership could not be validated."; return 1; }
        sayok "Machine joined to $SGND_ADC_REALM."
    }

    # fn: _adc_step_sssd
        # . Purpose
        #   Enable, restart, and validate the SSSD client service.
        #
        # . Returns
        #   0 when SSSD is active; non-zero otherwise.
        #
        # . Usage
        #   _adc_step_sssd
    _adc_step_sssd() {
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would restart SSSD."; return 0; }
        sudo systemctl enable sssd.service >/dev/null 2>&1 || true
        sudo systemctl restart sssd.service || return 1
        systemctl is-active --quiet sssd.service || { sayfail "SSSD is not active."; return 1; }
        sayok "SSSD is active."
    }

    # fn: _adc_dns_record_matches
        # . Purpose
        #   Test whether the client A record resolves to its current IPv4 address.
        #
        # . Returns
        #   0 when the DNS record matches; 1 otherwise.
        #
        # . Usage
        #   _adc_dns_record_matches
    _adc_dns_record_matches() {
        host -t A "$SGND_ADC_FQDN" "$SGND_ADC_DNS_SERVER" 2>/dev/null | awk '/has address/ {print $NF}' | grep -Fxq "$SGND_ADC_IP"
    }

    # fn: _adc_step_register_dns
        # . Purpose
        #   Create and verify the client Active Directory DNS A record when needed.
        #
        # . Returns
        #   0 when the record already exists or is successfully registered; non-zero otherwise.
        #
        # . Usage
        #   _adc_step_register_dns
    _adc_step_register_dns() {
        _adc_require_context || return 1
        _adc_dns_record_matches && { sayok "Client DNS record is already registered."; return 0; }
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would register $SGND_ADC_FQDN -> $SGND_ADC_IP."; return 0; }
        sudo samba-tool dns add "$SGND_ADC_DNS_SERVER" "$SGND_ADC_REALM" "$SGND_ADC_HOSTNAME_SHORT" A "$SGND_ADC_IP" -U "$SGND_ADC_ACCOUNT" </dev/tty || return $?
        _adc_dns_record_matches || { sayfail "Client DNS record could not be verified."; return 1; }
        sayok "Client DNS record registered."
    }

    # fn: _adc_join_domain
        # . Purpose
        #   Run the complete tracked Active Directory client join sequence.
        #
        # . Returns
        #   0 when the join completes or is cancelled before changes; non-zero on a failed step.
        #
        # . Usage
        #   _adc_join_domain
    _adc_join_domain() {
        local decision="No"
        sgnd_console_run_tracked "adc-install" _adc_step_install_packages || return $?
        sgnd_console_run_tracked "adc-preflight" _adc_step_preflight || return $?
        ask_decision --label "Join $SGND_ADC_FQDN to $SGND_ADC_REALM?" --choices "Yes|Y,No|N" --default "No" --var decision
        [[ "${decision^^}" == "YES" ]] || { sayinfo "Domain join cancelled."; return 0; }
        sgnd_console_run_tracked "adc-dns" _adc_step_dns || return $?
        sgnd_console_run_tracked "adc-identity" _adc_step_identity || return $?
        sgnd_console_run_tracked "adc-discover" _adc_step_discover || return $?
        sgnd_console_run_tracked "adc-join-step" _adc_step_join || return $?
        sgnd_console_run_tracked "adc-sssd" _adc_step_sssd || return $?
        sgnd_console_run_tracked "adc-register" _adc_step_register_dns || return $?
        sayok "Active Directory client join sequence completed."
    }

    # fn: _adc_validate
        # . Purpose
        #   Validate realm membership, Kerberos/LDAP discovery, and SSSD.
        #
        # . Returns
        #   0 when all checks pass; 1 when one or more checks fail.
        #
        # . Usage
        #   _adc_validate
    _adc_validate() {
        local realm="" failures=0
        realm="$(realm list --name-only 2>/dev/null | head -n 1)"
        sgnd_print; sgnd_print_sectionheader "Active Directory client validation"
        [[ -n "$realm" ]] && sgnd_print_labeledvalue --label "Realm membership" --value "Passed ($realm)" || { sgnd_print_labeledvalue --label "Realm membership" --value "Failed"; failures=$((failures+1)); }
        [[ -n "$realm" ]] && host -t SRV "_kerberos._tcp.${realm,,}" >/dev/null 2>&1 && sgnd_print_labeledvalue --label "Kerberos discovery" --value "Passed" || { sgnd_print_labeledvalue --label "Kerberos discovery" --value "Failed"; failures=$((failures+1)); }
        [[ -n "$realm" ]] && host -t SRV "_ldap._tcp.${realm,,}" >/dev/null 2>&1 && sgnd_print_labeledvalue --label "LDAP discovery" --value "Passed" || { sgnd_print_labeledvalue --label "LDAP discovery" --value "Failed"; failures=$((failures+1)); }
        systemctl is-active --quiet sssd.service && sgnd_print_labeledvalue --label "SSSD service" --value "Passed" || { sgnd_print_labeledvalue --label "SSSD service" --value "Failed"; failures=$((failures+1)); }
        (( failures == 0 )) && { sayok "Active Directory client validation passed."; return 0; }
        sayfail "$failures Active Directory client validation check(s) failed."; return 1
    }

    # fn: _adc_status
        # . Purpose
        #   Display client FQDN, realm membership, SSSD state, and realm details.
        #
        # . Returns
        #   0 after displaying available status information.
        #
        # . Usage
        #   _adc_status
    _adc_status() {
        local realm=""
        realm="$(realm list --name-only 2>/dev/null | head -n 1)"
        sgnd_print; sgnd_print_sectionheader "Active Directory client status"
        sgnd_print_labeledvalue --label "Machine FQDN" --value "$(hostname -f 2>/dev/null || true)"
        sgnd_print_labeledvalue --label "Realm" --value "${realm:-Not joined}"
        sgnd_print_labeledvalue --label "SSSD" --value "$(systemctl is-active sssd.service 2>/dev/null || true)"
        [[ -n "$realm" ]] && realm list
    }

    # fn: _adc_leave
        # . Purpose
        #   Leave the currently joined Active Directory realm after confirmation.
        #
        # . Returns
        #   0 when not joined, cancelled, dry-run, or leave succeeds; otherwise the realm command status.
        #
        # . Usage
        #   _adc_leave
    _adc_leave() {
        local realm="" decision="No"
        realm="$(realm list --name-only 2>/dev/null | head -n 1)"
        [[ -n "$realm" ]] || { sayinfo "This machine is not joined to a realm."; return 0; }
        ask_decision --label "Leave $realm?" --choices "Yes|Y,No|N" --default "No" --var decision
        [[ "${decision^^}" == "YES" ]] || return 0
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would leave $realm."; return 0; }
        sudo realm leave "$realm"
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
    sgnd_menu_register_group "$SGND_AD_CLIENT_MODULE_ID" "$SGND_AD_CLIENT_MODULE_NAME" "$SGND_AD_CLIENT_MODULE_DESC" 0 1 250
    sgnd_menu_register_item "adc-join" "$SGND_AD_CLIENT_MODULE_ID" "Join domain" "_adc_join_domain" "Run the complete Active Directory client join sequence" 0 15 1 0
    sgnd_menu_register_item "adc-install" "$SGND_AD_CLIENT_MODULE_ID" "Install AD client prerequisites" "_adc_step_install_packages" "Install realmd, SSSD, Kerberos, and AD client utilities" 0 15 1 1
    sgnd_menu_register_item "adc-preflight" "$SGND_AD_CLIENT_MODULE_ID" "Validate join inputs" "_adc_step_preflight" "Collect realm, DNS, account, and machine identity settings" 0 15 1 1
    sgnd_menu_register_item "adc-dns" "$SGND_AD_CLIENT_MODULE_ID" "Configure Active Directory DNS" "_adc_step_dns" "Point the client at the authoritative Active Directory DNS server" 0 15 1 1
    sgnd_menu_register_item "adc-identity" "$SGND_AD_CLIENT_MODULE_ID" "Prepare client identity" "_adc_step_identity" "Set and validate the machine FQDN before joining" 0 15 1 1
    sgnd_menu_register_item "adc-discover" "$SGND_AD_CLIENT_MODULE_ID" "Discover Active Directory services" "_adc_step_discover" "Validate realm, Kerberos, and LDAP service discovery" 0 15 1 1
    sgnd_menu_register_item "adc-join-step" "$SGND_AD_CLIENT_MODULE_ID" "Join Active Directory realm" "_adc_step_join" "Join the machine to the selected realm" 0 15 1 1
    sgnd_menu_register_item "adc-sssd" "$SGND_AD_CLIENT_MODULE_ID" "Start SSSD" "_adc_step_sssd" "Start and validate the SSSD client service" 0 15 1 1
    sgnd_menu_register_item "adc-register" "$SGND_AD_CLIENT_MODULE_ID" "Register client DNS" "_adc_step_register_dns" "Register and verify the client IPv4 host record" 0 15 1 1
    sgnd_menu_register_item "adc-validate" "$SGND_AD_CLIENT_MODULE_ID" "Validate AD client" "_adc_validate" "Validate membership, service discovery, and SSSD" 0 15 1 0
    sgnd_menu_register_item "adc-status" "$SGND_AD_CLIENT_MODULE_ID" "Show AD client status" "_adc_status" "Show machine identity and current realm membership" 0 15 1 0
    sgnd_menu_register_item "adc-leave" "$SGND_AD_CLIENT_MODULE_ID" "Leave domain" "_adc_leave" "Leave the currently joined Active Directory realm" 0 15 1 0
