#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Active Directory Client
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2626523
#   Source      : manage-active-directory-client.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Join, reconcile, validate, and inspect an Active Directory client
#
#   Checksum : db6376b99b59b30fff45fcf515970d9e0150ef0be3ee6aed309030ad8234045b
# Description:
#   Implements persistent Active Directory client management actions exposed by the
#   25-active-directory-client Management Console module.
# =====================================================================================
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
    _load_ad_management_library() {
        local script_file="" path_without_root="" component="" app_root="" lib_file=""
        local index=0 root_index=-1
        local -a path_parts=()

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || return 126
        path_without_root="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$path_without_root"

        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in
                usr|etc|var) root_index=$index ;;
            esac
        done

        (( root_index >= 0 )) || {
            sayfail "Cannot determine Active Directory application root."
            return 126
        }

        if (( root_index == 0 )); then
            app_root="/"
        else
            app_root=""
            for (( index=0; index<root_index; index++ )); do
                app_root+="/${path_parts[$index]}"
            done
        fi

        if [[ "$app_root" == "/" ]]; then
            lib_file="/usr/local/lib/solidgroundux/common/active-directory-management.sh"
        else
            lib_file="${app_root%/}/usr/local/lib/solidgroundux/common/active-directory-management.sh"
        fi

        [[ -r "$lib_file" ]] || {
            sayfail "Cannot read Active Directory management library: $lib_file"
            return 126
        }

        # shellcheck source=/dev/null
        source "$lib_file"
    }

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Manage Active Directory Client"
    : "${SGND_SCRIPT_DESC:=Join, reconcile, validate, and inspect Active Directory client membership.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2625721}"

# - Framework integration ----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||join-all,install,preflight,dns,identity,discover,join,sssd,register,reconcile,validate,status,leave"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action status"
        "  $SGND_SCRIPT_NAME --action validate"
        "  $SGND_SCRIPT_NAME --dryrun --action reconcile"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Active Directory client implementation -----------------------------------------
    SGND_ADC_REALM=""
    SGND_ADC_ACCOUNT="Administrator"
    SGND_ADC_DNS_SERVER=""
    SGND_ADC_IP=""
    SGND_ADC_HOSTNAME_SHORT=""
    SGND_ADC_FQDN=""

