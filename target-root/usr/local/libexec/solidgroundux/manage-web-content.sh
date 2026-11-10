#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Web Content
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2631102
#   Shortname   : MANAGE_WEB_CONTENT
#   Source      : manage-web-content.sh
#   Type        : script
#   Group       : Modules
#   Subgroup    : Web Content Management
#   Purpose     : Ingest, delete, generate, validate, and prepare static website content
#
#   Checksum : d181e0c8b0471aa0c6898a5522f6814fcf4644e3c57a14c7747d5804d50b55f3
# Description:
#   Provides the SolidGroundUX user-facing workflow for the reusable Python WebContent
#   engine. All prompts, state, progress, and result reporting remain in this Bash layer;
#   the Python package is deliberately non-interactive. Loose Markdown can be ingested
#   individually or in batches from a canonical incoming directory, normalized into a
#   website repository, and archived after successful ingestion. Canonical pages can
#   also be selected individually or in batches and removed recoverably by archiving them
#   outside the active content tree.
#
# Usage:
#   Run the executable from its shell command (or installed wrapper):
#   ```bash
#   manage-web-content --action ingest
#   manage-web-content --action generate
#   manage-web-content --action publish
#   manage-web-content --action publish-github-pages
#   manage-web-content --action validate
#   ```
#
#   Script-specific options:
#   - `--action NAME`, `-a`: Management action (supported actions: `ingest`, `delete`, `edit-metadata`, `move-page`, `manage-config`, `configure-source`, `retrieve-incoming`, `import-local`, `ingest-incoming`, `generate`, `publish`, `manage-publishing-profiles`, `publish-github-pages`, `validate`, `prepare-social`, `status`).
#   - `--ingest-dir VALUE`, `-i`: Override Markdown ingestion directory.
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
        #   ```bash
        #   _framework_locator || return $?
        #   ```
    _framework_locator() {
        local script_file="" suffix="" component="" script_root="" candidate=""
        local exe_common="" discovered="" parent="" tree="" common_suffix="usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
        local index=0 root_index=-1
        local -a path_parts=() matches=()

        script_file="$(readlink -f "${BASH_SOURCE[0]}")" || {
            printf 'FATAL: Cannot resolve executable path: %s\n' "${BASH_SOURCE[0]}" >&2
            return 126
        }
        suffix="${script_file#/}"
        IFS='/' read -r -a path_parts <<< "$suffix"
        for index in "${!path_parts[@]}"; do
            component="${path_parts[$index]}"
            case "$component" in usr|etc|var) root_index=$index ;; esac
        done
        (( root_index >= 0 )) || {
            printf 'FATAL: Cannot determine product root from %s\n' "$script_file" >&2
            return 126
        }
        script_root="/"
        if (( root_index > 0 )); then
            script_root=""
            for (( index=0; index<root_index; index++ )); do
                script_root+="/${path_parts[$index]}"
            done
        fi

        # A caller may explicitly select a separate Framework development tree.
        # A wrong explicit root is an error rather than a silent fallback.
        if [[ -n "${SGND_FRAMEWORK_ROOT:-}" ]]; then
            candidate="${SGND_FRAMEWORK_ROOT%/}"
            [[ -n "$candidate" ]] || candidate="/"
            [[ -r "${candidate%/}/$common_suffix" ]] || {
                printf 'FATAL: SGND_FRAMEWORK_ROOT is not a Framework tree: %s\n' "$candidate" >&2
                return 126
            }
            discovered="$candidate"
        elif [[ -r "${script_root%/}/$common_suffix" ]]; then
            discovered="$script_root"
        elif [[ "$script_root" != / ]]; then
            # Separate development trees: search only immediate sibling product
            # directories, optionally under their target-root. Never pick one of
            # several Framework trees arbitrarily.
            for parent in "$(dirname -- "$script_root")" "$(dirname -- "$(dirname -- "$script_root")")"; do
                for tree in "$parent"/* "$parent"/*/target-root; do
                    [[ -r "${tree%/}/$common_suffix" ]] || continue
                    candidate="$(cd -- "$tree" && pwd -P)" || continue
                    for component in "${matches[@]}"; do
                        [[ "$component" == "$candidate" ]] && break
                    done
                    [[ "$component" == "$candidate" ]] || matches+=("$candidate")
                done
            done
            case "${#matches[@]}" in
                0) discovered="/" ;;
                1) discovered="${matches[0]}" ;;
                *) printf 'FATAL: Multiple Framework trees found; set SGND_FRAMEWORK_ROOT explicitly.\n' >&2; return 126 ;;
            esac
        else
            discovered="/"
        fi

        exe_common="${discovered%/}/$common_suffix"
        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read Framework executable library: %s\n' "$exe_common" >&2
            return 126
        }
        SGND_FRAMEWORK_ROOT="$discovered"
        # shellcheck source=/dev/null
        source "$exe_common"
    }

# - Script metadata ----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"

# - Framework integration -----------------------------------------------------------
    # DataTable renders the profile list; SSH helper is MCM-owned and sourced
    # on demand, not resolved from Framework.
    SGND_USING=(sgnd-datatable.sh sgnd-menu.sh)
    SGND_ARGS_SPEC=(
        "auto||flag|FLAG_AUTO|Publish the selected website profile unattended|0|"
        "action|a|enum|ACTION|Management action||ingest,delete,edit-metadata,move-page,manage-config,configure-source,retrieve-incoming,import-local,ingest-incoming,generate,publish,manage-publishing-profiles,publish-github-pages,validate,prepare-social,status"
        "ingest-dir|i|value|INGEST_DIR|Override Markdown ingestion directory||"
        "profile||value|WEB_PROFILE_ARG|Use a named website publication profile||"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action ingest"
        "  $SGND_SCRIPT_NAME --action ingest --ingest-dir /path/to/incoming"
        "  $SGND_SCRIPT_NAME --action ingest-incoming"
        "  $SGND_SCRIPT_NAME --action delete"
        "  $SGND_SCRIPT_NAME --action generate"
        "  $SGND_SCRIPT_NAME --action publish"
        "  $SGND_SCRIPT_NAME --action publish --profile Development"
        "  $SGND_SCRIPT_NAME --action manage-publishing-profiles"
        "  $SGND_SCRIPT_NAME --action publish-github-pages"
        "  $SGND_SCRIPT_NAME --action manage-config"
        "  $SGND_SCRIPT_NAME --action validate"
        "  $SGND_SCRIPT_NAME --action prepare-social"
        "  $SGND_SCRIPT_NAME --action status"
    )
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=(
        SGND_WEB_CONTENT_SOURCE
        SGND_WEB_CONTENT_OUTPUT
        SGND_WEB_CONTENT_SOCIAL_OUTPUT
        SGND_WEB_CONTENT_LANGUAGE
        SGND_WEB_CONTENT_PLATFORM
        SGND_WEB_CONTENT_INGEST_DIR
        SGND_WEB_CONTENT_INGEST_LANGUAGE
        SGND_WEB_CONTENT_INGEST_KIND
        SGND_WEB_CONTENT_INGEST_PARENT
        SGND_WEB_PUBLISH_SOURCE
        SGND_WEB_PUBLISH_HOST
        SGND_WEB_PUBLISH_REMOTE_DIR
        SGND_WEB_PUBLISH_USER
        SGND_WEB_PUBLISH_PORT
        SGND_WEB_PUBLISH_IDENTITY
        SGND_WEB_PUBLISH_STRATEGY
        SGND_WEB_PUBLISH_HOSTNAME
        SGND_WEB_GITHUB_SOURCE
        SGND_WEB_GITHUB_REPO
        SGND_WEB_INCOMING_HOST
        SGND_WEB_INCOMING_USER
        SGND_WEB_INCOMING_PORT
        SGND_WEB_INCOMING_REMOTE_DIR
    )
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=1

# - Local declarations --------------------------------------------------------------
    : "${SGND_WEB_CONTENT_SOURCE:=${PWD}}"
    : "${SGND_WEB_CONTENT_OUTPUT:=${PWD}/public}"
    : "${SGND_WEB_CONTENT_SOCIAL_OUTPUT:=${SGND_SHARE_DIR:-${HOME}/.local/share/solidgroundux}/social-media-output}"
    : "${SGND_WEB_CONTENT_LANGUAGE:=ALL}"
    : "${SGND_WEB_CONTENT_PLATFORM:=linkedin}"
    : "${SGND_WEB_CONTENT_INGEST_DIR:=}"
    : "${SGND_WEB_CONTENT_INGEST_LANGUAGE:=}"
    : "${SGND_WEB_CONTENT_INGEST_KIND:=}"
    : "${SGND_WEB_CONTENT_INGEST_PARENT:=}"
    : "${SGND_WEB_PUBLISH_SOURCE:=}"
    : "${SGND_WEB_PUBLISH_HOST:=}"
    : "${SGND_WEB_PUBLISH_REMOTE_DIR:=}"
    : "${SGND_WEB_PUBLISH_USER:=}"
    : "${SGND_WEB_PUBLISH_PORT:=22}"
    : "${SGND_WEB_PUBLISH_IDENTITY:=}"
    : "${SGND_WEB_PUBLISH_STRATEGY:=Update}"
    : "${SGND_WEB_PUBLISH_HOSTNAME:=}"
    : "${SGND_WEB_PUBLISH_METHOD:=rsync}"
    : "${SGND_WEB_PUBLISH_MANAGE_SITE:=Yes}"
    : "${SGND_WEB_PUBLISH_PREVIEW_PORT:=8080}"
    WEB_ACTIVE_PROFILE=""
    WEB_PROFILE_ARG="${WEB_PROFILE_ARG:-}"
    : "${SGND_WEB_GITHUB_SOURCE:=}"
    : "${SGND_WEB_GITHUB_REPO:=}"
    : "${SGND_WEB_INCOMING_HOST:=td-web}"
    : "${SGND_WEB_INCOMING_USER:=sysadmin}"
    : "${SGND_WEB_INCOMING_PORT:=22}"
    : "${SGND_WEB_INCOMING_REMOTE_DIR:=/srv/storage/webcontent-incoming}"

# - Helpers -------------------------------------------------------------------------
    # fn: _web_content_python_root - Run the python root action through Web Content Management.
        # . Purpose
        #   Run the python root action through Web Content Management.
        #
        # . Usage
        #   ```bash
        #   _web_content_python_root
        #   ```
    _web_content_python_root() {
        # The WebContent engine belongs to MCM, not to the separately located Framework.
        local mcm_root="${SGND_SCRIPT_DIR%/libexec/solidgroundux}"
        if [[ -d "$mcm_root/lib/solidgroundux/py/webcontent" ]]; then
            printf '%s\n' "$mcm_root/lib/solidgroundux/py"
        else
            printf '%s\n' '/usr/local/lib/solidgroundux/py'
        fi
    }

    # fn: _web_content_validate_source - Run the validate source action through Web Content Management.
        # . Purpose
        #   Run the validate source action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Optional: filesystem path to inspect.
        # . Usage
        #   ```bash
        #   _web_content_validate_source "/srv/storage/example"
        #   ```
    _web_content_validate_source() {
        local path="${1:-}"
        [[ -d "$path" && -r "$path/config/site.cfg" && -d "$path/content" && -d "$path/templates" && -d "$path/css" ]]
    }

    # fn: _web_content_validate_language - Run the validate language action through Web Content Management.
        # . Purpose
        #   Run the validate language action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Optional: value to inspect or write.
        # . Usage
        #   ```bash
        #   _web_content_validate_language "NL"
        #   ```
    _web_content_validate_language() {
        local value="${1:-}"
        [[ "${value^^}" == "ALL" || "$value" =~ ^[A-Za-z]{2}([,][A-Za-z]{2})*$ ]]
    }

    # fn: _web_content_validate_platform - Run the validate platform action through Web Content Management.
        # . Purpose
        #   Run the validate platform action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Optional: value to inspect or write.
        # . Usage
        #   ```bash
        #   _web_content_validate_platform "linkedin"
        #   ```
    _web_content_validate_platform() {
        local value="${1:-}"
        [[ "$value" =~ ^[A-Za-z0-9_-]+$ ]]
    }

    # fn: _web_content_ensure_output_parent - Run the ensure output parent action through Web Content Management.
        # . Purpose
        #   Run the ensure output parent action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Filesystem path to inspect.
        # . Usage
        #   ```bash
        #   _web_content_ensure_output_parent "/srv/storage/example"
        #   ```
    _web_content_ensure_output_parent() {
        local path="${1:?missing output path}"
        local parent=""
        parent="$(dirname -- "$path")"
        [[ -d "$parent" ]] || mkdir -p -- "$parent" || return 1
    }

    # fn: _web_content_result_value - Extract a requested field from the most recent engine result.
        # . Purpose
        #   Extract a requested field from the most recent engine result.
        #
        # . Arguments
        #   - `$1`: Path to the operation result file.
        #   - `$2`: Configuration or response-field key.
        # . Usage
        #   ```bash
        #   _web_content_result_value "/srv/storage/example.txt" "example-key"
        #   ```
    _web_content_result_value() {
        local result_file="${1:?missing result file}"
        local key="${2:?missing key}"
        python3 - "$result_file" "$key" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle).get(sys.argv[2], "")
if isinstance(value, bool):
    print("Yes" if value else "No")
elif isinstance(value, list):
    for item in value:
        print(item)
else:
    print(value)
PY
    }

    # fn: _web_content_run_engine - Invoke the noninteractive Python engine and capture its structured result.
        # . Purpose
        #   Invoke the noninteractive Python engine and capture its structured result.
        #
        # . Arguments
        #   - `$1`: Path to the operation result file.
        # . Behavior
        #   - Coordinates the existing workflow without modifying article content directly.
        #   - Propagates errors to the caller and uses the framework for user interaction.
        #
        # . Usage
        #   ```bash
        #   _web_content_run_engine "/srv/storage/example.txt"
        #   ```
    _web_content_run_engine() {
        local result_file="${1:?missing result file}"
        shift
        local python_root=""
        python_root="$(_web_content_python_root)"
        [[ -d "$python_root/webcontent" ]] || {
            sayfail "WebContent Python package not found: $python_root/webcontent"
            return 127
        }
        command -v python3 >/dev/null 2>&1 || {
            sayfail "Python 3 is required for Web Content Management."
            return 127
        }
        PYTHONPATH="$python_root${PYTHONPATH:+:$PYTHONPATH}" \
            python3 -m webcontent.cli "$@" --result-file "$result_file"
    }

    # fn: _web_content_record_activity - Report how many canonical content files changed
        # . Purpose
        #   Allow the Management Console wrapper to distinguish a successful no-op content
        #   action from one that changed the canonical website content.
        #
        # . Behavior
        #   - Uses SGND_WEB_CONTENT_ACTIVITY_FILE only when a caller supplies it.
        #   - Writes a single non-negative integer and produces no user-facing output.
        #   - Does not make the underlying content action fail when the optional marker
        #     cannot be written.
        #
        # . Arguments
        #   - $1  COUNT - Number of canonical content files changed during this action.
        #
        # . Usage
        #   ```bash
        #   _web_content_record_activity "5"
        #   ```
    _web_content_record_activity() {
        local count="${1:-0}"
        local marker="${SGND_WEB_CONTENT_ACTIVITY_FILE:-}"

        [[ "$count" =~ ^[0-9]+$ ]] || count=0
        [[ -n "$marker" ]] || return 0
        printf '%s\n' "$count" > "$marker" 2>/dev/null || true
    }

    # fn: _web_content_report_errors - Run the report errors action through Web Content Management.
        # . Purpose
        #   Run the report errors action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Path to the operation result file.
        # . Usage
        #   ```bash
        #   _web_content_report_errors "8080"
        #   ```
    _web_content_report_errors() {
        local result_file="${1:?missing result file}"
        local errors=""
        errors="$(_web_content_result_value "$result_file" errors 2>/dev/null || true)"
        if [[ -n "$errors" ]]; then
            while IFS= read -r line; do
                [[ -n "$line" ]] && sayfail "$line"
            done <<< "$errors"
        fi
    }

    # fn: _web_content_report_warnings - Run the report warnings action through Web Content Management.
        # . Purpose
        #   Run the report warnings action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Path to the operation result file.
        # . Usage
        #   ```bash
        #   _web_content_report_warnings "8080"
        #   ```
    _web_content_report_warnings() {
        local result_file="${1:?missing result file}"
        local warnings=""
        warnings="$(_web_content_result_value "$result_file" warnings 2>/dev/null || true)"
        if [[ -n "$warnings" ]]; then
            while IFS= read -r line; do
                [[ -n "$line" ]] && saywarning "$line"
            done <<< "$warnings"
        fi
    }

    # fn: _web_content_select_source - Run the select source action through Web Content Management.
        # . Purpose
        #   Run the select source action through Web Content Management.
        #
        # . Usage
        #   ```bash
        #   _web_content_select_source
        #   ```
    _web_content_select_source() {
        ask --label "Website repository" --var SGND_WEB_CONTENT_SOURCE --default "$SGND_WEB_CONTENT_SOURCE" --validate _web_content_validate_source --back
    }

    # fn: _web_content_select_language - Run the select language action through Web Content Management.
        # . Purpose
        #   Run the select language action through Web Content Management.
        #
        # . Usage
        #   ```bash
        #   _web_content_select_language
        #   ```
    _web_content_select_language() {
        ask --label "Language (ALL or codes)" --var SGND_WEB_CONTENT_LANGUAGE --default "$SGND_WEB_CONTENT_LANGUAGE" --validate _web_content_validate_language --back
        SGND_WEB_CONTENT_LANGUAGE="${SGND_WEB_CONTENT_LANGUAGE^^}"
    }

    # fn: _web_content_validate_ingest_dir - Run the validate ingest dir action through Web Content Management.
        # . Purpose
        #   Run the validate ingest dir action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Optional: filesystem path to inspect.
        # . Usage
        #   ```bash
        #   _web_content_validate_ingest_dir "/srv/storage/example"
        #   ```
    _web_content_validate_ingest_dir() {
        local path="${1:-}"
        [[ -n "$path" ]]
    }

    # fn: _web_content_validate_slug - Run the validate slug action through Web Content Management.
        # . Purpose
        #   Run the validate slug action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Optional: value to inspect or write.
        # . Usage
        #   ```bash
        #   _web_content_validate_slug "example-page"
        #   ```
    _web_content_validate_slug() {
        local value="${1:-}"
        [[ "$value" =~ ^[a-z0-9][a-z0-9-]*$ ]]
    }

    # fn: _web_content_canonical_ingest_dir - Run the canonical ingest dir action through Web Content Management.
        # . Purpose
        #   Run the canonical ingest dir action through Web Content Management.
        #
        # . Usage
        #   ```bash
        #   _web_content_canonical_ingest_dir
        #   ```
    _web_content_canonical_ingest_dir() {
        # Incoming authoring files belong to the selected website repository but
        # stay outside content/ until their metadata has been resolved and confirmed.
        printf '%s\n' "${SGND_WEB_CONTENT_SOURCE%/}/incoming"
    }

    # fn: _web_content_canonical_archive_dir - Run the canonical archive dir action through Web Content Management.
        # . Purpose
        #   Run the canonical archive dir action through Web Content Management.
        #
        # . Usage
        #   ```bash
        #   _web_content_canonical_archive_dir
        #   ```
    _web_content_canonical_archive_dir() {
        # Successfully processed loose sources are retained outside content/ as a
        # date-grouped authoring archive; the website generator ignores this tree.
        printf '%s\n' "${SGND_WEB_CONTENT_SOURCE%/}/ingested"
    }

    # fn: _web_content_canonical_delete_archive_dir - Run the canonical delete archive dir action through Web Content Management.
        # . Purpose
        #   Run the canonical delete archive dir action through Web Content Management.
        #
        # . Usage
        #   ```bash
        #   _web_content_canonical_delete_archive_dir
        #   ```
    _web_content_canonical_delete_archive_dir() {
        # Removed canonical pages are moved outside content/ into a date-grouped
        # recovery archive so deletion remains reversible and generator-safe.
        printf '%s\n' "${SGND_WEB_CONTENT_SOURCE%/}/deleted"
    }

    # fn: _web_content_select_ingest_dir - Run the select ingest dir action through Web Content Management.
        # . Purpose
        #   Run the select ingest dir action through Web Content Management.
        #
        # . Usage
        #   ```bash
        #   _web_content_select_ingest_dir
        #   ```
    _web_content_select_ingest_dir() {
        local canonical=""
        local selected=""
        canonical="$(_web_content_canonical_ingest_dir)"

        if [[ -n "${INGEST_DIR:-}" ]]; then
            selected="$INGEST_DIR"
        else
            selected="${SGND_WEB_CONTENT_INGEST_DIR:-$canonical}"
            ask --label "Ingestion directory" --var selected --default "$selected" --validate _web_content_validate_ingest_dir --back || return 1
        fi

        selected="$(readlink -m -- "$selected")"
        mkdir -p -- "$selected" || { sayfail "Cannot create ingestion directory: $selected"; return 1; }
        SGND_WEB_CONTENT_INGEST_DIR="$selected"
    }

    # fn: _web_content_extract_parent_route - Run the extract parent route action through Web Content Management.
        # . Purpose
        #   Run the extract parent route action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Optional: Parent-route selection label.
        # . Usage
        #   ```bash
        #   _web_content_extract_parent_route "<selection>"
        #   ```
    _web_content_extract_parent_route() {
        local selection="${1:-}"
        local route="${selection##*[}"
        route="${route%]}"
        printf '%s\n' "$route"
    }

    # fn: _web_content_kind_label - Run the kind label action through Web Content Management.
        # . Purpose
        #   Run the kind label action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Optional: content type.
        # . Usage
        #   ```bash
        #   _web_content_kind_label "<kind>"
        #   ```
    _web_content_kind_label() {
        local kind="${1:-}"
        case "$kind" in
            page) printf '%s\n' "Page" ;;
            section) printf '%s\n' "Section index" ;;
            article) printf '%s\n' "Article" ;;
            *) printf '%s\n' "" ;;
        esac
    }

    # fn: _web_content_kind_value - Run the kind value action through Web Content Management.
        # . Purpose
        #   Run the kind value action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Optional: prompt or display label.
        # . Usage
        #   ```bash
        #   _web_content_kind_value "Select an option"
        #   ```
    _web_content_kind_value() {
        local label="${1:-}"
        case "$label" in
            Page) printf '%s\n' "page" ;;
            "Section index") printf '%s\n' "section" ;;
            Article) printf '%s\n' "article" ;;
            *) printf '%s\n' "" ;;
        esac
    }

    # fn: _web_content_choose_language - Run the choose language action through Web Content Management.
        # . Purpose
        #   Run the choose language action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Name of the shell variable receiving the result.
        # . Usage
        #   ```bash
        #   _web_content_choose_language "<out_var>"
        #   ```
    _web_content_choose_language() {
        local out_var="${1:?missing output variable}"
        shift
        local remembered="${SGND_WEB_CONTENT_INGEST_LANGUAGE:-}"
        local selected=""
        local decision=""
        local option=""
        local remembered_valid=0
        local -a options=("$@")

        for option in "${options[@]}"; do
            if [[ "$option" == "$remembered" ]]; then
                remembered_valid=1
                break
            fi
        done

        if (( remembered_valid )); then
            ask_decision --label "Use remembered language: $remembered" --choices "Yes|Y,No|N" --default "Yes" --var decision || return 1
            if [[ "$decision" == "YES" ]]; then
                selected="$remembered"
            fi
        fi
        if [[ -z "$selected" ]]; then
            ask_selection --label "Language" --var selected --items "${options[@]}" || return 1
        fi

        selected="${selected^^}"
        SGND_WEB_CONTENT_INGEST_LANGUAGE="$selected"
        printf -v "$out_var" '%s' "$selected"
    }

    # fn: _web_content_choose_kind - Run the choose kind action through Web Content Management.
        # . Purpose
        #   Run the choose kind action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Name of the shell variable receiving the result.
        # . Usage
        #   ```bash
        #   _web_content_choose_kind "<out_var>"
        #   ```
    _web_content_choose_kind() {
        local out_var="${1:?missing output variable}"
        local remembered="${SGND_WEB_CONTENT_INGEST_KIND:-}"
        local remembered_label=""
        local selected_label=""
        local selected=""
        local decision=""
        local -a options=("Page" "Section index" "Article")

        remembered_label="$(_web_content_kind_label "$remembered")"
        if [[ -n "$remembered_label" ]]; then
            ask_decision --label "Use remembered content type: $remembered_label" --choices "Yes|Y,No|N" --default "Yes" --var decision || return 1
            if [[ "$decision" == "YES" ]]; then
                selected="$remembered"
            fi
        fi
        if [[ -z "$selected" ]]; then
            ask_selection --label "Content type" --var selected_label --items "${options[@]}" || return 1
            selected="$(_web_content_kind_value "$selected_label")"
        fi

        SGND_WEB_CONTENT_INGEST_KIND="$selected"
        printf -v "$out_var" '%s' "$selected"
    }

    # fn: _web_content_choose_parent - Run the choose parent action through Web Content Management.
        # . Purpose
        #   Run the choose parent action through Web Content Management.
        #
        # . Arguments
        #   - `$1`: Name of the shell variable receiving the result.
        # . Usage
        #   ```bash
        #   _web_content_choose_parent "<out_var>"
        #   ```
    _web_content_choose_parent() {
        local out_var="${1:?missing output variable}"
        shift
        local remembered="${SGND_WEB_CONTENT_INGEST_PARENT:-}"
        local remembered_option=""
        local selected_option=""
        local selected=""
        local decision=""
        local option=""
        local option_route=""
        local -a options=("$@")

        for option in "${options[@]}"; do
            option_route="$(_web_content_extract_parent_route "$option")"
            if [[ -n "$remembered" && "$option_route" == "$remembered" ]]; then
                remembered_option="$option"
                break
            fi
        done

        if [[ -n "$remembered_option" ]]; then
            ask_decision --label "Use remembered parent: $remembered_option" --choices "Yes|Y,No|N" --default "Yes" --var decision || return 1
            if [[ "$decision" == "YES" ]]; then
                selected="$remembered"
            fi
        fi
        if [[ -z "$selected" ]]; then
            ask_selection --label "Parent section" --var selected_option --items "${options[@]}" || return 1
            selected="$(_web_content_extract_parent_route "$selected_option")"
        fi

        SGND_WEB_CONTENT_INGEST_PARENT="$selected"
        printf -v "$out_var" '%s' "$selected"
    }

