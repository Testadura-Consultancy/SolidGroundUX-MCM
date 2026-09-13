# ==================================================================================
# SolidGroundUX - Web Server
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2625621
#   Source      : 50-web-server.sh
#   Type        : module
#   Group       : SolidGround Console
#   Subgroup    : Console Modules
#   Purpose     : Install, configure, manage, validate, and inspect an Nginx web server
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
    SGND_WEB_SERVER_MODULE_ID="web-server"
    SGND_WEB_SERVER_MODULE_NAME="Web Server"
    SGND_WEB_SERVER_MODULE_VERSION="1.2.0"
    SGND_WEB_SERVER_MODULE_DESC="Install, configure, manage, validate, and inspect an Nginx web server"

    SGND_MODULE_ID="$SGND_WEB_SERVER_MODULE_ID"
    SGND_MODULE_NAME="$SGND_WEB_SERVER_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_WEB_SERVER_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_WEB_SERVER_MODULE_DESC"

    SGND_WEB_SERVER_CONFIG_FILE="${SGND_SYSCFG_DIR:-/etc/solidgroundux}/web-server.cfg"
    SGND_WEB_SERVER_DEFAULT_STORAGE_ROOT="/srv/storage"

    SGND_WEB_SERVER_STATE_FILE="${SGND_STATE_DIR:-${HOME}/.state/solidgroundux}/web-server.state"
    SGND_WEB_SERVER_STATE_VARIABLES=(
        SGND_WEB_PUBLISH_SITE
        SGND_WEB_PUBLISH_SOURCE_TYPE
        SGND_WEB_PUBLISH_SOURCE_HOST
        SGND_WEB_PUBLISH_SOURCE_USER
        SGND_WEB_PUBLISH_SOURCE_DIR
        SGND_WEB_DOC_SITE
        SGND_WEB_DOC_ADDRESS
        SGND_WEB_DOC_ROOT
        SGND_WEB_DOC_SOURCE_TYPE
        SGND_WEB_DOC_SOURCE_HOST
        SGND_WEB_DOC_SOURCE_USER
        SGND_WEB_DOC_SOURCE_DIR
        SGND_WEB_DOC_REPOSITORY
        SGND_WEB_DOC_REF
        SGND_WEB_DOC_REPO_PATH
    )

    : "${SGND_WEB_PUBLISH_SITE:=}"
    : "${SGND_WEB_PUBLISH_SOURCE_TYPE:=Remote machine}"
    : "${SGND_WEB_PUBLISH_SOURCE_HOST:=}"
    : "${SGND_WEB_PUBLISH_SOURCE_USER:=${SUDO_USER:-${USER:-sysadmin}}}"
    : "${SGND_WEB_PUBLISH_SOURCE_DIR:=}"
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

    if [[ -r "$SGND_WEB_SERVER_STATE_FILE" ]] && command -v sgnd_state_load_keys >/dev/null 2>&1; then
        sgnd_state_load_keys --file "$SGND_WEB_SERVER_STATE_FILE" --array SGND_WEB_SERVER_STATE_VARIABLES >/dev/null 2>&1 || true
    fi

