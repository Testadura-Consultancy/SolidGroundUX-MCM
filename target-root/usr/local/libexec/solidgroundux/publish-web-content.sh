#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Publish Web Content
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 1.2
#   Build       : 2626022
#   Source      : publish-web-content.sh
#   Type        : script
#   Group       : Console Actions
#   Purpose     : Publish local, remote, Git, and SolidGroundUX documentation content
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
    SGND_SCRIPT_TITLE="Publish Web Content"
    : "${SGND_SCRIPT_DESC:=Publish local, remote, Git, and SolidGroundUX documentation content to Nginx sites.}"
    : "${SGND_SCRIPT_VERSION:=2.1}"
    : "${SGND_SCRIPT_BUILD:=2625722}"

# - Framework integration -----------------------------------------------------------
    SGND_USING=()
    SGND_ARGS_SPEC=(
        "action|a|enum|ACTION|Publishing action||publish-site,publish-documentation"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action publish-site"
        "  $SGND_SCRIPT_NAME --dryrun --action publish-documentation"
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

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            [[ -d "$HOME/.ssh" ]] || sayinfo "DRYRUN: Would create $HOME/.ssh with mode 0700."
            [[ -f "$key" ]] || sayinfo "DRYRUN: Would create dedicated publishing key $key with an empty passphrase."
            sayinfo "DRYRUN: Would establish host trust and install the publishing key on $remote."
            return 0
        fi

        mkdir -p "$HOME/.ssh" || return 1
        chmod 0700 "$HOME/.ssh" || return 1

        if [[ ! -f "$key" ]]; then
            ssh-keygen -q -t ed25519 -f "$key" -N "" -C "SolidGroundUX publishing key" || return 1
            sayok "Created dedicated SolidGroundUX publishing key."
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
        local repository="${SGND_WEB_PUBLISH_REPOSITORY:-}"
        local repo_ref="${SGND_WEB_PUBLISH_REF:-main}"
        local repo_path="${SGND_WEB_PUBLISH_REPO_PATH:-}"
        local source_spec="" remote="" key="" document_root="" decision="YES" temp_dir=""
        local candidate="" remembered_site_found=0
        local -a sites=() ordered_sites=()

        command -v rsync >/dev/null 2>&1 || { sayfail "rsync is required for publishing."; return 1; }
        mapfile -t sites < <(find /etc/nginx/sites-available -mindepth 1 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort)
        (( ${#sites[@]} > 0 )) || { saywarning "No Nginx sites are available."; return 0; }

        if [[ -n "$site" ]]; then
            for candidate in "${sites[@]}"; do [[ "$candidate" == "$site" ]] && remembered_site_found=1 && break; done
            if (( remembered_site_found == 1 )); then
                ordered_sites+=("$site")
                for candidate in "${sites[@]}"; do [[ "$candidate" == "$site" ]] || ordered_sites+=("$candidate"); done
                sites=("${ordered_sites[@]}")
            else
                site=""
            fi
        fi

        sgnd_print
        sgnd_print_sectionheader "Publish web content"
        ask_selection --label "Publish to site" --var site --items "${sites[@]}" || return 0
        [[ -f "/etc/nginx/sites-available/$site" ]] || { sayfail "Site configuration no longer exists: $site"; return 1; }
        document_root="$(_web_server_site_document_root "$site" 2>/dev/null || true)"
        [[ -n "$document_root" ]] || { sayfail "Could not determine document root for $site."; return 1; }

        case "$source_type" in
            "Local directory") ask_selection --label "Source location" --var source_type --items "Local directory" "Remote machine" "Git repository" || return 0 ;;
            "Git repository") ask_selection --label "Source location" --var source_type --items "Git repository" "Local directory" "Remote machine" || return 0 ;;
            *) ask_selection --label "Source location" --var source_type --items "Remote machine" "Local directory" "Git repository" || return 0 ;;
        esac

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
                if (( ${FLAG_DRYRUN:-0} == 0 )); then
                    ssh -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes -i "$key" "$remote" "test -d '$source_dir'" >/dev/null 2>&1 || { sayfail "Remote source directory does not exist or is not accessible: $remote:$source_dir"; return 1; }
                fi
                source_spec="${remote}:${source_dir}/"
                ;;
            "Git repository")
                command -v git >/dev/null 2>&1 || { sayfail "git is required for Git repository publishing."; return 1; }
                ask --label "Repository URL" --var repository --default "$repository" --back || return 0
                ask --label "Branch or tag" --var repo_ref --default "$repo_ref" --back || return 0
                ask --label "Repository path" --var repo_path --default "$repo_path" --back || return 0
                [[ -n "$repository" && -n "$repo_ref" ]] || { sayfail "Repository URL and branch/tag are required."; return 1; }
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    source_spec="$repository@$repo_ref:${repo_path:-/}"
                else
                    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sgnd-web-publish.XXXXXX")" || return 1
                    git clone --quiet --depth 1 --branch "$repo_ref" "$repository" "$temp_dir/repository" || { rm -rf -- "$temp_dir"; return 1; }
                    source_dir="$temp_dir/repository/${repo_path#/}"
                    [[ -d "$source_dir" ]] || { sayfail "Repository path does not exist: ${repo_path:-/}"; rm -rf -- "$temp_dir"; return 1; }
                    source_spec="$source_dir/"
                fi
                ;;
        esac

        _web_server_ensure_directory "$document_root" "www-data:www-data" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        ask_decision --label "Synchronize source into $document_root" --choices "YES|Y,NO|N" --default "YES" --var decision
        [[ "$decision" == "YES" ]] || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 0; }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would synchronize $source_spec to $document_root/."
            return 0
        fi

        SGND_WEB_PUBLISH_SITE="$site"
        SGND_WEB_PUBLISH_SOURCE_TYPE="$source_type"
        SGND_WEB_PUBLISH_SOURCE_HOST="$source_host"
        SGND_WEB_PUBLISH_SOURCE_USER="$source_user"
        SGND_WEB_PUBLISH_SOURCE_DIR="$source_dir"
        SGND_WEB_PUBLISH_REPOSITORY="$repository"
        SGND_WEB_PUBLISH_REF="$repo_ref"
        SGND_WEB_PUBLISH_REPO_PATH="$repo_path"
        _web_server_save_state || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }

        if [[ "$source_type" == "Remote machine" ]]; then
            sudo rsync -a --delete -e "ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $key" "$source_spec" "$document_root/" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        else
            sudo rsync -a --delete "$source_spec" "$document_root/" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        fi
        sudo chown -R www-data:www-data "$document_root" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"
        sayok "Published content to $site."
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
            sayfail "Documentation site is not configured: $site"
            sayinfo "Configure the documentation site from the Web Server console first."
            return 1
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
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    source_spec="$repository@$repo_ref:$repo_path"
                else
                    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sgnd-web-docs.XXXXXX")" || return 1
                    git clone --quiet --depth 1 --branch "$repo_ref" "$repository" "$temp_dir/repository" || { rm -rf -- "$temp_dir"; return 1; }
                    source_dir="$temp_dir/repository/${repo_path#/}"
                    [[ -d "$source_dir" ]] || { sayfail "Documentation path does not exist in repository: $repo_path"; rm -rf -- "$temp_dir"; return 1; }
                    source_spec="$source_dir/"
                fi
                ;;
        esac

        _web_server_ensure_directory "$document_root" "www-data:www-data" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        ask_decision --label "Publish documentation to $site" --choices "YES|Y,NO|N" --default "YES" --var decision
        if [[ "$decision" != "YES" ]]; then
            [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"
            return 0
        fi

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would publish documentation from $source_type to $document_root/."
            [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"
            return 0
        fi

        SGND_WEB_DOC_SOURCE_TYPE="$source_type"
        SGND_WEB_DOC_SOURCE_HOST="$source_host"
        SGND_WEB_DOC_SOURCE_USER="$source_user"
        SGND_WEB_DOC_SOURCE_DIR="$source_dir"
        SGND_WEB_DOC_REPOSITORY="$repository"
        SGND_WEB_DOC_REF="$repo_ref"
        SGND_WEB_DOC_REPO_PATH="$repo_path"
        _web_server_save_state || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }

        if [[ "$source_type" == "Remote machine" ]]; then
            sudo rsync -a --delete -e "ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $key" "$source_spec" "$document_root/" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        else
            sudo rsync -a --delete "$source_spec" "$document_root/" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        fi
        sudo chown -R www-data:www-data "$document_root" || { [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"; return 1; }
        [[ -n "$temp_dir" ]] && rm -rf -- "$temp_dir"
        sayok "SolidGroundUX documentation published to $site."
    }

# - Action dispatch -----------------------------------------------------------------
    _run_action() {
        local action="${1:?missing action}" rc=0
        case "$action" in
            publish-site) _web_server_publish_site || rc=$? ;;
            publish-documentation) _web_server_publish_documentation || rc=$? ;;
            *) sayfail "Unknown web publishing action: $action"; return 2 ;;
        esac
        (( rc == 0 )) && _dryrun_complete
        return "$rc"
    }

# - Main ----------------------------------------------------------------------------
    main() {
        local action=""
        _framework_locator || return $?
        sgnd_exe_start "$@" || return $?
        _web_server_load_state
        action="${ACTION:-publish-site}"
        _run_action "$action"
    }
    main "$@"
#   Checksum : 336e477f1085ea8e3405c9cfc10917044c852775843c09d53b21dfd29499d07d