# - Actions -------------------------------------------------------------------------
    # fn: _web_content_ingest_one - Normalize and archive one loose Markdown file
        # . Purpose
        #   Normalize and archive one loose Markdown file.
        #
        # . Arguments
        #   - `$1`: Path to the source input file.
        #   - `$2`: Optional batch processing flag.
        # . Usage
        #   ```bash
        #   _web_content_ingest_one "/srv/storage/example.txt" "status"
        #   ```
    _web_content_ingest_one() {
        local input_file="${1:?missing input file}"
        local batch_mode="${2:-No}"
        local inspect_file=""
        local preview_file=""
        local result_file=""
        local title=""
        local language=""
        local kind=""
        local parent=""
        local slug=""
        local slug_explicit="No"
        local summary=""
        local destination=""
        local route=""
        local archive_path=""
        local decision=""
        local confirmation_default="No"
        local rc=0
        local -a supported_languages=()
        local -a parent_options=()

        inspect_file="$(mktemp)" || return 1
        _web_content_run_engine "$inspect_file" inspect-ingest \
            --source "$SGND_WEB_CONTENT_SOURCE" \
            --input-file "$input_file" || rc=$?
        _web_content_report_warnings "$inspect_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$inspect_file"
            rm -f "$inspect_file"
            return "$rc"
        fi

        title="$(_web_content_result_value "$inspect_file" title)"
        language="$(_web_content_result_value "$inspect_file" language)"
        kind="$(_web_content_result_value "$inspect_file" kind)"
        parent="$(_web_content_result_value "$inspect_file" parent)"
        slug="$(_web_content_result_value "$inspect_file" slug)"
        slug_explicit="$(_web_content_result_value "$inspect_file" slug_explicit)"
        summary="$(_web_content_result_value "$inspect_file" summary)"
        mapfile -t supported_languages < <(_web_content_result_value "$inspect_file" supported_languages)

        if [[ -z "$title" ]]; then
            ask --label "Title" --var title --back || { rm -f "$inspect_file"; return 2; }
        fi
        if [[ -z "$language" ]]; then
            _web_content_choose_language language "${supported_languages[@]}" || { rm -f "$inspect_file"; return 2; }
        fi
        language="${language^^}"

        # Parent choices are language-specific. Reinspect after language resolution so
        # the chooser contains only section indexes that actually exist in that language.
        rm -f "$inspect_file"
        inspect_file="$(mktemp)" || return 1
        rc=0
        _web_content_run_engine "$inspect_file" inspect-ingest \
            --source "$SGND_WEB_CONTENT_SOURCE" \
            --input-file "$input_file" \
            --language "$language" || rc=$?
        _web_content_report_warnings "$inspect_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$inspect_file"
            rm -f "$inspect_file"
            return "$rc"
        fi
        parent="$(_web_content_result_value "$inspect_file" parent)"
        mapfile -t parent_options < <(_web_content_result_value "$inspect_file" parent_options)

        if [[ -z "$kind" ]]; then
            _web_content_choose_kind kind || { rm -f "$inspect_file"; return 2; }
        fi

        if [[ -z "$parent" ]]; then
            if (( ${#parent_options[@]} == 0 )); then
                sayfail "No parent section indexes are available for language $language."
                rm -f "$inspect_file"
                return 1
            fi
            _web_content_choose_parent parent "${parent_options[@]}" || { rm -f "$inspect_file"; return 2; }
        fi

        [[ -n "$slug" ]] || slug="$(_web_content_result_value "$inspect_file" slug)"
        if [[ "$slug_explicit" != "Yes" ]]; then
            ask --label "Slug" --var slug --default "$slug" --validate _web_content_validate_slug --back || { rm -f "$inspect_file"; return 2; }
        fi

        if [[ -z "$summary" ]]; then
            summary="$(_web_content_result_value "$inspect_file" summary)"
        fi
        if [[ -z "$summary" ]]; then
            ask --label "Summary (optional)" --var summary --default "" --back || { rm -f "$inspect_file"; return 2; }
        fi
        rm -f "$inspect_file"

        preview_file="$(mktemp)" || return 1
        rc=0
        _web_content_run_engine "$preview_file" preview-ingest \
            --source "$SGND_WEB_CONTENT_SOURCE" \
            --input-file "$input_file" \
            --title "$title" \
            --language "$language" \
            --parent "$parent" \
            --kind "$kind" \
            --slug "$slug" \
            --summary "$summary" || rc=$?
        _web_content_report_warnings "$preview_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$preview_file"
            rm -f "$preview_file"
            return "$rc"
        fi

        destination="$(_web_content_result_value "$preview_file" destination)"
        route="$(_web_content_result_value "$preview_file" route)"
        archive_path="$(_web_content_result_value "$preview_file" archive_path)"
        sgnd_print
        sgnd_print_sectionheader --text "Ingest preview"
        sgnd_print_labeledvalue --label "Input" --value "$input_file" --labelwidth 20
        sgnd_print_labeledvalue --label "Title" --value "$title" --labelwidth 20
        sgnd_print_labeledvalue --label "Language" --value "$language" --labelwidth 20
        sgnd_print_labeledvalue --label "Type" --value "$kind" --labelwidth 20
        sgnd_print_labeledvalue --label "Parent" --value "$parent" --labelwidth 20
        sgnd_print_labeledvalue --label "Slug" --value "$slug" --labelwidth 20
        sgnd_print_labeledvalue --label "Route" --value "$route" --labelwidth 20
        sgnd_print_labeledvalue --label "Destination" --value "$destination" --labelwidth 20
        sgnd_print_labeledvalue --label "Archive" --value "$archive_path" --labelwidth 20
        sgnd_print_labeledvalue --label "Source action" --value "Archive original after successful ingestion" --labelwidth 20
        rm -f "$preview_file"

        [[ "$batch_mode" == "Yes" ]] && confirmation_default="Yes"
        ask_decision --label "Ingest this file" --choices "Yes|Y,No|N" --default "$confirmation_default" --var decision
        if [[ "$decision" != "YES" ]]; then
            saycancel "Content ingestion skipped: $(basename -- "$input_file")"
            return 2
        fi

        result_file="$(mktemp)" || return 1
        rc=0
        _web_content_run_engine "$result_file" ingest \
            --source "$SGND_WEB_CONTENT_SOURCE" \
            --input-file "$input_file" \
            --title "$title" \
            --language "$language" \
            --parent "$parent" \
            --kind "$kind" \
            --slug "$slug" \
            --summary "$summary" || rc=$?
        _web_content_report_warnings "$result_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$result_file"
            rm -f "$result_file"
            return "$rc"
        fi

        destination="$(_web_content_result_value "$result_file" destination)"
        route="$(_web_content_result_value "$result_file" route)"
        archive_path="$(_web_content_result_value "$result_file" archive_path)"
        sayok "Content ingested successfully."
        sgnd_print_labeledvalue --label "Destination" --value "$destination" --labelwidth 20
        sgnd_print_labeledvalue --label "Route" --value "$route" --labelwidth 20
        sgnd_print_labeledvalue --label "Archived source" --value "$archive_path" --labelwidth 20
        rm -f "$result_file"
        return 0
    }

    # fn: _web_content_valid_incoming_config - Validate saved source settings before network access
        # . Purpose
        #   Validate saved source settings before network access.
        #
        # . Usage
        #   ```bash
        #   _web_content_valid_incoming_config
        #   ```
    _web_content_valid_incoming_config() {
        [[ "$SGND_WEB_INCOMING_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] &&
        [[ "$SGND_WEB_INCOMING_USER" =~ ^[a-z_][a-zA-Z0-9_.-]*$ ]] &&
        [[ "$SGND_WEB_INCOMING_PORT" =~ ^[0-9]{1,5}$ ]] &&
        (( 10#$SGND_WEB_INCOMING_PORT >= 1 && 10#$SGND_WEB_INCOMING_PORT <= 65535 )) &&
        [[ "$SGND_WEB_INCOMING_REMOTE_DIR" == /* && "$SGND_WEB_INCOMING_REMOTE_DIR" != *".."* && "$SGND_WEB_INCOMING_REMOTE_DIR" =~ ^/[a-zA-Z0-9/_-]+$ ]]
    }

    # fn: _web_content_configure_incoming - Save SSH source settings through the framework state registry
        # . Purpose
        #   Save SSH source settings through the framework state registry.
        #
        # . Usage
        #   ```bash
        #   _web_content_configure_incoming
        #   ```
    _web_content_configure_incoming() {
        local host="$SGND_WEB_INCOMING_HOST" user="$SGND_WEB_INCOMING_USER" port="$SGND_WEB_INCOMING_PORT" remote="$SGND_WEB_INCOMING_REMOTE_DIR"
        ask --label "Incoming SSH server" --var host --default "$host" --back || return 0
        ask --label "Incoming SSH user" --var user --default "$user" --back || return 0
        ask --label "Incoming SSH port" --var port --default "$port" --back || return 0
        ask --label "Remote incoming directory" --var remote --default "$remote" --back || return 0
        local old_host="$SGND_WEB_INCOMING_HOST" old_user="$SGND_WEB_INCOMING_USER" old_port="$SGND_WEB_INCOMING_PORT" old_remote="$SGND_WEB_INCOMING_REMOTE_DIR"
        SGND_WEB_INCOMING_HOST="$host" SGND_WEB_INCOMING_USER="$user" SGND_WEB_INCOMING_PORT="$port" SGND_WEB_INCOMING_REMOTE_DIR="$remote"
        if ! _web_content_valid_incoming_config; then
            SGND_WEB_INCOMING_HOST="$old_host" SGND_WEB_INCOMING_USER="$old_user" SGND_WEB_INCOMING_PORT="$old_port" SGND_WEB_INCOMING_REMOTE_DIR="$old_remote"
            sayfail "Invalid SSH source settings; previous settings retained."
            return 2
        fi
        sayok "Incoming source saved in SolidGroundUX state."
    }

    # fn: _web_content_retrieve_incoming - Pull selected remote incoming packages safely via SSH
        # . Purpose
        #   Pull selected remote incoming packages safely via SSH.
        #
        # . Usage
        #   ```bash
        #   _web_content_retrieve_incoming
        #   ```
    _web_content_retrieve_incoming() {
        local remote="$SGND_WEB_INCOMING_REMOTE_DIR" host="$SGND_WEB_INCOMING_HOST" user="$SGND_WEB_INCOMING_USER" port="$SGND_WEB_INCOMING_PORT"
        local file="" temp="" transferred=0 skipped=0 failed=0
        local -a files=() targets=()
        _web_content_valid_incoming_config || { sayfail "Configure a valid incoming source first."; return 2; }
        command -v ssh >/dev/null && command -v scp >/dev/null || { sayfail "OpenSSH client tools are required."; return 127; }
        _web_content_select_source || return 0
        _web_content_select_ingest_dir || return 0
        sgnd_print_labeledvalue --label "Incoming source" --value "${user}@${host}:${remote}" --labelwidth 20
        _web_publish_prepare_ssh "$user" "$host" "$port" "" || return 1
        # Only a constrained filename character set is accepted. The remote path
        # was validated earlier; untrusted SSH output never becomes shell syntax.
        local listing=""
        listing="$(ssh -o BatchMode=yes -p "$port" -- "${user}@${host}" "find '$remote' -maxdepth 1 -type f -printf '%f\n'" 2>/dev/null)" || {
            sayfail "Could not list incoming files on the remote server."; return 1;
        }
        while IFS= read -r file; do
            [[ "$file" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*\.(md|zip|png|jpg|jpeg|gif|webp|svg|pdf|txt)$ ]] && files+=("$file")
        done <<< "$listing"
        if (( ${#files[@]} == 0 )); then sayinfo "No supported files available on source server."; return 0; fi
        ask_selection --label "Remote incoming files to retrieve" --var targets --multi --items "${files[@]}" || return 0
        (( ${#targets[@]} > 0 )) || return 0
        for file in "${targets[@]}"; do
            [[ "$file" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*\.(md|zip|png|jpg|jpeg|gif|webp|svg|pdf|txt)$ ]] || { ((failed+=1)); continue; }
            if [[ -e "$SGND_WEB_CONTENT_INGEST_DIR/$file" ]]; then
                saywarning "Already exists locally (not overwritten): $file"; ((skipped+=1)); continue
            fi
            temp="$(mktemp "$SGND_WEB_CONTENT_INGEST_DIR/.incoming.XXXXXXXX")" || { ((failed+=1)); continue; }
            if ! scp -q -P "$port" -o BatchMode=yes -- "${user}@${host}:${remote}/${file}" "$temp"; then
                rm -f -- "$temp"; sayfail "Download failed: $file"; ((failed+=1)); continue
            fi
            if ! [[ -f "$temp" && -s "$temp" ]]; then
                rm -f -- "$temp"; sayfail "Empty or invalid transfer: $file"; ((failed+=1)); continue
            fi
            if ! ln -- "$temp" "$SGND_WEB_CONTENT_INGEST_DIR/$file"; then
                rm -f -- "$temp"; saywarning "Could not safely place local file: $file"; ((failed+=1)); continue
            fi
            rm -f -- "$temp"
            ((transferred+=1))
            # Archive only after successful local placement. Existing archive names
            # are never overwritten, and unarchived sources can be retried later.
            if ! ssh -o BatchMode=yes -p "$port" -- "${user}@${host}" "mkdir -p '$remote/archived' && if test ! -e '$remote/archived/$file'; then mv -- '$remote/$file' '$remote/archived/$file'; else exit 8; fi"; then
                saywarning "Retrieved $file, but remote archiving failed; source retained."
            else
                sayok "Retrieved and archived $file"
            fi
        done
        sgnd_print_labeledvalue --label "Retrieved" --value "$transferred" --labelwidth 20
        sgnd_print_labeledvalue --label "Skipped" --value "$skipped" --labelwidth 20
        sgnd_print_labeledvalue --label "Failed" --value "$failed" --labelwidth 20
        (( failed == 0 ))
    }

    # fn: _web_content_ingest - Ingest one or more loose Markdown files into a website repository
        # . Purpose
        #   Ingest one or more loose Markdown files into a website repository.
        #
        # . Usage
        #   ```bash
        #   _web_content_ingest
        #   ```
    _web_content_ingest() {
        local mode=""
        local selected=""
        local input_file=""
        local rc=0
        local ingested=0
        local skipped=0
        local failed=0
        local batch_mode="No"
        local -a files=()
        local -a targets=()

        _web_content_select_source || return 0
        _web_content_select_ingest_dir || return 0

        mapfile -t files < <(find "$SGND_WEB_CONTENT_INGEST_DIR" -maxdepth 1 -type f -name '*.md' -printf '%f\n' 2>/dev/null | sort)
        if (( ${#files[@]} == 0 )); then
            saywarning "No Markdown files found in ingestion directory: $SGND_WEB_CONTENT_INGEST_DIR"
            return 0
        fi

        if (( ${#files[@]} == 1 )); then
            targets=("${files[0]}")
            sayinfo "Using ingestion file: ${files[0]}"
        else
            ask_selection --label "Ingestion mode" --var mode --items "Ingest all (${#files[@]} files)" "Select files" || return 0
            if [[ "$mode" == "Select files" ]]; then
                ask_selection --label "Markdown files to ingest" --var targets --multi --items "${files[@]}" || return 0
                (( ${#targets[@]} > 0 )) || return 0
                (( ${#targets[@]} > 1 )) && batch_mode="Yes"
            else
                targets=("${files[@]}")
                batch_mode="Yes"
            fi
        fi

        for selected in "${targets[@]}"; do
            input_file="$SGND_WEB_CONTENT_INGEST_DIR/$selected"
            if [[ "$batch_mode" == "Yes" ]]; then
                sgnd_print
                sgnd_print_sectionheader --text "Ingesting: $selected"
            fi

            rc=0
            _web_content_ingest_one "$input_file" "$batch_mode" || rc=$?
            case "$rc" in
                0) ((ingested++)) ;;
                2) ((skipped++)) ;;
                *) ((failed++)) ;;
            esac
        done

        if [[ "$batch_mode" == "Yes" ]]; then
            sgnd_print
            sgnd_print_sectionheader --text "Batch ingestion summary"
            sgnd_print_labeledvalue --label "Found" --value "${#targets[@]}" --labelwidth 20
            sgnd_print_labeledvalue --label "Ingested" --value "$ingested" --labelwidth 20
            sgnd_print_labeledvalue --label "Skipped" --value "$skipped" --labelwidth 20
            sgnd_print_labeledvalue --label "Failed" --value "$failed" --labelwidth 20
        fi

        _web_content_record_activity "$ingested"
        (( failed == 0 ))
    }

    # fn: _web_content_delete_one - Remove one selected page or child section recoverably
        # . Purpose
        #   Preview and archive one selected canonical page or child section while preserving
        #   translation and descendant safety rules.
        #
        # . Arguments
        #   - $1  SELECTION - Display value returned by inspect-delete / ask_selection.
        #   - $2  COUNT_VAR - Caller variable receiving the number of archived files.
        #
        # . Returns
        #   - 0 when content was archived and removed.
        #   - 2 when the selected item was skipped or its deletion was cancelled.
        #   Other non-zero values when inspection, preview, or deletion fails.
        #
        # . Usage
        #   ```bash
        #   _web_content_delete_one "<selection>" "5"
        #   ```
    _web_content_delete_one() {
        local selection="${1:?missing selection}"
        local count_var="${2:?missing count variable}"
        local preview_file=""
        local result_file=""
        local content_file=""
        local title=""
        local language=""
        local route=""
        local archive_root=""
        local recursive_required="No"
        local all_languages_required="No"
        local descendant_count="0"
        local translation_count="0"
        local affected_count="0"
        local deleted_count="0"
        local decision=""
        local rc=0
        local -a all_language_args=()
        local -a recursive_args=()

        printf -v "$count_var" '%s' 0

        content_file="${selection##*[}"
        content_file="${content_file%]}"

        # A previous selected item may already have removed this file, for example when
        # a selected section recursively contains another selected page or when a default-
        # language page removes a selected translation at the same time.
        if [[ ! -f "${SGND_WEB_CONTENT_SOURCE%/}/content/$content_file" ]]; then
            sayinfo "Skipping '$content_file'; it was already removed by another selected deletion."
            return 2
        fi

        preview_file="$(mktemp)" || return 1
        rc=0
        _web_content_run_engine "$preview_file" preview-delete \
            --source "$SGND_WEB_CONTENT_SOURCE" \
            --content-file "$content_file" || rc=$?
        _web_content_report_warnings "$preview_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$preview_file"
            rm -f "$preview_file"
            return "$rc"
        fi

        all_languages_required="$(_web_content_result_value "$preview_file" all_languages_required)"
        translation_count="$(_web_content_result_value "$preview_file" translation_count)"
        if [[ "$all_languages_required" == "Yes" ]]; then
            ask_decision \
                --label "Selected default-language page has $translation_count translation(s). Archive and remove all language versions?" \
                --choices "Yes|Y,No|N" \
                --default "Yes" \
                --var decision || { rm -f "$preview_file"; return 2; }
            if [[ "$decision" != "YES" ]]; then
                saycancel "Content deletion cancelled to avoid orphaned translations."
                rm -f "$preview_file"
                return 2
            fi
            all_language_args=(--all-languages)
            rm -f "$preview_file"
            preview_file="$(mktemp)" || return 1
            rc=0
            _web_content_run_engine "$preview_file" preview-delete \
                --source "$SGND_WEB_CONTENT_SOURCE" \
                --content-file "$content_file" \
                --all-languages || rc=$?
            _web_content_report_warnings "$preview_file"
            if (( rc != 0 )); then
                _web_content_report_errors "$preview_file"
                rm -f "$preview_file"
                return "$rc"
            fi
        fi

        recursive_required="$(_web_content_result_value "$preview_file" recursive_required)"
        descendant_count="$(_web_content_result_value "$preview_file" descendant_count)"
        if [[ "$recursive_required" == "Yes" ]]; then
            ask_decision \
                --label "Selected page has $descendant_count child page(s). Archive and remove the complete section?" \
                --choices "Yes|Y,No|N" \
                --default "No" \
                --var decision || { rm -f "$preview_file"; return 2; }
            if [[ "$decision" != "YES" ]]; then
                saycancel "Content deletion cancelled."
                rm -f "$preview_file"
                return 2
            fi
            recursive_args=(--recursive)
            rm -f "$preview_file"
            preview_file="$(mktemp)" || return 1
            rc=0
            _web_content_run_engine "$preview_file" preview-delete \
                --source "$SGND_WEB_CONTENT_SOURCE" \
                --content-file "$content_file" \
                "${all_language_args[@]}" \
                --recursive || rc=$?
            _web_content_report_warnings "$preview_file"
            if (( rc != 0 )); then
                _web_content_report_errors "$preview_file"
                rm -f "$preview_file"
                return "$rc"
            fi
        fi

        title="$(_web_content_result_value "$preview_file" title)"
        language="$(_web_content_result_value "$preview_file" language)"
        route="$(_web_content_result_value "$preview_file" route)"
        archive_root="$(_web_content_result_value "$preview_file" archive_root)"
        affected_count="$(_web_content_result_value "$preview_file" affected_files | awk 'NF {count++} END {print count+0}')"

        sgnd_print
        sgnd_print_sectionheader --text "Delete content"
        sgnd_print_labeledvalue --label "Title" --value "$title" --labelwidth 20
        sgnd_print_labeledvalue --label "Language" --value "$language" --labelwidth 20
        sgnd_print_labeledvalue --label "Route" --value "$route" --labelwidth 20
        sgnd_print_labeledvalue --label "Files affected" --value "$affected_count" --labelwidth 20
        sgnd_print_labeledvalue --label "Archive" --value "$archive_root" --labelwidth 20
        sgnd_print_labeledvalue --label "Action" --value "Move from active content into the recovery archive" --labelwidth 20

        ask_decision \
            --label "Archive and remove this content from the active website source?" \
            --choices "Yes|Y,No|N" \
            --default "No" \
            --var decision || { rm -f "$preview_file"; return 2; }
        if [[ "$decision" != "YES" ]]; then
            saycancel "Content deletion cancelled."
            rm -f "$preview_file"
            return 2
        fi
        rm -f "$preview_file"

        result_file="$(mktemp)" || return 1
        rc=0
        _web_content_run_engine "$result_file" delete \
            --source "$SGND_WEB_CONTENT_SOURCE" \
            --content-file "$content_file" \
            "${all_language_args[@]}" \
            "${recursive_args[@]}" || rc=$?
        _web_content_report_warnings "$result_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$result_file"
            rm -f "$result_file"
            return "$rc"
        fi

        deleted_count="$(_web_content_result_value "$result_file" deleted_count)"
        archive_root="$(_web_content_result_value "$result_file" archive_root)"
        sayok "Content removed from the active website source and archived for recovery."
        sgnd_print_labeledvalue --label "Archived files" --value "$deleted_count" --labelwidth 20
        sgnd_print_labeledvalue --label "Archive" --value "$archive_root" --labelwidth 20
        printf -v "$count_var" '%s' "$deleted_count"
        rm -f "$result_file"
        return 0
    }

    # fn: _web_content_delete - Remove one or more pages or child sections recoverably
        # . Purpose
        #   Select one or more canonical child pages/sections, archive the selected content,
        #   and optionally repeat the workflow without returning to the Management Console.
        #
        # . Behavior
        #   - Uses ask_selection in multi-select mode.
        #   - Applies translation and recursive-section safety checks per selected item.
        #   - Skips a selected item when an earlier selected deletion already removed it.
        #   - Reports a batch summary when multiple items were selected or any item failed/skipped.
        #   - Ends each completed pass with a section-header line and an auto-continue dialog:
        #     Enter returns to the menu; A or timeout starts another deletion pass.
        #   - Reports the total number of changed canonical files to the Management Console
        #     activity marker so website generation can be marked pending.
        #
        # . Usage
        #   ```bash
        #   _web_content_delete
        #   ```
    _web_content_delete() {
        local inspect_file=""
        local options_text=""
        local selection=""
        local deleted_this=0
        local deleted_total=0
        local pass_deleted=0
        local pass_skipped=0
        local pass_failed=0
        local overall_failed=0
        local dlg_rc=0
        local rc=0
        local -a options=()
        local -a selections=()

        _web_content_select_source || return 0

        while :; do
            options=()
            selections=()
            pass_deleted=0
            pass_skipped=0
            pass_failed=0

            inspect_file="$(mktemp)" || return 1
            rc=0
            _web_content_run_engine "$inspect_file" inspect-delete --source "$SGND_WEB_CONTENT_SOURCE" || rc=$?
            _web_content_report_warnings "$inspect_file"
            if (( rc != 0 )); then
                _web_content_report_errors "$inspect_file"
                rm -f "$inspect_file"
                _web_content_record_activity "$deleted_total"
                return "$rc"
            fi

            options_text="$(_web_content_result_value "$inspect_file" options 2>/dev/null || true)"
            rm -f "$inspect_file"
            if [[ -z "$options_text" ]]; then
                saywarning "No deletable child pages were found. Home and main-navigation section roots are protected."
                _web_content_record_activity "$deleted_total"
                return "$overall_failed"
            fi
            mapfile -t options <<< "$options_text"

            ask_selection \
                --label "Pages to delete" \
                --var selections \
                --multi \
                --items "${options[@]}" || {
                    _web_content_record_activity "$deleted_total"
                    return "$overall_failed"
                }

            for selection in "${selections[@]}"; do
                deleted_this=0
                rc=0
                _web_content_delete_one "$selection" deleted_this || rc=$?
                case "$rc" in
                    0)
                        if [[ "$deleted_this" =~ ^[0-9]+$ ]]; then
                            deleted_total=$((deleted_total + deleted_this))
                            pass_deleted=$((pass_deleted + deleted_this))
                        fi
                        ;;
                    2)
                        pass_skipped=$((pass_skipped + 1))
                        ;;
                    *)
                        pass_failed=$((pass_failed + 1))
                        overall_failed=1
                        ;;
                esac
            done

            if (( ${#selections[@]} > 1 || pass_skipped > 0 || pass_failed > 0 )); then
                sgnd_print
                sgnd_print_sectionheader --text "Deletion summary"
                sgnd_print_labeledvalue --label "Selected" --value "${#selections[@]}" --labelwidth 20
                sgnd_print_labeledvalue --label "Archived files" --value "$pass_deleted" --labelwidth 20
                sgnd_print_labeledvalue --label "Skipped" --value "$pass_skipped" --labelwidth 20
                sgnd_print_labeledvalue --label "Failed" --value "$pass_failed" --labelwidth 20
            fi

            _web_content_record_activity "$deleted_total"

            sgnd_print
            sgnd_print_sectionheader ""
            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --again \
                --legend "Enter=return to menu; A=one more; timeout=delete more content" \
                || dlg_rc=$?

            case "$dlg_rc" in
                1|3) continue ;;
                *) return "$overall_failed" ;;
            esac
        done
    }

    # fn: _web_content_generate - Generate a static website from a content repository
        # . Purpose
        #   Generate a static website from a content repository.
        #   On success, write the optional console completion marker so publication
        #   status can be marked pending without treating cancellation as generation.
        #
        # . Usage
        #   ```bash
        #   _web_content_generate
        #   ```
    _web_content_generate() {
        local result_file=""
        local pages=""
        local articles=""
        local rc=0
        local generation_mode="public"
        local rss_mode="no"
        local suggested_output=""
        local -a extra_args=()

        _web_content_select_source || return 0
        ask --label "Generation mode (public/preview)" --var generation_mode --default "public" --back || return 0
        case "${generation_mode,,}" in
            public) generation_mode="public" ;;
            preview) generation_mode="preview" ;;
            *) sayfail "Generation mode must be public or preview."; return 1 ;;
        esac
        if [[ "$generation_mode" == "preview" ]]; then
            saywarn "Preview pages are not protected by noindex. Never deploy this output publicly."
        else
            ask --label "Generate RSS feed? (yes/no)" --var rss_mode --default "no" --back || return 0
            case "${rss_mode,,}" in
                yes|y) extra_args+=(--rss) ;;
                no|n) ;;
                *) sayfail "Enter yes or no for RSS."; return 1 ;;
            esac
        fi
        suggested_output="$SGND_WEB_CONTENT_OUTPUT"
        if [[ "$generation_mode" == "preview" ]]; then
            suggested_output="${SGND_WEB_CONTENT_OUTPUT%/}-preview"
        fi
        ask --label "Output directory" --var SGND_WEB_CONTENT_OUTPUT --default "$suggested_output" --back || return 0
        _web_content_select_language || return 0
        _web_content_ensure_output_parent "$SGND_WEB_CONTENT_OUTPUT" || { sayfail "Cannot create output parent directory."; return 1; }

        result_file="$(mktemp)" || return 1
        _web_content_run_engine "$result_file" generate \
            --source "$SGND_WEB_CONTENT_SOURCE" \
            --output "$SGND_WEB_CONTENT_OUTPUT" \
            --language "$SGND_WEB_CONTENT_LANGUAGE" \
            --mode "$generation_mode" "${extra_args[@]}" || rc=$?

        _web_content_report_warnings "$result_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$result_file"
            rm -f "$result_file"
            return "$rc"
        fi

        pages="$(_web_content_result_value "$result_file" pages_generated)"
        articles="$(_web_content_result_value "$result_file" articles_generated)"
        sayok "Website generated successfully."
        sgnd_print_labeledvalue --label "Output" --value "$SGND_WEB_CONTENT_OUTPUT" --labelwidth 20
        sgnd_print_labeledvalue --label "Pages" --value "$pages" --labelwidth 20
        sgnd_print_labeledvalue --label "Articles" --value "$articles" --labelwidth 20
        sgnd_print_labeledvalue --label "Mode" --value "$generation_mode" --labelwidth 20
        sgnd_print_labeledvalue --label "Skipped pages" --value "$(_web_content_result_value "$result_file" skipped_pages)" --labelwidth 20
        sgnd_print_labeledvalue --label "Broken links" --value "$(_web_content_result_value "$result_file" broken_links)" --labelwidth 20
        rm -f "$result_file"
        # A successful selector cancellation also returns zero; only a completed
        # engine generation may mark the downstream publication step pending.
        if [[ -n "${SGND_WEB_CONTENT_GENERATION_MARKER_FILE:-}" ]]; then
            printf '%s\n' generated > "$SGND_WEB_CONTENT_GENERATION_MARKER_FILE" ||
                saywarning "Could not record successful website generation for menu status updates."
        fi
        return 0
    }

    # fn: _web_content_validate - Validate a web-content repository
        # . Purpose
        #   Validate a web-content repository.
        #
        # . Usage
        #   ```bash
        #   _web_content_validate
        #   ```
    _web_content_validate() {
        local result_file=""
        local files=""
        local styles=""
        local rc=0

        _web_content_select_source || return 0
        result_file="$(mktemp)" || return 1
        _web_content_run_engine "$result_file" validate --source "$SGND_WEB_CONTENT_SOURCE" || rc=$?
        _web_content_report_warnings "$result_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$result_file"
            rm -f "$result_file"
            return "$rc"
        fi
        files="$(_web_content_result_value "$result_file" content_files)"
        styles="$(_web_content_result_value "$result_file" style_classes)"
        sayok "Web content repository validation passed."
        sgnd_print_labeledvalue --label "Content files" --value "$files" --labelwidth 20
        sgnd_print_labeledvalue --label "Content styles" --value "$styles" --labelwidth 20
        rm -f "$result_file"
    }

    # fn: _web_content_prepare_social - Prepare a single article as a social-media draft.
        # . Purpose
        #   Prepare a single article as a social-media draft.
        #
        # The output stays outside the repository and is never posted automatically.
        #
        # . Usage
        #   ```bash
        #   _web_content_prepare_social
        #   ```
    _web_content_prepare_social() {
        local list_file="" result_file="" social_selected_page="" file="" rc=0
        local -a options=()
        _web_content_select_source || return 0
        list_file="$(mktemp)" || return 1
        result_file="$(mktemp)" || { rm -f -- "$list_file"; return 1; }
        _web_content_run_engine "$list_file" list-pages --source "$SGND_WEB_CONTENT_SOURCE" || {
            _web_content_report_errors "$list_file"
            rm -f -- "$list_file" "$result_file"
            return 1
        }
        mapfile -t options < <(python3 - "$list_file" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    pages = json.load(handle).get('pages', [])
for page in pages:
    if page['file'].split('/')[-1].startswith('index_'):
        continue
    if str(page['metadata'].get('draft', 'false')).lower() == 'true':
        continue
    print('{} | {} | {} [{}]'.format(page['title'], page['language'], page['route'], page['file']))
PYCODE
)
        if (( ${#options[@]} == 0 )); then
            saywarning "No published articles available."
            rm -f -- "$list_file" "$result_file"
            return 0
        fi
        echo
        ask_selection --label "Select article" --var social_selected_page --items "${options[@]}" || {
            rm -f -- "$list_file" "$result_file"
            return 0
        }
        [[ "$social_selected_page" =~ \[([^][]+)\]$ ]] || {
            sayfail "Invalid article selection"
            rm -f -- "$list_file" "$result_file"
            return 1
        }
        file="${BASH_REMATCH[1]}"
        ask --label "Draft output directory" --var SGND_WEB_CONTENT_SOCIAL_OUTPUT --default "$SGND_WEB_CONTENT_SOCIAL_OUTPUT" --back || {
            rm -f -- "$list_file" "$result_file"; return 0;
        }
        ask --label "Platform" --var SGND_WEB_CONTENT_PLATFORM --default "$SGND_WEB_CONTENT_PLATFORM" --validate _web_content_validate_platform --back || {
            rm -f -- "$list_file" "$result_file"; return 0;
        }
        _web_content_ensure_output_parent "$SGND_WEB_CONTENT_SOCIAL_OUTPUT" || {
            sayfail "Cannot create draft-output parent directory."
            rm -f -- "$list_file" "$result_file"; return 1;
        }
        _web_content_run_engine "$result_file" prepare-social \
            --source "$SGND_WEB_CONTENT_SOURCE" \
            --output "$SGND_WEB_CONTENT_SOCIAL_OUTPUT" \
            --platform "$SGND_WEB_CONTENT_PLATFORM" \
            --content-file "$file" --excerpt-length 150 || rc=$?
        _web_content_report_warnings "$result_file"
        if (( rc != 0 )); then
            _web_content_report_errors "$result_file"
        else
            sayok "Social-media draft prepared; nothing has been posted."
            sgnd_print_labeledvalue --label "Draft directory" --value "$(_web_content_result_value "$result_file" output)" --labelwidth 20
            _web_content_record_activity 1
        fi
        rm -f -- "$list_file" "$result_file"
        return "$rc"
    }

    # fn: _web_content_status - Show Web Content Management configuration and engine status
        # . Purpose
        #   Show Web Content Management configuration and engine status.
        #
        # . Usage
        #   ```bash
        #   _web_content_status
        #   ```
    _web_content_status() {
        local python_root=""
        local engine="Unavailable"
        local python_version="Unavailable"

        python_root="$(_web_content_python_root)"
        [[ -d "$python_root/webcontent" ]] && engine="Available"
        if command -v python3 >/dev/null 2>&1; then
            python_version="$(python3 --version 2>&1)"
        fi

        sgnd_print
        sgnd_print_sectionheader --text "Web Content Management"
        sgnd_print_labeledvalue --label "Engine" --value "$engine" --labelwidth 20
        sgnd_print_labeledvalue --label "Python" --value "$python_version" --labelwidth 20
        sgnd_print_labeledvalue --label "Repository" --value "$SGND_WEB_CONTENT_SOURCE" --labelwidth 20
        sgnd_print_labeledvalue --label "Output" --value "$SGND_WEB_CONTENT_OUTPUT" --labelwidth 20
        sgnd_print_labeledvalue --label "Language" --value "$SGND_WEB_CONTENT_LANGUAGE" --labelwidth 20
        sgnd_print_labeledvalue --label "Social platform" --value "$SGND_WEB_CONTENT_PLATFORM" --labelwidth 20
        sgnd_print_labeledvalue --label "Incoming source" --value "${SGND_WEB_INCOMING_USER}@${SGND_WEB_INCOMING_HOST}:${SGND_WEB_INCOMING_REMOTE_DIR}" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingestion directory" --value "${SGND_WEB_CONTENT_INGEST_DIR:-$(_web_content_canonical_ingest_dir)}" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingestion archive" --value "$(_web_content_canonical_archive_dir)" --labelwidth 20
        sgnd_print_labeledvalue --label "Deletion archive" --value "$(_web_content_canonical_delete_archive_dir)" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingest language" --value "${SGND_WEB_CONTENT_INGEST_LANGUAGE:-Not set}" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingest content type" --value "${SGND_WEB_CONTENT_INGEST_KIND:-Not set}" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingest parent" --value "${SGND_WEB_CONTENT_INGEST_PARENT:-Not set}" --labelwidth 20
    }

# Page management uses shared Python content discovery; changes remain uncommitted in Git.
    # Metadata editing stays on a page until Done; the wrapper offers another page afterward.
    # fn: _web_content_manage_page_once - Select one page and edit metadata or move its canonical source file.
        # . Purpose
        #   Select one page and edit metadata or move its canonical source file.
        #
        # . Arguments
        #   - `$1`: Requested operation.
        # . Behavior
        #   - Coordinates the existing workflow without modifying article content directly.
        #   - Propagates errors to the caller and uses the framework for user interaction.
        #
        # . Usage
        #   ```bash
        #   _web_content_manage_page_once "edit-metadata"
        #   ```
    _web_content_manage_page_once() {
        local operation="${1:?missing operation}"
        local list_file="" selected="" file="" field="" metadata_new_value="" parent="" slug="" result_file=""
        local -a options=()
        local row="" decision="" current_value=""
        list_file="$(mktemp)" || return 1
        result_file="$(mktemp)" || { rm -f -- "$list_file"; return 1; }
        _web_content_run_engine "$list_file" list-pages --source "$SGND_WEB_CONTENT_SOURCE" || {
            _web_content_report_errors "$list_file"
            rm -f -- "$list_file" "$result_file"
            return 1
        }
        mapfile -t options < <(python3 - "$list_file" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    pages = json.load(handle).get('pages', [])
for page in pages:
    print('{} | {} | {} [{}]'.format(page['title'], page['language'], page['route'], page['file']))
PYCODE
)
        if (( ${#options[@]} == 0 )); then
            saywarning "No pages available."
            rm -f -- "$list_file" "$result_file"
            return 0
        fi
        ask_selection --label "Select page" --var selected --items "${options[@]}" || {
            rm -f -- "$list_file" "$result_file"
            return 0
        }
        [[ "$selected" =~ \[([^][]+)\]$ ]] || { sayfail "Invalid page selection"; return 1; }
        file="${BASH_REMATCH[1]}"
        if [[ "$operation" == "edit-metadata" ]]; then
            # Stage field updates and explicit removals in a JSON batch (null
            # means remove; an empty string means clear). Save commits atomically;
            # discarding the batch leaves the source unchanged.
            local selected_field="" edit_field="" current_value="" metadata_new_value=""
            local staged_file="" staged_count=0
            local -a field_options=() resolved_lines=()
            staged_file="$(mktemp)" || { rm -f -- "$list_file" "$result_file"; return 1; }
            printf '{}\n' > "$staged_file"
            while true; do
                _web_content_run_engine "$list_file" inspect-metadata --source "$SGND_WEB_CONTENT_SOURCE" --content-file "$file" || {
                    _web_content_report_errors "$list_file"
                    rm -f -- "$list_file" "$result_file" "$staged_file"
                    return 1
                }
                sgnd_print
                sgnd_print_sectionheader --text "Metadata: $file"
                local derived_language=""
                derived_language="$(python3 - "$list_file" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    print(json.load(handle).get('language_from_filename', ''))
PYCODE
)"
                sgnd_print_labeledvalue --label "Language (filename)" --value "$derived_language" --labelwidth 20
                mapfile -t field_options < <(python3 - "$list_file" "$staged_file" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    metadata = json.load(handle).get('metadata', {})
with open(sys.argv[2], encoding='utf-8') as handle:
    changes = json.load(handle)
for key, value in changes.items():
    if value is None:
        metadata.pop(key, None)
    else:
        metadata[key] = value
for key, value in metadata.items():
    shown = str(value).lower() if isinstance(value, bool) else str(value if value is not None else '')
    print('{} = {}'.format(key, shown.replace('\n', ' ')))
PYCODE
)
                local metadata_line=""
                for metadata_line in "${field_options[@]}"; do
                    sgnd_print_labeledvalue --label "${metadata_line%% = *}" --value "${metadata_line#* = }" --labelwidth 20
                done
                sgnd_print
                sgnd_print_sectionheader --text "Resolved values (read-only; not staged)"
                mapfile -t resolved_lines < <(python3 - "$list_file" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    values = json.load(handle).get('resolved', {})
for key, entry in values.items():
    value = entry.get('value', '')
    if isinstance(value, bool):
        value = str(value).lower()
    print('{} = {} ({})'.format(key, str(value).replace('\n', ' '), entry.get('origin', 'unknown')))
PYCODE
)
                local resolved_line=""
                for resolved_line in "${resolved_lines[@]}"; do
                    sgnd_print_labeledvalue --label "${resolved_line%% = *}" --value "${resolved_line#* = }" --labelwidth 20
                done
                staged_count="$(python3 - "$staged_file" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    print(len(json.load(handle)))
PYCODE
)"
                sgnd_print_sectionheader --text "Staged changes: $staged_count"
                # Removed fields vanish from the effective field list. Show them
                # explicitly so a pending deletion cannot be mistaken for a save.
                local -a staged_removals=()
                mapfile -t staged_removals < <(python3 - "$staged_file" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    for key, value in json.load(handle).items():
        if value is None:
            print(key)
PYCODE
)
                local removed_field=""
                for removed_field in "${staged_removals[@]}"; do
                    sgnd_print_labeledvalue --label "$removed_field" --value "Remove on Save" --labelwidth 20
                done
                field_options+=("Add metadata field" "Remove metadata field" "Save all staged changes" "Discard changes and finish")
                selected_field=""
                ask_selection --label "Choose a metadata field or action" --var selected_field --items "${field_options[@]}" || break
                case "$selected_field" in
                    "Discard changes and finish") break ;;
                    "Save all staged changes")
                        if (( staged_count == 0 )); then
                            sayinfo "No changes to save."
                            continue
                        fi
                        if _web_content_run_engine "$result_file" edit-metadata-fields --source "$SGND_WEB_CONTENT_SOURCE" --content-file "$file" --changes-file "$staged_file"; then
                            _web_content_record_activity "$staged_count"
                            sayok "Saved $staged_count metadata fields. Git commit remains manual."
                            printf '{}\n' > "$staged_file"
                            break
                        else
                            _web_content_report_errors "$result_file"
                            continue
                        fi
                        ;;
                    "Add metadata field")
                        edit_field=""
                        ask --label "New metadata field name" --var edit_field --back || continue
                        [[ "$edit_field" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || { saywarning "Invalid field name."; continue; }
                        case "$edit_field" in parent|slug|language) saywarning "Location-dependent field cannot be edited here."; continue ;; esac
                        ;;
                    "Remove metadata field")
                        # Only explicit (including staged-new) fields are removable.
                        # Derived defaults do not exist in the source front matter.
                        local -a removable_fields=()
                        mapfile -t removable_fields < <(python3 - "$list_file" "$staged_file" <<'PYCODE'
import json, re, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    metadata = json.load(handle).get('metadata', {})
with open(sys.argv[2], encoding='utf-8') as handle:
    changes = json.load(handle)
for key, value in changes.items():
    if value is None:
        metadata.pop(key, None)
    else:
        metadata[key] = value
for key in metadata:
    if re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*', key) and key not in {'parent', 'slug', 'language'}:
        print(key)
PYCODE
)
                        if (( ${#removable_fields[@]} == 0 )); then
                            saywarning "No explicit metadata fields to remove."
                            continue
                        fi
                        local remove_field=""
                        ask_selection --label "Choose field to remove (staged until Save)" --var remove_field --items "${removable_fields[@]}" || continue
                        if ! python3 - "$list_file" "$staged_file" "$remove_field" <<'PYCODE'
import json, os, sys, tempfile
source, path, key = sys.argv[1:]
with open(source, encoding='utf-8') as handle:
    original = json.load(handle).get('metadata', {})
with open(path, encoding='utf-8') as handle:
    changes = json.load(handle)
# Removing a field created in this batch cancels its addition; removing a
# source field stages JSON null so the engine deletes its front-matter line.
if key in original:
    changes[key] = None
else:
    changes.pop(key, None)
fd, temp = tempfile.mkstemp(prefix='.wcm-stage-', dir=os.path.dirname(path))
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as handle:
        json.dump(changes, handle, ensure_ascii=False)
    os.replace(temp, path)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
PYCODE
                        then
                            saywarning "Could not stage metadata removal."
                            continue
                        fi
                        sayinfo "Staged removal: $remove_field (not yet saved)"
                        continue
                        ;;
                    *) edit_field="${selected_field%% = *}" ;;
                esac
                current_value="$(python3 - "$list_file" "$staged_file" "$edit_field" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    metadata = json.load(handle).get('metadata', {})
with open(sys.argv[2], encoding='utf-8') as handle:
    changes = json.load(handle)
for key, value in changes.items():
    if value is None:
        metadata.pop(key, None)
    else:
        metadata[key] = value
value = metadata.get(sys.argv[3], '')
if isinstance(value, bool):
    print(str(value).lower())
elif value is not None:
    print(str(value))
PYCODE
)"
                metadata_new_value="$current_value"
                ask --label "New value (:clear to empty)" --var metadata_new_value --default "$current_value" --back || continue
                [[ -z "$metadata_new_value" ]] && metadata_new_value="$current_value"
                [[ "$metadata_new_value" == ":clear" ]] && metadata_new_value=""
                if [[ "$metadata_new_value" == "$current_value" ]]; then
                    sayinfo "Metadata unchanged."
                    continue
                fi
                # A single JSON staging file is used for the whole batch. No
                # Markdown is written until the user selects Save.
                if ! python3 - "$staged_file" "$edit_field" "$metadata_new_value" <<'PYCODE'
import json, os, sys, tempfile
path, key, value = sys.argv[1:]
if key in {'featured', 'draft', 'hide_title', 'nav_hidden', 'hidden', 'private'}:
    value = value.strip().lower()
    if value not in {'true', 'false'}:
        raise SystemExit('Boolean fields require true or false')
with open(path, encoding='utf-8') as handle:
    staged = json.load(handle)
staged[key] = value
fd, temp = tempfile.mkstemp(prefix='.wcm-stage-', dir=os.path.dirname(path))
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as handle:
        json.dump(staged, handle, ensure_ascii=False)
    os.replace(temp, path)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
PYCODE
                then
                    saywarning "Invalid value; change not staged."
                    continue
                fi
                sayinfo "Staged: $edit_field (not yet saved)"
            done
            rm -f -- "$staged_file"
            rm -f -- "$list_file" "$result_file"
            return 0
        else
            saywarning "Moving a page changes its URL. Check references after regeneration."
            parent="$(dirname -- "$file")"
            [[ "$parent" == "." ]] && parent=""
            slug="$(basename -- "$file")"; slug="${slug%_??.md}"
            ask --label "Destination section (relative to content)" --var parent --default "$parent" --back || { rm -f -- "$list_file" "$result_file"; return 0; }
            ask --label "New slug" --var slug --default "$slug" --back || { rm -f -- "$list_file" "$result_file"; return 0; }
            sgnd_print_labeledvalue --label "From" --value "$file" --labelwidth 20
            sgnd_print_labeledvalue --label "To" --value "${parent:+$parent/}${slug}" --labelwidth 20
            ask_decision --label "Move this page and change its URL?" --choices "Yes|Y,No|N" --default "No" --var decision || { rm -f -- "$list_file" "$result_file"; return 0; }
            if [[ "$decision" != "YES" ]]; then
                saycancel "Page move cancelled."
                rm -f -- "$list_file" "$result_file"
                return 0
            fi
            _web_content_run_engine "$result_file" move-page --source "$SGND_WEB_CONTENT_SOURCE" --content-file "$file" --parent "$parent" --slug "$slug" || {
                _web_content_report_errors "$result_file"; rm -f -- "$list_file" "$result_file"; return 1;
            }
            saywarning "Update links referencing the previous URL, then regenerate and validate."
        fi
        _web_content_record_activity 1
        sayok "Content updated. Git commit remains manual."
        rm -f -- "$list_file" "$result_file"
    }


    # fn: _web_content_manage_page - Repeat content editing when requested.
        # . Purpose
        #   Repeat content editing when requested.
        #
        # Enter or timeout returns to the console; only A starts another selection.
        #
        # . Arguments
        #   - `$1`: Requested operation.
        # . Usage
        #   ```bash
        #   _web_content_manage_page "edit-metadata"
        #   ```
    _web_content_manage_page() {
        local operation="${1:?missing operation}"
        local dlg_rc=0
        local rc=0
        while true; do
            _web_content_manage_page_once "$operation" || rc=$?
            (( rc == 0 )) || return "$rc"
            sgnd_print
            sgnd_print_sectionheader ""
            dlg_rc=0
            ask_dlg_autocontinue \
                --seconds 5 \
                --message "Manage another page?" \
                --again \
                --pause \
                --legend "A=another page; Enter/timeout=return to menu; P/Space=pause" \
                || dlg_rc=$?
            # Framework returns 3 for 'again'; timeout and Enter return to menu.
            case "$dlg_rc" in
                3) continue ;;
                *) return 0 ;;
            esac
        done
    }

    # fn: _web_content_manage_config - Select an existing .cfg file and open it in nano.
        # . Purpose
        #   Select an existing .cfg file and open it in nano.
        #
        # . Behavior
        #   - Uses the currently selected website repository and its config/ directory.
        #   - Lists only regular .cfg files found directly under config/.
        #   - Uses the framework selection dialogue; cancellation changes nothing.
        #   - Reports editor failures and marks website generation pending only on changes.
        #   - Does not create arbitrary files or execute paths entered by the user.
        #
        # . Usage
        #   ```bash
        #   _web_content_manage_config
        #   ```
    _web_content_manage_config() {
        local config_dir="" selected="" target="" before="" after="" rc=0
        local -a files=()

        _web_content_select_source || return 0
        config_dir="${SGND_WEB_CONTENT_SOURCE%/}/config"
        if [[ ! -d "$config_dir" ]]; then
            sayfail "Website configuration directory not found: $config_dir"
            return 1
        fi
        if ! command -v nano >/dev/null 2>&1; then
            sayfail "nano is not installed. Install nano to edit website configuration."
            return 127
        fi

        while IFS= read -r -d '' target; do
            files+=("${target##*/}")
        done < <(find "$config_dir" -maxdepth 1 -type f -name '*.cfg' -print0 | sort -z)
        if (( ${#files[@]} == 0 )); then
            saywarning "No .cfg files found in: $config_dir"
            return 0
        fi

        ask_selection --label "Configuration file" --var selected --items "${files[@]}" || return 0
        # Never accept a path from the selection result, even when the menu is modified.
        [[ -n "$selected" && "$selected" == "${selected##*/}" && "$selected" == *.cfg ]] || {
            sayfail "Invalid configuration selection."
            return 1
        }
        target="$config_dir/$selected"
        [[ -f "$target" && ! -L "$target" ]] || {
            sayfail "Configuration file is unavailable or is a symbolic link: $target"
            return 1
        }
        [[ -r "$target" && -w "$target" ]] || {
            sayfail "Configuration file is not readable and writable: $target"
            return 1
        }

        before="$(sha256sum -- "$target" | cut -d ' ' -f 1)" || return 1
        sgnd_print
        sgnd_print_sectionheader --text "Edit website configuration"
        sgnd_print_labeledvalue --label "File" --value "$target" --labelwidth 20
        nano -- "$target" || rc=$?
        if (( rc != 0 )); then
            sayfail "nano exited with status $rc."
            return "$rc"
        fi
        after="$(sha256sum -- "$target" | cut -d ' ' -f 1)" || return 1
        if [[ "$before" != "$after" ]]; then
            _web_content_record_activity 1
            sayok "Configuration updated: $selected. Regenerate and validate the website."
        else
            sayinfo "Configuration unchanged: $selected"
        fi
    }

# - Website publication -------------------------------------------------------------
    # fn: _web_publish_safe_path - Require a dedicated absolute deployment directory.
        # . Purpose
        #   Require a dedicated absolute deployment directory.
        #
        # . Arguments
        #   - `$1`: Optional: filesystem path to inspect.
        # . Returns
        #   - 0 for a safe directory, 1 otherwise.
        # . Usage
        #   ```bash
        #     _web_publish_safe_path "$path"
        #   ```
        #   _web_publish_safe_path "$path"
    _web_publish_safe_path() {
        local path="${1:-}"
        [[ "$path" == /* && "$path" != / && "$path" != *'..'* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
        [[ "$path" != *'"'* && "$path" != *"'"* && "$path" != *'*'* && "$path" != *';'* && "$path" != *'$'* && "$path" != *'`'* && "$path" != *'!'* && "$path" != *'\'* ]] || return 1
        [[ "${path#/}" == */* && "$path" != *[[:space:]]* ]]
    }

    # fn: _web_publish_safe_external_path - Validate an FTP/SFTP account-root path.
        # . Purpose
        #   Accept a safe absolute directory, including hosting roots like /public_html.
        # . Arguments
        #   $1 Host-relative absolute directory.
        # . Usage
        #   ```bash
        #   _web_publish_safe_external_path /public_html
        #   ```
    _web_publish_safe_external_path() {
        local path="${1:-}"
        [[ "$path" == /* && "$path" != / && "$path" != *'..'* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
        [[ "$path" != *'"'* && "$path" != *"'"* && "$path" != *'*'* && "$path" != *';'* && "$path" != *'$'* && "$path" != *'`'* && "$path" != *'!'* && "$path" != *'\'* && "$path" != *[[:space:]]* ]]
    }

    # fn: _web_publish_discover_sites - List active remote Nginx hostnames and document roots.
        # . Purpose
        #   List active remote Nginx hostnames and document roots.
        #
        # . Behavior
        #   - Uses the active Nginx configuration; falls back to readable enabled
        #     site files if nginx -T requires unavailable privileges.
        #   - Requires no write access; sudo -n is attempted only for reading config.
        #   - Returns named virtual hosts for existing-site selection.
        #   - With mode `roots`, returns eligible document roots; uses named sites
        #     preferentially, falling back to the Nginx default root when needed.
        #   - A failed lookup is optional: the caller can always enter values manually.
        # . Arguments
        #   - $1 hostname; $2 user; $3 port; $4 optional SSH identity; $5 mode.
        # . Output
        #   Mode sites: hostname TAB absolute-root; mode roots: absolute-root.
        # . Returns
        #   - Nonzero if SSH, Nginx dump or parsing fails.
        # . Usage
        #   ```bash
        #     _web_publish_discover_sites "td-web" "deploy" "22" "" "sites"
        #   ```
        #   _web_publish_discover_sites "$host" "$user" "$port" "$identity"
    _web_publish_discover_sites() {
        local host="$1" user="$2" port="$3" identity="${4:-}" mode="${5:-sites}" config="" rc=0
        local -a ssh_args=(ssh -o BatchMode=yes -o ConnectTimeout=8 -p "$port")
        [[ -z "$identity" ]] || ssh_args+=(-i "${identity/#\~\//$HOME/}")
        config="$(mktemp)" || return 1
        # Prefer the live Nginx dump. On a standard Ubuntu installation the SSH
        # account may lack passwordless sudo and permission to inspect TLS keys;
        # in that case read enabled site files (not sites-available) if accessible.
        # This is read-only and never changes Nginx or its ownership.
        "${ssh_args[@]}" -- "${user}@${host}" \
            'config="$(sudo -n nginx -T 2>/dev/null)" || config="$(nginx -T 2>/dev/null)" || { config=""; count=0; for file in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do [ -r "$file" ] || continue; config="$config$(cat "$file")"; config="$config
"; count=$((count+1)); done; [ "$count" -gt 0 ] || exit 1; }; printf "%s\n" "$config"' > "$config" || rc=$?
        if (( rc != 0 )); then rm -f -- "$config"; return "$rc"; fi
        python3 - "$config" "$mode" <<'PYCODE'
import re
import sys

try:
    content = open(sys.argv[1], encoding='utf-8', errors='replace').read()
    # Nginx lexer: skip comments, preserve quoted tokens, track nested blocks.
    tokens = re.findall(r'(?m)\#[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{};]|[^\s{};#]+', content)
    levels = []
    directive = []
    sites = []
    current = None
    for token in tokens:
        if token.startswith('#'):
            continue
        if token == '{':
            kind = directive[0] if directive else ''
            levels.append(kind)
            if kind == 'server' and levels.count('server') == 1:
                current = {'names': [], 'root': ''}
            directive = []
        elif token == '}':
            if levels and levels[-1] == 'server' and current is not None:
                sites.append(current)
                current = None
            if levels:
                levels.pop()
            directive = []
        elif token == ';':
            if current is not None and levels and levels[-1] == 'server':
                if directive and directive[0] == 'server_name':
                    current['names'].extend(directive[1:])
                elif len(directive) > 1 and directive[0] == 'root':
                    current['root'] = directive[1]
            directive = []
        else:
            directive.append(token.strip('"\''))
    roots = {}
    valid_roots = set()
    for site in sites:
        root = site['root']
        if not root.startswith('/') or any(c.isspace() for c in root) or '$' in root:
            continue
        valid_roots.add(root)
        for name in site['names']:
            if re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]*', name) and '.' in name:
                roots.setdefault(name.lower(), set()).add(root)
    if sys.argv[2] == 'roots':
        # Prefer actual named websites over the distribution's default welcome page.
        named_roots = {root for values in roots.values() if len(values) == 1 for root in values}
        for root in sorted(named_roots or valid_roots):
            print(root)
    else:
        for name in sorted(roots):
            if len(roots[name]) == 1:
                print(name + '\t' + next(iter(roots[name])))
except (OSError, ValueError) as exc:
    print('Nginx configuration could not be parsed: ' + str(exc), file=sys.stderr)
    sys.exit(1)
PYCODE
        rc=$?
        rm -f -- "$config"
        return "$rc"
    }

    # fn: _web_publish_load_ssh_helper - Load the MCM-owned SSH helper from its own tree.
        # . Purpose
        #   Load the shared SSH helper independently of the Framework development tree.
        # . Returns
        #   0 when the helper is available; 127 if it cannot be loaded.
        # . Usage
        #   ```bash
        #   _web_publish_load_ssh_helper
        #   ```
    _web_publish_load_ssh_helper() {
        if declare -F sgnd_ssh_ensure_access >/dev/null && declare -F sgnd_ssh_agent_discover >/dev/null; then
            return 0
        fi
        local mcm_root="${SGND_SCRIPT_DIR%/libexec/solidgroundux}"
        local helper="$mcm_root/lib/solidgroundux/common/sgnd-ssh-deployment.sh"
        [[ -r "$helper" ]] || helper='/usr/local/lib/solidgroundux/common/sgnd-ssh-deployment.sh'
        [[ -r "$helper" ]] || { sayfail "SSH deployment library is missing: $helper"; return 127; }
        # shellcheck source=/dev/null
        source "$helper" || return $?
        declare -F sgnd_ssh_ensure_access >/dev/null && declare -F sgnd_ssh_agent_discover >/dev/null || {
            sayfail 'SSH deployment library is incomplete.'
            return 127
        }
    }

    # fn: _web_publish_prepare_ssh - Discover the shared agent and repair SSH access when requested.
        # . Purpose
        #   Prepare SSH access for the normal publishing workflow, including recovery.
        # . Arguments
        #   $1 User; $2 host; $3 port; $4 optional SSH private key.
        # . Returns
        #   The result of the shared SSH access helper.
        # . Usage
        #   ```bash
        #   _web_publish_prepare_ssh "deploy" "host.example.test" "22" ""
        #   ```
    _web_publish_prepare_ssh() {
        local user="$1" host="$2" port="${3:-22}" identity="${4:-}"
        _web_publish_load_ssh_helper || return $?
        sgnd_ssh_ensure_access "$user" "$host" "$port" "$identity"
    }

    # fn: _web_publish_remote_site - Offer optional Nginx provisioning before the first rsync deployment.
        # . Purpose
        #   Offer optional Nginx provisioning before the first rsync deployment.
        #
        # . Arguments
        #   - `$1`: Remote host or site name.
        #   - `$2`: User account.
        #   - `$3`: TCP port.
        #   - `$4`: SSH identity file.
        #   - `$5`: Remote destination directory.
        #   - `$6`: Website hostname.
        # . Behavior
        #   - Checks by SSH whether the named virtual host exists.
        #   - Only provisions after explicit local approval; does not modify existing hosts.
        #   - Invokes the Web Server Management ensure-site action on the remote machine.
        #   - Requires the remote module to be installed and sudo to work noninteractively.
        #   - DNS is managed by the separate optional remote DNS dialog.
        #
        # . Usage
        #   ```bash
        #   _web_publish_remote_site "td-web" "deploy" "22" "" "/srv/storage/www/sgnd" "sgnd.example.test"
        #   ```
    _web_publish_remote_site() {
        local host="$1" user="$2" port="$3" identity="$4" target="$5" address="$6"
        local name="" decision="NO" ssh_identity="" output="" rc=0
        local remote_command="" site_list="" site_name="" site_root="" found_in_active=0
        local -a ssh_args=(ssh -o BatchMode=yes -p "$port")
        [[ -z "$address" ]] && return 0
        [[ "$address" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$address" == *.* ]] || { sayfail "Invalid website hostname."; return 1; }
        name="${address%%.*}"
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { sayfail "Invalid derived site name."; return 1; }
        if [[ -n "$identity" ]]; then
            ssh_identity="${identity/#\~\//$HOME/}"
            ssh_args+=(-i "$ssh_identity")
        fi
        # Inspect the same active Nginx configuration used by the website picker;
        # a server_name directive can contain multiple hostnames on one line.
        site_list="$(mktemp)" || return 1
        if _web_publish_discover_sites "$host" "$user" "$port" "$identity" > "$site_list"; then
            found_in_active=1
            rc=4
            while IFS=$'\t' read -r site_name site_root; do
                [[ "${site_name,,}" == "${address,,}" ]] || continue
                if [[ "$site_root" != "$target" ]]; then
                    rc=5
                else
                    printf -v remote_command 'test -d %q && test -w %q' "$target" "$target"
                    if "${ssh_args[@]}" "${user}@${host}" "$remote_command" >/dev/null 2>&1; then
                        rc=0
                    else
                        rc=6
                    fi
                fi
                break
            done < "$site_list"
        fi
        rm -f -- "$site_list"
        if (( found_in_active == 0 )); then
            # Fallback for hosts where the SSH account cannot dump Nginx config.
            local probe='for f in /etc/nginx/sites-available/*; do [ -f "$f" ] || continue; if grep -Eq "^[[:space:]]*server_name[[:space:]]+${1};" "$f"; then r=""; while read -r k v rest; do if [ "$k" = root ]; then r="${v%;}"; break; fi; done < "$f"; [ "$r" = "$2" ] || exit 5; [ -d "$2" ] && [ -w "$2" ] && exit 0; exit 6; fi; done; exit 4'
            printf -v remote_command 'bash -c %q -- %q %q' "$probe" "$address" "$target"
            "${ssh_args[@]}" "${user}@${host}" "$remote_command" >/dev/null 2>&1
            rc=$?
        fi
        if (( rc == 0 )); then
            sayinfo "Nginx hostname $address is already configured on $host."
            return 0
        fi
        if (( rc == 6 )); then
            saywarning "Nginx hostname exists, but the deployment user cannot write to $target."
            ask_decision --label "Repair document root ownership on $host" --choices "Yes|Y,No|N" --default "No" --var decision || return 1
            [[ "$decision" == YES ]] || return 1
            local repair='p=/usr/local/libexec/solidgroundux/manage-web-server.sh; if [ -x "$p" ]; then exec sudo -n "$p" --action ensure-directory --document-root "$1" --deployment-user "$2"; fi; echo "Remote web server module missing" >&2; exit 127'
            printf -v remote_command 'bash -c %q -- %q %q' "$repair" "$target" "$user"
            output="$("${ssh_args[@]}" "${user}@${host}" "$remote_command" 2>&1)" || rc=$?
            if (( rc != 0 )); then
                sayfail "Could not repair remote document root (exit $rc)."
                [[ -z "$output" ]] || sgnd_print --text "$output"
                return "$rc"
            fi
            sayok "Document root is writable for the deployment account."
            return 0
        fi
        if (( rc == 5 )); then
            sayfail "Existing Nginx hostname $address has a different document root. Resolve it in Web Server Management before publishing."
            return 1
        fi
        if (( rc != 4 )); then
            sayfail "Could not check remote Nginx configuration (SSH exit $rc)."
            return "$rc"
        fi
        saywarning "No Nginx site for $address was found on $host."
        ask_decision --label "Configure Nginx site on $host for $address and $target?" --choices "Yes|Y,No|N" --default "No" --var decision || return 0
        [[ "$decision" == YES ]] || return 0
        local remote_script=''
        remote_script='p=/usr/local/libexec/solidgroundux/manage-web-server.sh; if [ -x "$p" ]; then exec sudo -n "$p" --action ensure-site --site-name "$1" --web-address "$2" --document-root "$3" --deployment-user "$4"; fi; echo "Remote manage-web-server.sh not installed at /usr/local/libexec/solidgroundux/" >&2; exit 127'
        # Same approved identity and SSH session used for publication.
        printf -v remote_command 'bash -c %q -- %q %q %q %q' "$remote_script" "$name" "$address" "$target" "$user"
        rc=0
        output="$("${ssh_args[@]}" "${user}@${host}" "$remote_command" 2>&1)" || rc=$?
        if (( rc != 0 )); then
            sayfail "Remote Nginx setup failed (exit $rc)."
            [[ -z "$output" ]] || sgnd_print --text "$output"
            return "$rc"
        fi
        sayok "Remote hosting setup completed for $address."
    }

    # fn: _web_publish_offer_dns - Run the existing Web Server DNS dialog remotely, on request.
        # . Purpose
        #   Run the existing Web Server DNS dialog remotely, on request.
        #
        # This requires an interactive SSH terminal and samba-tool on the remote web server.
        #
        # . Arguments
        #   - `$1`: Remote host or site name.
        #   - `$2`: User account.
        #   - `$3`: TCP port.
        #   - `$4`: SSH identity file.
        #   - `$5`: Website hostname whose DNS may need registration.
        # . Usage
        #   ```bash
        #   _web_publish_offer_dns "<host>" "example-user" "8080" "<identity>" "192.0.2.10"
        #   ```
    _web_publish_offer_dns() {
        local host="$1" user="$2" port="$3" identity="$4" address="$5"
        local decision="NO" ssh_identity="" remote_command="" rc=0
        [[ -n "$address" ]] || return 0
        [[ -t 0 ]] || { sayinfo "DNS registration skipped in noninteractive mode."; return 0; }
        ask_decision --label "Check/register internal DNS for $address on $host" --choices "Yes|Y,No|N" --default "No" --var decision || return 0
        [[ "$decision" == YES ]] || return 0
        local -a ssh_args=(ssh -tt -p "$port")
        if [[ -n "$identity" ]]; then ssh_identity="${identity/#\~\//$HOME/}"; ssh_args+=(-i "$ssh_identity"); fi
        local remote='p=/usr/local/libexec/solidgroundux/manage-web-server.sh; if [ -x "$p" ]; then exec sudo -n "$p" --action configure-dns --web-address "$1"; fi; echo "Remote web server module missing" >&2; exit 127'
        printf -v remote_command 'bash -c %q -- %q' "$remote" "$address"
        "${ssh_args[@]}" "${user}@${host}" "$remote_command" || rc=$?
        if (( rc != 0 )); then saywarning "DNS configuration was not completed (exit $rc); publication can proceed."; fi
        return 0
    }

    # fn: _web_publish_verify_http - Report DNS and HTTP availability after a successful deployment.
        # . Purpose
        #   Report DNS and HTTP availability after a successful deployment.
        #
        # Failure to resolve or serve is reported separately from a successful file transfer.
        #
        # . Arguments
        #   - `$1`: Website hostname for HTTP reachability verification.
        # . Usage
        #   ```bash
        #   _web_publish_verify_http "192.0.2.10"
        #   ```
    _web_publish_verify_http() {
        local address="$1" response="" resolved=""
        [[ -n "$address" ]] || return 0
        if command -v getent >/dev/null 2>&1; then
            resolved="$(getent ahostsv4 "$address" 2>/dev/null | awk 'NR==1 {print $1}')"
            [[ -n "$resolved" ]] && sayok "DNS resolved $address to $resolved." || saywarning "DNS cannot resolve $address from this machine."
        fi
        if command -v curl >/dev/null 2>&1; then
            response="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 10 -- "http://$address/" 2>/dev/null)"
            if [[ "$response" == 200 ]]; then
                sayok "HTTP verification passed: http://$address/ (200)."
            else
                saywarning "HTTP verification pending: http://$address/ (status ${response:-unreachable})."
            fi
        else
            sayinfo "HTTP verification unavailable (curl not installed)."
        fi
    }

# - Local import into staging -------------------------------------------------------
    # fn: _web_content_import_local - Review server-local files before copying to incoming.
        # . Purpose
        #   Review server-local files before copying to incoming.
        #
        # . Behavior
        #   - Previews every destination and conflict through the Python transfer planner.
        #   - Requires an explicit decision before copying, and leaves source files intact.
        #   - Does not ingest content or mark website generation pending.
        #
        # . Usage
        #   ```bash
        #   _web_content_import_local
        #   ```
    _web_content_import_local() {
        local input_path="" incoming="" policy="abort" decision="NO"
        local result_file="" rc=0 count="0" conflicts="" errors=""
        _web_content_select_source || return 0
        incoming="${SGND_WEB_CONTENT_SOURCE%/}/incoming"
        ask --label "Local file, ZIP or directory to copy" --var input_path --default "/tmp" --back || return 0
        [[ -n "$input_path" ]] || return 0
        ask --label "Incoming staging directory" --var incoming --default "$incoming" --back || return 0
        [[ -n "$incoming" ]] || return 0
        result_file="$(mktemp)" || { sayfail "Could not create import preview file."; return 1; }
        if ! _web_content_run_engine "$result_file" preview-local-import --input-path "$input_path" --incoming "$incoming" --conflict-policy abort; then
            conflicts="$(_web_content_result_value "$result_file" conflicts 2>/dev/null || true)"
            errors="$(_web_content_result_value "$result_file" errors 2>/dev/null || true)"
            if [[ -n "$errors" ]]; then
                _web_content_report_errors "$result_file"
                rm -f -- "$result_file"
                return 1
            fi
            if [[ -n "$conflicts" ]]; then
                saywarning "Existing incoming files detected:"
                while IFS= read -r line; do [[ -n "$line" ]] && sgnd_print --text "$line"; done <<< "$conflicts"
                ask_decision --label "Skip existing files and copy only new files?" --choices "Yes|Y,No|N" --default "No" --var decision || { rm -f -- "$result_file"; return 0; }
                [[ "$decision" == "YES" || "$decision" == "Y" ]] || { rm -f -- "$result_file"; return 0; }
                policy="skip"
                _web_content_run_engine "$result_file" preview-local-import --input-path "$input_path" --incoming "$incoming" --conflict-policy "$policy" || {
                    _web_content_report_errors "$result_file"
                    rm -f -- "$result_file"
                    return 1
                }
            else
                sayfail "Could not prepare local import preview."
                rm -f -- "$result_file"
                return 1
            fi
        fi
        count="$(_web_content_result_value "$result_file" copy_count 2>/dev/null || printf '0')"
        sayinfo "Import preview: $count new file(s) to $incoming (policy: $policy)."
        local planned=""
        planned="$(python3 - "$result_file" <<'PYCODE'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    data=json.load(f)
conflicts=set(data.get('conflicts', [])) if data.get('conflict_policy') == 'skip' else set()
from pathlib import Path
for item in data.get('files', []):
    destination=item['destination']
    if Path(destination).relative_to(data['incoming']).as_posix() not in conflicts:
        print(destination)
PYCODE
)" || { rm -f -- "$result_file"; return 1; }
        while IFS= read -r line; do [[ -n "$line" ]] && sgnd_print --text "$line"; done <<< "$planned"
        if [[ "$count" == "0" ]]; then
            sayinfo "Nothing new to copy."
            rm -f -- "$result_file"
            return 0
        fi
        decision="NO"
        ask_decision --label "Copy these files into Incoming?" --choices "Yes|Y,No|N" --default "No" --var decision || { rm -f -- "$result_file"; return 0; }
        if [[ "$decision" != "YES" && "$decision" != "Y" ]]; then
            sayinfo "Local import cancelled; no files copied."
            rm -f -- "$result_file"
            return 0
        fi
        if _web_content_run_engine "$result_file" import-to-incoming --input-path "$input_path" --incoming "$incoming" --conflict-policy "$policy" --confirm; then
            sayok "Local files copied to Incoming. Use Ingest to accept content into the website."
        else
            rc=$?
            _web_content_report_errors "$result_file"
        fi
        rm -f -- "$result_file"
        return "$rc"
    }

# - Safe staged package ingestion ---------------------------------------------------
    # fn: _web_content_ingest_incoming - Preview and confirm ingestion of one staged package.
        # . Purpose
        #   Preview and confirm ingestion of one staged package.
        #
        # . Behavior
        #   - Only accepts a path inside the selected website's incoming directory.
        #   - Reports every destination and conflict; never overwrites existing files.
        #   - Preserves the staged originals and requires explicit confirmation.
        #
        # . Usage
        #   ```bash
        #   _web_content_ingest_incoming
        #   ```
    _web_content_ingest_incoming() {
        local incoming="" input_path="" result_file="" policy="abort" decision="NO"
        local conflicts="" errors="" files="" rc=0
        _web_content_select_source || return 0
        incoming="${SGND_WEB_CONTENT_SOURCE%/}/incoming"
        # Select ONE staged package. The incoming root is an inbox, not a package:
        # treating it as a directory previously copied ZIPs and .gitignore into content.
        local -a packages=() choices=()
        local candidate="" selected=""
        [[ -d "$incoming" ]] || { saywarning "Incoming directory not found: $incoming"; return 0; }
        shopt -s nullglob
        for candidate in "$incoming"/*; do
            # Successfully committed packages are kept under archive/, which
            # must never be offered again as an active incoming package.
            [[ "${candidate##*/}" == "archive" ]] && continue
            [[ -f "$candidate" || -d "$candidate" ]] || continue
            [[ -L "$candidate" ]] && continue
            packages+=("${candidate##*/}")
        done
        shopt -u nullglob
        if (( ${#packages[@]} == 0 )); then
            sayinfo "No staged packages in $incoming"
            return 0
        fi
        ask_selection --label "Select one incoming package" --var selected --items "${packages[@]}" || return 0
        [[ -n "$selected" ]] || return 0
        # Reject paths and control files even if the selection API changes.
        [[ "$selected" != .* && "$selected" != */* && "$selected" != *'..'* ]] || {
            sayfail "Invalid incoming package selection"; return 1;
        }
        input_path="$incoming/$selected"
        result_file="$(mktemp)" || return 1
        if ! _web_content_run_engine "$result_file" preview-incoming-ingest --input-path "$input_path" --source "$SGND_WEB_CONTENT_SOURCE" --conflict-policy abort; then
            errors="$(_web_content_result_value "$result_file" errors 2>/dev/null || true)"
            conflicts="$(_web_content_result_value "$result_file" conflicts 2>/dev/null || true)"
            if [[ -n "$errors" ]]; then
                _web_content_report_errors "$result_file"
                rm -f -- "$result_file"
                return 1
            fi
            if [[ -n "$conflicts" ]]; then
                saywarning "Existing content files detected:"
                while IFS= read -r line; do [[ -n "$line" ]] && sgnd_print --text "$line"; done <<< "$conflicts"
                ask_decision --label "Skip existing files and ingest only new files?" --choices "Yes|Y,No|N" --default "No" --var decision || { rm -f -- "$result_file"; return 0; }
                [[ "$decision" == "YES" || "$decision" == "Y" ]] || { rm -f -- "$result_file"; return 0; }
                policy="skip"
                _web_content_run_engine "$result_file" preview-incoming-ingest --input-path "$input_path" --source "$SGND_WEB_CONTENT_SOURCE" --conflict-policy skip || {
                    _web_content_report_errors "$result_file"; rm -f -- "$result_file"; return 1;
                }
            else
                _web_content_report_errors "$result_file"
                rm -f -- "$result_file"
                return 1
            fi
        fi
        files="$(_web_content_result_value "$result_file" files 2>/dev/null || true)"
        sayinfo "Content ingestion preview (policy: $policy):"
        while IFS= read -r line; do [[ -n "$line" ]] && sgnd_print --text "$line"; done <<< "$files"
        decision="NO"
        ask_decision --label "Accept this package into website content?" --choices "Yes|Y,No|N" --default "No" --var decision || { rm -f -- "$result_file"; return 0; }
        if [[ "$decision" == "YES" || "$decision" == "Y" ]]; then
            if _web_content_run_engine "$result_file" ingest-incoming --input-path "$input_path" --source "$SGND_WEB_CONTENT_SOURCE" --conflict-policy "$policy" --confirm; then
                sayok "Package ingestion completed. Validate and generate the website before publishing."
                local archived_to="" archive_warning=""
                archived_to="$(_web_content_result_value "$result_file" archived_to 2>/dev/null || true)"
                archive_warning="$(_web_content_result_value "$result_file" archive_warning 2>/dev/null || true)"
                [[ -z "$archived_to" ]] || sayinfo "Incoming package archived to: $archived_to"
                [[ -z "$archive_warning" ]] || saywarning "$archive_warning"
            else
                rc=$?
                _web_content_report_errors "$result_file"
            fi
        else
            sayinfo "Ingestion cancelled; content unchanged."
        fi
        rm -f -- "$result_file"
        return "$rc"
    }

# - GitHub Pages documentation deployment --------------------------------------------
    # fn: _web_content_github_pages_configure - Save local Pages deployment paths.
        # . Purpose
        #   Choose the already-generated documentation HTML and the checked-out
        #   SolidGroundUX repository, without any Markdown or remote website profile.
        # . Returns
        #   - 0 on completion; 2 when the operator cancels a prompt.
        # . Usage
        #   ```bash
        #   _web_content_github_pages_configure
        #   ```
    _web_content_github_pages_configure() {
        local selected_source="${SGND_WEB_GITHUB_SOURCE:-${SGND_WEB_CONTENT_OUTPUT%/}}"
        local selected_repo="${SGND_WEB_GITHUB_REPO:-}"
        ask --label "Generated documentation HTML" --var selected_source --default "$selected_source" --back || return 2
        ask --label "SolidGroundUX Git repository root" --var selected_repo --default "$selected_repo" --back || return 2
        [[ -n "$selected_source" && -n "$selected_repo" ]] || {
            sayfail "Both the generated website and the repository root are required."
            return 1
        }
        SGND_WEB_GITHUB_SOURCE="$selected_source"
        SGND_WEB_GITHUB_REPO="$selected_repo"
        return 0
    }

    # fn: _web_content_github_pages_rebase - Adapt the API search to GitHub Pages' subpath.
        # . Purpose
        #   The WebContent generator already writes relative HTML links, but the
        #   documentation API search script and JSON still use site-root paths.
        #   Change those paths only inside the Pages copy, not the original output.
        # . Arguments
        #   - `$1` — Checked-out GitHub Pages docs directory.
        # . Returns
        #   - 0 on success; nonzero if a present API search resource cannot be adapted.
        # . Usage
        #   ```bash
        #   _web_content_github_pages_rebase "$docs_dir"
        #   ```
    _web_content_github_pages_rebase() {
        local docs_dir="${1:?missing docs directory}"
        python3 - "$docs_dir" <<'PY_GITHUB_PAGES'
import json
import sys
from pathlib import Path

site = Path(sys.argv[1])
base = '/SolidGroundUX'
script = site / 'js' / 'sgnd-api-index.js'
if script.is_file():
    value = script.read_text(encoding='utf-8')
    old = "fetch('/assets/sgnd-api-index.json')"
    new = f"fetch('{base}/assets/sgnd-api-index.json')"
    if old in value:
        script.write_text(value.replace(old, new), encoding='utf-8')
    elif new not in value:
        raise RuntimeError('Unrecognized documentation API search script URL')

index = site / 'assets' / 'sgnd-api-index.json'
if index.is_file():
    records = json.loads(index.read_text(encoding='utf-8'))
    if not isinstance(records, list):
        raise ValueError('Documentation API search index must be an array')
    for record in records:
        if not isinstance(record, dict):
            raise ValueError('Invalid documentation API search entry')
        url = record.get('url')
        if isinstance(url, str) and url.startswith('/') and not url.startswith('//') and not url.startswith(base + '/'):
            record['url'] = base + url
    index.write_text(json.dumps(records, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
PY_GITHUB_PAGES
    }

    # fn: _web_content_github_pages_push - Publish documentation to main/docs.
        # . Purpose
        #   Reuse the generated HTML, commit only the Framework repository's docs
        #   directory, and push it to the existing GitHub Pages branch.
        # . Behavior
        #   - Verifies the source is a generated SolidGroundUX documentation site.
        #   - Rejects a wrong Git remote, wrong branch, symlinks, and dirty docs.
        #   - Never stages or commits changes outside docs/.
        #   - GitHub Pages builds the result from main/docs; no GitHub API is used.
        # . Returns
        #   - 0 on success; nonzero for invalid paths or failed copy/commit/push.
        # . Usage
        #   ```bash
        #   _web_content_github_pages_push
        #   ```
    _web_content_github_pages_push() {
        local source="" repo="" docs="" branch="" origin=""
        local pending=""
        command -v git >/dev/null 2>&1 || { sayfail "Git is not installed."; return 127; }
        command -v rsync >/dev/null 2>&1 || { sayfail "rsync is not installed."; return 127; }
        command -v python3 >/dev/null 2>&1 || { sayfail "Python 3 is not installed."; return 127; }
        source="$(realpath -e -- "$SGND_WEB_GITHUB_SOURCE")" || { sayfail "Generated documentation directory not found."; return 1; }
        repo="$(realpath -e -- "$SGND_WEB_GITHUB_REPO")" || { sayfail "SolidGroundUX repository directory not found."; return 1; }
        # WCM generates a root homepage; bundle introductions and prefaces are
        # placed in the documentation hierarchy, not introduction/index.html.
        [[ -d "$source" && -f "$source/index.html" ]] || {
            sayfail "The selected source does not contain a generated website homepage (index.html)."
            return 1
        }
        grep -qi 'SolidGroundUX' "$source/index.html" || {
            sayfail "The generated homepage does not identify SolidGroundUX documentation."
            return 1
        }
        [[ -z "$(find "$source" -type l -print -quit)" ]] || {
            sayfail "Generated documentation contains symbolic links; refusing to publish files outside its root."
            return 1
        }
        [[ "$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" == "$repo" ]] || {
            sayfail "The destination must be the root of a checked-out Git repository."
            return 1
        }
        branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
            sayfail "Check out the main branch before publishing GitHub Pages."
            return 1
        }
        [[ "$branch" == "main" ]] || { sayfail "GitHub Pages uses main/docs. Current branch is $branch."; return 1; }
        origin="$(git -C "$repo" remote get-url origin 2>/dev/null)" || {
            sayfail "Git remote 'origin' is not configured."
            return 1
        }
        case "${origin%.git}" in
            */SolidGroundUX|*:SolidGroundUX) ;;
            *) sayfail "The origin remote does not identify the SolidGroundUX repository: $origin"; return 1 ;;
        esac
        docs="$repo/docs"
        [[ ! -L "$docs" ]] || { sayfail "Refusing to deploy into a symbolic-link docs directory."; return 1; }
        # The generated HTML must not be inside the destination (or vice versa).
        [[ "$source" != "$docs" && "$source" != "$docs/"* && "$docs" != "$source/"* ]] || {
            sayfail "The generated site and the repository docs directory must be separate."
            return 1
        }
        pending="$(git -C "$repo" status --porcelain -- docs)" || return 1
        [[ -z "$pending" ]] || {
            sayfail "Repository docs/ contains uncommitted changes. Commit or restore them before replacing the Pages site."
            return 1
        }
        git -C "$repo" diff --cached --quiet || {
            sayfail "Other Git changes are staged. Commit or unstage them before publishing."
            return 1
        }
        mkdir -p -- "$docs" || { sayfail "Cannot create the docs directory."; return 1; }
        rsync -a --delete --exclude='.git' -- "$source/" "$docs/" || {
            sayfail "Could not synchronize the generated site into docs/."
            return 1
        }
        # GitHub Pages must serve generated assets beginning with underscores.
        touch -- "$docs/.nojekyll" || return 1
        _web_content_github_pages_rebase "$docs" || {
            sayfail "GitHub Pages URL adjustment failed; the generated HTML was not committed."
            return 1
        }
        git -C "$repo" add -A -- docs || { sayfail "Could not stage docs/."; return 1; }
        if ! git -C "$repo" diff --cached --quiet -- docs; then
            git -C "$repo" commit -m 'Update generated SolidGroundUX documentation for GitHub Pages' -- docs || {
                sayfail "Git commit failed. No push attempted."
                return 1
            }
        else
            sayinfo "Generated documentation is unchanged; checking the GitHub remote."
        fi
        git -C "$repo" push origin main || { sayfail "GitHub push failed. The local Git commit is retained for retry."; return 1; }
        sayok "GitHub Pages documentation pushed to main/docs."
        sgnd_print_labeledvalue --label "GitHub Pages" --value "https://testadura-consultancy.github.io/SolidGroundUX/" --labelwidth 22
        return 0
    }

    # fn: _web_content_publish_github_pages - Review paths and choose Push or Modify.
        # . Purpose
        #   Publish only generated documentation to the existing Pages location.
        #   Retain paths in ordinary SolidGroundUX state variables.
        # . Returns
        #   - 0 on successful push or operator cancellation; nonzero on failure.
        # . Usage
        #   ```bash
        #   _web_content_publish_github_pages
        #   ```
    _web_content_publish_github_pages() {
        local choice="" rc=0
        if [[ -z "$SGND_WEB_GITHUB_SOURCE" || -z "$SGND_WEB_GITHUB_REPO" ]]; then
            _web_content_github_pages_configure || {
                rc=$?
                (( rc == 2 )) && return 0
                return "$rc"
            }
        fi
        while :; do
            sgnd_print
            sgnd_print_sectionheader --text "Push to GitHub Pages"
            sgnd_print_labeledvalue --label "Generated HTML" --value "$SGND_WEB_GITHUB_SOURCE" --labelwidth 22
            sgnd_print_labeledvalue --label "Git repository" --value "$SGND_WEB_GITHUB_REPO" --labelwidth 22
            sgnd_print_labeledvalue --label "Pages location" --value "main:/docs" --labelwidth 22
            ask_selection --label "Action" --var choice --items "Push" "Modify" || return 0
            case "$choice" in
                Push) _web_content_github_pages_push; return $? ;;
                Modify)
                    _web_content_github_pages_configure || {
                        rc=$?
                        (( rc == 2 )) && return 0
                        return "$rc"
                    }
                    ;;
                *) return 0 ;;
            esac
        done
    }

# - Named website publishing profiles -----------------------------------------------
    # fn: _web_profiles_tool - Run the non-interactive Framework profile store.
        # . Purpose
        #   Access WCM profile data in the resolved Framework tree.
        # . Returns
        #   Exit status of the profile store, or 127 if it is absent.
        # . Usage
        #   ```bash
        #   _web_profiles_tool list
        #   ```
    _web_profiles_tool() {
        local helper="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/py/sgnd_deployment_profiles.py"
        [[ -r "$helper" ]] || { sayfail "Framework profile store missing: $helper"; return 127; }
        # Preserve the framework's effective user home under elevated launchers.
        if [[ -z "${XDG_CONFIG_HOME:-}" && -n "${SGND_USER_HOME:-}" ]]; then
            SGND_PROFILE_HOME="$SGND_USER_HOME" python3 "$helper" wcm "$@"
        else
            python3 "$helper" wcm "$@"
        fi
    }

    # fn: _web_profiles_migrate - Preserve ordinary 2631102 publishing state once.
        # . Purpose
        #   Import the last configured SSH website without reading obsolete Base64 data.
        # . Usage
        #   ```bash
        #   _web_profiles_migrate
        #   ```
    _web_profiles_migrate() {
        _web_profiles_tool migrate --migration-id 'wcm-state-2631102' \
            --field "source=${SGND_WEB_PUBLISH_SOURCE:-}" \
            --field "host=${SGND_WEB_PUBLISH_HOST:-}" \
            --field "user=${SGND_WEB_PUBLISH_USER:-}" \
            --field "port=${SGND_WEB_PUBLISH_PORT:-22}" \
            --field "identity=${SGND_WEB_PUBLISH_IDENTITY:-}" \
            --field "path=${SGND_WEB_PUBLISH_REMOTE_DIR:-}" \
            --field "hostname=${SGND_WEB_PUBLISH_HOSTNAME:-}" \
            --field "website=${SGND_WEB_PUBLISH_HOSTNAME:-Website}" \
            --field "strategy=${SGND_WEB_PUBLISH_STRATEGY:-Update}" >/dev/null
    }

    # fn: _web_profiles_read_record - Read a saved profile without selecting it.
        # . Purpose
        #   Populate an associative array from the validated NUL-delimited profile store.
        # . Arguments
        #   $1 Profile name; $2 destination associative array variable.
        # . Returns
        #   0 on success; nonzero when the record cannot be read.
        # . Usage
        #   ```bash
        #   local -A record=()
        #   _web_profiles_read_record Development record
        #   ```
    _web_profiles_read_record() {
        local name="$1" destination="$2" buffer="" i=0
        local -a fields=()
        local -n record_ref="$destination"
        record_ref=()
        buffer="$(mktemp)" || return 1
        if ! _web_profiles_tool get --name "$name" > "$buffer"; then
            rm -f -- "$buffer"
            return 1
        fi
        mapfile -d '' -t fields < "$buffer"
        rm -f -- "$buffer"
        (( ${#fields[@]} % 2 == 0 )) || return 1
        for (( i=0; i<${#fields[@]}; i+=2 )); do
            record_ref["${fields[$i]}"]="${fields[$((i+1))]}"
        done
    }

    # fn: _web_profiles_restore_selection - Display the persisted profile at menu entry.
        # . Purpose
        #   Restore the selected destination without altering the profile store.
        #   Optional 'persisted' ignores the one-time CLI --profile override.
        # . Usage
        #   ```bash
        #   _web_profiles_restore_selection
        #   _web_profiles_restore_selection persisted
        #   ```
    _web_profiles_restore_selection() {
        local name=""
        if [[ -n "${WEB_PROFILE_ARG:-}" && "${1:-}" != persisted ]]; then
            name="$WEB_PROFILE_ARG"
        else
            name="$(_web_profiles_tool selected)" || return $?
        fi
        WEB_ACTIVE_PROFILE=''
        WEB_PROFILE_WEBSITE=''
        [[ -z "$name" ]] || _web_profiles_load "$name"
    }

    # fn: _web_profiles_load - Load a named destination without executing profile code.
        # . Purpose
        #   Populate publishing settings from a validated NUL-delimited record.
        # . Arguments
        #   $1 Profile name.
        # . Usage
        #   ```bash
        #   _web_profiles_load 'HQ'
        #   ```
    _web_profiles_load() {
        local name="$1" buffer="" i=0 key="" value=""
        local -a fields=()
        buffer="$(mktemp)" || return 1
        if ! _web_profiles_tool get --name "$name" > "$buffer"; then rm -f -- "$buffer"; return 1; fi
        mapfile -d '' -t fields < "$buffer"
        rm -f -- "$buffer"
        (( ${#fields[@]} % 2 == 0 )) || return 1
        for (( i=0; i<${#fields[@]}; i+=2 )); do
            key="${fields[$i]}"; value="${fields[$((i+1))]}"
            case "$key" in
                website) WEB_PROFILE_WEBSITE="$value" ;;
                method) SGND_WEB_PUBLISH_METHOD="${value:-rsync}" ;;
                source) SGND_WEB_PUBLISH_SOURCE="$value" ;;
                host) SGND_WEB_PUBLISH_HOST="$value" ;;
                user) SGND_WEB_PUBLISH_USER="$value" ;;
                port) SGND_WEB_PUBLISH_PORT="${value:-22}" ;;
                identity) SGND_WEB_PUBLISH_IDENTITY="$value" ;;
                path) SGND_WEB_PUBLISH_REMOTE_DIR="$value" ;;
                hostname) SGND_WEB_PUBLISH_HOSTNAME="$value" ;;
                strategy) SGND_WEB_PUBLISH_STRATEGY="${value:-Update}" ;;
                manage_site) SGND_WEB_PUBLISH_MANAGE_SITE="${value:-No}" ;;
                preview_port) SGND_WEB_PUBLISH_PREVIEW_PORT="${value:-8080}" ;;
                url) WEB_PROFILE_URL="$value" ;;
                last_success) WEB_PROFILE_LAST_SUCCESS="$value" ;;
            esac
        done
        WEB_ACTIVE_PROFILE="$name"
        return 0
    }

    # fn: _web_profiles_save - Save a website/destination pair atomically.
        # . Purpose
        #   Save validated settings for one publication destination in the Framework store.
        # . Usage
        #   ```bash
        #   _web_profiles_save 'Development'
        #   ```
    _web_profiles_save() {
        local name="$1"
        _web_profiles_tool save --name "$name" \
            --field "website=${WEB_PROFILE_WEBSITE:-Website}" \
            --field "method=${SGND_WEB_PUBLISH_METHOD:-rsync}" \
            --field "source=${SGND_WEB_PUBLISH_SOURCE:-}" \
            --field "host=${SGND_WEB_PUBLISH_HOST:-}" \
            --field "user=${SGND_WEB_PUBLISH_USER:-}" \
            --field "port=${SGND_WEB_PUBLISH_PORT:-22}" \
            --field "identity=${SGND_WEB_PUBLISH_IDENTITY:-}" \
            --field "path=${SGND_WEB_PUBLISH_REMOTE_DIR:-}" \
            --field "hostname=${SGND_WEB_PUBLISH_HOSTNAME:-}" \
            --field "strategy=${SGND_WEB_PUBLISH_STRATEGY:-Update}" \
            --field "manage_site=${SGND_WEB_PUBLISH_MANAGE_SITE:-No}" \
            --field "preview_port=${SGND_WEB_PUBLISH_PREVIEW_PORT:-8080}" \
            --field "url=${WEB_PROFILE_URL:-}" || return $?
        _web_profiles_tool select --name "$name" || return $?
        WEB_ACTIVE_PROFILE="$name"
    }

    # fn: _web_profiles_choose - Choose an existing website publishing destination.
        # . Purpose
        #   Offer names grouped by their website, without preselecting a destination.
        # . Usage
        #   ```bash
        #   _web_profiles_choose
        #   ```
    _web_profiles_choose() {
        _web_profiles_prompt_name || return $?
        _web_profiles_load "$WEB_CHOSEN_PROFILE" || return $?
        _web_profiles_tool select --name "$WEB_CHOSEN_PROFILE"
    }

    # fn: _web_profiles_prompt_name - Choose a profile without activating it.
        # . Purpose
        #   Offer website-grouped choices for read-only viewing and connection checks.
        # . Returns
        #   0 when WEB_CHOSEN_PROFILE contains a saved name; 2 on cancellation.
        # . Usage
        #   ```bash
        #   _web_profiles_prompt_name
        #   ```
    _web_profiles_prompt_name() {
        local buffer="" choice="" row="" index=0
        local -a names=() labels=()
        WEB_CHOSEN_PROFILE=''
        buffer="$(mktemp)" || return 1
        if ! _web_profiles_tool list --display > "$buffer"; then rm -f -- "$buffer"; return 1; fi
        mapfile -t names < "$buffer"
        rm -f -- "$buffer"
        (( ${#names[@]} )) || { saywarning 'No publishing profiles have been created.'; return 2; }
        for row in "${names[@]}"; do labels+=("${row%%$'\t'*} / ${row#*$'\t'}"); done
        ask_selection --label 'Website publishing profile' --var choice --items "${labels[@]}" || return 2
        for index in "${!labels[@]}"; do
            if [[ "${labels[$index]}" == "$choice" ]]; then
                WEB_CHOSEN_PROFILE="${names[$index]#*$'\t'}"
                return 0
            fi
        done
        return 1
    }

    # fn: _web_profiles_list - Show all saved website publishing destinations.
        # . Purpose
        #   Display grouped website, profile, method, destination and last publication;
        #   mark the active profile without modifying any profile or selection.
        # . Usage
        #   ```bash
        #   _web_profiles_list
        #   ```
    _web_profiles_list() {
        local buffer="" name="" active="" method="" destination="" last="" value="" website=""
        local -a names=() profile_rows=()
        local -A record=()
        buffer="$(mktemp)" || return 1
        if ! _web_profiles_tool list > "$buffer"; then rm -f -- "$buffer"; return 1; fi
        mapfile -t names < "$buffer"
        rm -f -- "$buffer"
        sgnd_print_sectionheader --text 'Publishing Profiles'
        if (( ${#names[@]} == 0 )); then
            sayinfo 'No publishing profiles have been created.'
            return 0
        fi
        active="$(_web_profiles_tool selected)" || return $?
        for name in "${names[@]}"; do
            _web_profiles_read_record "$name" record || return $?
            method="${record[method]:-rsync}"
            case "$method" in
                preview) method='Local preview'; destination="${record[path]:-}" ;;
                rsync) method='SSH / rsync'; destination="${record[user]:-}@${record[host]:-}:${record[path]:-}" ;;
                ftp|ftps|sftp) method="${method^^}"; destination="${record[host]:-}:${record[path]:-}" ;;
            esac
            last="${record[last_success]:--}"
            last="${last/T/ }"
            value="$name"
            [[ "$name" != "$active" ]] || value="* $name"
            # DataTable uses | as the column delimiter; literal profile data cannot split rows.
            website="${record[website]:-Website}"
            profile_rows+=("${website//|/¦}|${value//|/¦}|${method//|/¦}|${destination//|/¦}|${last//|/¦}")
        done
        sgnd_dt_print_table 'Website|Profile|Method|Destination|Last published' profile_rows 1 || return $?
        sgnd_print_labeledvalue --label 'Selected profile' --value "${active:-None}"
    }

    # fn: _web_profiles_view - Show one saved destination without selecting it.
        # . Purpose
        #   Display the complete non-secret profile configuration and publication date.
        # . Arguments
        #   $1 Name of saved profile.
        # . Usage
        #   ```bash
        #   _web_profiles_view Hostnet
        #   ```
    _web_profiles_view() {
        local name="$1" method="" selected=""
        local -A record=()
        _web_profiles_read_record "$name" record || return $?
        selected="$(_web_profiles_tool selected)" || return $?
        method="${record[method]:-rsync}"
        sgnd_print_sectionheader --text 'View Publishing Profile'
        sgnd_print_labeledvalue --label 'Website' --value "${record[website]:-Website}"
        sgnd_print_labeledvalue --label 'Profile' --value "$name"
        sgnd_print_labeledvalue --label 'Selected' --value "$( [[ "$name" == "$selected" ]] && printf Yes || printf No )"
        sgnd_print_labeledvalue --label 'Method' --value "$method"
        sgnd_print_labeledvalue --label 'Generated HTML' --value "${record[source]:-Not configured}"
        sgnd_print_labeledvalue --label 'Target directory' --value "${record[path]:-Not configured}"
        if [[ "$method" == preview ]]; then
            sgnd_print_labeledvalue --label 'Preferred HTTP port' --value "${record[preview_port]:-8080}"
            sgnd_print_labeledvalue --label 'Preview URL' --value "${record[url]:-Assigned when local server starts}"
        else
            sgnd_print_labeledvalue --label 'Destination host' --value "${record[host]:-Not configured}"
            sgnd_print_labeledvalue --label 'Destination user' --value "${record[user]:-Not configured}"
            sgnd_print_labeledvalue --label 'Transport port' --value "${record[port]:-22}"
            if [[ "$method" == rsync || "$method" == sftp ]]; then
                sgnd_print_labeledvalue --label 'SSH identity' --value "${record[identity]:-Default SSH identity}"
            fi
            sgnd_print_labeledvalue --label 'Public hostname' --value "${record[hostname]:-Not configured}"
            sgnd_print_labeledvalue --label 'Nginx/DNS management' --value "${record[manage_site]:-No}"
        fi
        sgnd_print_labeledvalue --label 'Synchronization' --value "${record[strategy]:-Update}"
        sgnd_print_labeledvalue --label 'Last published' --value "${record[last_success]:-Never}"
    }

    # fn: _web_profiles_test_connection - Verify destination access without publishing.
        # . Purpose
        #   Check local preview paths, SSH authentication/rsync/target permissions, or
        #   FTP/FTPS/SFTP directory access using the configured transport.
        #   Never creates files, starts servers, or changes Nginx/DNS settings.
        # . Arguments
        #   $1 Name of the profile to verify, selected or otherwise.
        # . Returns
        #   0 for a successful check; nonzero if access or prerequisites failed.
        # . Usage
        #   ```bash
        #   _web_profiles_test_connection Hostnet
        #   ```
    _web_profiles_test_connection() {
        local name="$1" method="" source="" target="" host="" user="" port="" identity=""
        local ancestor="" escaped="" remote_command="" endpoint="" result=0
        local ssh_diagnostic="" ssh_line="" shown=0
        local -a ssh_args=() curl_args=()
        local -A record=()
        _web_profiles_read_record "$name" record || return $?
        method="${record[method]:-rsync}"
        source="${record[source]:-}"
        target="${record[path]:-}"
        host="${record[host]:-}"
        user="${record[user]:-}"
        port="${record[port]:-22}"
        identity="${record[identity]:-}"
        sgnd_print_sectionheader --text 'Test Publishing Connection'
        sgnd_print_labeledvalue --label 'Website' --value "${record[website]:-Website}"
        sgnd_print_labeledvalue --label 'Profile' --value "$name"
        sgnd_print_labeledvalue --label 'Method' --value "$method"
        if [[ "$method" == preview ]]; then
            [[ -d "$source" && -r "${source%/}/index.html" ]] || {
                sayfail 'Generated website directory or readable index.html is missing.'
                return 1
            }
            _web_publish_safe_path "$target" || { sayfail 'Invalid local target directory.'; return 1; }
            [[ ! -L "$target" ]] || { sayfail 'Local target is a symbolic link.'; return 1; }
            ancestor="$target"
            while [[ ! -e "$ancestor" && "$ancestor" != / ]]; do
                ancestor="$(dirname -- "$ancestor")"
            done
            [[ -d "$ancestor" && -w "$ancestor" && -x "$ancestor" ]] || {
                sayfail "Local target or its parent is not writable: $ancestor"
                return 1
            }
            command -v rsync >/dev/null 2>&1 || { sayfail 'rsync is missing.'; return 127; }
            sayok 'Local preview source and destination are accessible (server not started).'
            return 0
        fi
        [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { sayfail 'Invalid destination host.'; return 1; }
        [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port > 0 && 10#$port <= 65535 )) || {
            sayfail 'Invalid transport port.'
            return 1
        }
        if [[ "$method" == rsync ]]; then
            [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || { sayfail 'Invalid SSH user.'; return 1; }
            _web_publish_safe_path "$target" || { sayfail 'Invalid SSH target directory.'; return 1; }
            command -v ssh >/dev/null 2>&1 || { sayfail 'SSH client is missing.'; return 127; }
            # Use the same dedicated agent discovery and SSH policy as publishing.
            # A connection check never starts an agent or offers key installation.
            _web_publish_load_ssh_helper || return $?
            sgnd_ssh_agent_discover || true
            ssh_args=(ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -p "$port")
            if [[ -n "$identity" ]]; then
                identity="${identity/#\~\//$HOME/}"
                [[ -r "$identity" ]] || { sayfail 'SSH identity is not readable.'; return 1; }
                ssh_args+=(-i "$identity")
            fi
            printf -v escaped '%q' "$target"
            remote_command="command -v rsync >/dev/null 2>&1 || exit 20; test -d $escaped || exit 21; test -w $escaped || exit 22"
            ssh_diagnostic="$("${ssh_args[@]}" -- "${user}@${host}" "$remote_command" 2>&1)" || result=$?
            case "$result" in
                0) sayok 'SSH authentication, remote rsync, and writable destination verified.'; return 0 ;;
                20) sayfail 'Connected over SSH, but rsync is not installed on the server.' ;;
                21) sayfail 'Connected over SSH, but the remote directory does not exist.' ;;
                22) sayfail 'Connected over SSH, but the remote directory is not writable.' ;;
                *) sayfail "SSH connection or authentication failed (exit $result)." ;;
            esac
            # Preserve actionable SSH diagnostics instead of hiding them. Limit
            # output and remove control characters before passing it to the UI.
            while IFS= read -r ssh_line && (( shown < 4 )); do
                ssh_line="${ssh_line//[$'\001'-$'\010'$'\013'$'\014'$'\016'-$'\037'$'\177']/}"
                [[ -z "$ssh_line" ]] || { saywarning "SSH: ${ssh_line:0:240}"; shown=$((shown+1)); }
            done <<< "$ssh_diagnostic"
            return 1
        fi
        if [[ "$method" == ftp || "$method" == ftps || "$method" == sftp ]]; then
            _web_publish_safe_external_path "$target" || { sayfail 'Invalid hosting directory.'; return 1; }
            [[ "$user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@+-]*$ ]] || { sayfail 'Invalid hosting user.'; return 1; }
            command -v curl >/dev/null 2>&1 || { sayfail 'curl is missing.'; return 127; }
            endpoint="${method}://${host}:${port}${target%/}/"
            curl_args=(curl --fail --silent --show-error --list-only --connect-timeout 8 --max-time 25)
            if [[ "$method" == ftp || "$method" == ftps ]]; then
                [[ -f "${HOME}/.netrc" ]] || { sayfail 'FTP credentials in ~/.netrc are missing.'; return 1; }
                curl_args+=(--netrc-file "$HOME/.netrc")
                [[ "$method" != ftps ]] || curl_args+=(--ssl-reqd)
            else
                curl_args+=(--user "${user}:")
                if [[ -n "$identity" ]]; then
                    identity="${identity/#\~\//$HOME/}"
                    [[ -r "$identity" ]] || { sayfail 'SSH identity is not readable.'; return 1; }
                    curl_args+=(--key "$identity")
                fi
            fi
            if "${curl_args[@]}" "$endpoint" >/dev/null; then
                sayok 'Hosting authentication and directory listing verified (no upload performed).'
                return 0
            fi
            sayfail 'Hosting connection or directory listing failed; verify credentials and permissions.'
            return 1
        fi
        sayfail "Unsupported publication method: $method"
        return 1
    }

    # fn: _web_profiles_select_nginx_site - Select an existing remote Nginx root.
        # . Purpose
        #   Optionally reuse an active Nginx hostname and document root on the SSH host.
        # . Arguments
        #   $1 host; $2 user; $3 port; $4 identity.
        # . Usage
        #   ```bash
        #   _web_profiles_select_nginx_site td-web sysadmin 22 ''
        #   ```
    _web_profiles_select_nginx_site() {
        local host="$1" user="$2" port="$3" identity="$4" file="" chosen="" row=""
        local -a sites=() labels=()
        _web_publish_prepare_ssh "$user" "$host" "$port" "${identity/#\~\//$HOME/}" || return $?
        file="$(mktemp)" || return 1
        if ! _web_publish_discover_sites "$host" "$user" "$port" "$identity" > "$file"; then
            rm -f -- "$file"
            saywarning 'Unable to list active Nginx websites; enter the target manually.'
            return 1
        fi
        mapfile -t sites < "$file"
        rm -f -- "$file"
        (( ${#sites[@]} )) || { saywarning 'No named Nginx websites found.'; return 1; }
        for row in "${sites[@]}"; do labels+=("${row%%$'\t'*} : ${row#*$'\t'}"); done
        ask_selection --label 'Existing website' --var chosen --items "${labels[@]}" || return 2
        local index=0
        for index in "${!labels[@]}"; do
            if [[ "${labels[$index]}" == "$chosen" ]]; then
                WEB_DISCOVERED_HOSTNAME="${sites[$index]%%$'\t'*}"
                WEB_DISCOVERED_TARGET="${sites[$index]#*$'\t'}"
                return 0
            fi
        done
        return 1
    }

    # fn: _web_profiles_configure - Configure a named local or remote destination.
        # . Purpose
        #   Collect one website, destination, protocol, and optional server management.
        # . Returns
        #   0 saved, 2 cancelled, nonzero on invalid configuration.
        # . Usage
        #   ```bash
        #   _web_profiles_configure 'Development'
        #   ```
    _web_profiles_configure() {
        local name="$1" method="" source="${SGND_WEB_PUBLISH_SOURCE:-${SGND_WEB_CONTENT_OUTPUT%/}}"
        local website="${WEB_PROFILE_WEBSITE:-}" host="${SGND_WEB_PUBLISH_HOST:-}" user="${SGND_WEB_PUBLISH_USER:-${USER:-}}"
        local port="${SGND_WEB_PUBLISH_PORT:-22}" target="${SGND_WEB_PUBLISH_REMOTE_DIR:-}" hostname="${SGND_WEB_PUBLISH_HOSTNAME:-}"
        local strategy="${SGND_WEB_PUBLISH_STRATEGY:-Update}" manage="${SGND_WEB_PUBLISH_MANAGE_SITE:-No}"
        local preview_port="${SGND_WEB_PUBLISH_PREVIEW_PORT:-8080}" url="${WEB_PROFILE_URL:-}" identity="${SGND_WEB_PUBLISH_IDENTITY:-}"
        if [[ "${2:-}" == create ]]; then
            # A new website must not inherit a selected destination's server/root.
            website=''; host=''; user="${USER:-}"; port=22; target=''; hostname=''
            identity=''; strategy=Update; manage=No; preview_port=8080; url=''
        fi
        ask --label 'Website name' --var website --default "$website" --back || return 2
        [[ -n "$website" ]] || { sayfail 'Website name is required.'; return 1; }
        method="${SGND_WEB_PUBLISH_METHOD:-rsync}"
        case "$method" in
            preview) method='Local preview' ;;
            rsync) method='SSH / rsync' ;;
            ftp) method='FTP' ;;
            ftps) method='FTPS' ;;
            sftp) method='SFTP' ;;
        esac
        ask_selection --label 'Publication method' --var method --items 'Local preview' 'SSH / rsync' 'FTP' 'FTPS' 'SFTP' || return 2
        case "$method" in
            'Local preview') method=preview ;;
            'SSH / rsync') method=rsync ;;
            FTP) method=ftp ;;
            FTPS) method=ftps ;;
            SFTP) method=sftp ;;
        esac
        ask --label 'Generated HTML directory' --var source --default "$source" --back || return 2
        [[ -d "$source" && -f "${source%/}/index.html" ]] || { sayfail "Missing generated website at $source"; return 1; }
        if [[ "$method" == preview ]]; then
            target="${target:-${source%/}-local}"
            ask --label 'Local website directory' --var target --default "$target" --back || return 2
            ask --label 'Preferred HTTP port' --var preview_port --default "$preview_port" --back || return 2
            [[ "$preview_port" =~ ^[0-9]+$ ]] && (( 10#$preview_port > 0 && 10#$preview_port <= 65535 )) || { sayfail 'Invalid HTTP port.'; return 1; }
            host='' ; user='' ; hostname='' ; identity='' ; manage=No ; port=22
        else
            ask --label 'Destination hostname' --var host --default "$host" --back || return 2
            [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { sayfail 'Invalid destination host.'; return 1; }
            ask --label 'Destination user' --var user --default "$user" --back || return 2
            if [[ "$method" == ftp || "$method" == ftps || "$method" == sftp ]]; then
                [[ "$user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@+-]*$ ]] || { sayfail 'Invalid hosting username.'; return 1; }
            else
                [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || { sayfail 'Invalid SSH user.'; return 1; }
            fi
            [[ "$port" =~ ^[0-9]+$ ]] || port=22
            if [[ "$method" == ftp || "$method" == ftps ]]; then
                [[ "$port" != 22 ]] || port=21
            fi
            ask --label 'Transport port' --var port --default "$port" --back || return 2
            [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port > 0 && 10#$port <= 65535 )) || { sayfail 'Invalid destination port.'; return 1; }
            if [[ "$method" == rsync ]]; then
                ask --label 'SSH identity file (optional)' --var identity --default "$identity" --back || return 2
                ask_selection --label 'Nginx/DNS management' --var manage --items Yes No || return 2
                if [[ "$manage" == Yes ]]; then
                    local target_action=''
                    ask_selection --label 'Website target' --var target_action --items 'Select existing Nginx website' 'Enter manually' || return 2
                    if [[ "$target_action" == 'Select existing Nginx website' ]]; then
                        if _web_profiles_select_nginx_site "$host" "$user" "$port" "$identity"; then
                            target="$WEB_DISCOVERED_TARGET"; hostname="$WEB_DISCOVERED_HOSTNAME"
                        else
                            saywarning 'Website selection unavailable; enter the target manually.'
                        fi
                    fi
                fi
            else
                identity='' ; manage=No
                sayinfo 'External hosting uses existing FTP credentials (~/.netrc) or SSH authentication. Nginx and DNS are not managed.'
            fi
            ask --label 'Remote website directory' --var target --default "$target" --back || return 2
            if [[ "$method" == ftp || "$method" == ftps || "$method" == sftp ]]; then
                _web_publish_safe_external_path "$target" || { sayfail 'External hosting directory must be an absolute safe path.'; return 1; }
            else
                _web_publish_safe_path "$target" || { sayfail 'Remote directory must be an absolute safe path.'; return 1; }
            fi
            ask --label 'Public website hostname (optional)' --var hostname --default "$hostname" --back || return 2
            [[ -z "$hostname" || "$hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { sayfail 'Invalid website hostname.'; return 1; }
        fi
        if [[ "$method" == preview || "$method" == rsync ]]; then
            ask_selection --label 'Synchronization' --var strategy --items Update Mirror || return 2
        else
            strategy=Update
        fi
        if [[ "$manage" == Yes && -z "$hostname" ]]; then
            sayfail 'Nginx management requires a public website hostname.'
            return 1
        fi
        WEB_PROFILE_WEBSITE="$website"; WEB_PROFILE_URL="$url"
        SGND_WEB_PUBLISH_METHOD="$method"; SGND_WEB_PUBLISH_SOURCE="$source"
        SGND_WEB_PUBLISH_HOST="$host"; SGND_WEB_PUBLISH_USER="$user"; SGND_WEB_PUBLISH_PORT="$port"
        SGND_WEB_PUBLISH_IDENTITY="$identity"; SGND_WEB_PUBLISH_REMOTE_DIR="$target"
        SGND_WEB_PUBLISH_HOSTNAME="$hostname"; SGND_WEB_PUBLISH_STRATEGY="$strategy"
        SGND_WEB_PUBLISH_MANAGE_SITE="$manage"; SGND_WEB_PUBLISH_PREVIEW_PORT="$preview_port"
        _web_profiles_save "$name"
    }

    # fn$ _web_profiles_menu_action - Execute a selected Framework menu item.
        # . Purpose
        #   Run one publishing-profile action without altering the main menu model.
        # . Arguments
        #   $1 Action identifier registered in the Framework menu.
        # . Returns
        #   0 on success or voluntary cancellation; nonzero on an action error.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_action test
        #   ```
    _web_profiles_menu_action() {
        local action="${1:?missing menu action}" name="" decision="No" preview_url="" rc=0
        case "$action" in
            list) _web_profiles_list || rc=$? ;;
            view)
                if _web_profiles_prompt_name; then
                    _web_profiles_view "$WEB_CHOSEN_PROFILE" || rc=$?
                fi
                ;;
            test)
                if [[ -z "$WEB_ACTIVE_PROFILE" ]]; then
                    saywarning 'Select a publishing profile first.'
                else
                    _web_profiles_test_connection "$WEB_ACTIVE_PROFILE" || rc=$?
                fi
                ;;
            select) _web_profiles_choose || rc=$? ;;
            create)
                if ask --label 'New profile name' --var name --default '' --back; then
                    if _web_profiles_tool get --name "$name" >/dev/null 2>&1; then
                        saywarning 'That profile name already exists; use Modify.'
                    else
                        _web_profiles_configure "$name" create || rc=$?
                        (( rc == 0 || rc == 2 )) || saywarning 'Profile was not saved.'
                    fi
                fi
                ;;
            modify)
                if [[ -z "$WEB_ACTIVE_PROFILE" ]]; then
                    saywarning 'Select a publishing profile first.'
                else
                    _web_profiles_configure "$WEB_ACTIVE_PROFILE" || rc=$?
                fi
                ;;
            delete)
                if [[ -z "$WEB_ACTIVE_PROFILE" ]]; then
                    saywarning 'Select a publishing profile first.'
                else
                    if ask_decision --label "Delete profile $WEB_ACTIVE_PROFILE" --choices 'Yes|Y,No|N' --default No --var decision; then
                        if [[ "$decision" == YES ]]; then
                            if _web_profiles_tool delete --name "$WEB_ACTIVE_PROFILE"; then
                                sayok "Publishing profile deleted: $WEB_ACTIVE_PROFILE"
                                WEB_ACTIVE_PROFILE=''
                                WEB_PROFILE_WEBSITE=''
                                WEB_PROFILE_ARG=''
                            else
                                rc=$?
                                sayfail 'Could not delete the selected publishing profile.'
                            fi
                        else
                            sayinfo 'Profile deletion cancelled.'
                        fi
                    fi
                fi
                ;;
            start|stop)
                if [[ -z "$WEB_ACTIVE_PROFILE" ]]; then
                    saywarning 'Select a publishing profile first.'
                elif [[ "${SGND_WEB_PUBLISH_METHOD:-}" != preview ]]; then
                    saywarning 'Only local preview profiles have an HTTP server.'
                elif [[ "$action" == start ]]; then
                    if preview_url="$(_web_profiles_preview_server start "$SGND_WEB_PUBLISH_REMOTE_DIR" "${SGND_WEB_PUBLISH_PREVIEW_PORT:-8080}")"; then
                        sgnd_print_labeledvalue --label 'Preview URL' --value "$preview_url"
                        sayok 'Local preview server is running.'
                    else
                        rc=$?
                        sayfail 'Could not start the local preview server.'
                    fi
                else
                    if _web_profiles_preview_server stop "$SGND_WEB_PUBLISH_REMOTE_DIR" "${SGND_WEB_PUBLISH_PREVIEW_PORT:-8080}"; then
                        sayok 'Local preview server stopped.'
                    else
                        rc=$?
                        sayfail 'Could not stop the local preview server.'
                    fi
                fi
                ;;
            *) sayfail "Unknown publishing profile action: $action"; return 2 ;;
        esac
        return "$rc"
    }

    # fn$ _web_profiles_menu_list - Show all saved profiles.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_list
        #   ```
    _web_profiles_menu_list() { _web_profiles_menu_action list; }

    # fn$ _web_profiles_menu_view - Inspect a saved profile without selecting it.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_view
        #   ```
    _web_profiles_menu_view() { _web_profiles_menu_action view; }

    # fn$ _web_profiles_menu_test - Test the selected destination.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_test
        #   ```
    _web_profiles_menu_test() { _web_profiles_menu_action test; }

    # fn$ _web_profiles_menu_select - Select an existing publishing profile.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_select
        #   ```
    _web_profiles_menu_select() { _web_profiles_menu_action select; }

    # fn$ _web_profiles_menu_create - Create a publishing profile.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_create
        #   ```
    _web_profiles_menu_create() { _web_profiles_menu_action create; }

    # fn$ _web_profiles_menu_modify - Modify the selected publishing profile.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_modify
        #   ```
    _web_profiles_menu_modify() { _web_profiles_menu_action modify; }

    # fn$ _web_profiles_menu_delete - Delete the selected profile with confirmation.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_delete
        #   ```
    _web_profiles_menu_delete() { _web_profiles_menu_action delete; }

    # fn$ _web_profiles_menu_start - Start HTTP preview for the selected local profile.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_start
        #   ```
    _web_profiles_menu_start() { _web_profiles_menu_action start; }

    # fn$ _web_profiles_menu_stop - Stop HTTP preview for the selected local profile.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_stop
        #   ```
    _web_profiles_menu_stop() { _web_profiles_menu_action stop; }

    # fn$ _web_profiles_menu_summary - Draw the current selection above menu groups.
        # . Purpose
        #   Print the selected destination and website as Framework labeled values
        #   beneath the menu title, with yellow values and no duplicate subtitle.
        # . Returns
        #   0 after rendering.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_summary
        #   ```
    _web_profiles_menu_summary() {
        local selected="${WEB_ACTIVE_PROFILE:-None}"
        local website="${WEB_PROFILE_WEBSITE:-None}"
        local selected_color="${YELLOW:-${SGND_UI_VALUE:-}}"
        sgnd_print_labeledvalue --label 'Selected profile' --value "$selected" --labelwidth 20 --pad 4 --valueclr "$selected_color"
        sgnd_print_labeledvalue --label 'Website' --value "$website" --labelwidth 20 --pad 4 --valueclr "$selected_color"
        sgnd_print
    }

    # fn$ _web_profiles_menu_build - Register groups and actions through sgnd-menu.
        # . Purpose
        #   Recreate the standard Framework menu with contiguous item numbering.
        #   A standard Framework preamble shows the selected website/profile
        #   between the title bar and first menu group.
        # . Returns
        #   0 when the menu has been built; nonzero on registration failure.
        # . Usage
        #   ```bash
        #   _web_profiles_menu_build
        #   ```
    _web_profiles_menu_build() {
        sgnd_menu_create 'Manage Publishing Profiles' ' ' '_web_profiles_menu_summary' || return $?
        SGND_MENU_SHOW_TOGGLEBAR=0
        SGND_CURRENT_MODULE_SOURCE='manage-web-content-profiles'
        SGND_MENU_ACTIVE_SOURCE="$SGND_CURRENT_MODULE_SOURCE"
        sgnd_menu_register_group 'profiles-view' 'View' '' 0 1 10 || return $?
        sgnd_menu_register_item 'profiles-list' 'profiles-view' 'List profiles' '_web_profiles_menu_list' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'profiles-view-one' 'profiles-view' 'View profile' '_web_profiles_menu_view' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'profiles-test' 'profiles-view' 'Test connection' '_web_profiles_menu_test' '' 0 0 1 0 || return $?
        sgnd_menu_register_group 'profiles-manage' 'Manage' '' 0 1 20 || return $?
        sgnd_menu_register_item 'profiles-select' 'profiles-manage' 'Select' '_web_profiles_menu_select' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'profiles-create' 'profiles-manage' 'Create' '_web_profiles_menu_create' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'profiles-modify' 'profiles-manage' 'Modify' '_web_profiles_menu_modify' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'profiles-delete' 'profiles-manage' 'Delete' '_web_profiles_menu_delete' '' 0 0 1 0 || return $?
        sgnd_menu_register_group 'profiles-preview' 'Preview' '' 0 1 30 || return $?
        sgnd_menu_register_item 'profiles-preview-start' 'profiles-preview' 'Start local preview' '_web_profiles_menu_start' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'profiles-preview-stop' 'profiles-preview' 'Stop local preview' '_web_profiles_menu_stop' '' 0 0 1 0 || return $?
    }

    # fn: _web_profiles_manage - Manage the selected website publishing profile.
        # . Purpose
        #   Show a freshly rendered Framework menu after each action, never append
        #   a second menu beneath output from a previous action.
        # . Behavior
        #   - sgnd-menu clears the terminal and renders title, groups and 1-9 choices.
        #   - Q/ESC returns to the caller, with no numeric Exit option.
        #   - Connection testing and deletion operate on the selected profile.
        #   - Each dispatched action ends with one interruptible autoclose dialog.
        # . Returns
        #   0 on Back; nonzero when a menu cannot be initialized.
        # . Usage
        #   ```bash
        #   _web_profiles_manage
        #   ```
    _web_profiles_manage() {
        local choice="" rc=0
        _web_profiles_restore_selection || return $?
        while :; do
            _web_profiles_menu_build || return $?
            sgnd_menu_show_menu || return $?
            # Framework renderer adds a blank line after Preview; add another
            # before Selection to keep Back distinct from the input prompt.
            sgnd_print --text 'Q. Back' --pad 3
            sgnd_print
            printf 'Selection : ' >/dev/tty
            sgnd_menu_read_choice choice || return $?
            case "$choice" in
                EXIT|ESC) return 0 ;;
                RESET|REDRAW|'<'|'>'|L|l) continue ;;
            esac
            rc=0
            sgnd_menu_dispatch "$choice" || rc=$?
            if [[ -t 0 && "${FLAG_AUTO:-0}" != 1 ]]; then
                sgnd_print
                ask_dlg_autocontinue \
                    --seconds 15 \
                    --message 'Returning to Manage Publishing Profiles' \
                    --pause \
                    --legend 'Enter=return to menu; P/Space=pause; timeout=menu' \
                    || true
            fi
            # Refresh only after an action: the first menu honors CLI --profile.
            _web_profiles_restore_selection persisted || return $?
            # The next sgnd_menu_show_menu clears the previous action output.
        done
    }

    # fn: _web_profiles_preview_server - Start or stop the owned local HTTP server.
        # . Purpose
        #   Start or stop the localhost-bound server, preferring 8080 and higher ports.
        # . Usage
        #   ```bash
        #   _web_profiles_preview_server start /tmp/website 8080
        #   ```
    _web_profiles_preview_server() {
        local python_root=""
        python_root="$(_web_content_python_root)"
        PYTHONPATH="$python_root${PYTHONPATH:+:$PYTHONPATH}" python3 -m webcontent.preview_server "$1" --directory "$2" --port "${3:-8080}"
    }

    # fn: _web_profiles_transfer - Publish selected profile without coupling to Nginx.
        # . Purpose
        #   Dry-run, confirm and publish generated HTML through the configured transport.
        # . Returns
        #   0 if transfer succeeded or user cancelled, nonzero for failed publication.
        # . Usage
        #   ```bash
        #   _web_profiles_transfer
        #   ```
    _web_profiles_transfer() {
        local source="${SGND_WEB_PUBLISH_SOURCE:-${SGND_WEB_CONTENT_OUTPUT%/}}" target="$SGND_WEB_PUBLISH_REMOTE_DIR"
        local method="${SGND_WEB_PUBLISH_METHOD:-rsync}" strategy="${SGND_WEB_PUBLISH_STRATEGY:-Update}"
        local host="${SGND_WEB_PUBLISH_HOST:-}" user="${SGND_WEB_PUBLISH_USER:-}" port="${SGND_WEB_PUBLISH_PORT:-22}"
        local identity="${SGND_WEB_PUBLISH_IDENTITY:-}" hostname="${SGND_WEB_PUBLISH_HOSTNAME:-}"
        local rc=0 preview="" decision=No destination="" transport_command="" file="" rel="" url="" root=""
        local -a args=() curl_args=()
        [[ -d "$source" && -f "${source%/}/index.html" ]] || { sayfail "Generated website missing: $source"; return 1; }
        source="$(realpath -e -- "$source")" || return 1
        [[ "$source" != / && "$source" != *-preview && "$source" != */preview && "$source" != */preview/* ]] || { sayfail 'Unsafe source directory.'; return 1; }
        [[ -z "$(find "$source" -type l -print -quit)" ]] || { sayfail 'Symbolic links in the website are not supported.'; return 1; }
        [[ "$strategy" == Update || "$strategy" == Mirror ]] || { sayfail 'Invalid synchronization strategy.'; return 1; }
        if [[ "$method" == preview ]]; then
            _web_publish_safe_path "$target" || { sayfail 'Unsafe local website directory.'; return 1; }
            target="$(realpath -m -- "$target")" || return 1
            [[ "$target" != "$source" && "$target" != "$source"/* && "$source" != "$target"/* ]] || { sayfail 'Source and target directories cannot contain each other.'; return 1; }
            [[ ! -L "$target" ]] || { sayfail 'Local destination must not be a symbolic link.'; return 1; }
            command -v rsync >/dev/null 2>&1 || { sayfail 'rsync is required.'; return 127; }
            mkdir -p -- "$target" || return 1
            [[ -z "$(find "$target" -type l -print -quit)" ]] || { sayfail 'Destination contains symbolic links.'; return 1; }
            args=(rsync -rltvi)
            [[ "$strategy" != Mirror ]] || args+=(--delete)
            destination="$target/"
        elif [[ "$method" == rsync ]]; then
            _web_publish_safe_path "$target" || { sayfail 'Unsafe remote website directory.'; return 1; }
            [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || { sayfail 'Invalid SSH destination.'; return 1; }
            [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port > 0 && 10#$port <= 65535 )) || { sayfail 'Invalid SSH port.'; return 1; }
            command -v rsync >/dev/null 2>&1 || { sayfail 'rsync is required.'; return 127; }
            [[ -z "$identity" || ( -r "${identity/#\~\//$HOME/}" && "$identity" != *[[:space:]]* ) ]] || { sayfail 'SSH identity is unreadable or contains whitespace.'; return 1; }
            _web_publish_prepare_ssh "$user" "$host" "$port" "${identity/#\~\//$HOME/}" || return $?
            # Never provision or modify a remote Nginx site during a dry-run
            # or before the operator has approved publication.
            transport_command="ssh -o BatchMode=yes -p $port"
            [[ -z "$identity" ]] || transport_command+=" -i ${identity/#\~\//$HOME/}"
            args=(rsync -rltvi -e "$transport_command")
            [[ "$strategy" != Mirror ]] || args+=(--delete)
            destination="${user}@${host}:${target}/"
        elif [[ "$method" == ftp || "$method" == ftps || "$method" == sftp ]]; then
            [[ "$strategy" == Update ]] || { sayfail 'Mirror is not supported for external FTP/SFTP hosting.'; return 1; }
            _web_publish_safe_external_path "$target" || { sayfail 'Unsafe external website directory.'; return 1; }
            [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@+-]*$ ]] || { sayfail 'Invalid external hosting address.'; return 1; }
            command -v curl >/dev/null 2>&1 || { sayfail 'curl is required for FTP/SFTP.'; return 127; }
            if [[ "$method" == ftp || "$method" == ftps ]]; then
                [[ -f "${HOME}/.netrc" ]] || { sayfail 'FTP credentials must be configured in ~/.netrc.'; return 1; }
            fi
            destination="${method}://${host}:${port}${target}/"
        else
            sayfail "Unsupported publishing method: $method"
            return 1
        fi
        sgnd_print_sectionheader --text 'Publication preview'
        sgnd_print_labeledvalue --label 'Website' --value "${WEB_PROFILE_WEBSITE:-Website}"
        sgnd_print_labeledvalue --label 'Profile' --value "$WEB_ACTIVE_PROFILE"
        sgnd_print_labeledvalue --label 'Source' --value "$source"
        sgnd_print_labeledvalue --label 'Destination' --value "$destination"
        sgnd_print_labeledvalue --label 'Synchronization' --value "$strategy"
        if [[ "$method" == preview || "$method" == rsync ]]; then
            preview="$(mktemp)" || return 1
            "${args[@]}" --dry-run -- "$source/" "$destination" > "$preview" 2>&1 || rc=$?
            if (( rc != 0 )); then
                sayfail "Publication dry-run failed ($rc)."
                while IFS= read -r file; do [[ -z "$file" ]] || sgnd_print --text "$file"; done < "$preview"
                rm -f -- "$preview"
                return "$rc"
            fi
            sgnd_print_labeledvalue --label 'New files' --value "$(grep -Ec '^>f\+|^cd\+' "$preview" || true)"
            sgnd_print_labeledvalue --label 'Changed files' --value "$(grep -Ec '^>f[^+]|^\.f' "$preview" || true)"
            sgnd_print_labeledvalue --label 'Delete candidates' --value "$(grep -c '^\*deleting' "$preview" || true)"
            rm -f -- "$preview"
        else
            sgnd_print_labeledvalue --label 'Transport' --value 'curl (credentials are not stored)'
        fi
        [[ "$strategy" != Mirror ]] || saywarning 'Mirror deletes destination-only files.'
        if [[ "${FLAG_DRYRUN:-0}" == 1 ]]; then
            sayinfo 'Dry-run complete; no website files were transferred.'
            return 0
        fi
        if [[ "${FLAG_AUTO:-0}" == 1 ]]; then
            [[ "$strategy" != Mirror ]] || { sayfail 'Mirror requires interactive confirmation.'; return 1; }
            decision=YES
        else
            ask_decision --label 'Publish website' --choices 'Yes|Y,No|N' --default No --var decision || return 0
        fi
        [[ "$decision" == YES ]] || { saycancel 'Publication cancelled.'; return 0; }
        if [[ "$method" == rsync && "${SGND_WEB_PUBLISH_MANAGE_SITE:-No}" == Yes ]]; then
            _web_publish_remote_site "$host" "$user" "$port" "$identity" "$target" "$hostname" || return $?
        fi
        if [[ "$method" == preview || "$method" == rsync ]]; then
            "${args[@]}" -- "$source/" "$destination" || return $?
        else
            # The server path and filenames are URL-encoded independently; credentials
            # are delegated to curl's existing netrc/SSH setup, never stored here.
            while IFS= read -r -d '' file; do
                rel="${file#"$source"/}"
                url="$(python3 - "$destination" "$rel" <<'PYURL'
import sys
from urllib.parse import quote, urlsplit, urlunsplit
base, name = sys.argv[1:]
parts = urlsplit(base)
print(urlunsplit((parts.scheme, parts.netloc, quote(parts.path, safe='/') + quote(name, safe='/'), '', '')))
PYURL
)" || return 1
                curl_args=(curl --fail --show-error --silent --ftp-create-dirs --upload-file "$file")
                if [[ "$method" == ftps ]]; then curl_args+=(--ssl-reqd --netrc-file "$HOME/.netrc"); fi
                if [[ "$method" == ftp ]]; then curl_args+=(--netrc-file "$HOME/.netrc"); fi
                if [[ "$method" == sftp ]]; then
                    curl_args+=(--user "${user}:")
                    [[ -z "$identity" ]] || curl_args+=(--key "${identity/#\~\//$HOME/}")
                fi
                "${curl_args[@]}" "$url" || { sayfail "Upload failed: $rel"; return 1; }
            done < <(find "$source" -type f -print0)
        fi
        sayok "Website published to $destination."
        WEB_PUBLISH_RESULT=success
        _web_profiles_tool success --name "$WEB_ACTIVE_PROFILE" || saywarning 'Could not update successful publication timestamp.'
        if [[ "$method" == preview ]]; then
            if [[ "${FLAG_AUTO:-0}" != 1 ]]; then
                ask_decision --label 'Start local webserver' --choices 'Yes|Y,No|N' --default No --var decision || return 0
                if [[ "$decision" == YES ]]; then
                    if url="$(_web_profiles_preview_server start "$target" "${SGND_WEB_PUBLISH_PREVIEW_PORT:-8080}")"; then
                        sgnd_print_labeledvalue --label 'Preview URL' --value "$url"
                    else
                        saywarning 'Website is published, but starting the local HTTP server failed.'
                    fi
                fi
            fi
        elif [[ "$method" == rsync && "${SGND_WEB_PUBLISH_MANAGE_SITE:-No}" == Yes ]]; then
            _web_publish_offer_dns "$host" "$user" "$port" "$identity" "$hostname"
            _web_publish_verify_http "$hostname"
        fi
        return 0
    }

    # fn: _web_content_publish - Select and publish a named website profile.
        # . Purpose
        #   Preserve normal publishing entry action while enabling multiple destinations.
        # . Usage
        #   ```bash
        #   _web_content_publish
        #   ```
    _web_content_publish() {
        local action="" name="" rc=0
        WEB_PUBLISH_RESULT=cancelled
        _web_profiles_migrate || return $?
        if [[ -n "${WEB_PROFILE_ARG:-}" ]]; then
            _web_profiles_load "$WEB_PROFILE_ARG" || return $?
        else
            name="$(_web_profiles_tool selected)" || return $?
            [[ -z "$name" ]] || _web_profiles_load "$name" || return $?
        fi
        if [[ -z "$WEB_ACTIVE_PROFILE" ]]; then
            if [[ "${FLAG_AUTO:-0}" == 1 ]]; then
                sayfail 'No publication profile selected for unattended publishing.'
                return 1
            fi
            _web_profiles_manage || return $?
            [[ -n "$WEB_ACTIVE_PROFILE" ]] || return 0
        fi
        while :; do
            sgnd_print_sectionheader --text 'Publish Website'
            sgnd_print_labeledvalue --label 'Website' --value "${WEB_PROFILE_WEBSITE:-Website}"
            sgnd_print_labeledvalue --label 'Profile' --value "$WEB_ACTIVE_PROFILE"
            sgnd_print_labeledvalue --label 'Method' --value "${SGND_WEB_PUBLISH_METHOD:-rsync}"
            sgnd_print_labeledvalue --label 'Source' --value "${SGND_WEB_PUBLISH_SOURCE:-${SGND_WEB_CONTENT_OUTPUT%/}}"
            sgnd_print_labeledvalue --label 'Destination' --value "${SGND_WEB_PUBLISH_HOST:-local}:${SGND_WEB_PUBLISH_REMOTE_DIR:-}"
            sgnd_print_labeledvalue --label 'Last published' --value "${WEB_PROFILE_LAST_SUCCESS:-Not available}"
            if [[ "${FLAG_AUTO:-0}" == 1 ]]; then action=Publish
            else ask_selection --label 'Publication' --var action --items Publish Modify 'Select profile' 'Manage profiles' Cancel || return 0; fi
            case "$action" in
                Publish) break ;;
                Modify) _web_profiles_configure "$WEB_ACTIVE_PROFILE" || return $? ;;
                'Select profile') _web_profiles_choose || true ;;
                'Manage profiles') _web_profiles_manage || return $? ;;
                Cancel) return 0 ;;
            esac
        done
        _web_profiles_transfer
    }

# - Action dispatch -----------------------------------------------------------------
    # fn: _run_action - Dispatch the requested command-line management action.
        # . Purpose
        #   Dispatch the requested command-line management action.
        #
        # . Arguments
        #   - `$1`: Management action to execute.
        # . Behavior
        #   - Publishing shows the framework's existing auto-continue dialogue after
        #     success, cancellation, or failure, allowing the operator to inspect output.
        #   - The operator can press P/Space to pause the countdown.
        #   - Preserves the original publication exit status after the dialogue.
        #
        # . Usage
        #   ```bash
        #   _run_action "status"
        #   ```
    _run_action() {
        local action="${1:?missing action}" rc=0 completion_message=""
        case "$action" in
            ingest) _web_content_ingest ;;
            configure-source) _web_content_configure_incoming ;;
            retrieve-incoming) _web_content_retrieve_incoming ;;
            import-local) _web_content_import_local ;;
            ingest-incoming) _web_content_ingest_incoming ;;
            edit-metadata) _web_content_manage_page edit-metadata ;;
            move-page) _web_content_manage_page move-page ;;
            manage-config) _web_content_manage_config ;;
            delete)
                # Deletion owns its closing section line and repeat/return dialog.
                _web_content_delete
                return $?
                ;;
            generate) _web_content_generate ;;
            publish-github-pages) _web_content_publish_github_pages ;;
            manage-publishing-profiles) _web_profiles_migrate && _web_profiles_manage ;;
            publish)
                _web_content_publish || rc=$?
                if (( rc != 0 )); then
                    completion_message="Publication failed. Return to menu?"
                elif [[ "${WEB_PUBLISH_RESULT:-}" == "success" ]]; then
                    completion_message="Publication completed. Return to menu?"
                else
                    completion_message="Publication cancelled. Return to menu?"
                fi
                sgnd_print
                sgnd_print_sectionheader ""
                if [[ -t 0 && "${FLAG_AUTO:-0}" != 1 ]]; then
                    # Reuse the verified framework dialogue; do not introduce a new ask API.
                    ask_dlg_autocontinue \
                        --seconds 60 \
                        --message "$completion_message" \
                        --pause \
                        --legend "Enter=return to menu; P/Space=pause; timeout=menu" \
                        || true
                fi
                return "$rc"
                ;;
            validate) _web_content_validate ;;
            prepare-social) _web_content_prepare_social ;;
            status) _web_content_status ;;
            *) sayfail "Unknown web-content management action: $action"; return 2 ;;
        esac
        local rc=$?
        sgnd_print
        sgnd_print_sectionheader ""
        return "$rc"
    }

# - Main ----------------------------------------------------------------------------
    # fn: main - Parse command-line arguments and dispatch the requested command.
        # . Purpose
        #   Parse command-line arguments and dispatch the requested command.
        #
        # . Usage
        #   ```bash
        #   main "$@"
        #   ```
    main() {
        local action=""
        _framework_locator || return $?
        sgnd_exe_start --autostate -- "$@" || return $?
        action="${ACTION:-status}"
        _run_action "$action"
    }
    main "$@"
