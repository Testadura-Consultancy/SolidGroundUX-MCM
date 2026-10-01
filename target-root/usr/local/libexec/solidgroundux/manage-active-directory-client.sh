#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Active Directory Client
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627412
#   Shortname   : MANAGE_AD_CLIENT
#   Source      : manage-active-directory-client.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Join, reconcile, validate, and inspect an Active Directory client
#
#   Checksum : 2c51917c4b11d48a773e27c47f75f5a25263b9edaf8cad70fa3b8471bef2f40e
# Description:
#   Implements persistent Active Directory client management actions exposed by the
#   25-active-directory-client Management Console module.
#
# Attribution:
#   Developers    : Mark Fieten
#   Company       : Testadura Consultancy
#   Client        : -
#   Copyright     : © 2025 - 2026 Testadura Consultancy
#   License       : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
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
        if sgnd_ad_is_domain_member; then
            saywarning "This machine is already joined to an Active Directory realm; no join is required."
            return 2
        fi
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
            identity_script="/usr/local/libexec/solidgroundux/manage-identity.sh"
        else
            identity_script="${SGND_FRAMEWORK_ROOT%/}/usr/local/libexec/solidgroundux/manage-identity.sh"
        fi

        [[ -x "$identity_script" ]] || { sayfail "Cannot execute canonical identity tool: $identity_script"; return 1; }
        "$identity_script" --dns-only --DNS "$SGND_ADC_DNS_SERVER" --DNS-search "$SGND_ADC_REALM" --Auto || return $?
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

    # fn: _adc_host_keytab_valid - Validate the local Active Directory host keytab
        # . Purpose
        #   Confirm that /etc/krb5.keytab exists, contains usable principals, and authenticates
        #   the machine account against the joined Active Directory realm.
        #
        # . Returns
        #   0 when the host keytab is readable by root and adcli validates the machine trust;
        #   1 otherwise.
        #
        # . Usage
        #   _adc_host_keytab_valid
    _adc_host_keytab_valid() {
        sudo test -s /etc/krb5.keytab || return 1
        sudo klist -kte /etc/krb5.keytab >/dev/null 2>&1 || return 1
        sudo adcli testjoin --host-keytab=/etc/krb5.keytab >/dev/null 2>&1 || return 1
        return 0
    }

    # fn: _adc_ensure_host_keytab - Repair a missing or invalid Active Directory host keytab
        # . Purpose
        #   Restore the machine keytab required by SSSD without changing the configured realm,
        #   DNS, or host identity.
        #
        # . Behavior
        #   - Returns immediately when /etc/krb5.keytab already validates.
        #   - Requires an existing realmd domain membership before attempting repair.
        #   - Uses adcli join with the existing machine identity to refresh the computer-account
        #     password and recreate /etc/krb5.keytab.
        #   - Prompts for an authorized AD account only when repair is actually required.
        #   - Validates the recreated keytab with klist and adcli testjoin before returning.
        #
        # . Returns
        #   0 when the keytab is already valid or repaired successfully; non-zero otherwise.
        #
        # . Usage
        #   _adc_ensure_host_keytab
    _adc_ensure_host_keytab() {
        local realm=""
        local fqdn=""
        local computer_name=""
        local repair_account="${SGND_ADC_ACCOUNT:-Administrator}"

        _adc_host_keytab_valid && return 0

        realm="$(realm list --name-only 2>/dev/null | head -n 1 || true)"
        [[ -n "$realm" ]] || {
            sayfail "A host keytab cannot be repaired because this machine is not joined to an Active Directory realm."
            return 1
        }

        fqdn="$(hostname -f 2>/dev/null || true)"
        computer_name="$(hostname -s 2>/dev/null || true)"
        [[ -n "$fqdn" && -n "$computer_name" ]] || {
            sayfail "The machine identity required to repair /etc/krb5.keytab could not be determined."
            return 1
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would repair /etc/krb5.keytab for '$computer_name' in realm '$realm'."
            return 0
        fi

        saywarning "Active Directory host keytab is missing or invalid: /etc/krb5.keytab"
        ask \
            --label "AD repair account" \
            --var repair_account \
            --default "$repair_account" \
            --validate _adc_validate_account || return $?

        sayinfo "Repairing the Active Directory host keytab for $fqdn."
        sudo adcli join \
            --domain="$realm" \
            --login-user="$repair_account" \
            --host-fqdn="$fqdn" \
            --computer-name="$computer_name" \
            --host-keytab=/etc/krb5.keytab \
            </dev/tty || {
                sayfail "Active Directory host keytab repair failed."
                return 1
            }

        _adc_host_keytab_valid || {
            sayfail "The repaired Active Directory host keytab could not be validated."
            return 1
        }

        sayok "Active Directory host keytab repaired and validated."
        return 0
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
        _adc_ensure_host_keytab || return $?
        sayok "Machine joined to $SGND_ADC_REALM with a validated host keytab."
    }

    # fn: _adc_step_sssd
        # . Purpose
        #   Normalize, enable, restart, and validate the SSSD client service.
        #
        # . Behavior
        #   - Removes obsolete SolidGroundUX-managed SSSD settings through the shared AD API.
        #   - Validates the resulting SSSD configuration before activation.
        #   - Enables and restarts sssd.service only after configuration validation succeeds.
        #
        # . Returns
        #   0 when the SSSD configuration is valid and the service is active; non-zero otherwise.
        #
        # . Usage
        #   _adc_step_sssd
    _adc_step_sssd() {
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "DRYRUN: Would normalize, validate, and restart SSSD."; return 0; }
        sgnd_ad_normalize_sssd_config || return $?
        sudo systemctl enable sssd.service >/dev/null 2>&1 || true
        sudo systemctl restart sssd.service || { sayfail "SSSD could not be restarted."; return 1; }
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

    # fn: _adc_join_domain - Run the complete Active Directory client join sequence
        # . Purpose
        #   Execute the complete join workflow in one process so collected join context is
        #   preserved while exposing the failing child step to the console module.
        #
        # . Behavior
        #   - Reports each child step before it starts so progress remains visible during the run.
        #   - Keeps realm, DNS, account, and machine identity context in this process.
        #   - Returns a distinct workflow status for each failing child step.
        #   - Returns a distinct cancellation status when the administrator declines the join.
        #
        # . Returns
        #   0  when every join step succeeds.
        #   21 when prerequisite installation fails.
        #   20 when the machine is already joined (warning; no join required).
        #   22 when join-input validation fails.
        #   23 when the administrator cancels after successful preflight.
        #   24 when Active Directory DNS configuration fails.
        #   25 when client identity preparation fails.
        #   26 when Active Directory service discovery fails.
        #   27 when the realm join fails.
        #   28 when SSSD activation fails.
        #   29 when client DNS registration fails.
        #
        # . Usage
        #   _adc_join_domain
    _adc_join_domain() {
        local decision="No"

        sayinfo "Join step 1/8: Install AD client prerequisites."
        _adc_step_install_packages || return 21

        sayinfo "Join step 2/8: Validate join inputs."
        _adc_step_preflight
        case $? in
            0) ;;
            2) return 20 ;;
            *) return 22 ;;
        esac

        sgnd_print
        sgnd_print_sectionheader ""
        ask_decision --label "Join $SGND_ADC_FQDN to $SGND_ADC_REALM?" --choices "Yes|Y,No|N" --default "No" --var decision
        [[ "${decision^^}" == "YES" ]] || { sayinfo "Domain join cancelled."; return 23; }

        sayinfo "Join step 3/8: Configure Active Directory DNS."
        _adc_step_dns || return 24

        sayinfo "Join step 4/8: Prepare client identity."
        _adc_step_identity || return 25

        sayinfo "Join step 5/8: Discover Active Directory services."
        _adc_step_discover || return 26

        sayinfo "Join step 6/8: Join Active Directory realm."
        _adc_step_join || return 27

        sayinfo "Join step 7/8: Start SSSD."
        _adc_step_sssd || return 28

        sayinfo "Join step 8/8: Register client DNS."
        _adc_step_register_dns || return 29

        sayok "Active Directory client join sequence completed."
        return 0
    }

    # fn: _adc_validate - Validate Active Directory client membership, DNS/search-domain configuration, and local integration
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
        if [[ -n "$realm" ]] && _adc_host_keytab_valid; then
            sgnd_print_labeledvalue --label "Host keytab" --value "Passed"
        else
            sgnd_print_labeledvalue --label "Host keytab" --value "Failed"
            failures=$((failures+1))
        fi
        [[ -n "$realm" ]] && sgnd_ad_discover_kerberos "$realm" "$dns_server" && sgnd_print_labeledvalue --label "Kerberos discovery" --value "Passed" || { sgnd_print_labeledvalue --label "Kerberos discovery" --value "Failed"; failures=$((failures+1)); }
        [[ -n "$realm" ]] && sgnd_ad_discover_ldap "$realm" "$dns_server" && sgnd_print_labeledvalue --label "LDAP discovery" --value "Passed" || { sgnd_print_labeledvalue --label "LDAP discovery" --value "Failed"; failures=$((failures+1)); }
        systemctl is-active --quiet sssd.service && sgnd_print_labeledvalue --label "SSSD service" --value "Passed" || { sgnd_print_labeledvalue --label "SSSD service" --value "Failed"; failures=$((failures+1)); }
        if sudo sssctl config-check >/dev/null 2>&1; then
            sgnd_print_labeledvalue --label "SSSD configuration" --value "Passed"
        else
            sgnd_print_labeledvalue --label "SSSD configuration" --value "Failed"
            failures=$((failures+1))
        fi
        if [[ -n "$current_dns" && ( -z "$desired_dns" || "$current_dns" == "$desired_dns" ) ]]; then
            sgnd_print_labeledvalue --label "AD DNS configured" --value "Passed ($current_dns)"
        else
            sgnd_print_labeledvalue --label "AD DNS configured" --value "Failed (${current_dns:-none}; expected ${desired_dns:-unknown})"
            failures=$((failures+1))
        fi
        local current_search_domain=""
        current_search_domain="$(resolvectl domain "$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')" 2>/dev/null | awk -F: 'NR == 1 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); split($2, domains, /[[:space:]]+/); for (i = 1; i <= length(domains); i++) if (domains[i] !~ /^~/ && domains[i] != "") {print domains[i]; exit}}')"
        if [[ -n "$realm" && "${current_search_domain,,}" == "${realm,,}" ]]; then
            sgnd_print_labeledvalue --label "DNS search domain" --value "Passed ($current_search_domain)"
        else
            sgnd_print_labeledvalue --label "DNS search domain" --value "Failed (${current_search_domain:-none}; expected ${realm:-unknown})"
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
        # . Behavior
        #   - Reconciles DNS server, DNS search-domain, and machine identity drift.
        #   - Repairs a missing or invalid /etc/krb5.keytab before SSSD activation.
        #   - Restarts SSSD when inactive and repairs the client DNS record when needed.
    _adc_reconcile() {
        local realm="" current_dns="" desired_dns="" current_search_domain="" primary_iface="" ip="" fqdn="" repaired=0
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
        primary_iface="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
        if [[ -n "$primary_iface" ]] && command -v resolvectl >/dev/null 2>&1; then
            current_search_domain="$(resolvectl domain "$primary_iface" 2>/dev/null | awk -F: 'NR == 1 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); split($2, domains, /[[:space:]]+/); for (i = 1; i <= length(domains); i++) if (domains[i] !~ /^~/ && domains[i] != "") {print domains[i]; exit}}')"
        fi

        sgnd_print
        sgnd_print_sectionheader "Reconcile Active Directory client"
        sgnd_print_labeledvalue --label "Realm" --value "$realm"
        sgnd_print_labeledvalue --label "Current DNS" --value "${current_dns:-Not detected}"
        sgnd_print_labeledvalue --label "Detected AD DNS" --value "${desired_dns:-Not detected}"
        sgnd_print_labeledvalue --label "DNS search domain" --value "${current_search_domain:-Not detected}"

        if [[ -n "$desired_dns" && ( "$current_dns" != "$desired_dns" || "${current_search_domain,,}" != "${SGND_ADC_REALM,,}" ) ]]; then
            repaired=1
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would reconcile Active Directory DNS to '$desired_dns' with search domain '$SGND_ADC_REALM'."
            else
                _adc_step_dns || return $?
                current_dns="$(sgnd_ad_current_dns)"
                current_search_domain="$(resolvectl domain "$primary_iface" 2>/dev/null | awk -F: 'NR == 1 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); split($2, domains, /[[:space:]]+/); for (i = 1; i <= length(domains); i++) if (domains[i] !~ /^~/ && domains[i] != "") {print domains[i]; exit}}')"
                [[ "$current_dns" == "$desired_dns" && "${current_search_domain,,}" == "${SGND_ADC_REALM,,}" ]] || {
                    sayfail "Active Directory DNS reconciliation did not produce the expected DNS server and search domain."
                    return 1
                }
                sayok "Active Directory DNS reconciled to $desired_dns with search domain $SGND_ADC_REALM."
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

        if ! _adc_host_keytab_valid; then
            repaired=1
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would repair and validate /etc/krb5.keytab."
            else
                _adc_ensure_host_keytab || return $?
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