# - Internal helpers ---------------------------------------------------------------
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

    # fn: _web_server_save_state - Persist web-server module state
        # . Returns
        #   0 on success; non-zero when state cannot be saved.
        # . Usage
        #   _web_server_save_state
    _web_server_save_state() {
        command -v sgnd_state_save_keys >/dev/null 2>&1 || return 0
        mkdir -p "$(dirname -- "$SGND_WEB_SERVER_STATE_FILE")" || return 1
        sgnd_state_save_keys --file "$SGND_WEB_SERVER_STATE_FILE" --array SGND_WEB_SERVER_STATE_VARIABLES
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
            sayinfo "Dry run: Would register ${record_name}.${local_domain} -> $local_ip on $dns_server."
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
            sayinfo "Dry run: Would remove all content below $document_root."
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
                sayinfo "Dry run: Would create directory $path."
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
            sayinfo "Dry run: Would reload nginx.service."
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
            sayinfo "Dry run: Would install Nginx web-server prerequisites."
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
            sayinfo "Dry run: Would enable and start nginx.service."
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
        sgnd_console_run_tracked "web-install" _web_server_step_install_packages || return $?
        sgnd_console_run_tracked "web-start" _web_server_step_start || return $?
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
            sayinfo "Dry run: Would configure web content root as $selected."
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
            sayinfo "Dry run: Would perform web service action: $action."
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
            sayinfo "Dry run: Would allow the Nginx Full firewall profile."
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
            sayinfo "Dry run: Would create Nginx site $site_name using $document_root."
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
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would enable $site."; return 0; fi
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
        if (( ${FLAG_DRYRUN:-0} == 1 )); then sayinfo "Dry run: Would disable $site."; return 0; fi
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
            sayinfo "Dry run: Would remove site configuration $site."
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

    # fn: _web_server_publish_key - Return the dedicated SolidGroundUX publishing key path
        # . Returns
        #   0 on success.
        # . Usage
        #   _web_server_publish_key
    _web_server_publish_key() {
        printf '%s\n' "${HOME}/.ssh/id_ed25519_sgnd_publish"
    }

    # fn: _web_server_remote_access_ready - Test passwordless SSH publishing access
        # . Returns
        #   0 when passwordless access works; non-zero otherwise.
        # . Usage
        #   _web_server_remote_access_ready <user@host>
    _web_server_remote_access_ready() {
        local remote="$1"
        local key=""

        key="$(_web_server_publish_key)"
        [[ -f "$key" ]] || return 1
        ssh -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes -i "$key" "$remote" true >/dev/null 2>&1
    }

    # fn: _web_server_setup_remote_access - Configure dedicated passwordless SSH publishing access
        # . Returns
        #   0 on success; non-zero when setup fails or is cancelled.
        # . Usage
        #   _web_server_setup_remote_access <user@host>
    _web_server_setup_remote_access() {
        local remote="$1"
        local key=""
        local decision="YES"

        command -v ssh >/dev/null 2>&1 || { sayfail "ssh is required for remote publishing."; return 1; }
        command -v ssh-keygen >/dev/null 2>&1 || { sayfail "ssh-keygen is required for remote publishing."; return 1; }
        command -v ssh-copy-id >/dev/null 2>&1 || { sayfail "ssh-copy-id is required for remote publishing."; return 1; }

        key="$(_web_server_publish_key)"

        ask_decision --label "Configure passwordless publishing access to $remote" --choices "YES|Y,NO|N" --default "YES" --var decision
        [[ "$decision" == "YES" ]] || return 1

        mkdir -p "$HOME/.ssh" || return 1
        chmod 0700 "$HOME/.ssh" || return 1

        if [[ ! -f "$key" ]]; then
            if (( ${FLAG_DRYRUN:-0} == 1 )); then
                sayinfo "Dry run: Would create dedicated publishing key $key with an empty passphrase."
            else
                ssh-keygen -q -t ed25519 -f "$key" -N "" -C "SolidGroundUX publishing key" || return 1
                sayok "Created dedicated SolidGroundUX publishing key."
            fi
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would establish host trust and install the publishing key on $remote."
            return 0
        fi

        # First contact may require accepting the host fingerprint and entering the
        # remote account password. The dedicated publishing key itself has no passphrase.
        ssh -o StrictHostKeyChecking=ask -o IdentitiesOnly=yes "$remote" true || true
        ssh-copy-id -i "${key}.pub" "$remote" || return 1

        if ! _web_server_remote_access_ready "$remote"; then
            sayfail "Passwordless SSH publishing access to $remote could not be verified."
            return 1
        fi

        sayok "Passwordless publishing access configured for $remote."
    }

    # fn: _web_server_publish_site - Publish local or remote content into a site document root
        # . Returns
        #   0 on success; non-zero when the operation cannot be completed.
        # . Usage
        #   _web_server_publish_site
    _web_server_publish_site() {
        local site="${SGND_WEB_PUBLISH_SITE:-}"
        local source_type="${SGND_WEB_PUBLISH_SOURCE_TYPE:-Remote machine}"
        local source_host="${SGND_WEB_PUBLISH_SOURCE_HOST:-}"
        local source_user="${SGND_WEB_PUBLISH_SOURCE_USER:-${SUDO_USER:-${USER:-sysadmin}}}"
        local source_dir="${SGND_WEB_PUBLISH_SOURCE_DIR:-}"
        local source_spec=""
        local remote=""
        local key=""
        local config_file=""
        local document_root=""
        local decision="YES"
        local candidate=""
        local remembered_site_found=0
        local -a sites=()
        local -a ordered_sites=()

        command -v rsync >/dev/null 2>&1 || { sayfail "rsync is required for publishing."; return 1; }

        # Always rebuild the selectable site list directly from the current nginx
        # configuration on disk. Persisted state may influence ordering only; it
        # must never re-introduce a site that no longer exists.
        mapfile -t sites < <(
            find /etc/nginx/sites-available \
                -mindepth 1 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
        )
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites are available."; return 0; }

        if [[ -n "$site" ]]; then
            for candidate in "${sites[@]}"; do
                if [[ "$candidate" == "$site" ]]; then
                    remembered_site_found=1
                    break
                fi
            done

            if (( remembered_site_found == 1 )); then
                ordered_sites+=("$site")
                for candidate in "${sites[@]}"; do
                    [[ "$candidate" == "$site" ]] || ordered_sites+=("$candidate")
                done
                sites=("${ordered_sites[@]}")
            else
                site=""
                SGND_WEB_PUBLISH_SITE=""
                if command -v sgnd_state_save_keys >/dev/null 2>&1; then
                    mkdir -p "$(dirname -- "$SGND_WEB_SERVER_STATE_FILE")" || return 1
                    sgnd_state_save_keys --file "$SGND_WEB_SERVER_STATE_FILE" --array SGND_WEB_SERVER_STATE_VARIABLES || return 1
                fi
            fi
        fi

        ask_selection --label "Publish to site" --var site --items "${sites[@]}" || return 0

        # Revalidate the selected site immediately. This protects a long-running
        # console from stale runtime state if a site was removed after the menu was
        # rendered, and avoids asking source questions for an invalid target.
        config_file="/etc/nginx/sites-available/$site"
        [[ -f "$config_file" ]] || {
            sayfail "Site configuration no longer exists: $site"
            if [[ "${SGND_WEB_PUBLISH_SITE:-}" == "$site" ]]; then
                SGND_WEB_PUBLISH_SITE=""
                if command -v sgnd_state_save_keys >/dev/null 2>&1; then
                    mkdir -p "$(dirname -- "$SGND_WEB_SERVER_STATE_FILE")" || return 1
                    sgnd_state_save_keys --file "$SGND_WEB_SERVER_STATE_FILE" --array SGND_WEB_SERVER_STATE_VARIABLES || return 1
                fi
            fi
            return 1
        }

        document_root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
        [[ -n "$document_root" ]] || { sayfail "Could not determine document root for $site."; return 1; }

        if [[ "$source_type" == "Local directory" ]]; then
            ask_selection --label "Source location" --var source_type --items "Local directory" "Remote machine" || return 0
        else
            ask_selection --label "Source location" --var source_type --items "Remote machine" "Local directory" || return 0
        fi

        case "$source_type" in
            "Local directory")
                ask --label "Source directory" --var source_dir --default "$source_dir" --back || return 0
                [[ -d "$source_dir" ]] || { sayfail "Source directory does not exist: $source_dir"; return 1; }
                source_spec="$source_dir/"
                ;;
            "Remote machine")
                command -v ssh >/dev/null 2>&1 || { sayfail "ssh is required for remote publishing."; return 1; }
                ask --label "Source host" --var source_host --default "$source_host" --back || return 0
                ask --label "Source user" --var source_user --default "$source_user" --back || return 0
                ask --label "Source directory" --var source_dir --default "$source_dir" --back || return 0
                [[ -n "$source_host" && -n "$source_user" && -n "$source_dir" ]] || { sayfail "Source host, user, and directory are required."; return 1; }

                remote="${source_user}@${source_host}"
                key="$(_web_server_publish_key)"

                if ! _web_server_remote_access_ready "$remote"; then
                    saywarning "Passwordless SSH publishing access is not configured for $remote."
                    _web_server_setup_remote_access "$remote" || return 1
                fi

                if ! ssh -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes -i "$key" "$remote" "test -d '$source_dir'" >/dev/null 2>&1; then
                    sayfail "Remote source directory does not exist or is not accessible: $remote:$source_dir"
                    return 1
                fi
                source_spec="${remote}:${source_dir}/"
                ;;
        esac

        SGND_WEB_PUBLISH_SITE="$site"
        SGND_WEB_PUBLISH_SOURCE_TYPE="$source_type"
        SGND_WEB_PUBLISH_SOURCE_HOST="$source_host"
        SGND_WEB_PUBLISH_SOURCE_USER="$source_user"
        SGND_WEB_PUBLISH_SOURCE_DIR="$source_dir"
        if command -v sgnd_state_save_keys >/dev/null 2>&1; then
            mkdir -p "$(dirname -- "$SGND_WEB_SERVER_STATE_FILE")" || return 1
            sgnd_state_save_keys --file "$SGND_WEB_SERVER_STATE_FILE" --array SGND_WEB_SERVER_STATE_VARIABLES || return 1
        fi

        # Verify once more just before touching the destination. A site may have
        # been removed while the source was being configured.
        [[ -f "$config_file" ]] || { sayfail "Site configuration no longer exists: $site"; return 1; }
        _web_server_ensure_directory "$document_root" "www-data:www-data" || return 1
        ask_decision --label "Synchronize source into $document_root" --choices "YES|Y,NO|N" --default "YES" --var decision
        [[ "$decision" == "YES" ]] || return 0

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would synchronize $source_spec to $document_root/."
            return 0
        fi

        if [[ "$source_type" == "Remote machine" ]]; then
            sudo rsync -a --delete -e "ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $key" "$source_spec" "$document_root/" || return 1
        else
            sudo rsync -a --delete "$source_spec" "$document_root/" || return 1
        fi
        sudo chown -R www-data:www-data "$document_root" || return 1
        sayok "Published $source_dir to $site."
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
                sayinfo "Dry run: Would create documentation site $site at $address using $document_root."
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
        _web_server_save_state || return 1
        sayok "Documentation publishing target configured: $site"
    }

    # fn: _web_server_publish_documentation - Publish SolidGroundUX documentation
        # . Purpose
        #   Publish documentation from the installed tree, a local/remote directory,
        #   or a GitHub repository into the configured documentation site.
        # . Usage
        #   _web_server_publish_documentation
    _web_server_publish_documentation() {
        local site="${SGND_WEB_DOC_SITE:-SolidGroundUX-Documentation}"
        local source_type="${SGND_WEB_DOC_SOURCE_TYPE:-Installed documentation}"
        local source_host="${SGND_WEB_DOC_SOURCE_HOST:-}"
        local source_user="${SGND_WEB_DOC_SOURCE_USER:-${SUDO_USER:-${USER:-sysadmin}}}"
        local source_dir="${SGND_WEB_DOC_SOURCE_DIR:-}"
        local repository="${SGND_WEB_DOC_REPOSITORY:-}"
        local repo_ref="${SGND_WEB_DOC_REF:-master}"
        local repo_path="${SGND_WEB_DOC_REPO_PATH:-target-root/usr/local/share/testadura/solidgroundux/doc}"
        local installed_docs=""
        local document_root=""
        local source_spec=""
        local remote=""
        local key=""
        local temp_dir=""
        local decision="YES"

        command -v rsync >/dev/null 2>&1 || { sayfail "rsync is required for documentation publishing."; return 1; }
        [[ -r "/etc/nginx/sites-available/$site" ]] || {
            saywarning "Documentation site is not configured: $site"
            _web_server_configure_documentation_site || return 1
            site="${SGND_WEB_DOC_SITE:-$site}"
        }

        document_root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
        [[ -n "$document_root" ]] || { sayfail "Could not determine document root for documentation site $site."; return 1; }
        installed_docs="$(_web_server_installed_docs_root)"

        case "$source_type" in
            "Installed documentation")
                ask_selection --label "Documentation source" --var source_type --items "Installed documentation" "Local directory" "Remote machine" "GitHub repository" || return 0
                ;;
            "Local directory")
                ask_selection --label "Documentation source" --var source_type --items "Local directory" "Installed documentation" "Remote machine" "GitHub repository" || return 0
                ;;
            "Remote machine")
                ask_selection --label "Documentation source" --var source_type --items "Remote machine" "Installed documentation" "Local directory" "GitHub repository" || return 0
                ;;
            *)
                ask_selection --label "Documentation source" --var source_type --items "GitHub repository" "Installed documentation" "Local directory" "Remote machine" || return 0
                ;;
        esac

        case "$source_type" in
            "Installed documentation")
                [[ -d "$installed_docs" ]] || { sayfail "Installed documentation directory does not exist: $installed_docs"; return 1; }
                source_dir="$installed_docs"
                source_spec="$source_dir/"
                ;;
            "Local directory")
                ask --label "Source directory" --var source_dir --default "$source_dir" --back || return 0
                [[ -d "$source_dir" ]] || { sayfail "Source directory does not exist: $source_dir"; return 1; }
                source_spec="$source_dir/"
                ;;
            "Remote machine")
                command -v ssh >/dev/null 2>&1 || { sayfail "ssh is required for remote documentation publishing."; return 1; }
                ask --label "Source host" --var source_host --default "$source_host" --back || return 0
                ask --label "Source user" --var source_user --default "$source_user" --back || return 0
                ask --label "Source directory" --var source_dir --default "$source_dir" --back || return 0
                [[ -n "$source_host" && -n "$source_user" && -n "$source_dir" ]] || { sayfail "Source host, user, and directory are required."; return 1; }
                remote="${source_user}@${source_host}"
                key="$(_web_server_publish_key)"
                if ! _web_server_remote_access_ready "$remote"; then
                    saywarning "Passwordless SSH publishing access is not configured for $remote."
                    _web_server_setup_remote_access "$remote" || return 1
                fi
                if ! ssh -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes -i "$key" "$remote" "test -d '$source_dir'" >/dev/null 2>&1; then
                    sayfail "Remote documentation directory does not exist or is not accessible: $remote:$source_dir"
                    return 1
                fi
                source_spec="${remote}:${source_dir}/"
                ;;
            "GitHub repository")
                command -v git >/dev/null 2>&1 || { sayfail "git is required for GitHub documentation publishing."; return 1; }
                ask --label "Repository URL" --var repository --default "$repository" --back || return 0
                ask --label "Branch or tag" --var repo_ref --default "$repo_ref" --back || return 0
                ask --label "Documentation path" --var repo_path --default "$repo_path" --back || return 0
                [[ -n "$repository" && -n "$repo_ref" && -n "$repo_path" ]] || { sayfail "Repository URL, branch/tag, and documentation path are required."; return 1; }
                temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sgnd-web-docs.XXXXXX")" || return 1
                git clone --quiet --depth 1 --branch "$repo_ref" "$repository" "$temp_dir/repository" || { rm -rf -- "$temp_dir"; return 1; }
                source_dir="$temp_dir/repository/${repo_path#/}"
                [[ -d "$source_dir" ]] || { sayfail "Documentation path does not exist in repository: $repo_path"; rm -rf -- "$temp_dir"; return 1; }
                source_spec="$source_dir/"
                ;;
        esac

        SGND_WEB_DOC_SOURCE_TYPE="$source_type"
        SGND_WEB_DOC_SOURCE_HOST="$source_host"
        SGND_WEB_DOC_SOURCE_USER="$source_user"
        SGND_WEB_DOC_SOURCE_DIR="$source_dir"
        SGND_WEB_DOC_REPOSITORY="$repository"
        SGND_WEB_DOC_REF="$repo_ref"
        SGND_WEB_DOC_REPO_PATH="$repo_path"
        _web_server_save_state || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }

        _web_server_ensure_directory "$document_root" "www-data:www-data" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        ask_decision --label "Publish documentation to $site" --choices "YES|Y,NO|N" --default "YES" --var decision
        if [[ "$decision" != "YES" ]]; then
            [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"
            return 0
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would publish documentation from $source_type to $document_root/."
            [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"
            return 0
        fi

        if [[ "$source_type" == "Remote machine" ]]; then
            sudo rsync -a --delete -e "ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $key" "$source_spec" "$document_root/" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        else
            sudo rsync -a --delete "$source_spec" "$document_root/" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        fi
        sudo chown -R www-data:www-data "$document_root" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"
        sayok "SolidGroundUX documentation published to $site."
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

# - Console registration -----------------------------------------------------------
    # Provides basic Nginx host management: installation, content-root selection,
    # site lifecycle, publishing, service and firewall control, status, and
    # validation. Application-specific site administration remains out of scope.
    #
    # . Menu items
    # ! Prepare web server
    #   > Install, validate, enable, and start Nginx.
    #   > Handler: _web_server_prepare
    #
    # ! Install Nginx
    #   > Install Nginx and basic web-server utilities.
    #   > Handler: _web_server_step_install_packages
    #
    # ! Configure web content root
    #   > Select or create the storage location used for web content.
    #   > Handler: _web_server_configure_root
    #
    # ! Manage sites
    #   > Create, enable, disable, remove, clear content from, and list Nginx sites.
    #   > Handler: _web_server_manage_sites
    #
    # ! Publish site content
    #   > Synchronize a local or remote source directory into a site's document root.
    #   > Handler: _web_server_publish_site
    #
    # ! Configure documentation site
    #   > Create or select the Nginx site used to host SolidGroundUX documentation.
    #   > Handler: _web_server_configure_documentation_site
    #
    # ! Publish documentation
    #   > Publish installed, local, remote, or GitHub documentation content.
    #   > Handler: _web_server_publish_documentation
    #
    # ! Show documentation status
    #   > Show documentation site and source configuration.
    #   > Handler: _web_server_documentation_status
    #
    # ! Manage web service
    #   > Start, stop, restart, enable, or disable nginx.service.
    #   > Handler: _web_server_manage_service
    #
    # ! Configure web firewall
    #   > Allow HTTP and HTTPS through UFW.
    #   > Handler: _web_server_configure_firewall
    #
    # ! Validate web server
    #   > Validate package, configuration, service, listeners, and web root.
    #   > Handler: _web_server_validate
    #
    # ! Show web-server status
    #   > Show package, service, storage, listener, and site status.
    #   > Handler: _web_server_status
    sgnd_menu_register_group \
        "$SGND_WEB_SERVER_MODULE_ID" \
        "General" \
        "General Nginx host and site management" \
        0 1 500

    sgnd_menu_register_group \
        "web-documentation" \
        "SolidGroundUX Documentation" \
        "Configure and publish the documentation delivered with SolidGroundUX" \
        0 1 510

    sgnd_menu_register_group \
        "web-service" \
        "Service" \
        "Nginx service, firewall, validation, and status" \
        0 1 520

    sgnd_menu_register_item "web-prepare" "$SGND_WEB_SERVER_MODULE_ID" "Prepare web server" "_web_server_prepare" "Install, validate, enable, and start Nginx" 0 15 1 0
    sgnd_menu_register_item "web-install" "$SGND_WEB_SERVER_MODULE_ID" "Install Nginx" "_web_server_step_install_packages" "Install Nginx and basic web-server utilities" 0 15 1 1
    sgnd_menu_register_item "web-root" "$SGND_WEB_SERVER_MODULE_ID" "Configure web content root" "_web_server_configure_root" "Select or create the storage location used for web content" 0 15 1 0
    sgnd_menu_register_item "web-sites" "$SGND_WEB_SERVER_MODULE_ID" "Manage sites" "_web_server_manage_sites" "Create, enable, disable, remove, clear content from, and list Nginx sites" 0 15 1 0
    sgnd_menu_register_item "web-publish" "$SGND_WEB_SERVER_MODULE_ID" "Publish site content" "_web_server_publish_site" "Synchronize a local or remote source directory into a site's document root" 0 15 1 0

    sgnd_menu_register_item "web-doc-configure" "web-documentation" "Configure documentation site" "_web_server_configure_documentation_site" "Create or select the Nginx site used for SolidGroundUX documentation" 0 15 1 0
    sgnd_menu_register_item "web-doc-publish" "web-documentation" "Publish documentation" "_web_server_publish_documentation" "Publish installed, local, remote, or GitHub documentation content" 0 15 1 0
    sgnd_menu_register_item "web-doc-status" "web-documentation" "Show documentation status" "_web_server_documentation_status" "Show documentation site and source configuration" 0 15 1 0

    sgnd_menu_register_item "web-service-manage" "web-service" "Manage web service" "_web_server_manage_service" "Start, stop, restart, enable, or disable nginx.service" 0 15 1 0
    sgnd_menu_register_item "web-firewall" "web-service" "Configure web firewall" "_web_server_configure_firewall" "Allow HTTP and HTTPS through UFW" 0 15 1 0
    sgnd_menu_register_item "web-validate" "web-service" "Validate web server" "_web_server_validate" "Validate package, configuration, service, listeners, and web root" 0 15 1 0
    sgnd_menu_register_item "web-status" "web-service" "Show web-server status" "_web_server_status" "Show package, service, storage, listener, and site status" 0 15 1 0

    sayinfo "Web Server module registered with the console."
#   Checksum : 687c35da400870c45fdc1c62efe6edb05def065ec0dcb35ca565c0bec85ef0ea
