#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Web Server
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 1.1
#   Build       : 2625822
#   Source      : manage-web-server.sh
#   Type        : script
#   Group       : Console Actions
#   Purpose     : Configure, manage, validate, and inspect an Nginx web server
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

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_TITLE="Manage Web Server"
    : "${SGND_SCRIPT_DESC:=Configure, manage, validate, and inspect an Nginx web server.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2625722}"

# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Management action||prepare,install,configure-root,manage-sites,configure-documentation,documentation-status,service,firewall,validate,status"
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
    : "${SGND_WEB_DOC_REPO_PATH:=target-root/usr/local/share/testadura/solidgroundux/doc}"

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

    # fn: _web_server_installed_docs_root - Resolve the installed SolidGroundUX documentation path
        # . Output
        #   Writes the documentation directory belonging to the active framework root.
        # . Usage
        #   _web_server_installed_docs_root
    _web_server_installed_docs_root() {
        local framework_root="${SGND_FRAMEWORK_ROOT:-/}"

        if [[ "$framework_root" == "/" ]]; then
            printf '/usr/local/share/testadura/solidgroundux/doc\n'
        else
            printf '%s/usr/local/share/testadura/solidgroundux/doc\n' "${framework_root%/}"
        fi
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
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_prepare
    _web_server_prepare() {
        _web_server_step_install_packages || return $?
        _web_server_step_start || return $?
        sayok "Web-server preparation completed successfully."
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

        ask_selection --label "Select web content root" --var selected --items "${options[@]}" || return 0
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
        ask_selection --label "Web service action" --var action --items "Start" "Stop" "Restart" "Enable at boot" "Disable at boot" || return 0

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
        command -v ufw >/dev/null 2>&1 || { saywarning "UFW is not installed."; return 0; }
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
        ask_selection --label "Enable Nginx site" --var site --items "${sites[@]}" || return 0
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
        ask_selection --label "Disable Nginx site" --var site --items "${sites[@]}" || return 0
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "DRYRUN: Would disable $site."; return 0; fi
        sudo rm -f "/etc/nginx/sites-enabled/$site" || return 1
        _web_server_reload || return 1
        sayok "Site disabled: $site"
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
        local -a sites=()

        mapfile -t sites < <(_web_server_available_sites 2>/dev/null || true)
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites are available."; return 0; }
        ask_selection --label "Remove Nginx site configuration" --var site --items "${sites[@]}" || return 0
        document_root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"

        ask_decision --label "Remove site configuration '$site'" --choices "YES|Y,NO|N" --default "NO" --var decision
        [[ "$decision" == "YES" ]] || return 0

        if [[ -n "$document_root" ]]; then
            sgnd_print_labeledvalue --label "Document root" --value "$document_root" --labelwidth 22
            ask_decision --label "Remove site content as well" --choices "YES|Y,NO|N" --default "NO" --var remove_content
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would remove site configuration $site."
            [[ "$remove_content" == "YES" && -n "$document_root" ]] && _web_server_remove_document_content "$document_root"
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
        ask_selection --label "Remove content from site" --var site --items "${sites[@]}" || return 0

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
        done
    }

    # fn: _web_server_manage_sites - Open the site-management workflow
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_manage_sites
    _web_server_manage_sites() {
        local action=""
        ask_selection --label "Site management" --var action --items "Create site" "Enable site" "Disable site" "Remove site" "Remove site content" "List sites" || return 0
        case "$action" in
            "Create site") _web_server_create_site ;;
            "Enable site") _web_server_enable_site ;;
            "Disable site") _web_server_disable_site ;;
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
    # fn: _web_server_documentation_status - Show documentation publishing status
        # . Usage
        #   _web_server_documentation_status "<address>" "<address>"
    _web_server_documentation_status() {
        local site="${SGND_WEB_DOC_SITE:-SolidGroundUX-Documentation}"
        local config_file="/etc/nginx/sites-available/${SGND_WEB_DOC_SITE:-SolidGroundUX-Documentation}"
        local state="Not configured"
        local enabled="No"
        local address="${SGND_WEB_DOC_ADDRESS:-Not configured}"
        local document_root="${SGND_WEB_DOC_ROOT:-Not configured}"
        local installed_docs=""

        installed_docs="$(_web_server_installed_docs_root)"
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
        sgnd_print_labeledvalue --label "Document root" --value "$document_root" --labelwidth 24
        sgnd_print_labeledvalue --label "Installed docs" --value "$installed_docs" --labelwidth 24
        sgnd_print_labeledvalue --label "Source type" --value "${SGND_WEB_DOC_SOURCE_TYPE:-Installed documentation}" --labelwidth 24
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
            configure-root) _web_server_configure_root || rc=$? ;;
            manage-sites) _web_server_manage_sites || rc=$? ;;
            configure-documentation) _web_server_configure_documentation_site || rc=$? ;;
            documentation-status) _web_server_documentation_status || rc=$? ;;
            service) _web_server_manage_service || rc=$? ;;
            firewall) _web_server_configure_firewall || rc=$? ;;
            validate) _web_server_validate || rc=$? ;;
            status) _web_server_status || rc=$? ;;
            *) sayfail "Unknown web-server management action: $action"; return 2 ;;
        esac
        if (( rc == 0 )); then
            case "$action" in status|validate|documentation-status) ;; *) _dryrun_complete ;; esac
        fi
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
#   Checksum : e580d88b630a6779760d98c902bd531ff255bb8f73406bfc8cff8a77c25892d9
