#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Web Server
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2629401
#   Shortname   : MANAGE_WEB_SERVER
#   Source      : manage-web-server.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Configure, manage, validate, and inspect an Nginx web server
#
#   Checksum : 5b03c347a018f0f6bf4cf65d5ff8d2bc20ce28e3fe05d8437b116fa882b7d3a0
# Description:
#   Configure, manage, validate, and inspect an Nginx web server.
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
# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||prepare,install,start,configure-root,manage-sites,ensure-site,ensure-directory,configure-dns,configure-documentation,documentation-status,update-documentation,service,firewall,validate,status"
        "site-name||value|SITE_NAME|Nginx site identifier for ensure-site||"
        "web-address||value|WEB_ADDRESS|Hostname for ensure-site||"
        "document-root||value|DOCUMENT_ROOT|Absolute document root for ensure-site||"
        "deployment-user||value|DEPLOYMENT_USER|Unprivileged SSH publishing account||"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action status"
        "  $SGND_SCRIPT_NAME --dryrun --action configure-root"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0

# - Local declarations --------------------------------------------------------------
    SGND_WEB_SERVER_CONFIG_FILE="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/web-server.cfg"
    SGND_WEB_SERVER_DEFAULT_STORAGE_ROOT="/srv/storage"
    SGND_WEB_SERVER_STATE_FILE="${SGND_STATE_DIR:-${HOME}/.state/solidgroundux}/web-server.state"
    SGND_WEB_SERVER_STATE_VARIABLES=(
        SGND_WEB_PUBLISH_SITE SGND_WEB_PUBLISH_SOURCE_TYPE SGND_WEB_PUBLISH_SOURCE_HOST
        SGND_WEB_PUBLISH_SOURCE_USER SGND_WEB_PUBLISH_SOURCE_DIR
        SGND_WEB_PUBLISH_REPOSITORY SGND_WEB_PUBLISH_REF SGND_WEB_PUBLISH_REPO_PATH
        SGND_WEB_DOC_SITE SGND_WEB_DOC_ADDRESS SGND_WEB_DOC_ROOT SGND_WEB_DOC_SOURCE_TYPE
        SGND_WEB_DOC_SOURCE_HOST SGND_WEB_DOC_SOURCE_USER SGND_WEB_DOC_SOURCE_DIR
        SGND_WEB_DOC_REPOSITORY SGND_WEB_DOC_REF SGND_WEB_DOC_REPO_PATH
    )
    : "${SGND_WEB_PUBLISH_SITE:=}"
    : "${SGND_WEB_PUBLISH_SOURCE_TYPE:=Remote machine}"
    : "${SGND_WEB_PUBLISH_SOURCE_HOST:=}"
    : "${SGND_WEB_PUBLISH_SOURCE_USER:=${SUDO_USER:-${USER:-sysadmin}}}"
    : "${SGND_WEB_PUBLISH_SOURCE_DIR:=}"
    : "${SGND_WEB_PUBLISH_REPOSITORY:=}"
    : "${SGND_WEB_PUBLISH_REF:=main}"
    : "${SGND_WEB_PUBLISH_REPO_PATH:=}"
    : "${SGND_WEB_DOC_SITE:=SolidGroundUX-Documentation}"
    : "${SGND_WEB_DOC_ADDRESS:=}"
    : "${SGND_WEB_DOC_ROOT:=}"
    : "${SGND_WEB_DOC_SOURCE_TYPE:=Installed documentation}"
    : "${SGND_WEB_DOC_SOURCE_HOST:=}"
    : "${SGND_WEB_DOC_SOURCE_USER:=${SUDO_USER:-${USER:-sysadmin}}}"
    : "${SGND_WEB_DOC_SOURCE_DIR:=}"
    : "${SGND_WEB_DOC_REPOSITORY:=}"
    : "${SGND_WEB_DOC_REF:=master}"
    : "${SGND_WEB_DOC_REPO_PATH:=target-root/usr/local/share/doc/solidgroundux-codex}"

    # Render a local numbered selector using the Web Server action layout.
    # The framework ask_selection API is intentionally left unchanged.
    _web_ask_selection() {
        local label="Select an option"
        local var_name="selection"
        local input=""
        local i=0
        local -a items=()

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --label) label="$2"; shift 2 ;;
                --var) var_name="$2"; shift 2 ;;
                --items) shift; items=("$@"); break ;;
                *) return 2 ;;
            esac
        done

        [[ "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
        (( ${#items[@]} > 0 )) || return 2

        sgnd_print
        sgnd_print_sectionheader --text "$label"
        for (( i=0; i<${#items[@]}; i++ )); do
            sgnd_print --text "$((i + 1)). ${items[i]}" --pad 2
        done
        sgnd_print --text "Q. Back" --pad 2
        sgnd_print
        sgnd_print_sectionheader ""

        while :; do
            input=""
            ask --label "Selection" --var input
            input="${input#"${input%%[![:space:]]*}"}"
            input="${input%"${input##*[![:space:]]}"}"
            [[ "${input^^}" == "Q" ]] && return 1
            if [[ "$input" =~ ^[1-9][0-9]*$ ]] && (( input <= ${#items[@]} )); then
                printf -v "$var_name" '%s' "${items[input - 1]}"
                return 0
            fi
            saywarning "Invalid selection: $input"
        done
    }

    _web_server_load_state() {
        if [[ -r "$SGND_WEB_SERVER_STATE_FILE" ]] && command -v sgnd_state_load_keys >/dev/null 2>&1; then
            sgnd_state_load_keys --file "$SGND_WEB_SERVER_STATE_FILE" --array SGND_WEB_SERVER_STATE_VARIABLES >/dev/null 2>&1 || true
        fi
    }

    _web_server_save_state() {
        command -v sgnd_state_save_keys >/dev/null 2>&1 || return 0
        mkdir -p "$(dirname -- "$SGND_WEB_SERVER_STATE_FILE")" || return 1
        sgnd_state_save_keys --file "$SGND_WEB_SERVER_STATE_FILE" --array SGND_WEB_SERVER_STATE_VARIABLES
    }

    _dryrun_complete() {
        (( ${FLAG_DRYRUN:-0} == 1 )) || return 0
        sayok "DRYRUN complete. The changes shown above would have been applied; no changes were written."
    }
    # fn: _web_server_package_installed - Test whether Nginx is installed
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_package_installed
    _web_server_package_installed() {
        dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -q '^install ok installed$'
    }

    # fn: _web_server_storage_root - Resolve the configured SolidGroundUX storage root
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_storage_root
    _web_server_storage_root() {
        local configured=""
        local storage_cfg="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/storage.cfg"

        if [[ -r "$storage_cfg" ]]; then
            configured="$(awk -F= '$1 == "SGND_STORAGE_MOUNTPOINT" {sub(/^[^=]*=/, ""); print; exit}' "$storage_cfg" 2>/dev/null || true)"
        fi

        [[ -n "$configured" ]] || configured="$SGND_WEB_SERVER_DEFAULT_STORAGE_ROOT"
        printf '%s\n' "$configured"
    }

    # fn: _web_server_root - Resolve the configured web content root
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_root
    _web_server_root() {
        local configured=""

        if [[ -r "$SGND_WEB_SERVER_CONFIG_FILE" ]]; then
            configured="$(awk -F= '$1 == "SGND_WEB_ROOT" {sub(/^[^=]*=/, ""); print; exit}' "$SGND_WEB_SERVER_CONFIG_FILE" 2>/dev/null || true)"
        fi

        [[ -n "$configured" ]] || configured="$(_web_server_storage_root)/www"
        printf '%s\n' "$configured"
    }

    # fn: _web_server_save_root - Persist the configured web content root
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_save_root
    _web_server_save_root() {
        local root="$1"
        local config_dir=""

        config_dir="$(dirname "$SGND_WEB_SERVER_CONFIG_FILE")"
        sudo mkdir -p "$config_dir" || return 1
        printf 'SGND_WEB_ROOT=%s\n' "$root" | sudo tee "$SGND_WEB_SERVER_CONFIG_FILE" >/dev/null || return 1
        sudo chmod 0644 "$SGND_WEB_SERVER_CONFIG_FILE" || return 1
    }

    # fn: _web_server_installed_docs_root - Resolve installed documentation from configuration
        # . Purpose
        #   Use SGND_WEB_DOC_INSTALLED_ROOT from the environment or web-server.cfg;
        #   otherwise use the supported installed documentation location. This replaces
        #   the legacy /usr/local/share/testadura/solidgroundux/doc default.
        # . Output
        #   Prints an absolute path beneath the active framework root when staged.
    _web_server_installed_docs_root() {
        local configured="${SGND_WEB_DOC_INSTALLED_ROOT:-}"
        local framework_root="${SGND_FRAMEWORK_ROOT:-/}"
        if [[ -z "$configured" && -r "$SGND_WEB_SERVER_CONFIG_FILE" ]]; then
            configured="$(awk -F= '$1 == "SGND_WEB_DOC_INSTALLED_ROOT" {sub(/^[^=]*=/, ""); print; exit}' "$SGND_WEB_SERVER_CONFIG_FILE")"
        fi
        [[ -n "$configured" ]] || configured="/usr/local/share/doc/solidgroundux-codex"
        [[ "$configured" == /* ]] || { sayfail "Documentation source must be an absolute path." >&2; return 2; }
        if [[ "$framework_root" != "/" && "$configured" == /usr/* ]]; then
            configured="${framework_root%/}${configured}"
        fi
        printf '%s\n' "$configured"
    }

    # fn: _web_server_enabled_sites - List enabled Nginx sites
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_enabled_sites
    _web_server_enabled_sites() {
        local entry=""
        [[ -d /etc/nginx/sites-enabled ]] || return 1
        while IFS= read -r -d '' entry; do
            basename -- "$entry"
        done < <(find /etc/nginx/sites-enabled -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z)
    }

    # fn: _web_server_available_sites - List available Nginx sites
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_available_sites
    _web_server_available_sites() {
        local entry=""
        [[ -d /etc/nginx/sites-available ]] || return 1
        while IFS= read -r -d '' entry; do
            basename -- "$entry"
        done < <(find /etc/nginx/sites-available -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
    }

    # fn: _web_server_validate_site_name - Validate an Nginx site name
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_validate_site_name
    _web_server_validate_site_name() {
        local value="$1"
        (( ${#value} >= 1 && ${#value} <= 64 )) || return 1
        [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    }

    # fn: _web_server_current_dns - Resolve the first configured non-loopback DNS server
        # . Usage
        #   _web_server_current_dns "<arg1>" "<dns>"
    _web_server_current_dns() {
        local dns=""
        if command -v resolvectl >/dev/null 2>&1; then
            dns="$(resolvectl dns 2>/dev/null | awk '{for (i=3; i<=NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $i !~ /^127\./) {print $i; exit}}')"
        fi
        if [[ -z "$dns" && -r /etc/resolv.conf ]]; then
            dns="$(awk '/^nameserver[[:space:]]+/ && $2 !~ /^127\./ {print $2; exit}' /etc/resolv.conf)"
        fi
        printf '%s\n' "$dns"
    }

    # fn: _web_server_local_ipv4 - Resolve this server's primary IPv4 address
        # . Usage
        #   _web_server_local_ipv4
    _web_server_local_ipv4() {
        hostname -I 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $i !~ /^127\./) {print $i; exit}}'
    }

    # fn: _web_server_offer_dns_record - Optionally register an internal AD DNS A record
        # . Usage
        #   _web_server_offer_dns_record "<web_address>"
    _web_server_offer_dns_record() {
        local web_address="$1"
        local local_domain=""
        local record_name=""
        local dns_server=""
        local local_ip=""
        local account="Administrator"
        local decision="YES"
        local existing_ip=""

        local_domain="$(hostname -d 2>/dev/null || true)"
        local_domain="${local_domain,,}"
        [[ -n "$local_domain" ]] || return 0

        if [[ "$web_address" == *.* ]]; then
            [[ "${web_address,,}" == *."$local_domain" ]] || {
                sayinfo "Web address is outside the local DNS domain; DNS registration was skipped."
                return 0
            }
            record_name="${web_address%.$local_domain}"
        else
            record_name="$web_address"
        fi

        [[ -n "$record_name" && "$record_name" != "$web_address" || "$web_address" != *.* ]] || return 0
        dns_server="$(_web_server_current_dns)"
        local_ip="$(_web_server_local_ipv4)"
        [[ -n "$dns_server" && -n "$local_ip" ]] || {
            saywarning "Local DNS server or IPv4 address could not be determined; DNS registration was skipped."
            return 0
        }

        ask_decision --label "Create DNS record for ${record_name}.${local_domain}" --choices "YES|Y,NO|N" --default "YES" --var decision
        [[ "$decision" == "YES" ]] || return 0

        ask --label "DNS server" --var dns_server --default "$dns_server" --validate sgnd_validate_ipv4 --back || return 0
        ask --label "DNS account" --var account --default "$account" --back || return 0

        existing_ip="$(host -t A "${record_name}.${local_domain}" "$dns_server" 2>/dev/null | awk '/has address/ {print $NF; exit}')"
        if [[ "$existing_ip" == "$local_ip" ]]; then
            sayok "DNS record already points to this web server: ${record_name}.${local_domain} -> $local_ip"
            return 0
        fi
        if [[ -n "$existing_ip" ]]; then
            saywarning "DNS record already exists and points to $existing_ip; it was not changed."
            return 0
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would register ${record_name}.${local_domain} -> $local_ip on $dns_server."
            return 0
        fi

        command -v samba-tool >/dev/null 2>&1 || {
            saywarning "samba-tool is not installed; DNS registration was skipped."
            return 0
        }
        sudo samba-tool dns add "$dns_server" "$local_domain" "$record_name" A "$local_ip" -U "$account" </dev/tty || {
            saywarning "Site was created, but the DNS record could not be registered."
            return 0
        }
        host -t A "${record_name}.${local_domain}" "$dns_server" 2>/dev/null | awk '/has address/ {print $NF}' | grep -Fxq "$local_ip" \
            && sayok "DNS record registered: ${record_name}.${local_domain} -> $local_ip" \
            || saywarning "DNS command completed, but the new record could not be verified."
    }

    # fn: _web_server_remove_dns_record - Offer deletion of a site's exact internal AD DNS A record
        # . Purpose
        #   During site removal, delete only a confirmed A record pointing at this host.
        #   Never remove unrelated records, aliases, or a hostname with multiple A values.
        # . Usage
        #   _web_server_remove_dns_record "<saved site hostname>"
    _web_server_remove_dns_record() {
        local web_address="${1%.}"
        local local_domain="" record_name="" dns_server="" local_ip=""
        local account="Administrator" decision="NO" lookup="" resolved=""
        local -a addresses=()

        [[ -n "$web_address" && "$web_address" != "_" ]] || return 0
        # A site can contain several server_name aliases; never guess which DNS record to delete.
        [[ "$web_address" != *[[:space:]]* ]] || {
            saywarning "Multiple web addresses configured; DNS cleanup skipped."
            return 0
        }
        local_domain="$(hostname -d 2>/dev/null || true)"
        local_domain="${local_domain,,}"
        web_address="${web_address,,}"
        [[ -n "$local_domain" ]] || { saywarning "Local DNS domain is unknown; DNS cleanup skipped."; return 0; }
        if [[ "$web_address" == *.* ]]; then
            [[ "$web_address" == *".$local_domain" ]] || {
                sayinfo "Web address is outside the local DNS domain; DNS cleanup skipped."
                return 0
            }
            record_name="${web_address%."$local_domain"}"
        else
            record_name="$web_address"
        fi
        [[ -n "$record_name" && "$record_name" != *[[:space:]]* ]] || return 0
        dns_server="$(_web_server_current_dns)"
        local_ip="$(_web_server_local_ipv4)"
        [[ -n "$dns_server" && -n "$local_ip" ]] || {
            saywarning "DNS server or local IPv4 unavailable; DNS cleanup skipped."
            return 0
        }

        ask --label "DNS server" --var dns_server --default "$dns_server" --validate sgnd_validate_ipv4 --back || return 0
        lookup="$(host -t A "${record_name}.${local_domain}" "$dns_server" 2>/dev/null)" || {
            saywarning "Could not query the DNS server; no DNS record was removed."
            return 0
        }
        while IFS= read -r resolved; do
            [[ -n "$resolved" ]] && addresses+=("$resolved")
        done < <(printf '%s\n' "$lookup" | awk '/ has address / {print $NF}')
        if (( ${#addresses[@]} != 1 )) || [[ "${addresses[0]:-}" != "$local_ip" ]]; then
            sayinfo "DNS A record is absent, ambiguous, or does not point to this web server; leaving DNS unchanged."
            return 0
        fi

        sgnd_print_labeledvalue --label "DNS A record" --value "${record_name}.${local_domain} -> $local_ip" --labelwidth 22
        ask_decision --label "Remove this DNS A record as well" --choices "YES|Y,NO|N" --default "NO" --var decision || return 0
        [[ "$decision" == "YES" ]] || return 0
        ask --label "DNS account" --var account --default "$account" --back || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would remove ${record_name}.${local_domain} A $local_ip on $dns_server."
            return 0
        fi
        command -v samba-tool >/dev/null 2>&1 || {
            saywarning "samba-tool is unavailable; DNS record was not removed."
            return 0
        }
        sudo samba-tool dns delete "$dns_server" "$local_domain" "$record_name" A "$local_ip" -U "$account" </dev/tty || {
            saywarning "DNS deletion failed; the site was removed but the DNS record may remain."
            return 0
        }
        if host -t A "${record_name}.${local_domain}" "$dns_server" 2>/dev/null | awk '/ has address / {print $NF}' | grep -Fxq "$local_ip"; then
            saywarning "DNS deletion returned successfully, but the old A record still resolves. Check DNS replication/cache."
        else
            sayok "DNS A record removed: ${record_name}.${local_domain} -> $local_ip"
        fi
    }

    # fn: _web_server_site_document_root - Resolve the document root for an Nginx site
        # . Returns
        #   0 when a document root can be resolved; non-zero otherwise.
        # . Usage
        #   _web_server_site_document_root <site>
    _web_server_site_document_root() {
        local site="$1"
        local config_file="/etc/nginx/sites-available/$site"
        local root=""

        [[ -r "$config_file" ]] || return 1
        root="$(awk '$1 == "root" {gsub(/;/, "", $2); print $2; exit}' "$config_file" 2>/dev/null || true)"
        [[ -n "$root" && "$root" == /* && "$root" != "/" ]] || return 1
        printf '%s\n' "$root"
    }

    # fn: _web_server_remove_document_content - Remove all content below a document root
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_remove_document_content <document-root>
    _web_server_remove_document_content() {
        local document_root="$1"

        [[ -n "$document_root" && "$document_root" == /* && "$document_root" != "/" ]] || {
            sayfail "Refusing to remove content from an unsafe document root: $document_root"
            return 1
        }

        [[ -d "$document_root" ]] || {
            saywarning "Document root does not exist: $document_root"
            return 0
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would remove all content below $document_root."
            return 0
        fi

        sudo find "$document_root" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
        sayok "Site content removed from: $document_root"
    }

    # fn: _web_server_ensure_directory - Create and prepare a web content directory when needed
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_ensure_directory
    _web_server_ensure_directory() {
        local path="$1"
        local owner="${2:-www-data:www-data}"
        local decision="YES"

        if [[ ! -d "$path" ]]; then
            ask_decision --label "Directory does not exist. Create it" --choices "YES|Y,NO|N" --default "YES" --var decision
            [[ "$decision" == "YES" ]] || return 1

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would create directory $path."
                return 0
            fi
            sudo mkdir -p "$path" || return 1
        fi

        if (( ${FLAG_DRYRUN:-0} == 0 )); then
            sudo chown "$owner" "$path" || return 1
            sudo chmod 0755 "$path" || return 1
        fi
    }

    # fn: _web_server_reload - Validate and reload Nginx
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_reload
    _web_server_reload() {
        sudo nginx -t || return 1
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would reload nginx.service."
            return 0
        fi
        sudo systemctl reload nginx.service || return 1
    }

# - Role preparation ---------------------------------------------------------------
    # fn: _web_server_step_install_packages - Install Nginx and publishing prerequisites
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_step_install_packages
    _web_server_step_install_packages() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would install Nginx web-server prerequisites."
            return 0
        fi

        sudo apt-get update || return 1
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y nginx curl rsync git || return 1
        command -v nginx >/dev/null 2>&1 || {
            sayfail "Nginx was installed but the nginx command is unavailable."
            return 1
        }
        sayok "Nginx web-server prerequisites installed."
    }

    # fn: _web_server_step_start - Enable and start Nginx
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_step_start
    _web_server_step_start() {
        command -v nginx >/dev/null 2>&1 || { sayfail "Nginx is not installed."; return 1; }
        sudo nginx -t >/dev/null 2>&1 || { sayfail "Nginx configuration validation failed."; return 1; }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would enable and start nginx.service."
            return 0
        fi

        sudo systemctl enable --now nginx.service || return 1
        systemctl is-active --quiet nginx.service || { sayfail "nginx.service is not active."; return 1; }
        sayok "Nginx web server is active."
    }

    # fn: _web_server_prepare - Run the tracked web-server preparation workflow
        # . Purpose
        #   Run the complete Web Server preparation sequence in one management process.
        #
        # . Returns
        #   0 when preparation completes successfully.
        #   41 when prerequisite installation fails.
        #   42 when enabling or starting Nginx fails.
        #
        # . Usage
        #   _web_server_prepare
    _web_server_prepare() {
        # Distinct workflow codes let the console synchronize the child menu results
        # while keeping the complete preparation workflow inside this executable.
        _web_server_step_install_packages || return 41
        _web_server_step_start || return 42
        sayok "Web-server preparation completed successfully."
        return 0
    }

# - Configuration ------------------------------------------------------------------
    # fn: _web_server_configure_root - Select or create the web content root
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_configure_root
    _web_server_configure_root() {
        local storage_root=""
        local current_root=""
        local selected=""
        local manual=""
        local -a options=()
        local path=""

        storage_root="$(_web_server_storage_root)"
        current_root="$(_web_server_root)"
        options+=("$current_root")

        if [[ -d "$storage_root" ]]; then
            while IFS= read -r path; do
                [[ -n "$path" && "$path" != "$current_root" ]] && options+=("$path")
            done < <(find "$storage_root" -mindepth 1 -maxdepth 2 -type d 2>/dev/null | sort)
        fi
        options+=("Enter path manually")

        _web_ask_selection --label "Select web content root" --var selected --items "${options[@]}" || return 0
        if [[ "$selected" == "Enter path manually" ]]; then
            ask --label "Web content root" --var manual --default "$current_root" || return 0
            selected="$manual"
        fi

        [[ "$selected" == /* ]] || selected="$storage_root/$selected"
        _web_server_ensure_directory "$selected" "www-data:www-data" || return 1

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would configure web content root as $selected."
            return 0
        fi

        _web_server_save_root "$selected" || return 1
        sayok "Web content root configured: $selected"
    }

    # fn: _web_server_manage_service - Manage nginx.service state and startup behavior
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_manage_service
    _web_server_manage_service() {
        local action=""
        local service_state="Unavailable"
        local boot_state="Unavailable"

        if command -v systemctl >/dev/null 2>&1; then
            service_state="$(systemctl is-active nginx.service 2>/dev/null || true)"
            [[ -n "$service_state" ]] || service_state="inactive"
            if systemctl is-enabled --quiet nginx.service 2>/dev/null; then
                boot_state="Enabled"
            else
                boot_state="Disabled"
            fi
        fi

        sgnd_print_labeledvalue --label "Service" --value "$service_state" --labelwidth 20
        sgnd_print_labeledvalue --label "At boot" --value "$boot_state" --labelwidth 20
        _web_ask_selection --label "Web service action" --var action --items "Start" "Stop" "Restart" "Enable at boot" "Disable at boot" || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would perform web service action: $action."
            return 0
        fi

        case "$action" in
            Start) sudo systemctl start nginx.service ;;
            Stop) sudo systemctl stop nginx.service ;;
            Restart) sudo nginx -t && sudo systemctl restart nginx.service ;;
            "Enable at boot") sudo systemctl enable nginx.service ;;
            "Disable at boot") sudo systemctl disable nginx.service ;;
        esac
    }

    # fn: _web_server_configure_firewall - Allow HTTP and HTTPS through UFW
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_configure_firewall
    _web_server_configure_firewall() {
        local firewall_state="Inactive"
        local nginx_profile_state="Not allowed"
        local decision="YES"

        command -v ufw >/dev/null 2>&1 || { saywarning "UFW is not installed."; return 0; }
        sudo ufw status 2>/dev/null | grep -q '^Status: active' && firewall_state="Active"
        sudo ufw status 2>/dev/null | grep -Eq '^Nginx Full[[:space:]]+ALLOW' && nginx_profile_state="Allowed"

        sgnd_print_labeledvalue --label "Firewall" --value "$firewall_state" --labelwidth 20
        sgnd_print_labeledvalue --label "HTTP / HTTPS" --value "$nginx_profile_state" --labelwidth 20
        sgnd_print
        sgnd_print_sectionheader ""
        ask_decision --label "Allow HTTP and HTTPS through UFW" --choices "YES|Y,NO|N" --default "YES" --var decision || return 0
        [[ "$decision" == "YES" ]] || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would allow the Nginx Full firewall profile."
            return 0
        fi
        sudo ufw allow 'Nginx Full' || return 1
        sayok "HTTP and HTTPS allowed through UFW."
    }

# - Site management ----------------------------------------------------------------
    # fn: _web_server_create_site - Create and enable an Nginx site
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_create_site
    _web_server_create_site() {
        local site_name=""
        local server_name=""
        local document_root=""
        local web_root=""
        local config_file=""

        _web_server_package_installed || { sayfail "Nginx is not installed."; return 1; }
        web_root="$(_web_server_root)"

        ask --label "Site name" --var site_name --validate _web_server_validate_site_name --back || return 0
        ask --label "Web address" --var server_name --default "$(hostname -f 2>/dev/null || hostname)" --back || return 0
        ask --label "Document root" --var document_root --default "$web_root/$site_name" --back || return 0
        [[ "$document_root" == /* ]] || document_root="$web_root/$document_root"
        config_file="/etc/nginx/sites-available/$site_name"

        [[ ! -e "$config_file" ]] || { sayfail "Site configuration already exists: $site_name"; return 1; }
        _web_server_ensure_directory "$document_root" "www-data:www-data" || return 1

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would create Nginx site $site_name using $document_root."
            return 0
        fi

        sudo tee "$config_file" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $server_name;
    root $document_root;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        sudo ln -s "$config_file" "/etc/nginx/sites-enabled/$site_name" || return 1
        _web_server_reload || {
            sudo rm -f "/etc/nginx/sites-enabled/$site_name"
            sudo rm -f "$config_file"
            return 1
        }
        sayok "Nginx site created and enabled: $site_name"
        _web_server_offer_dns_record "$server_name"
    }

    # fn: _web_server_ensure_site - Noninteractive, idempotent site provisioning for an approved remote deployment.
        # . Behavior
        #   - Only creates a dedicated site under the configured web root.
        #   - Returns success for an existing identical configuration, without changing it.
        #   - Rejects duplicate hostnames and conflicting sites; never rewrites existing sites.
        #   - Runs as root via the authorized SolidGroundUX executable sudo rule.
        #   - Preserves the explicitly supplied unprivileged publisher for directory ownership.
        #   - Tests Nginx before reload and rolls back only newly created configuration.
        #   - Does not register DNS; DNS changes are a separate management action.
    _web_server_ensure_site() {
        local name="${SITE_NAME:-}" address="${WEB_ADDRESS:-}" root="${DOCUMENT_ROOT:-}"
        local base="" cfg="" linked="" other="" current_address="" current_root="" publisher="${DEPLOYMENT_USER:-}"
        (( EUID == 0 )) || { sayfail "ensure-site must be invoked as root through authorized sudo."; return 1; }
        [[ "$publisher" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] && id "$publisher" >/dev/null 2>&1 || { sayfail "Invalid deployment account: $publisher"; return 2; }
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { sayfail "Invalid site name."; return 2; }
        [[ "$address" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$address" == *.* ]] || { sayfail "Invalid web hostname."; return 2; }
        [[ "$root" == /* && "$root" != *'..'* && "$root" != *[[:space:]]* && "$root" != *';'* && "$root" != *'$'* ]] || {
            sayfail "Unsafe document root."; return 2;
        }
        base="$(_web_server_root)"
        [[ "$root" == "$base/"* && "$root" != "$base/" ]] || {
            sayfail "Document root must be a dedicated directory below $base."; return 2;
        }
        cfg="/etc/nginx/sites-available/$name"
        linked="/etc/nginx/sites-enabled/$name"
        if [[ -e "$cfg" || -L "$cfg" ]]; then
            [[ -f "$cfg" && ! -L "$cfg" ]] || { sayfail "Unsafe existing site entry: $cfg"; return 1; }
            current_address="$(awk '$1=="server_name" {gsub(/;/,"",$2); print $2;exit}' "$cfg")"
            current_root="$(_web_server_site_document_root "$name" 2>/dev/null || true)"
            if [[ "$current_address" == "$address" && "$current_root" == "$root" && -L "$linked" ]]; then
                sayok "Nginx site already configured: $name ($address => $root)."
                return 0
            fi
            sayfail "Site '$name' already exists with different settings or is disabled; no changes made."
            return 3
        fi
        # Prevent a second site taking over an already configured virtual hostname.
        for other in /etc/nginx/sites-available/*; do
            [[ -f "$other" ]] || continue
            if awk -v host="$address" '$1=="server_name" {for(i=2;i<=NF;i++){gsub(/;/,"",$i); if($i==host) found=1}} END {exit !found}' "$other"; then
                sayfail "Hostname $address already appears in $(basename -- "$other"); no changes made."
                return 3
            fi
        done
        [[ ! -e "$linked" && ! -L "$linked" ]] || { sayfail "Site enable path is already occupied."; return 3; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would create $name for $address at $root and enable Nginx."
            return 0
        fi
        # Publishing must be possible as the SSH user; do not chown an existing site directory.
        if [[ ! -d "$root" ]]; then
            install -d -m 2755 -o "$publisher" -g www-data -- "$root" || { sayfail "Cannot create writable document root $root."; return 1; }
        fi
        runuser -u "$publisher" -- test -w "$root" || { sayfail "Deployment user $publisher cannot write to $root; no Nginx configuration created."; return 1; }
        { printf 'server {\n    listen 80;\n    listen [::]:80;\n    server_name %s;\n    root %s;\n    index index.html;\n    location / {\n        try_files $uri $uri/ =404;\n    }\n}\n' "$address" "$root"; } | tee "$cfg" >/dev/null || { sayfail "Could not write Nginx site."; return 1; }
        if ! ln -s "$cfg" "$linked"; then
            rm -f -- "$cfg" || true
            sayfail "Could not enable Nginx site."
            return 1
        fi
        if ! nginx -t || ! systemctl reload nginx.service; then
            rm -f -- "$linked" "$cfg" || true
            nginx -t >/dev/null 2>&1 && systemctl reload nginx.service >/dev/null 2>&1 || true
            sayfail "Nginx validation/reload failed; new site configuration rolled back."
            return 1
        fi
        sayok "Nginx site created: $name ($address => $root)."
    }

    # fn: _web_server_ensure_directory_for_publish - Noninteractive preparation/repair of a dedicated publishing directory.
    # Existing content is preserved; only the document root inode receives ownership/mode changes.
    _web_server_ensure_directory_for_publish() {
        local root="${DOCUMENT_ROOT:-}" base="" publisher="${DEPLOYMENT_USER:-}"
        (( EUID == 0 )) || { sayfail "ensure-directory must be invoked as root through authorized sudo."; return 1; }
        [[ "$publisher" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] && id "$publisher" >/dev/null 2>&1 || { sayfail "Invalid deployment account: $publisher"; return 2; }
        [[ "$root" == /* && "$root" != *'..'* && "$root" != *[[:space:]]* && "$root" != *';'* && "$root" != *'$'* ]] || {
            sayfail "Unsafe document root."; return 2;
        }
        base="$(_web_server_root)"
        [[ "$root" == "$base/"* && "$root" != "$base/" ]] || {
            sayfail "Document root is outside the configured web root: $base"; return 2;
        }
        [[ ! -L "$root" ]] || { sayfail "Symlink document roots cannot be repaired automatically."; return 2; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would ensure $root owned by ${publisher}:www-data with mode 2755."
            return 0
        fi
        if [[ ! -d "$root" ]]; then
            install -d -m 2755 -o "$publisher" -g www-data -- "$root" || return 1
        else
            chown -- "${publisher}:www-data" "$root" || return 1
            chmod -- 2755 "$root" || return 1
        fi
        runuser -u "$publisher" -- test -w "$root" || { sayfail "Deployment account $publisher still cannot write to $root."; return 1; }
        sayok "Deployment directory ready: $root"
    }

    # fn: _web_server_configure_dns - Reuse existing interactive AD DNS setup via a direct action.
    _web_server_configure_dns() {
        local address="${WEB_ADDRESS:-}"
        [[ "$address" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$address" == *.* ]] || {
            sayfail "Invalid website hostname for DNS registration."; return 2;
        }
        _web_server_offer_dns_record "$address"
    }

    # fn: _web_server_enable_site - Enable an available Nginx site
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_enable_site
    _web_server_enable_site() {
        local site=""
        local -a sites=()
        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites are available."; return 0; }
        _web_ask_selection --label "Enable Nginx site" --var site --items "${sites[@]}" || return 0
        [[ -e "/etc/nginx/sites-enabled/$site" ]] && { sayok "Site is already enabled: $site"; return 0; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "DRYRUN: Would enable $site."; return 0; fi
        sudo ln -s "/etc/nginx/sites-available/$site" "/etc/nginx/sites-enabled/$site" || return 1
        _web_server_reload || return 1
        sayok "Site enabled: $site"
    }

    # fn: _web_server_disable_site - Disable an enabled Nginx site
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_disable_site
    _web_server_disable_site() {
        local site=""
        local -a sites=()
        mapfile -t sites < <(_web_server_enabled_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No enabled Nginx sites found."; return 0; }
        _web_ask_selection --label "Disable Nginx site" --var site --items "${sites[@]}" || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "DRYRUN: Would disable $site."; return 0; fi
        sudo rm -f "/etc/nginx/sites-enabled/$site" || return 1
        _web_server_reload || return 1
        sayok "Site disabled: $site"
    }


    # fn: _web_server_change_document_root - Change the document root for an Nginx site
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_change_document_root
    _web_server_change_document_root() {
        local site=""
        local config_file=""
        local current_root=""
        local document_root=""
        local temp_file=""
        local backup_file=""
        local -a sites=()

        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites are available."; return 0; }
        _web_ask_selection --label "Change document root" --var site --items "${sites[@]}" || return 0

        config_file="/etc/nginx/sites-available/$site"
        current_root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
        [[ -n "$current_root" ]] || { sayfail "Could not determine document root for $site."; return 1; }

        ask --label "Document root" --var document_root --default "$current_root" --back || return 0
        [[ "$document_root" == /* && "$document_root" != "/" ]] || {
            sayfail "Document root must be an absolute path other than /."
            return 1
        }
        [[ "$document_root" != *$'\n'* && "$document_root" != *$'\r'* ]] || {
            sayfail "Document root contains invalid characters."
            return 1
        }

        [[ "$document_root" != "$current_root" ]] || { sayok "Document root is already configured as $current_root"; return 0; }
        _web_server_ensure_directory "$document_root" "www-data:www-data" || return 1

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would change document root for $site from $current_root to $document_root."
            return 0
        fi

        temp_file="$(mktemp "${TMPDIR:-/tmp}/sgnd-nginx-site.XXXXXX")" || return 1
        backup_file="$(mktemp "${TMPDIR:-/tmp}/sgnd-nginx-site-backup.XXXXXX")" || { rm -f -- "$temp_file"; return 1; }
        sudo cp -- "$config_file" "$backup_file" || { rm -f -- "$temp_file" "$backup_file"; return 1; }
        sudo chown "$(id -u):$(id -g)" "$backup_file" || { rm -f -- "$temp_file" "$backup_file"; return 1; }

        awk -v new_root="$document_root" '
            BEGIN { changed=0 }
            !changed && $1 == "root" { print "    root " new_root ";"; changed=1; next }
            { print }
            END { if (!changed) exit 3 }
        ' "$config_file" > "$temp_file" || { rm -f -- "$temp_file" "$backup_file"; sayfail "Could not update document root in $config_file."; return 1; }

        sudo cp -- "$temp_file" "$config_file" || { rm -f -- "$temp_file" "$backup_file"; return 1; }
        if ! _web_server_reload; then
            sudo cp -- "$backup_file" "$config_file" >/dev/null 2>&1 || true
            sudo nginx -t >/dev/null 2>&1 && sudo systemctl reload nginx.service >/dev/null 2>&1 || true
            rm -f -- "$temp_file" "$backup_file"
            sayfail "Document root change was rolled back because Nginx validation or reload failed."
            return 1
        fi

        rm -f -- "$temp_file" "$backup_file"
        if [[ "${SGND_WEB_DOC_SITE:-}" == "$site" ]]; then
            SGND_WEB_DOC_ROOT="$document_root"
            _web_server_save_state || return 1
        fi
        sayok "Document root changed for $site: $document_root"
    }

    # fn: _web_server_remove_site - Remove an Nginx site configuration
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_remove_site
    _web_server_remove_site() {
        local site=""
        local document_root=""
        local decision="NO"
        local remove_content="NO"
        local web_address=""
        local -a sites=()

        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites are available."; return 0; }
        _web_ask_selection --label "Remove Nginx site configuration" --var site --items "${sites[@]}" || return 0
        document_root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
        # Save the hostname before removing its Nginx configuration.
        web_address="$(awk '$1 == "server_name" {for (i=2; i<=NF; i++) {gsub(/;/, "", $i); printf "%s%s", (i==2 ? "" : " "), $i}; exit}' "/etc/nginx/sites-available/$site" 2>/dev/null || true)"

        ask_decision --label "Remove site configuration '$site'" --choices "YES|Y,NO|N" --default "NO" --var decision
        [[ "$decision" == "YES" ]] || return 0

        if [[ -n "$document_root" ]]; then
            sgnd_print_labeledvalue --label "Document root" --value "$document_root" --labelwidth 22
            ask_decision --label "Remove site content as well" --choices "YES|Y,NO|N" --default "NO" --var remove_content
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would remove site configuration $site."
            [[ "$remove_content" == "YES" && -n "$document_root" ]] && _web_server_remove_document_content "$document_root"
            [[ -n "$web_address" ]] && _web_server_remove_dns_record "$web_address"
            return 0
        fi

        sudo rm -f "/etc/nginx/sites-enabled/$site" "/etc/nginx/sites-available/$site" || return 1
        _web_server_reload || return 1
        sayok "Site configuration removed: $site"

        if [[ "${SGND_WEB_PUBLISH_SITE:-}" == "$site" ]]; then
            SGND_WEB_PUBLISH_SITE=""
            if command -v sgnd_state_save_keys >/dev/null 2>&1; then
                mkdir -p "$(dirname -- "$SGND_WEB_SERVER_STATE_FILE")" || return 1
                sgnd_state_save_keys --file "$SGND_WEB_SERVER_STATE_FILE" --array SGND_WEB_SERVER_STATE_VARIABLES || return 1
            fi
        fi

        if [[ "$remove_content" == "YES" && -n "$document_root" ]]; then
            _web_server_remove_document_content "$document_root" || return 1
        elif [[ -n "$document_root" ]]; then
            sayinfo "Document content retained: $document_root"
        fi
        # Only offer DNS cleanup after the site configuration was removed successfully.
        [[ -n "$web_address" ]] && _web_server_remove_dns_record "$web_address"
        return 0
    }

    # fn: _web_server_remove_site_content - Remove the contents of a site's document root
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_remove_site_content
    _web_server_remove_site_content() {
        local site=""
        local document_root=""
        local decision="NO"
        local -a sites=()

        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites are available."; return 0; }
        _web_ask_selection --label "Remove content from site" --var site --items "${sites[@]}" || return 0

        document_root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
        [[ -n "$document_root" ]] || { sayfail "Could not determine document root for $site."; return 1; }

        sgnd_print_labeledvalue --label "Document root" --value "$document_root" --labelwidth 22
        ask_decision --label "Remove all content from '$site'" --choices "YES|Y,NO|N" --default "NO" --var decision
        [[ "$decision" == "YES" ]] || return 0

        _web_server_remove_document_content "$document_root"
    }

    # fn: _web_server_list_sites - List Nginx sites and document roots
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_list_sites
    _web_server_list_sites() {
        local -a sites=()
        local site=""
        local state=""
        local root=""
        local address=""

        _web_server_package_installed || { sayfail "Nginx is not installed."; return 1; }
        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)

        sgnd_print
        sgnd_print_sectionheader "Nginx sites"
        if (( ${#sites[@]} == 0 )); then
            sgnd_print_labeledvalue --label "Sites" --value "None" --labelwidth 20
            return 0
        fi

        for site in "${sites[@]}"; do
            state="Disabled"
            [[ -e "/etc/nginx/sites-enabled/$site" ]] && state="Enabled"
            root="$(awk '$1 == "root" {gsub(/;/, "", $2); print $2; exit}' "/etc/nginx/sites-available/$site" 2>/dev/null || true)"
            address="$(awk '$1 == "server_name" {gsub(/;/, "", $2); print $2; exit}' "/etc/nginx/sites-available/$site" 2>/dev/null || true)"
            [[ "$address" == "_" ]] && address="Default/catch-all"
            sgnd_print_labeledvalue --label "$site" --value "$state" --labelwidth 24
            sgnd_print_labeledvalue --label "  Web address" --value "${address:-Not configured}" --labelwidth 24
            sgnd_print_labeledvalue --label "  Document root" --value "${root:-Not configured}" --labelwidth 24
            if grep -Eq '^[[:space:]]*listen[[:space:]]+.*443[[:space:]]+ssl' "/etc/nginx/sites-available/$site"; then
                sgnd_print_labeledvalue --label "  HTTPS" --value "Configured" --labelwidth 24
            else
                sgnd_print_labeledvalue --label "  HTTPS" --value "Not configured" --labelwidth 24
            fi
        done
    }

    # fn: _web_server_configure_https - Configure optional TLS for one managed Nginx site
    # . Purpose
    #   Enable HTTPS using an existing certificate or a locally generated self-signed
    #   certificate. Keep other sites untouched and roll back on Nginx failure.
    #   A self-signed certificate is for testing only until trusted by clients.
    _web_server_configure_https() {
        local site="" cfg="" address="" root="" option="" cert="" key="" redirect="NO"
        local backup="" staged="" host="" answer="" tls_dir="" cert_tmp="" key_tmp=""
        local -a sites=()
        command -v openssl >/dev/null 2>&1 || { sayfail "openssl is required for HTTPS setup."; return 1; }
        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites are available."; return 0; }
        _web_ask_selection --label "Configure HTTPS for site" --var site --items "${sites[@]}" || return 0
        [[ "$site" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { sayfail "Invalid site identifier."; return 2; }
        cfg="/etc/nginx/sites-available/$site"
        [[ -f "$cfg" && ! -L "$cfg" ]] || { sayfail "Unsupported site configuration: $cfg"; return 1; }
        [[ -L "/etc/nginx/sites-enabled/$site" ]] || { sayfail "Enable the site before configuring HTTPS."; return 1; }
        address="$(awk '$1=="server_name" {print $2;exit}' "$cfg" | tr -d ';')"
        root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
        [[ "$address" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$address" == *.* && -n "$root" ]] || {
            sayfail "Site must have one valid hostname and a document root."; return 1;
        }
        # Existing HTTPS configurations must not be rewritten. This is particularly
        # important once another managed feature (Basic Auth or uploads) has been added.
        if grep -Eq '^[[:space:]]*listen[[:space:]]+(\[::\]:)?443[[:space:]]+ssl;' "$cfg"; then
            sayok "HTTPS is already configured for $site; existing directives preserved."
            return 0
        fi
        # Manage only our own simple site templates; refuse custom or already TLS-enabled configs.
        # Whitelist the directives produced by the MCM site creator to avoid dropping
        # unrelated configuration when rewriting the site's server blocks.
        if awk '''
            /^[[:space:]]*($|#|server[[:space:]]*\{|\}|location[[:space:]]+\/[[:space:]]*\{|listen[[:space:]]+80;|listen[[:space:]]+\[::\]:80;|server_name[[:space:]]+[^;]+;|root[[:space:]]+[^;]+;|index[[:space:]]+index.html([[:space:]]+index.htm)?;|try_files[[:space:]]+\$uri[[:space:]]+\$uri\/[[:space:]]+=404;)$/ { next }
            { bad=1 }
            END { exit !bad }
        ''' "$cfg"; then
            saywarning "Custom Nginx directives detected; refusing to replace site configuration."
            return 1
        fi
        if grep -Eq '^[[:space:]]*(ssl_certificate|listen[[:space:]].*443|include[[:space:]]|proxy_pass|return[[:space:]]|rewrite[[:space:]])' "$cfg"; then
            saywarning "Existing TLS or customized Nginx directives detected. HTTPS settings were left unchanged."
            return 1
        fi
        sgnd_print_labeledvalue --label "Site" --value "$site" --labelwidth 22
        sgnd_print_labeledvalue --label "Hostname" --value "$address" --labelwidth 22
        _web_ask_selection --label "Certificate source" --var option --items "Existing certificate and key" "Generate self-signed test certificate" || return 0
        case "$option" in
            "Existing certificate and key")
                ask --label "Certificate PEM file (full chain)" --var cert --back || return 0
                ask --label "Private key PEM file" --var key --back || return 0
                [[ "$cert" == /* && "$key" == /* && "$cert" != *[[:space:]]* && "$key" != *[[:space:]]* && "$cert" != *\;* && "$key" != *\;* && -r "$cert" && -r "$key" ]] || {
                    sayfail "Certificate and key must be readable absolute paths."; return 1;
                }
                ;;
            "Generate self-signed test certificate")
                tls_dir="/etc/nginx/solidgroundux-certs"
                cert="$tls_dir/$site.crt"
                key="$tls_dir/$site.key"
                [[ ! -e "$cert" && ! -e "$key" ]] || {
                    sayfail "Certificate already exists for $site. Use the existing-certificate option instead."; return 1;
                }
                ;;
        esac
        ask_decision --label "Redirect HTTP to HTTPS" --choices "YES|Y,NO|N" --default "YES" --var redirect || return 0
        sgnd_print_labeledvalue --label "TLS certificate" --value "$cert" --labelwidth 22
        sgnd_print_labeledvalue --label "Redirect HTTP" --value "$redirect" --labelwidth 22
        answer="NO"
        ask_decision --label "Enable HTTPS for $site" --choices "YES|Y,NO|N" --default "NO" --var answer || return 0
        [[ "$answer" == "YES" ]] || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would configure HTTPS on $address and redirect=$redirect; no changes written."
            return 0
        fi
        # This interactive MCM action requires admin access to Nginx configuration.
        sudo -v || { sayfail "Administrator authorization is required."; return 1; }
        backup="$(mktemp)" || return 1
        staged="$(mktemp)" || { rm -f -- "$backup"; return 1; }
        sudo cp -- "$cfg" "$backup" || { rm -f -- "$backup" "$staged"; return 1; }
        if [[ "$option" == "Generate self-signed test certificate" ]]; then
            sudo install -d -m 0700 -- "$tls_dir" || { rm -f -- "$backup" "$staged"; return 1; }
            cert_tmp="$tls_dir/.${site}.$$.crt"
            key_tmp="$tls_dir/.${site}.$$.key"
            if ! sudo openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
                -keyout "$key_tmp" -out "$cert_tmp" -subj "/CN=$address" \
                -addext "subjectAltName=DNS:$address" >/dev/null 2>&1; then
                sudo rm -f -- "$cert_tmp" "$key_tmp"
                rm -f -- "$backup" "$staged"
                sayfail "Certificate generation failed."
                return 1
            fi
            sudo chmod 0600 "$key_tmp" || return 1
            sudo mv -- "$key_tmp" "$key" || return 1
            sudo mv -- "$cert_tmp" "$cert" || return 1
        fi
        # Ensure the selected key matches the certificate; reject accidental mismatches.
        if ! sudo openssl x509 -in "$cert" -noout >/dev/null 2>&1 ||
           ! sudo openssl pkey -in "$key" -noout >/dev/null 2>&1 ||
           [[ "$(sudo openssl x509 -in "$cert" -pubkey -noout | openssl sha256)" != "$(sudo openssl pkey -in "$key" -pubout | openssl sha256)" ]]; then
            sayfail "Invalid certificate/key pair; Nginx configuration unchanged."
            rm -f -- "$backup" "$staged"
            return 1
        fi
        {
            printf 'server {\n    listen 80;\n    listen [::]:80;\n    server_name %s;\n' "$address"
            if [[ "$redirect" == "YES" ]]; then
                printf '    return 301 https://$host$request_uri;\n'
            else
                printf '    root %s;\n    index index.html index.htm;\n    location / { try_files $uri $uri/ =404; }\n' "$root"
            fi
            printf '}\nserver {\n    listen 443 ssl;\n    listen [::]:443 ssl;\n    server_name %s;\n' "$address"
            printf '    ssl_certificate %s;\n    ssl_certificate_key %s;\n' "$cert" "$key"
            printf '    ssl_protocols TLSv1.2 TLSv1.3;\n    root %s;\n    index index.html index.htm;\n    location / { try_files $uri $uri/ =404; }\n}\n' "$root"
        } > "$staged"
        if ! sudo cp -- "$staged" "$cfg" || ! sudo nginx -t || ! sudo systemctl reload nginx.service; then
            sudo cp -- "$backup" "$cfg" || true
            sudo nginx -t >/dev/null 2>&1 && sudo systemctl reload nginx.service >/dev/null 2>&1 || true
            sayfail "HTTPS setup failed; previous site configuration restored."
            rm -f -- "$backup" "$staged"
            return 1
        fi
        rm -f -- "$backup" "$staged"
        sayok "HTTPS enabled for $address."
        if [[ "$option" == "Generate self-signed test certificate" ]]; then
            saywarning "Self-signed certificate: browsers will not trust this until its certificate is explicitly trusted. Do not use for public uploads."
        fi
    }

    # fn: _web_server_configure_basic_auth - Protect one HTTPS URL prefix with Nginx Basic Auth
    # . Purpose
    #   Add or remove password protection without changing the public site or TLS setup.
    #   HTTP must already redirect to HTTPS. Passwords use bcrypt in a file outside
    #   the document root; custom Nginx configurations are never rewritten.
    # . Behavior
    #   Supports one managed protected URL prefix per site. A second prefix, existing
    #   custom auth configuration, or unexpected site layout requires manual review.
    #   Keep password files after disabling protection to avoid deleting credentials
    #   that might be used elsewhere; only the Nginx guard is removed.
    _web_server_configure_basic_auth() {
        local site="" cfg="" action="" prefix="" username="" decision="NO"
        local host="" marker_start="# SGND_BASIC_AUTH_BEGIN" marker_end="# SGND_BASIC_AUTH_END"
        local auth_dir="/etc/nginx/solidgroundux-auth" auth_file="" temp_pass=""
        local staged="" backup="" config_copy="" rc=0
        local -a sites=()
        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites available."; return 0; }
        _web_ask_selection --label "Configure private URL section" --var site --items "${sites[@]}" || return 0
        [[ "$site" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { sayfail "Invalid site identifier."; return 2; }
        cfg="/etc/nginx/sites-available/$site"
        [[ -f "$cfg" && ! -L "$cfg" && -L "/etc/nginx/sites-enabled/$site" ]] || {
            sayfail "Site must be a regular, enabled Nginx configuration."; return 1;
        }
        # Only the MCM-generated HTTPS layout is supported. This also excludes a
        # separate HTTP content site that could bypass the password protection.
        grep -Eq '^[[:space:]]*listen[[:space:]]+443[[:space:]]+ssl;' "$cfg" || {
            sayfail "Enable HTTPS for this site before configuring private pages."; return 1;
        }
        grep -Fq 'return 301 https://$host$request_uri;' "$cfg" || {
            sayfail "HTTP must redirect to HTTPS before private pages can be enabled."; return 1;
        }
        if grep -Eq '^[[:space:]]*(auth_basic|auth_basic_user_file)' "$cfg" && ! grep -Fq "$marker_start" "$cfg"; then
            sayfail "Existing unmanaged Basic Auth directives detected; no changes made."; return 1;
        fi
        if grep -Fq "$marker_start" "$cfg"; then
            _web_ask_selection --label "Private section" --var action --items "Disable existing protection" "Replace credentials and protected path" || return 0
        else
            action="Enable protection"
        fi
        if [[ "$action" != "Disable existing protection" ]]; then
            ask --label "Protected URL prefix (for example /over-deze-website/)" --var prefix --default "/over-deze-website/" --back || return 0
            [[ "$prefix" =~ ^/[a-zA-Z0-9/_-]+/$ && "$prefix" != "//" && "$prefix" != *"//"* && "$prefix" != *".."* ]] || {
                sayfail "Use an absolute directory URL ending in /, without spaces or traversal."; return 2;
            }
            ask --label "Authentication user" --var username --default "editor" --back || return 0
            [[ "$username" =~ ^[a-zA-Z][a-zA-Z0-9_.-]{0,63}$ ]] || { sayfail "Invalid authentication username."; return 2; }
            if ! command -v htpasswd >/dev/null 2>&1; then
                local install_answer="NO"
                saywarning "Basic Authentication requires apache2-utils (htpasswd)."
                ask_decision --label "Install apache2-utils now" --choices "YES|Y,NO|N" --default "NO" --var install_answer || return 0
                [[ "$install_answer" == YES ]] || { saywarning "Dependency was not installed."; return 127; }
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "DRYRUN: Would install apache2-utils."
                    return 0
                fi
                sudo -v || { sayfail "Administrator authorization is required."; return 1; }
                sudo apt-get update && sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y apache2-utils || {
                    sayfail "Could not install apache2-utils."; return 1;
                }
                command -v htpasswd >/dev/null 2>&1 || { sayfail "htpasswd unavailable after installation."; return 127; }
            fi
        fi
        decision="NO"
        ask_decision --label "Apply private-section change to $site" --choices "YES|Y,NO|N" --default "NO" --var decision || return 0
        [[ "$decision" == YES ]] || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would modify Basic Auth for $site ($action)."
            return 0
        fi
        sudo -v || { sayfail "Administrator authorization is required."; return 1; }
        backup="$(mktemp)" || return 1
        staged="$(mktemp)" || { rm -f -- "$backup"; return 1; }
        sudo cp -- "$cfg" "$backup" || { rm -f -- "$backup" "$staged"; return 1; }
        config_copy="$(mktemp)" || { rm -f -- "$backup" "$staged"; return 1; }
        # Strip only a fully delimited block previously written by this function.
        # Preserve the rest of the existing HTTPS configuration byte-for-byte.
        awk -v b="$marker_start" -v e="$marker_end" '
            index($0,b) { if (inside) exit 2; inside=1; begin_count++; next }
            index($0,e) { if (!inside) exit 2; inside=0; end_count++; next }
            !inside { print }
            END { if (inside || begin_count!=end_count || begin_count>1) exit 2 }
        ' "$cfg" > "$config_copy" || {
            sayfail "Malformed existing managed Basic Auth block; no changes made."
            rm -f -- "$backup" "$staged" "$config_copy"; return 1;
        }
        if [[ "$action" == "Disable existing protection" ]]; then
            cp -- "$config_copy" "$staged" || rc=1
        else
            auth_file="$auth_dir/$site.htpasswd"
            # Do not overwrite existing credentials unless they belong to an
            # already managed block for this same site.
            if [[ -e "$auth_file" ]] && ! grep -Fq "$marker_start" "$cfg"; then
                sayfail "Credential file already exists; refusing to overwrite $auth_file."
                rm -f -- "$backup" "$staged" "$config_copy"; return 1
            fi
            # Use an unguessable temp path for new credentials; no plaintext password
            # appears in the command line or environment. htpasswd prompts securely.
            sudo install -d -m 0750 -o root -g www-data -- "$auth_dir" || rc=1
            temp_pass="$auth_dir/.${site}.$$.new"
            if (( rc == 0 )); then
                sudo htpasswd -cB "$temp_pass" "$username" || rc=1
                (( rc == 0 )) && sudo chown root:www-data "$temp_pass" && sudo chmod 0640 "$temp_pass" || true
            fi
            if (( rc == 0 )); then
                # Require exactly one expected HTTPS location; fail closed on
                # unexpected/custom templates instead of inserting arbitrarily.
                awk -v b="$marker_start" -v e="$marker_end" -v path="$prefix" -v file="$auth_file" '
                    /^[[:space:]]*listen[[:space:]]+443[[:space:]]+ssl;/ { tls=1 }
                    tls && /^[[:space:]]*location \/ \{ try_files \$uri \$uri\/ =404; \}$/ {
                        print "    " b
                        print "    location ^~ " path " {"
                        print "        auth_basic \"Restricted\";"
                        print "        auth_basic_user_file " file ";"
                        print "        try_files $uri $uri/ =404;"
                        print "    }"
                        print "    " e
                        inserted++
                    }
                    { print }
                    END { if (inserted!=1) exit 3 }
                ' "$config_copy" > "$staged" || rc=1
            fi
        fi
        rm -f -- "$config_copy"
        if (( rc != 0 )); then
            [[ -n "$temp_pass" ]] && sudo rm -f -- "$temp_pass"
            rm -f -- "$backup" "$staged"
            sayfail "Could not prepare Basic Auth configuration; site unchanged."
            return 1
        fi
        # Nginx needs the password file in place for nginx -t. Preserve an old file
        # for rollback when replacing credentials.
        local old_pass=""
        if [[ -n "$temp_pass" ]]; then
            if [[ -e "$auth_file" ]]; then
                old_pass="$auth_dir/.${site}.$$.old"
                sudo cp -p -- "$auth_file" "$old_pass" || rc=1
            fi
            (( rc == 0 )) && sudo mv -- "$temp_pass" "$auth_file" || rc=1
        fi
        if (( rc == 0 )) && sudo cp -- "$staged" "$cfg" && sudo nginx -t && sudo systemctl reload nginx.service; then
            [[ -n "$old_pass" ]] && sudo rm -f -- "$old_pass"
            rm -f -- "$backup" "$staged"
            sayok "Private-section authentication updated for $site."
            [[ "$action" == "Disable existing protection" ]] && sayinfo "Credential file retained outside the web root; remove separately if no longer needed."
            return 0
        fi
        sudo cp -- "$backup" "$cfg" || true
        if [[ -n "$old_pass" ]]; then
            sudo mv -- "$old_pass" "$auth_file" || true
        elif [[ -n "$temp_pass" ]]; then
            sudo rm -f -- "$auth_file" "$temp_pass" || true
        fi
        sudo nginx -t >/dev/null 2>&1 && sudo systemctl reload nginx.service >/dev/null 2>&1 || true
        rm -f -- "$backup" "$staged"
        sayfail "Basic Auth configuration failed; restored the previous site settings."
        return 1
    }

    # fn: _web_server_update_markdown_upload - Migrate a configured upload service to the canonical library implementation.
    # . Purpose
    #   Keep Python implementation in lib/solidgroundux/py, not a duplicate
    #   libexec copy. Preserve site-specific hostname, upload directory and
    #   systemd sandbox settings; restart only after validating the new unit.
    _web_server_update_markdown_upload() {
        local unit="/etc/systemd/system/solidgroundux-markdown-upload.service"
        local canonical="/usr/local/lib/solidgroundux/py/webcontent/webcontent-upload-service.py"
        local old="/usr/local/libexec/solidgroundux/webcontent-upload-service.py"
        local current="" staged="" backup="" decision="NO"
        [[ -r "$canonical" ]] || { sayfail "Upload receiver library missing: $canonical"; return 1; }
        sudo test -f "$unit" || { saywarning "Upload service is not installed on this host."; return 1; }
        current="$(sudo sed -n 's/^ExecStart=\/usr\/bin\/python3 \([^ ]*\) .*/\1/p' "$unit")"
        [[ "$current" == "$old" || "$current" == "$canonical" ]] || {
            sayfail "Unknown upload service entry point; refusing to modify: $current"; return 1;
        }
        if [[ "$current" == "$canonical" ]]; then
            sayinfo "Upload service already uses the canonical library implementation."
            return 0
        fi
        ask_decision --label "Switch upload service to canonical Python library and restart it" --choices "YES|Y,NO|N" --default "NO" --var decision || return 0
        [[ "$decision" == YES ]] || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "DRYRUN: Would migrate upload receiver service."; return 0; fi
        sudo -v || return 1
        sudo python3 -m py_compile "$canonical" || { sayfail "Upload receiver failed Python syntax check."; return 1; }
        staged="$(mktemp)" || return 1
        backup="$(mktemp)" || { rm -f "$staged"; return 1; }
        sudo cp -- "$unit" "$backup" || { rm -f "$staged" "$backup"; return 1; }
        sed "s|^ExecStart=/usr/bin/python3 $old |ExecStart=/usr/bin/python3 $canonical |" "$backup" > "$staged" || {
            rm -f "$staged" "$backup"; return 1;
        }
        if ! grep -Fq "ExecStart=/usr/bin/python3 $canonical " "$staged"; then
            sayfail "Could not update ExecStart safely."; rm -f "$staged" "$backup"; return 1
        fi
        if sudo install -m 0644 -o root -g root "$staged" "$unit" &&
           sudo systemctl daemon-reload &&
           sudo systemctl restart solidgroundux-markdown-upload.service &&
           sudo systemctl is-active --quiet solidgroundux-markdown-upload.service; then
            sayok "Upload receiver now runs the canonical Python library file."
            rm -f "$staged" "$backup"; return 0
        fi
        sayfail "Upload service update failed; restoring previous unit."
        sudo install -m 0644 -o root -g root "$backup" "$unit" || true
        sudo systemctl daemon-reload || true
        sudo systemctl restart solidgroundux-markdown-upload.service || true
        rm -f "$staged" "$backup"
        return 1
    }

    # fn: _web_server_configure_markdown_upload - Install and protect the optional Markdown receiver
    # . Purpose
    #   Bind the upload service to localhost, outside the document root, with
    #   Basic Authentication on its Nginx endpoint. Roll back Nginx on failure.
    #   Currently supports one upload service per host; never expose it without auth.
    _web_server_configure_markdown_upload() {
        local site="" cfg="" host="" root="" publisher="" source="" directory="/srv/storage/webcontent-incoming"
        local backup="" staged="" unit_tmp="" decision="NO" auth_file="" rc=0
        local -a sites=()
        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No managed site available."; return 0; }
        _web_ask_selection --label "Install Markdown upload for HTTPS site" --var site --items "${sites[@]}" || return 0
        [[ "$site" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { sayfail "Invalid site name."; return 2; }
        cfg="/etc/nginx/sites-available/$site"
        source="/usr/local/lib/solidgroundux/py/webcontent/webcontent-upload-service.py"
        [[ -f "$cfg" && ! -L "$cfg" && -L "/etc/nginx/sites-enabled/$site" ]] || { sayfail "Site must be enabled and managed."; return 1; }
        [[ -r "$source" ]] || { sayfail "Missing companion file: $source"; return 1; }
        # Resolve the *effective managed* password file from the Nginx configuration.
        # Never guess its name: pre-existing deployments may use another path.
        # Require exactly one managed block containing Basic Auth directives.
        if ! grep -Fq '# SGND_BASIC_AUTH_BEGIN' "$cfg" ||
           ! grep -Fq '# SGND_BASIC_AUTH_END' "$cfg"; then
            sayfail "No managed private section found for $site; upload remains disabled."
            return 1
        fi
        auth_file="$(awk '
            /# SGND_BASIC_AUTH_BEGIN/ { if (inside || found) exit 3; inside=1; next }
            /# SGND_BASIC_AUTH_END/ { if (!inside) exit 3; inside=0; found=1; next }
            inside && $1 == "auth_basic_user_file" { gsub(/;$/, "", $2); file=$2; count++ }
            END { if (inside || !found || count != 1) exit 3; print file }
        ' "$cfg")" || {
            sayfail "Cannot resolve a unique managed Basic Auth password file; upload remains disabled."
            return 1
        }
        [[ "$auth_file" == /* && "$auth_file" != *[[:space:]]* && "$auth_file" != *\;* ]] || {
            sayfail "Unsafe Basic Auth password file path; upload remains disabled."; return 1;
        }
        if ! sudo test -f "$auth_file"; then
            sayfail "Configured Basic Auth password file is missing: $auth_file"
            return 1
        fi
        grep -Eq '^[[:space:]]*listen[[:space:]]+443[[:space:]]+ssl;' "$cfg" &&
        grep -Fq 'return 301 https://$host$request_uri;' "$cfg" || { sayfail "HTTPS with redirect is required."; return 1; }
        if grep -Fq '# SGND_UPLOAD_BEGIN' "$cfg" || grep -Eq 'location[[:space:]]+=[[:space:]]+/api/markdown-upload' "$cfg"; then
            saywarning "Upload is already configured; refusing to overwrite it."; return 1
        fi
        host="$(awk '$1=="server_name" {print $2;exit}' "$cfg" | tr -d ';')"
        root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
        publisher="$(stat -c %U -- "$root" 2>/dev/null || true)"
        [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$publisher" =~ ^[a-z_][a-zA-Z0-9_-]*$ && "$publisher" != root ]] || {
            sayfail "Site needs a valid hostname and a non-root document root owner."; return 1;
        }
        if [[ -e /etc/systemd/system/solidgroundux-markdown-upload.service ]] || systemctl is-active --quiet solidgroundux-markdown-upload.service; then
            saywarning "An upload service is already configured on this host; one upload site is supported."; return 1
        fi
        ask --label "Non-public upload directory" --var directory --default "$directory" --back || return 0
        [[ "$directory" =~ ^/[a-zA-Z0-9/_-]+$ && "$directory" != *".."* && "$directory" != "$root"* ]] || {
            sayfail "Choose a safe absolute path outside the site document root."; return 2;
        }
        ask_decision --label "Install protected upload endpoint for $host" --choices "YES|Y,NO|N" --default "NO" --var decision || return 0
        [[ "$decision" == YES ]] || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "DRYRUN: Would configure protected Markdown upload."; return 0; fi
        sudo -v || return 1
        command -v python3 >/dev/null 2>&1 || { sayfail "Python 3 is required."; return 127; }
        backup="$(mktemp)" || return 1
        staged="$(mktemp)" || { rm -f "$backup"; return 1; }
        sudo cp -- "$cfg" "$backup" || { rm -f "$backup" "$staged"; return 1; }
        # Fail unless the expected managed HTTPS location can be identified exactly.
        awk -v file="$auth_file" '
            /^[[:space:]]*listen[[:space:]]+443[[:space:]]+ssl;/ { tls=1 }
            tls && /^[[:space:]]*location \/ \{ try_files \$uri \$uri\/ =404; \}$/ {
                print "    # SGND_UPLOAD_BEGIN"
                print "    location = /api/markdown-upload {"
                print "        auth_basic \"Restricted\";"
                print "        auth_basic_user_file " file ";"
                print "        client_max_body_size 105m;"
                print "        proxy_request_buffering on;"
                print "        proxy_set_header Host $host;"
                print "        proxy_set_header X-Forwarded-Proto https;"
                print "        proxy_pass http://127.0.0.1:18765;"
                print "    }"
                print "    # SGND_UPLOAD_END"
                inserted++
            }
            { print }
            END { if (inserted != 1) exit 3 }
        ' "$cfg" > "$staged" || {
            sayfail "Unexpected Nginx template; no upload changes made."; rm -f "$backup" "$staged"; return 1;
        }
        # A working Basic Auth setup is an input, not something upload setup owns.
        # Check effective www-data access without changing existing ownership or modes.
        if ! sudo -u www-data test -r "$auth_file"; then
            sayfail "Nginx worker cannot read Basic Auth password file: $auth_file"
            sayinfo "Correct its group/directory permissions before enabling uploads."
            rc=1
        fi
        (( rc == 0 )) && sudo install -d -m 0750 -o "$publisher" -g "$publisher" -- "$directory" || rc=1
        unit_tmp="$(mktemp)" || rc=1
        if (( rc == 0 )); then
            cat > "$unit_tmp" <<UNIT
[Unit]
Description=SolidGroundUX Markdown upload receiver
After=network.target
[Service]
Type=simple
User=$publisher
Group=$publisher
ExecStart=/usr/bin/python3 $source --hostname $host --directory $directory
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$directory
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNIT
            sudo install -m 0644 -o root -g root "$unit_tmp" /etc/systemd/system/solidgroundux-markdown-upload.service || rc=1
            (( rc == 0 )) && sudo systemctl daemon-reload && sudo systemctl enable --now solidgroundux-markdown-upload.service && sudo systemctl is-active --quiet solidgroundux-markdown-upload.service || rc=1
        fi
        if (( rc == 0 )) && sudo cp -- "$staged" "$cfg" && sudo nginx -t && sudo systemctl reload nginx.service; then
            sayok "Protected upload service enabled for $host. Files: $directory"
            rm -f -- "$backup" "$staged" "$unit_tmp"
            return 0
        fi
        sudo cp -- "$backup" "$cfg" || true
        sudo nginx -t >/dev/null 2>&1 && sudo systemctl reload nginx.service >/dev/null 2>&1 || true
        sudo systemctl disable --now solidgroundux-markdown-upload.service >/dev/null 2>&1 || true
        sudo rm -f /etc/systemd/system/solidgroundux-markdown-upload.service
        sudo systemctl daemon-reload >/dev/null 2>&1 || true
        rm -f -- "$backup" "$staged" "$unit_tmp"
        sayfail "Upload installation failed; Nginx configuration restored."
        return 1
    }

    # fn: _web_server_manage_sites - Open the site-management workflow
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_manage_sites
    _web_server_manage_sites() {
        local action=""
        _web_ask_selection --label "Site management" --var action --items "Create site" "Enable site" "Disable site" "Change document root" "Configure HTTPS" "Configure private section" "Configure Markdown upload" "Update Markdown upload receiver" "Remove site" "Remove site content" "List sites" || return 0
        case "$action" in
            "Create site") _web_server_create_site ;;
            "Enable site") _web_server_enable_site ;;
            "Disable site") _web_server_disable_site ;;
            "Change document root") _web_server_change_document_root ;;
            "Configure HTTPS") _web_server_configure_https ;;
            "Configure private section") _web_server_configure_basic_auth ;;
            "Configure Markdown upload") _web_server_configure_markdown_upload ;;
            "Update Markdown upload receiver") _web_server_update_markdown_upload ;;
            "Remove site") _web_server_remove_site ;;
            "Remove site content") _web_server_remove_site_content ;;
            "List sites") _web_server_list_sites ;;
        esac
    }

# - SolidGroundUX documentation ----------------------------------------------------
    # fn: _web_server_default_docs_address - Return a sensible documentation web address
        # . Usage
        #   _web_server_default_docs_address
    _web_server_default_docs_address() {
        local domain=""
        domain="$(hostname -d 2>/dev/null || true)"
        if [[ -n "$domain" ]]; then
            printf 'sgnddocs.%s\n' "$domain"
        else
            hostname -f 2>/dev/null || hostname
        fi
    }

    # fn: _web_server_configure_documentation_site - Configure the documentation web site
        # . Purpose
        #   Create or select the Nginx site used to publish SolidGroundUX documentation.
        # . Usage
        #   _web_server_configure_documentation_site "<existing_address>" "<existing_address>"
    _web_server_configure_documentation_site() {
        local site="${SGND_WEB_DOC_SITE:-SolidGroundUX-Documentation}"
        local address="${SGND_WEB_DOC_ADDRESS:-}"
        local document_root="${SGND_WEB_DOC_ROOT:-}"
        local web_root=""
        local config_file=""
        local existing_address=""
        local existing_root=""

        _web_server_package_installed || { sayfail "Nginx is not installed."; return 1; }
        web_root="$(_web_server_root)"
        [[ -n "$address" ]] || address="$(_web_server_default_docs_address)"
        [[ -n "$document_root" ]] || document_root="$web_root/$site"

        ask --label "Documentation site" --var site --default "$site" --validate _web_server_validate_site_name --back || return 0
        config_file="/etc/nginx/sites-available/$site"

        if [[ -r "$config_file" ]]; then
            existing_address="$(awk '$1 == "server_name" {gsub(/;/, "", $2); print $2; exit}' "$config_file" 2>/dev/null || true)"
            existing_root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
            [[ -n "$existing_address" ]] && address="$existing_address"
            [[ -n "$existing_root" ]] && document_root="$existing_root"
            sayinfo "Using existing Nginx site configuration: $site"
        else
            ask --label "Web address" --var address --default "$address" --back || return 0
            ask --label "Document root" --var document_root --default "$web_root/$site" --back || return 0
            [[ "$document_root" == /* ]] || document_root="$web_root/$document_root"
            _web_server_ensure_directory "$document_root" "www-data:www-data" || return 1

            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "DRYRUN: Would create documentation site $site at $address using $document_root."
            else
                sudo tee "$config_file" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $address;
    root $document_root;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
                sudo ln -s "$config_file" "/etc/nginx/sites-enabled/$site" || return 1
                _web_server_reload || {
                    sudo rm -f "/etc/nginx/sites-enabled/$site"
                    sudo rm -f "$config_file"
                    return 1
                }
                sayok "Documentation site created and enabled: $site"
                _web_server_offer_dns_record "$address"
            fi
        fi

        SGND_WEB_DOC_SITE="$site"
        SGND_WEB_DOC_ADDRESS="$address"
        SGND_WEB_DOC_ROOT="$document_root"
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would persist documentation publishing target '$site'."
            return 0
        fi
        _web_server_save_state || return 1
        sayok "Documentation publishing target configured: $site"
    }
    # fn: _web_server_documentation_paths - Resolve and validate documentation sync endpoints
        # . Purpose
        #   Never sync a missing, nested, identical, or symlinked documentation root.
        #   An installed source needs index.html; publishing never creates a new Nginx site.
        # . Usage
        #   _web_server_documentation_paths <source-var> <destination-var>
    _web_server_documentation_paths() {
        local source_var="$1" destination_var="$2" site="${SGND_WEB_DOC_SITE:-SolidGroundUX-Documentation}"
        local src_inner="" dst_inner="" config_file="/etc/nginx/sites-available/$site"
        [[ -r "$config_file" ]] || { saywarning "Documentation Nginx site not configured: $site"; return 1; }
        src_inner="$(_web_server_installed_docs_root)" || return 1
        dst_inner="$(_web_server_site_document_root "$site")" || return 1
        [[ -d "$src_inner" && -f "$src_inner/index.html" ]] || { saywarning "Installed documentation missing or index.html absent: $src_inner"; return 1; }
        [[ -d "$dst_inner" ]] || { saywarning "Published documentation directory missing: $dst_inner"; return 1; }
        [[ ! -L "$src_inner" && ! -L "$dst_inner" ]] || { sayfail "Symlinked documentation roots are unsupported."; return 1; }
        src_inner="$(realpath -e -- "$src_inner")" || return 1
        dst_inner="$(realpath -e -- "$dst_inner")" || return 1
        [[ "$src_inner" != "$dst_inner" && "$src_inner" != "$dst_inner"/* && "$dst_inner" != "$src_inner"/* ]] || {
            sayfail "Documentation source and destination overlap; refusing synchronization."
            return 1
        }
        [[ "$dst_inner" != / && "$src_inner" != / ]] || return 1
        printf -v "$source_var" '%s' "$src_inner"
        printf -v "$destination_var" '%s' "$dst_inner"
    }

    # fn: _web_server_documentation_changes - Check whether published documentation differs
        # . Purpose
        #   Compare the full tree with rsync's read-only itemized dry-run, including
        #   removed files. Exit 0 when equal, 1 when different, 2 on comparison error.
    _web_server_documentation_changes() {
        local source="$1" destination="$2" output="" rc=0
        command -v rsync >/dev/null 2>&1 || { saywarning "rsync is not installed."; return 2; }
        output="$(rsync -rclni --delete --out-format='%i %n' -- "$source/" "$destination/" 2>&1)" || rc=$?
        if (( rc != 0 )); then
            saywarning "Documentation comparison failed (rsync exit $rc): $output"
            return 2
        fi
        [[ -z "$output" ]] && return 0
        return 1
    }

    # fn: _web_server_update_documentation - Preview and optionally publish installed docs
        # . Purpose
        #   This action only updates an EXISTING configured documentation site.
        #   A mirrored update may remove obsolete files; explicit consent is required.
    _web_server_update_documentation() {
        local source="" destination="" decision="NO" rc=0
        _web_server_documentation_paths source destination || return 1
        _web_server_documentation_changes "$source" "$destination"; rc=$?
        case "$rc" in
            0) sayok "Published documentation is up to date."; return 0 ;;
            1) ;;
            *) return 1 ;;
        esac
        sgnd_print_labeledvalue --label "Installed docs" --value "$source" --labelwidth 24
        sgnd_print_labeledvalue --label "Published docs" --value "$destination" --labelwidth 24
        sayinfo "Installed and published documentation differ. A mirror update also deletes obsolete published files."
        ask_decision --label "Update published documentation" --choices "YES|Y,NO|N" --default "NO" --var decision || return 0
        [[ "$decision" == YES ]] || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would mirror $source to $destination (including deletions)."
            return 0
        fi
        # The existing site is owned by the web server; do not change its ownership.
        sudo rsync -rlpt --delete -- "$source/" "$destination/" || {
            sayfail "Documentation update failed; published files may be partially changed."
            return 1
        }
        sayok "Published documentation updated: $destination"
    }

    # fn: _web_server_documentation_status - Show docs site and detect pending updates
        # . Purpose
        #   Only installed-documentation sources can be compared automatically;
        #   remote and Git sources follow their separate publishing workflows.
    _web_server_documentation_status() {
        local site="${SGND_WEB_DOC_SITE:-SolidGroundUX-Documentation}"
        local config_file="/etc/nginx/sites-available/${SGND_WEB_DOC_SITE:-SolidGroundUX-Documentation}"
        local state="Not configured" enabled="No"
        local address="${SGND_WEB_DOC_ADDRESS:-Not configured}"
        local document_root="${SGND_WEB_DOC_ROOT:-Not configured}"
        local installed_docs="" source="" destination="" compare_rc=0
        installed_docs="$(_web_server_installed_docs_root)" || return 1
        if [[ -r "$config_file" ]]; then
            state="Configured"
            [[ -e "/etc/nginx/sites-enabled/$site" ]] && enabled="Yes"
            address="$(awk '$1 == "server_name" {gsub(/;/, "", $2); print $2; exit}' "$config_file" 2>/dev/null || printf '%s' "$address")"
            document_root="$(_web_server_site_document_root "$site" 2>/dev/null || printf '%s' "$document_root")"
        fi
        sgnd_print
        sgnd_print_sectionheader "SolidGroundUX Documentation"
        sgnd_print_labeledvalue --label "Site" --value "$site" --labelwidth 24
        sgnd_print_labeledvalue --label "Status" --value "$state" --labelwidth 24
        sgnd_print_labeledvalue --label "Enabled" --value "$enabled" --labelwidth 24
        sgnd_print_labeledvalue --label "Web address" --value "$address" --labelwidth 24
        if [[ "$address" != "Not configured" && -n "$address" ]]; then
            sgnd_print_labeledvalue --label "HTTP address" --value "http://$address/" --labelwidth 24
        else
            sgnd_print_labeledvalue --label "HTTP address" --value "Not configured" --labelwidth 24
        fi
        sgnd_print_labeledvalue --label "Document root" --value "$document_root" --labelwidth 24
        sgnd_print_labeledvalue --label "Installed docs" --value "$installed_docs" --labelwidth 24
        sgnd_print_labeledvalue --label "Source type" --value "${SGND_WEB_DOC_SOURCE_TYPE:-Installed documentation}" --labelwidth 24
        if [[ "${SGND_WEB_DOC_SOURCE_TYPE:-Installed documentation}" != "Installed documentation" ]]; then
            sayinfo "Update comparison is available for installed documentation only."
            return 0
        fi
        _web_server_documentation_paths source destination || return 0
        _web_server_documentation_changes "$source" "$destination"; compare_rc=$?
        case "$compare_rc" in
            0) sayok "Published documentation matches installed documentation." ;;
            1)
                saywarning "Installed documentation differs from published documentation."
                _web_server_update_documentation
                ;;
            *) saywarning "Documentation currency could not be determined." ;;
        esac
    }

# - Status / validation ------------------------------------------------------------
    # fn: _web_server_status - Show web-server status and configuration
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_status
    _web_server_status() {
        local package_state="not installed"
        local package_version="-"
        local service_state="unavailable"
        local enabled_state="No"
        local config_state="unavailable"
        local http_listener="No"
        local https_listener="No"
        local web_root=""
        local site_count=0
        local -a sites=()

        web_root="$(_web_server_root)"
        if _web_server_package_installed; then
            package_state="installed"
            package_version="$(dpkg-query -W -f='${Version}' nginx 2>/dev/null || printf '-')"
            service_state="$(systemctl is-active nginx.service 2>/dev/null || true)"
            [[ -n "$service_state" ]] || service_state="inactive"
            systemctl is-enabled --quiet nginx.service 2>/dev/null && enabled_state="Yes"
            sudo nginx -t >/dev/null 2>&1 && config_state="valid" || config_state="invalid"
        fi

        ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)80$' && http_listener="Yes"
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)443$' && https_listener="Yes"
        mapfile -t sites < <(_web_server_enabled_sites 2>/dev/null || true)
        site_count="${#sites[@]}"

        sgnd_print
        sgnd_print_sectionheader "Web Server"
        sgnd_print_labeledvalue --label "Package" --value "$package_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Version" --value "$package_version" --labelwidth 22
        sgnd_print_labeledvalue --label "Service" --value "$service_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Enabled at boot" --value "$enabled_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Configuration" --value "$config_state" --labelwidth 22
        sgnd_print_labeledvalue --label "Web content root" --value "$web_root" --labelwidth 22
        sgnd_print_labeledvalue --label "HTTP listener" --value "$http_listener" --labelwidth 22
        sgnd_print_labeledvalue --label "HTTPS listener" --value "$https_listener" --labelwidth 22
        sgnd_print_labeledvalue --label "Enabled sites" --value "$site_count" --labelwidth 22
    }

    # fn: _web_server_validate - Validate the web-server role
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_validate
    _web_server_validate() {
        local failures=0
        local result=""
        local web_root=""

        web_root="$(_web_server_root)"
        sgnd_print
        sgnd_print_sectionheader "Validate Web Server"

        if _web_server_package_installed && command -v nginx >/dev/null 2>&1; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Nginx package" --value "$result" --labelwidth 24

        if command -v nginx >/dev/null 2>&1 && sudo nginx -t >/dev/null 2>&1; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Configuration" --value "$result" --labelwidth 24

        if systemctl is-enabled --quiet nginx.service 2>/dev/null; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Enabled at boot" --value "$result" --labelwidth 24

        if systemctl is-active --quiet nginx.service 2>/dev/null; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Service active" --value "$result" --labelwidth 24

        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)80$|(^|:)443$'; then result="Passed"; else result="Failed"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "HTTP/HTTPS listener" --value "$result" --labelwidth 24

        if [[ -d "$web_root" && -x "$web_root" ]]; then result="Passed ($web_root)"; else result="Failed ($web_root)"; failures=$((failures + 1)); fi
        sgnd_print_labeledvalue --label "Web content root" --value "$result" --labelwidth 24

        sgnd_print
        if (( failures == 0 )); then sayok "Web-server validation passed."; return 0; fi
        sayfail "$failures web-server validation check(s) failed."
        return 1
    }

# - Action dispatch -----------------------------------------------------------------
    _run_action() {
        local action="${1:?missing action}" rc=0
        case "$action" in
            prepare) _web_server_prepare || rc=$? ;;
            install) _web_server_step_install_packages || rc=$? ;;
            start) _web_server_step_start || rc=$? ;;
            configure-root) _web_server_configure_root || rc=$? ;;
            manage-sites) _web_server_manage_sites || rc=$? ;;
            ensure-site) _web_server_ensure_site || rc=$? ;;
            ensure-directory) _web_server_ensure_directory_for_publish || rc=$? ;;
            configure-dns) _web_server_configure_dns || rc=$? ;;
            configure-documentation) _web_server_configure_documentation_site || rc=$? ;;
            documentation-status) _web_server_documentation_status || rc=$? ;;
            update-documentation) _web_server_update_documentation || rc=$? ;;
            service) _web_server_manage_service || rc=$? ;;
            firewall) _web_server_configure_firewall || rc=$? ;;
            validate) _web_server_validate || rc=$? ;;
            status) _web_server_status || rc=$? ;;
            *) sayfail "Unknown web-server management action: $action"; return 2 ;;
        esac
        if (( rc == 0 )); then
            case "$action" in status|validate|documentation-status) ;; *) _dryrun_complete ;; esac
        fi
        sgnd_print
        sgnd_print_sectionheader ""
        return "$rc"
    }

# - Main ----------------------------------------------------------------------------
    main() {
        local action=""
        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        _web_server_load_state
        action="${ACTION:-status}"
        _run_action "$action"
    }
    main "$@"
#   Checksum : 390a5d307128f5ebe0a8c78b4d74266817f128b68fc4458518f846de366d59ff