# - Internal helpers ---------------------------------------------------------------
    _adc_validate_realm() { sgnd_ad_validate_realm "$@"; }
    _adc_validate_account() { sgnd_ad_validate_account "$@"; }

    # fn: _adc_collect_context - Collect Active Directory client join context
    _adc_collect_context() {
        local current_domain=""

        SGND_ADC_HOSTNAME_SHORT="$(hostname -s 2>/dev/null || true)"
        SGND_ADC_IP="$(sgnd_ad_primary_ipv4)"
        current_domain="$(hostname -d 2>/dev/null || true)"
        [[ -n "$current_domain" ]] || current_domain="testadura.hq"

        [[ -n "$SGND_ADC_REALM" ]] || SGND_ADC_REALM="$current_domain"
        [[ -n "$SGND_ADC_DNS_SERVER" ]] || SGND_ADC_DNS_SERVER="$(sgnd_ad_current_dns)"

        [[ -n "$SGND_ADC_HOSTNAME_SHORT" && "$SGND_ADC_HOSTNAME_SHORT" != localhost ]] || {
            sayfail "A valid hostname is required."
            return 1
        }
        [[ -n "$SGND_ADC_IP" && "$SGND_ADC_IP" != 127.* ]] || {
            sayfail "A primary non-loopback IPv4 address is required."
            return 1
        }

        sgnd_print
        sgnd_print_sectionheader ""
        ask --label "AD realm" --var SGND_ADC_REALM --default "$SGND_ADC_REALM" --validate _adc_validate_realm || return $?
        SGND_ADC_REALM="${SGND_ADC_REALM,,}"
        ask --label "AD DNS server" --var SGND_ADC_DNS_SERVER --default "$SGND_ADC_DNS_SERVER" --validate sgnd_validate_ipv4 || return $?
        ask --label "Join account" --var SGND_ADC_ACCOUNT --default "$SGND_ADC_ACCOUNT" --validate _adc_validate_account || return $?
        SGND_ADC_FQDN="${SGND_ADC_HOSTNAME_SHORT}.${SGND_ADC_REALM}"

        sgnd_print
        sgnd_print_sectionheader ""
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
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "DRYRUN: Would install Active Directory client prerequisites."; return 0; fi
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
        if sgnd_ad_is_domain_member; then sayfail "This machine is already joined to an Active Directory realm."; return 1; fi
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
        local identity_script=""
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "DRYRUN: Would set DNS to $SGND_ADC_DNS_SERVER."; return 0; }

        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            identity_script="/usr/local/libexec/solidgroundux/set-identity.sh"
        else
            identity_script="${SGND_FRAMEWORK_ROOT%/}/usr/local/libexec/solidgroundux/set-identity.sh"
        fi

        [[ -x "$identity_script" ]] || { sayfail "Cannot execute canonical identity tool: $identity_script"; return 1; }
        "$identity_script" --dns-only --DNS "$SGND_ADC_DNS_SERVER" --Auto || return $?
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
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "DRYRUN: Would set hostname/FQDN to $SGND_ADC_FQDN."; return 0; }
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
        sgnd_ad_discover_kerberos "$SGND_ADC_REALM" "$SGND_ADC_DNS_SERVER" || { sayfail "Kerberos service discovery failed."; return 1; }
        sgnd_ad_discover_ldap "$SGND_ADC_REALM" "$SGND_ADC_DNS_SERVER" || { sayfail "LDAP service discovery failed."; return 1; }
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
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "DRYRUN: Would join $SGND_ADC_REALM as $SGND_ADC_ACCOUNT."; return 0; }
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
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "DRYRUN: Would restart SSSD."; return 0; }
        sudo systemctl enable sssd.service >/dev/null 2>&1 || true
        sudo systemctl restart sssd.service || return 1
        systemctl is-active --quiet sssd.service || { sayfail "SSSD is not active."; return 1; }
        sayok "SSSD is active."
    }

    _adc_dns_record_matches() { sgnd_ad_dns_a_record_matches "$SGND_ADC_FQDN" "$SGND_ADC_IP" "$SGND_ADC_DNS_SERVER"; }

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
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "DRYRUN: Would register $SGND_ADC_FQDN -> $SGND_ADC_IP."; return 0; }
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
        _adc_step_install_packages || return $?
        _adc_step_preflight || return $?
        sgnd_print
        sgnd_print_sectionheader ""
        ask_decision --label "Join $SGND_ADC_FQDN to $SGND_ADC_REALM?" --choices "Yes|Y,No|N" --default "No" --var decision
        [[ "${decision^^}" == "YES" ]] || { sayinfo "Domain join cancelled."; return 0; }
        _adc_step_dns || return $?
        _adc_step_identity || return $?
        _adc_step_discover || return $?
        _adc_step_join || return $?
        _adc_step_sssd || return $?
        _adc_step_register_dns || return $?
        sayok "Active Directory client join sequence completed."
    }

    # fn: _adc_validate - Validate Active Directory client membership and local integration
    _adc_validate() {
        local realm="" failures=0 expected_fqdn="" current_dns="" ip="" dns_server="" desired_dns=""
        realm="$(realm list --name-only 2>/dev/null | head -n 1)"
        ip="$(sgnd_ad_primary_ipv4)"
        current_dns="$(sgnd_ad_current_dns)"
        desired_dns="$(sgnd_ad_domain_controller_ipv4 "$realm" 2>/dev/null || true)"
        dns_server="${desired_dns:-$current_dns}"
        expected_fqdn="$(hostname -f 2>/dev/null || true)"

        sgnd_print
        sgnd_print_sectionheader "Active Directory client validation"

        [[ -n "$realm" ]] && sgnd_print_labeledvalue --label "Realm membership" --value "Passed ($realm)" || { sgnd_print_labeledvalue --label "Realm membership" --value "Failed"; failures=$((failures+1)); }
        [[ -n "$realm" ]] && sgnd_ad_discover_kerberos "$realm" "$dns_server" && sgnd_print_labeledvalue --label "Kerberos discovery" --value "Passed" || { sgnd_print_labeledvalue --label "Kerberos discovery" --value "Failed"; failures=$((failures+1)); }
        [[ -n "$realm" ]] && sgnd_ad_discover_ldap "$realm" "$dns_server" && sgnd_print_labeledvalue --label "LDAP discovery" --value "Passed" || { sgnd_print_labeledvalue --label "LDAP discovery" --value "Failed"; failures=$((failures+1)); }
        systemctl is-active --quiet sssd.service && sgnd_print_labeledvalue --label "SSSD service" --value "Passed" || { sgnd_print_labeledvalue --label "SSSD service" --value "Failed"; failures=$((failures+1)); }
        if [[ -n "$current_dns" && ( -z "$desired_dns" || "$current_dns" == "$desired_dns" ) ]]; then
            sgnd_print_labeledvalue --label "AD DNS configured" --value "Passed ($current_dns)"
        else
            sgnd_print_labeledvalue --label "AD DNS configured" --value "Failed (${current_dns:-none}; expected ${desired_dns:-unknown})"
            failures=$((failures+1))
        fi
        if [[ -n "$realm" && -n "$ip" && "$expected_fqdn" == *."${realm,,}" ]]; then
            sgnd_print_labeledvalue --label "Machine FQDN" --value "Passed ($expected_fqdn)"
        else
            sgnd_print_labeledvalue --label "Machine FQDN" --value "Failed ($expected_fqdn)"
            failures=$((failures+1))
        fi
        if [[ -n "$realm" && -n "$ip" && -n "$dns_server" ]] && sgnd_ad_dns_a_record_matches "$expected_fqdn" "$ip" "$dns_server"; then
            sgnd_print_labeledvalue --label "Client DNS record" --value "Passed"
        else
            sgnd_print_labeledvalue --label "Client DNS record" --value "Failed"
            failures=$((failures+1))
        fi
        (( failures == 0 )) && { sayok "Active Directory client validation passed."; return 0; }
        sayfail "$failures Active Directory client validation check(s) failed."
        return 1
    }

    # fn: _adc_reconcile - Repair safe local Active Directory client drift
    _adc_reconcile() {
        local realm="" current_dns="" desired_dns="" ip="" fqdn="" repaired=0
        realm="$(realm list --name-only 2>/dev/null | head -n 1)"
        [[ -n "$realm" ]] || { sayfail "This machine is not joined to an Active Directory realm; use Join domain or an explicit rejoin."; return 1; }
        ip="$(sgnd_ad_primary_ipv4)"
        current_dns="$(sgnd_ad_current_dns)"
        desired_dns="$(sgnd_ad_domain_controller_ipv4 "$realm" 2>/dev/null || true)"
        [[ -n "$desired_dns" ]] || desired_dns="$current_dns"

        SGND_ADC_REALM="${realm,,}"
        SGND_ADC_IP="$ip"
        SGND_ADC_DNS_SERVER="$desired_dns"
        SGND_ADC_HOSTNAME_SHORT="$(hostname -s 2>/dev/null || true)"
        SGND_ADC_FQDN="${SGND_ADC_HOSTNAME_SHORT}.${SGND_ADC_REALM}"
        fqdn="$(hostname -f 2>/dev/null || true)"

        sgnd_print
        sgnd_print_sectionheader "Reconcile Active Directory client"
        sgnd_print_labeledvalue --label "Realm" --value "$realm"
        sgnd_print_labeledvalue --label "Current DNS" --value "${current_dns:-Not detected}"
        sgnd_print_labeledvalue --label "Detected AD DNS" --value "${desired_dns:-Not detected}"

        if [[ -n "$desired_dns" && "$current_dns" != "$desired_dns" ]]; then
            repaired=1
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would point the client resolver at Active Directory DNS '$desired_dns'."
            else
                declare -F sgnd_console_set_dns_server >/dev/null 2>&1 || { sayfail "Console DNS helper is unavailable."; return 1; }
                sgnd_console_set_dns_server "$desired_dns" || return $?
                sudo resolvectl flush-caches 2>/dev/null || true
                sayok "Active Directory DNS reconciled to $desired_dns."
            fi
        fi

        if [[ "$fqdn" != "$SGND_ADC_FQDN" ]]; then
            repaired=1
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would reconcile machine identity to '$SGND_ADC_FQDN'."
            else
                _adc_step_identity || return $?
            fi
        fi

        if ! systemctl is-active --quiet sssd.service; then
            repaired=1
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would enable and restart SSSD."
            else
                _adc_step_sssd || return $?
            fi
        fi

        if ! _adc_dns_record_matches; then
            repaired=1
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would register client DNS record '$SGND_ADC_FQDN' -> '$SGND_ADC_IP'."
            else
                _adc_step_register_dns || return $?
            fi
        fi

        (( repaired == 0 )) && sayok "Active Directory client configuration is already reconciled."
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
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "DRYRUN: Would leave $realm."; return 0; }
        sudo realm leave "$realm"
    }


