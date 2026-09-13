# ==================================================================================
# SolidGroundUX - Active Directory Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624102
#   Checksum    : 08eae622f9f542950ea2431dd34887a01a82ea2728dc8efbd03fb98aeaef6dfd
#   Source      : 20-active-directory-server.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Install, provision, validate, and inspect a Samba Active Directory server
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
    SGND_AD_SERVER_MODULE_VERSION="1.0.0"
    SGND_AD_SERVER_MODULE_DESC="Install, provision, validate, and inspect a Samba Active Directory domain controller"
    SGND_MODULE_NAME="$SGND_AD_SERVER_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_AD_SERVER_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_AD_SERVER_MODULE_DESC"

# - Provisioning context -----------------------------------------------------------
    SGND_AD_REALM=""
    SGND_AD_DNS_DOMAIN=""
    SGND_AD_NETBIOS_DOMAIN=""
    SGND_AD_DNS_FORWARDER=""
    SGND_AD_SERVER_IP=""
    SGND_AD_HOSTNAME_SHORT=""
    SGND_AD_HOSTNAME_FQDN=""

    # fn: _adsvr_validate_realm
        # . Purpose
        #   Validate an Active Directory DNS/Kerberos realm name.
        #
        # . Returns
        #   0 for a valid dotted realm name; 1 otherwise.
        #
        # . Usage
        #   _adsvr_validate_realm
    _adsvr_validate_realm() { [[ "${1-}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; }
    # fn: _adsvr_validate_netbios
        # . Purpose
        #   Validate the NetBIOS domain name.
        #
        # . Returns
        #   0 for a valid NetBIOS name of at most 15 characters; 1 otherwise.
        #
        # . Usage
        #   _adsvr_validate_netbios
    _adsvr_validate_netbios() { [[ "${1-}" =~ ^[A-Za-z][A-Za-z0-9_-]{0,14}$ ]]; }
    # fn: _adsvr_primary_ipv4
        # . Purpose
        #   Resolve the machine primary routed IPv4 address.
        #
        # . Returns
        #   Prints the primary IPv4 address when available.
        #
        # . Usage
        #   _adsvr_primary_ipv4
    _adsvr_primary_ipv4() { ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i=1;i<=NF;i++) if ($i=="src") { print $(i+1); exit } }'; }
    # fn: _adsvr_default_gateway
        # . Purpose
        #   Resolve the first IPv4 default gateway.
        #
        # . Returns
        #   Prints the gateway address when available.
        #
        # . Usage
        #   _adsvr_default_gateway
    _adsvr_default_gateway() { ip -4 route show default 2>/dev/null | awk 'NR==1 { print $3 }'; }

    # fn: _adsvr_domain_is_provisioned
        # . Purpose
        #   Detect whether this machine already contains a Samba AD domain.
        #
        # . Returns
        #   0 when sam.ldb exists and Samba reports the AD DC server role; 1 otherwise.
        #
        # . Usage
        #   _adsvr_domain_is_provisioned
    _adsvr_domain_is_provisioned() {
        [[ -s /var/lib/samba/private/sam.ldb ]] && sudo testparm -s --parameter-name='server role' 2>/dev/null | grep -qi '^active directory domain controller$'
    }

    # fn: _adsvr_collect_context
        # . Purpose
        #   Collect and validate the realm, NetBIOS, DNS forwarder, host, and server-address provisioning context.
        #
        # . Returns
        #   0 when a complete provisioning context is available; non-zero on validation or cancellation.
        #
        # . Usage
        #   _adsvr_collect_context
    _adsvr_collect_context() {
        local current_domain=""
        SGND_AD_HOSTNAME_SHORT="$(hostname -s 2>/dev/null || true)"
        SGND_AD_SERVER_IP="$(_adsvr_primary_ipv4)"
        current_domain="$(hostname -d 2>/dev/null || true)"
        [[ -n "$current_domain" ]] || current_domain="testadura.hq"

        [[ -n "$SGND_AD_HOSTNAME_SHORT" && "$SGND_AD_HOSTNAME_SHORT" != localhost ]] || { sayfail "A valid machine hostname is required."; return 1; }
        [[ -n "$SGND_AD_SERVER_IP" && "$SGND_AD_SERVER_IP" != 127.* ]] || { sayfail "A primary non-loopback IPv4 address is required."; return 1; }

        [[ -n "$SGND_AD_REALM" ]] || SGND_AD_REALM="${current_domain^^}"
        [[ -n "$SGND_AD_NETBIOS_DOMAIN" ]] || SGND_AD_NETBIOS_DOMAIN="${current_domain%%.*}"
        SGND_AD_NETBIOS_DOMAIN="${SGND_AD_NETBIOS_DOMAIN^^}"
        [[ -n "$SGND_AD_DNS_FORWARDER" ]] || SGND_AD_DNS_FORWARDER="$(_adsvr_default_gateway)"
        [[ -n "$SGND_AD_DNS_FORWARDER" ]] || SGND_AD_DNS_FORWARDER="192.168.0.1"

        ask --label "Kerberos realm" --var SGND_AD_REALM --default "$SGND_AD_REALM" --validate _adsvr_validate_realm || return $?
        SGND_AD_REALM="${SGND_AD_REALM^^}"
        SGND_AD_DNS_DOMAIN="${SGND_AD_REALM,,}"
        ask --label "NetBIOS domain" --var SGND_AD_NETBIOS_DOMAIN --default "$SGND_AD_NETBIOS_DOMAIN" --validate _adsvr_validate_netbios || return $?
        SGND_AD_NETBIOS_DOMAIN="${SGND_AD_NETBIOS_DOMAIN^^}"
        ask --label "DNS forwarder" --var SGND_AD_DNS_FORWARDER --default "$SGND_AD_DNS_FORWARDER" --validate sgnd_validate_ipv4 || return $?
        SGND_AD_HOSTNAME_FQDN="${SGND_AD_HOSTNAME_SHORT}.${SGND_AD_DNS_DOMAIN}"

        sgnd_print
        sgnd_print_labeledvalue --label "Hostname" --value "$SGND_AD_HOSTNAME_SHORT"
        sgnd_print_labeledvalue --label "FQDN" --value "$SGND_AD_HOSTNAME_FQDN"
        sgnd_print_labeledvalue --label "Server IPv4" --value "$SGND_AD_SERVER_IP"
        sgnd_print_labeledvalue --label "DNS domain" --value "$SGND_AD_DNS_DOMAIN"
        sgnd_print_labeledvalue --label "Kerberos realm" --value "$SGND_AD_REALM"
        sgnd_print_labeledvalue --label "NetBIOS domain" --value "$SGND_AD_NETBIOS_DOMAIN"
        sgnd_print_labeledvalue --label "DNS forwarder" --value "$SGND_AD_DNS_FORWARDER"
    }

    # fn: _adsvr_load_context
        # . Purpose
        #   Load Active Directory context from the current Samba configuration.
        #
        # . Returns
        #   0 when a configured realm can be loaded; 1 otherwise.
        #
        # . Usage
        #   _adsvr_load_context
    _adsvr_load_context() {
        local realm="" workgroup="" forwarder=""
        realm="$(sudo testparm -s --parameter-name='realm' 2>/dev/null || true)"
        [[ -n "$realm" ]] || return 1
        workgroup="$(sudo testparm -s --parameter-name='workgroup' 2>/dev/null || true)"
        forwarder="$(sudo testparm -s --parameter-name='dns forwarder' 2>/dev/null || true)"
        SGND_AD_REALM="${realm^^}"
        SGND_AD_DNS_DOMAIN="${realm,,}"
        SGND_AD_NETBIOS_DOMAIN="${workgroup^^}"
        SGND_AD_DNS_FORWARDER="$forwarder"
        SGND_AD_SERVER_IP="$(_adsvr_primary_ipv4)"
        SGND_AD_HOSTNAME_SHORT="$(hostname -s 2>/dev/null || true)"
        SGND_AD_HOSTNAME_FQDN="${SGND_AD_HOSTNAME_SHORT}.${SGND_AD_DNS_DOMAIN}"
    }

    # fn: _adsvr_require_context
        # . Purpose
        #   Ensure Active Directory provisioning context is available.
        #
        # . Returns
        #   0 when existing or interactively collected context is available; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_require_context
    _adsvr_require_context() {
        [[ -n "$SGND_AD_REALM" && -n "$SGND_AD_SERVER_IP" ]] && return 0
        _adsvr_load_context && return 0
        _adsvr_collect_context
    }

# - Helpers -----------------------------------------------------------------------
    # fn: _adsvr_prepare_hosts
        # . Purpose
        #   Rewrite /etc/hosts so the domain controller short name resolves to its canonical FQDN and IPv4 address.
        #
        # . Returns
        #   0 when hostname -f resolves to the expected FQDN; non-zero on file or validation failure.
        #
        # . Usage
        #   _adsvr_prepare_hosts
    _adsvr_prepare_hosts() {
        local tmp_file=""
        tmp_file="$(mktemp)" || return 1
        awk -v short_name="$SGND_AD_HOSTNAME_SHORT" '
            function contains_host(line, host, n, f, i) { n=split(line,f,/[[:space:]]+/); for(i=2;i<=n;i++) if(tolower(f[i])==tolower(host)) return 1; return 0 }
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
            { if (!contains_host($0,short_name)) print }
        ' /etc/hosts > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
        printf '%s\t%s %s\n' "$SGND_AD_SERVER_IP" "$SGND_AD_HOSTNAME_FQDN" "$SGND_AD_HOSTNAME_SHORT" >> "$tmp_file"
        sudo install -o root -g root -m 0644 "$tmp_file" /etc/hosts || { rm -f "$tmp_file"; return 1; }
        rm -f "$tmp_file"
        [[ "$(hostname -f 2>/dev/null || true)" == "$SGND_AD_HOSTNAME_FQDN" ]]
    }

    # fn: _adsvr_set_dns_forwarder
        # . Purpose
        #   Set the Samba global dns forwarder value while preserving the rest of smb.conf.
        #
        # . Returns
        #   0 when smb.conf is updated; non-zero on temporary-file or install failure.
        #
        # . Usage
        #   _adsvr_set_dns_forwarder
    _adsvr_set_dns_forwarder() {
        local tmp_file=""
        tmp_file="$(mktemp)" || return 1
        awk -v forwarder="$SGND_AD_DNS_FORWARDER" '
            BEGIN { in_global=0; written=0 }
            /^\[global\][[:space:]]*$/ { in_global=1; print; next }
            /^\[/ { if(in_global && !written){printf "\tdns forwarder = %s\n",forwarder; written=1} in_global=0 }
            in_global && /^[[:space:]]*dns forwarder[[:space:]]*=/ { if(!written){printf "\tdns forwarder = %s\n",forwarder; written=1} next }
            { print }
            END { if(in_global && !written) printf "\tdns forwarder = %s\n",forwarder }
        ' /etc/samba/smb.conf > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
        sudo install -o root -g root -m 0644 "$tmp_file" /etc/samba/smb.conf || { rm -f "$tmp_file"; return 1; }
        rm -f "$tmp_file"
    }

    # fn: _adsvr_wait_configured
        # . Purpose
        #   Wait for Samba is-configured to report the service ready.
        #
        # . Returns
        #   0 when Samba becomes configured before the timeout; 1 otherwise.
        #
        # . Usage
        #   _adsvr_wait_configured
    _adsvr_wait_configured() {
        local elapsed=0 timeout_seconds="${1:-20}" helper="/usr/share/samba/is-configured"
        [[ -x "$helper" ]] || { sayfail "Samba configuration helper unavailable: $helper"; return 1; }
        while (( elapsed < timeout_seconds )); do
            sudo "$helper" samba >/dev/null 2>&1 && return 0
            sleep 1; elapsed=$((elapsed + 1))
        done
        sayfail "Samba did not become service-ready within ${timeout_seconds}s."
        return 1
    }

    # fn: _adsvr_wait_dns
        # . Purpose
        #   Wait until Samba owns IPv4 TCP and UDP port 53 on the domain controller.
        #
        # . Returns
        #   0 when both DNS listeners are detected before timeout; 1 otherwise.
        #
        # . Usage
        #   _adsvr_wait_dns
    _adsvr_wait_dns() {
        local elapsed=0 timeout_seconds="${1:-15}" pattern="${SGND_AD_SERVER_IP//./\\.}"
        local tcp="" udp=""
        while (( elapsed < timeout_seconds )); do
            tcp="$(sudo ss -lntp 2>/dev/null || true)"; udp="$(sudo ss -lnup 2>/dev/null || true)"
            if grep -E "(^|[[:space:]])(0\\.0\\.0\\.0|${pattern}):53[[:space:]]" <<< "$tcp" | grep -Eq '(dns\[master\]|samba)' && \
               grep -E "(^|[[:space:]])(0\\.0\\.0\\.0|${pattern}):53[[:space:]]" <<< "$udp" | grep -Eq '(dns\[master\]|samba)'; then return 0; fi
            sleep 1; elapsed=$((elapsed + 1))
        done
        sayfail "Samba does not own IPv4 TCP and UDP port 53 on $SGND_AD_SERVER_IP."
        return 1
    }

# - Provisioning steps ------------------------------------------------------------
    # fn: _adsvr_step_install_packages
        # . Purpose
        #   Install and validate Samba AD/DC, Kerberos, and DNS prerequisites.
        #
        # . Returns
        #   0 on success or dry-run; non-zero on package or command validation failure.
        #
        # . Usage
        #   _adsvr_step_install_packages
    _adsvr_step_install_packages() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would install Samba AD server prerequisites."; return 0; fi
        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y bind9-dnsutils krb5-user samba-ad-dc samba-common-bin || return 1
        sudo systemctl disable --now smbd.service nmbd.service winbind.service 2>/dev/null || true
        sudo systemctl mask smbd.service nmbd.service winbind.service 2>/dev/null || true
        sudo systemctl unmask samba-ad-dc.service || return 1
        command -v samba-tool >/dev/null && command -v kinit >/dev/null && command -v host >/dev/null || return 1
        sayok "Active Directory server prerequisites installed."
    }

    # fn: _adsvr_step_preflight
        # . Purpose
        #   Collect provisioning inputs and reject an already-provisioned or invalid domain-controller state.
        #
        # . Returns
        #   0 when provisioning may continue; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_step_preflight
    _adsvr_step_preflight() {
        _adsvr_collect_context || return 1
        _adsvr_domain_is_provisioned && { sayfail "This machine already contains a provisioned AD domain."; return 1; }
        [[ "$SGND_AD_DNS_FORWARDER" != "$SGND_AD_SERVER_IP" && "$SGND_AD_DNS_FORWARDER" != 127.* ]] || { sayfail "DNS forwarder must be upstream, not this DC."; return 1; }
        sayok "AD server provisioning inputs validated."
    }

    # fn: _adsvr_step_identity
        # . Purpose
        #   Prepare the domain controller hostname and hosts-file identity.
        #
        # . Returns
        #   0 when the configured FQDN is active; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_step_identity
    _adsvr_step_identity() {
        _adsvr_require_context || return 1
        sayinfo "Changes: /etc/hosts -> $SGND_AD_HOSTNAME_FQDN ($SGND_AD_SERVER_IP)."
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would prepare the DC FQDN."; return 0; }
        _adsvr_prepare_hosts || { sayfail "Could not prepare the DC FQDN."; return 1; }
        sayok "Domain controller identity prepared."
    }

    # fn: _adsvr_step_provision
        # . Purpose
        #   Provision the Samba Active Directory domain database and configuration.
        #
        # . Returns
        #   0 when samba-tool domain provision completes; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_step_provision
    _adsvr_step_provision() {
        local backup=""
        _adsvr_require_context || return 1
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would provision $SGND_AD_REALM."; return 0; }
        sudo systemctl stop samba-ad-dc.service 2>/dev/null || true
        if [[ -e /etc/samba/smb.conf ]]; then backup="/etc/samba/smb.conf.pre-ad.$(date +%Y%m%d%H%M%S)"; sudo mv /etc/samba/smb.conf "$backup" || return 1; fi
        sudo samba-tool domain provision --use-rfc2307 --realm="$SGND_AD_REALM" --domain="$SGND_AD_NETBIOS_DOMAIN" --server-role=dc --dns-backend=SAMBA_INTERNAL </dev/tty || { [[ -n "$backup" && ! -e /etc/samba/smb.conf ]] && sudo mv "$backup" /etc/samba/smb.conf; return 1; }
        _adsvr_domain_is_provisioned || { sayfail "Samba provisioning could not be validated."; return 1; }
        sayok "Samba Active Directory database provisioned."
    }

    # fn: _adsvr_step_domain_settings
        # . Purpose
        #   Apply initial Administrator password policy and Samba DNS forwarder settings.
        #
        # . Returns
        #   0 when the requested initial settings are applied; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_step_domain_settings
    _adsvr_step_domain_settings() {
        _adsvr_require_context || return 1
        _adsvr_domain_is_provisioned || { sayfail "Provision the domain first."; return 1; }
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would set Administrator policy and DNS forwarder."; return 0; }
        sayinfo "Set the domain Administrator password."
        sudo samba-tool user setpassword Administrator </dev/tty || return 1
        sudo samba-tool user setexpiry Administrator --noexpiry || return 1
        _adsvr_set_dns_forwarder || return 1
        [[ "$(sudo testparm -s --parameter-name='dns forwarder' 2>/dev/null || true)" == "$SGND_AD_DNS_FORWARDER" ]] || return 1
        sayok "Initial domain settings applied."
    }

    # fn: _adsvr_step_kerberos
        # . Purpose
        #   Install and validate the Kerberos configuration generated by Samba.
        #
        # . Returns
        #   0 when /etc/krb5.conf is installed and usable; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_step_kerberos
    _adsvr_step_kerberos() {
        _adsvr_require_context || return 1
        [[ -s /var/lib/samba/private/krb5.conf ]] || { sayfail "Generated Kerberos configuration is missing."; return 1; }
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would install /etc/krb5.conf."; return 0; }
        sudo install -o root -g root -m 0644 /var/lib/samba/private/krb5.conf /etc/krb5.conf || return 1
        grep -qi "default_realm[[:space:]]*=[[:space:]]*$SGND_AD_REALM" /etc/krb5.conf || return 1
        sayok "Kerberos configuration installed."
    }

    # fn: _adsvr_step_resolver
        # . Purpose
        #   Configure the domain controller resolver to use Samba DNS and prepare port 53 ownership.
        #
        # . Returns
        #   0 when resolver configuration succeeds; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_step_resolver
    _adsvr_step_resolver() {
        local dropin_dir="/etc/systemd/resolved.conf.d" dropin_file="/etc/systemd/resolved.conf.d/solidgroundux-samba-ad.conf" listeners=""
        _adsvr_require_context || return 1
        declare -F sgnd_console_set_dns_server >/dev/null 2>&1 || { sayfail "Console DNS helper is unavailable."; return 1; }
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would point the DC at its own DNS and release port 53."; return 0; }
        sgnd_console_set_dns_server "$SGND_AD_SERVER_IP" || return 1
        sudo install -d -m 0755 "$dropin_dir" || return 1
        printf '%s\n' '[Resolve]' "Domains=~$SGND_AD_DNS_DOMAIN" 'DNSStubListener=no' | sudo tee "$dropin_file" >/dev/null || return 1
        grep -Fxq "Domains=~$SGND_AD_DNS_DOMAIN" "$dropin_file" && grep -Fxq 'DNSStubListener=no' "$dropin_file" || return 1
        sudo ln -sfn /run/systemd/resolve/resolv.conf /etc/resolv.conf || return 1
        sudo systemctl restart systemd-resolved.service || return 1
        sleep 1
        listeners="$(sudo ss -lntup 2>/dev/null | grep -E '127\.0\.0\.(53|54):53[[:space:]]' | grep -F 'systemd-resolve' || true)"
        [[ -z "$listeners" ]] || { sayfail "systemd-resolved still owns an IPv4 DNS stub listener."; return 1; }
        sayok "Local resolver prepared for Samba AD DNS."
    }

    # fn: _adsvr_step_start
        # . Purpose
        #   Start Samba AD/DC and wait for service and DNS readiness.
        #
        # . Returns
        #   0 when the AD/DC service and DNS listeners become ready; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_step_start
    _adsvr_step_start() {
        _adsvr_require_context || return 1
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would start samba-ad-dc.service."; return 0; }
        _adsvr_wait_configured 20 || return 1
        sudo systemctl unmask samba-ad-dc.service || return 1
        sudo systemctl enable --now samba-ad-dc.service || return 1
        systemctl is-active --quiet samba-ad-dc.service || { sudo systemctl status samba-ad-dc.service --no-pager || true; return 1; }
        _adsvr_wait_dns 15 || return 1
        sayok "Samba AD/DC and IPv4 DNS are active."
    }

    # fn: _adsvr_step_register_dns
        # . Purpose
        #   Register and verify the domain controller DNS records required for AD discovery.
        #
        # . Returns
        #   0 when the A, SOA, Kerberos, and LDAP records validate; non-zero otherwise.
        #
        # . Usage
        #   _adsvr_step_register_dns
    _adsvr_step_register_dns() {
        _adsvr_require_context || return 1
        systemctl is-active --quiet samba-ad-dc.service || { sayfail "AD/DC service is not active."; return 1; }
        (( ${FLAG_DRYRUN:-0} == 1 )) && { sayinfo "Dry run: Would register the DC DNS records."; return 0; }
        sudo samba_dnsupdate --verbose || return 1
        host -t SOA "$SGND_AD_DNS_DOMAIN" "$SGND_AD_SERVER_IP" >/dev/null 2>&1 || return 1
        host -t A "$SGND_AD_HOSTNAME_FQDN" "$SGND_AD_SERVER_IP" 2>/dev/null | awk '/has address/ {print $NF}' | grep -Fxq "$SGND_AD_SERVER_IP" || return 1
        host -t SRV "_kerberos._tcp.$SGND_AD_DNS_DOMAIN" "$SGND_AD_SERVER_IP" >/dev/null 2>&1 || return 1
        host -t SRV "_ldap._tcp.$SGND_AD_DNS_DOMAIN" "$SGND_AD_SERVER_IP" >/dev/null 2>&1 || return 1
        sayok "Domain controller DNS records registered."
    }

    # fn: _adsvr_provision_domain
        # . Purpose
        #   Run the complete tracked Active Directory server provisioning sequence.
        #
        # . Returns
        #   0 when provisioning completes or is cancelled before changes; non-zero on a failed step.
        #
        # . Usage
        #   _adsvr_provision_domain
    _adsvr_provision_domain() {
        local decision="No"
        sgnd_console_run_tracked "adsvr-install" _adsvr_step_install_packages || return $?
        sgnd_console_run_tracked "adsvr-preflight" _adsvr_step_preflight || return $?
        ask_decision --label "Provision $SGND_AD_REALM on $SGND_AD_HOSTNAME_SHORT?" --choices "Yes|Y,No|N" --default "No" --var decision
        [[ "${decision^^}" == "YES" ]] || { sayinfo "Domain provisioning cancelled."; return 0; }
        sgnd_console_run_tracked "adsvr-identity" _adsvr_step_identity || return $?
        sgnd_console_run_tracked "adsvr-domain" _adsvr_step_provision || return $?
        sgnd_console_run_tracked "adsvr-settings" _adsvr_step_domain_settings || return $?
        sgnd_console_run_tracked "adsvr-krb" _adsvr_step_kerberos || return $?
        sgnd_console_run_tracked "adsvr-resolver" _adsvr_step_resolver || return $?
        sgnd_console_run_tracked "adsvr-start" _adsvr_step_start || return $?
        sgnd_console_run_tracked "adsvr-dns" _adsvr_step_register_dns || return $?
        sayok "Active Directory domain provisioning sequence completed."
    }

# - Validation/status -------------------------------------------------------------
    # fn: _adsvr_validate
        # . Purpose
        #   Run active validation checks for the Samba AD/DC service, DNS, directory, and Kerberos discovery.
        #
        # . Returns
        #   0 when all checks pass; 1 when one or more checks fail.
        #
        # . Usage
        #   _adsvr_validate
    _adsvr_validate() {
        local failures=0 realm="" dns_domain="" ip="" tcp="" udp="" pattern=""
        _adsvr_load_context || { sayfail "No provisioned AD domain was found."; return 1; }
        realm="$SGND_AD_REALM"; dns_domain="$SGND_AD_DNS_DOMAIN"; ip="$SGND_AD_SERVER_IP"; pattern="${ip//./\\.}"
        sgnd_print; sgnd_print_sectionheader "Active Directory server validation"
        systemctl is-active --quiet samba-ad-dc.service && sgnd_print_labeledvalue --label "AD/DC service" --value "Passed" || { sgnd_print_labeledvalue --label "AD/DC service" --value "Failed"; failures=$((failures+1)); }
        tcp="$(sudo ss -lntp 2>/dev/null || true)"; udp="$(sudo ss -lnup 2>/dev/null || true)"
        grep -E "(^|[[:space:]])(0\\.0\\.0\\.0|${pattern}):53[[:space:]]" <<< "$tcp" | grep -Eq '(dns\[master\]|samba)' && sgnd_print_labeledvalue --label "Samba DNS TCP" --value "Passed" || { sgnd_print_labeledvalue --label "Samba DNS TCP" --value "Failed"; failures=$((failures+1)); }
        grep -E "(^|[[:space:]])(0\\.0\\.0\\.0|${pattern}):53[[:space:]]" <<< "$udp" | grep -Eq '(dns\[master\]|samba)' && sgnd_print_labeledvalue --label "Samba DNS UDP" --value "Passed" || { sgnd_print_labeledvalue --label "Samba DNS UDP" --value "Failed"; failures=$((failures+1)); }
        host -t SOA "$dns_domain" >/dev/null 2>&1 && sgnd_print_labeledvalue --label "DNS zone" --value "Passed" || { sgnd_print_labeledvalue --label "DNS zone" --value "Failed"; failures=$((failures+1)); }
        host -t SRV "_kerberos._tcp.$dns_domain" >/dev/null 2>&1 && sgnd_print_labeledvalue --label "Kerberos discovery" --value "Passed" || { sgnd_print_labeledvalue --label "Kerberos discovery" --value "Failed"; failures=$((failures+1)); }
        host -t SRV "_ldap._tcp.$dns_domain" >/dev/null 2>&1 && sgnd_print_labeledvalue --label "LDAP discovery" --value "Passed" || { sgnd_print_labeledvalue --label "LDAP discovery" --value "Failed"; failures=$((failures+1)); }
        sudo samba-tool domain info "$ip" >/dev/null 2>&1 && sgnd_print_labeledvalue --label "Directory query" --value "Passed" || { sgnd_print_labeledvalue --label "Directory query" --value "Failed"; failures=$((failures+1)); }
        sudo samba-tool dbcheck --cross-ncs >/dev/null 2>&1 && sgnd_print_labeledvalue --label "Directory database" --value "Passed" || { sgnd_print_labeledvalue --label "Directory database" --value "Failed"; failures=$((failures+1)); }
        [[ -s /etc/krb5.conf ]] && grep -qi "default_realm[[:space:]]*=[[:space:]]*$realm" /etc/krb5.conf && sgnd_print_labeledvalue --label "Kerberos config" --value "Passed" || { sgnd_print_labeledvalue --label "Kerberos config" --value "Failed"; failures=$((failures+1)); }
        (( failures == 0 )) && { sayok "Active Directory server validation passed."; return 0; }
        sayfail "$failures Active Directory server validation check(s) failed."; return 1
    }

    # fn: _adsvr_status
        # . Purpose
        #   Display the configured Samba server role, realm, workgroup, DNS forwarder, and service state.
        #
        # . Returns
        #   0 after displaying available status information.
        #
        # . Usage
        #   _adsvr_status
    _adsvr_status() {
        local role="" realm="" state="inactive"
        command -v testparm >/dev/null 2>&1 || { saywarning "Samba is not installed."; return 1; }
        role="$(sudo testparm -s --parameter-name='server role' 2>/dev/null || true)"; realm="$(sudo testparm -s --parameter-name='realm' 2>/dev/null || true)"
        systemctl is-active --quiet samba-ad-dc.service && state="active"
        sgnd_print; sgnd_print_sectionheader "Active Directory server status"
        sgnd_print_labeledvalue --label "Server role" --value "${role:-Not configured}"
        sgnd_print_labeledvalue --label "Realm" --value "${realm:-Not configured}"
        sgnd_print_labeledvalue --label "AD/DC service" --value "$state"
    }

# - Console registration ---------------------------------------------------------
    # Provides Samba Active Directory domain-controller provisioning and host-level
    # management. Individual provisioning steps remain exposed for diagnosis and
    # recovery, alongside complete provisioning, validation, and status workflows.
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