# - Action dispatch ----------------------------------------------------------------
    _adc_action_is_mutating() {
        case "${1:-}" in join-all|install|dns|identity|join|sssd|register|reconcile|leave) return 0 ;; *) return 1 ;; esac
    }

    _adc_run_action() {
        local action="${1:?missing action}" rc=0
        case "$action" in
            join-all)  _adc_join_domain || rc=$? ;;
            install)   _adc_step_install_packages || rc=$? ;;
            preflight) _adc_step_preflight || rc=$? ;;
            dns)       _adc_step_dns || rc=$? ;;
            identity)  _adc_step_identity || rc=$? ;;
            discover)  _adc_step_discover || rc=$? ;;
            join)      _adc_step_join || rc=$? ;;
            sssd)      _adc_step_sssd || rc=$? ;;
            register)  _adc_step_register_dns || rc=$? ;;
            reconcile) _adc_reconcile || rc=$? ;;
            validate)  _adc_validate || rc=$? ;;
            status)    _adc_status || rc=$? ;;
            leave)     _adc_leave || rc=$? ;;
            *) sayfail "Unknown Active Directory client management action: $action"; return 2 ;;
        esac
        if (( rc == 0 )) && (( ${FLAG_DRYRUN:-0} == 1 )) && _adc_action_is_mutating "$action"; then
            sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
        fi
        return "$rc"
    }

# - Main ---------------------------------------------------------------------------
    main() {
        local action=""
        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        _load_ad_management_library || return $?
        action="${ACTION:-}"
        [[ -n "$action" ]] || { sayfail "No management action supplied. Use --action <action>."; return 2; }
        _adc_run_action "$action"
        local rc=$?
        sgnd_print
        sgnd_print_sectionheader ""
        return "$rc"
    }
    main "$@"
