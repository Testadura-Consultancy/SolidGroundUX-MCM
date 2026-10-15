#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX Management Console Modules - Manage Web Content
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2628700
#   Shortname   : MANAGE_WEB_CONTENT
#   Source      : manage-web-content.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Ingest, delete, generate, validate, and prepare static website content
#
#   Checksum : af471b3b221c3efc220afff0193943bb3392e02fb7a3e865e233864f7ecebe48
# Description:
#   Provides the SolidGroundUX user-facing workflow for the reusable Python WebContent
#   engine. All prompts, state, progress, and result reporting remain in this Bash layer;
#   the Python package is deliberately non-interactive. Loose Markdown can be ingested
#   individually or in batches from a canonical incoming directory, normalized into a
#   website repository, and archived after successful ingestion. Canonical pages can
#   also be selected individually or in batches and removed recoverably by archiving them
#   outside the active content tree.
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
        "action|a|enum|ACTION|Management action||ingest,delete,edit-metadata,move-page,manage-sections,manage-config,generate,publish,validate,prepare-social,status"
        "ingest-dir|i|value|INGEST_DIR|Override Markdown ingestion directory||"
    )
    SGND_SCRIPT_EXAMPLES=(
        "  $SGND_SCRIPT_NAME --action ingest"
        "  $SGND_SCRIPT_NAME --action ingest --ingest-dir /path/to/incoming"
        "  $SGND_SCRIPT_NAME --action delete"
        "  $SGND_SCRIPT_NAME --action generate"
        "  $SGND_SCRIPT_NAME --action publish"
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

# - Helpers -------------------------------------------------------------------------
    # fn: _web_content_python_root - Run the python root action through Web Content Management.
    _web_content_python_root() {
        if [[ "$SGND_FRAMEWORK_ROOT" == "/" ]]; then
            printf '%s\n' "/usr/local/lib/solidgroundux/py"
        else
            printf '%s\n' "${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/py"
        fi
    }

    # fn: _web_content_validate_source - Run the validate source action through Web Content Management.
    _web_content_validate_source() {
        local path="${1:-}"
        [[ -d "$path" && -r "$path/config/site.cfg" && -d "$path/content" && -d "$path/templates" && -d "$path/css" ]]
    }

    # fn: _web_content_validate_language - Run the validate language action through Web Content Management.
    _web_content_validate_language() {
        local value="${1:-}"
        [[ "${value^^}" == "ALL" || "$value" =~ ^[A-Za-z]{2}([,][A-Za-z]{2})*$ ]]
    }

    # fn: _web_content_validate_platform - Run the validate platform action through Web Content Management.
    _web_content_validate_platform() {
        local value="${1:-}"
        [[ "$value" =~ ^[A-Za-z0-9_-]+$ ]]
    }

    # fn: _web_content_ensure_output_parent - Run the ensure output parent action through Web Content Management.
    _web_content_ensure_output_parent() {
        local path="${1:?missing output path}"
        local parent=""
        parent="$(dirname -- "$path")"
        [[ -d "$parent" ]] || mkdir -p -- "$parent" || return 1
    }

    # fn: _web_content_result_value - Extract a requested field from the most recent engine result.
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
        # . Behavior
        #   - Coordinates the existing workflow without modifying article content directly.
        #   - Propagates errors to the caller and uses the framework for user interaction.
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
        #   $1  COUNT - Number of canonical content files changed during this action.
    _web_content_record_activity() {
        local count="${1:-0}"
        local marker="${SGND_WEB_CONTENT_ACTIVITY_FILE:-}"

        [[ "$count" =~ ^[0-9]+$ ]] || count=0
        [[ -n "$marker" ]] || return 0
        printf '%s\n' "$count" > "$marker" 2>/dev/null || true
    }

    # fn: _web_content_report_errors - Run the report errors action through Web Content Management.
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
    _web_content_select_source() {
        ask --label "Website repository" --var SGND_WEB_CONTENT_SOURCE --default "$SGND_WEB_CONTENT_SOURCE" --validate _web_content_validate_source --back
    }

    # fn: _web_content_select_language - Run the select language action through Web Content Management.
    _web_content_select_language() {
        ask --label "Language (ALL or codes)" --var SGND_WEB_CONTENT_LANGUAGE --default "$SGND_WEB_CONTENT_LANGUAGE" --validate _web_content_validate_language --back
        SGND_WEB_CONTENT_LANGUAGE="${SGND_WEB_CONTENT_LANGUAGE^^}"
    }

    # fn: _web_content_validate_ingest_dir - Run the validate ingest dir action through Web Content Management.
    _web_content_validate_ingest_dir() {
        local path="${1:-}"
        [[ -n "$path" ]]
    }

    # fn: _web_content_validate_slug - Run the validate slug action through Web Content Management.
    _web_content_validate_slug() {
        local value="${1:-}"
        [[ "$value" =~ ^[a-z0-9][a-z0-9-]*$ ]]
    }

    # fn: _web_content_canonical_ingest_dir - Run the canonical ingest dir action through Web Content Management.
    _web_content_canonical_ingest_dir() {
        # Incoming authoring files belong to the selected website repository but
        # stay outside content/ until their metadata has been resolved and confirmed.
        printf '%s\n' "${SGND_WEB_CONTENT_SOURCE%/}/incoming"
    }

    # fn: _web_content_canonical_archive_dir - Run the canonical archive dir action through Web Content Management.
    _web_content_canonical_archive_dir() {
        # Successfully processed loose sources are retained outside content/ as a
        # date-grouped authoring archive; the website generator ignores this tree.
        printf '%s\n' "${SGND_WEB_CONTENT_SOURCE%/}/ingested"
    }

    # fn: _web_content_canonical_delete_archive_dir - Run the canonical delete archive dir action through Web Content Management.
    _web_content_canonical_delete_archive_dir() {
        # Removed canonical pages are moved outside content/ into a date-grouped
        # recovery archive so deletion remains reversible and generator-safe.
        printf '%s\n' "${SGND_WEB_CONTENT_SOURCE%/}/deleted"
    }

    # fn: _web_content_select_ingest_dir - Run the select ingest dir action through Web Content Management.
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
    _web_content_extract_parent_route() {
        local selection="${1:-}"
        local route="${selection##*[}"
        route="${route%]}"
        printf '%s\n' "$route"
    }

    # fn: _web_content_kind_label - Run the kind label action through Web Content Management.
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
            ask_decision --label "Use remembered language: $remembered" --choices "YES|Y,NO|N" --default "YES" --var decision || return 1
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
            ask_decision --label "Use remembered content type: $remembered_label" --choices "YES|Y,NO|N" --default "YES" --var decision || return 1
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
            ask_decision --label "Use remembered parent: $remembered_option" --choices "YES|Y,NO|N" --default "YES" --var decision || return 1
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
        local confirmation_default="NO"
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

        [[ "$batch_mode" == "Yes" ]] && confirmation_default="YES"
        ask_decision --label "Ingest this file" --choices "YES|Y,NO|N" --default "$confirmation_default" --var decision
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

    # fn: _web_content_ingest - Ingest one or more loose Markdown files into a website repository
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
            ask_selection --label "Ingestion mode" --var mode --items "Ingest all (${#files[@]} files)" "Select one file" || return 0
            if [[ "$mode" == "Select one file" ]]; then
                ask_selection --label "Markdown file to ingest" --var selected --items "${files[@]}" || return 0
                targets=("$selected")
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
        #   $1  SELECTION - Display value returned by inspect-delete / ask_selection.
        #   $2  COUNT_VAR - Caller variable receiving the number of archived files.
        #
        # . Returns
        #   0 when content was archived and removed.
        #   2 when the selected item was skipped or its deletion was cancelled.
        #   Other non-zero values when inspection, preview, or deletion fails.
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
                --choices "YES|Y,NO|N" \
                --default "YES" \
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
                --choices "YES|Y,NO|N" \
                --default "NO" \
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
            --choices "YES|Y,NO|N" \
            --default "NO" \
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
    }

    # fn: _web_content_validate - Validate a web-content repository
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
    # The output stays outside the repository and is never posted automatically.
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
        sgnd_print_labeledvalue --label "Ingestion directory" --value "${SGND_WEB_CONTENT_INGEST_DIR:-$(_web_content_canonical_ingest_dir)}" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingestion archive" --value "$(_web_content_canonical_archive_dir)" --labelwidth 20
        sgnd_print_labeledvalue --label "Deletion archive" --value "$(_web_content_canonical_delete_archive_dir)" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingest language" --value "${SGND_WEB_CONTENT_INGEST_LANGUAGE:-Not set}" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingest content type" --value "${SGND_WEB_CONTENT_INGEST_KIND:-Not set}" --labelwidth 20
        sgnd_print_labeledvalue --label "Ingest parent" --value "${SGND_WEB_CONTENT_INGEST_PARENT:-Not set}" --labelwidth 20
    }

# fn: _web_content_manage_page - Browse existing content and edit metadata or move a page.
    # Uses the shared Python content discovery logic; changes stay uncommitted in Git.
    # Metadata editing stays on a page until Done; the wrapper offers another page afterward.
    # fn: _web_content_manage_page_once - Select one page and edit metadata or move its canonical source file.
        # . Behavior
        #   - Coordinates the existing workflow without modifying article content directly.
        #   - Propagates errors to the caller and uses the framework for user interaction.
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
            # Remain on the chosen page until Done is selected. Refresh metadata
            # after each save so defaults and the selection list stay current.
            local selected_field="" edit_field="" edit_choice="" changed_count=0
            local -a field_options=()
            while true; do
                _web_content_run_engine "$list_file" list-pages --source "$SGND_WEB_CONTENT_SOURCE" || {
                    _web_content_report_errors "$list_file"
                    rm -f -- "$list_file" "$result_file"
                    return 1
                }
                sgnd_print
                sgnd_print_sectionheader --text "Current metadata: $file"
                mapfile -t field_options < <(python3 - "$list_file" "$file" <<'PYCODE'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as handle:
    pages = json.load(handle).get('pages', [])
page = next((page for page in pages if page['file'] == sys.argv[2]), None)
if page is not None:
    for key, val in page['metadata'].items():
        shown = str(val).lower() if isinstance(val, bool) else str(val if val is not None else '')
        print('{} = {}'.format(key, shown.replace('\n', ' ')))
PYCODE
)
                if (( ${#field_options[@]} == 0 )); then
                    saywarning "No editable metadata was found for this page."
                else
                    local metadata_line=""
                    for metadata_line in "${field_options[@]}"; do
                        sgnd_print_labeledvalue --label "${metadata_line%% = *}" --value "${metadata_line#* = }" --labelwidth 20
                    done
                fi
                sgnd_print
                sgnd_print_sectionheader --text "Edit metadata"
                field_options+=("Add metadata field" "Done - finish this page")
                selected_field=""
                ask_selection --label "Choose a metadata field" --var selected_field --items "${field_options[@]}" || break
                case "$selected_field" in
                    "Done - finish this page") break ;;
                    "Add metadata field")
                        edit_field=""
                        ask --label "New metadata field name" --var edit_field --back || continue
                        [[ -n "$edit_field" ]] || { saywarning "Field name cannot be empty."; continue; }
                        ;;
                    *) edit_field="${selected_field%% = *}" ;;
                esac
                # Read the current value from the refreshed page data. This is
                # also safe for newly-added fields (whose default is blank).
                current_value="$(python3 - "$list_file" "$file" "$edit_field" <<'PYCODE'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as handle:
    pages = json.load(handle).get('pages', [])
for page in pages:
    if page['file'] == sys.argv[2]:
        value = page['metadata'].get(sys.argv[3], '')
        if isinstance(value, bool):
            print(str(value).lower())
        elif value is not None:
            print(str(value))
        break
PYCODE
)"
                metadata_new_value="$current_value"
                ask --label "New value (:clear to empty)" --var metadata_new_value --default "$current_value" --back || continue
                [[ -z "$metadata_new_value" ]] && metadata_new_value="$current_value"
                [[ "$metadata_new_value" == ":clear" ]] && metadata_new_value=""
                if [[ "$edit_field" == "featured" || "$edit_field" == "draft" || "$edit_field" == "hide_title" ]]; then
                    metadata_new_value="$(python3 -c 'import sys; print(sys.argv[1].strip().lower())' "$metadata_new_value")"
                fi
                if [[ "$metadata_new_value" == "$current_value" ]]; then
                    sayinfo "Metadata unchanged."
                    continue
                fi
                if ! _web_content_run_engine "$result_file" edit-metadata --source "$SGND_WEB_CONTENT_SOURCE" --content-file "$file" --key "$edit_field" --value "$metadata_new_value"; then
                    _web_content_report_errors "$result_file"
                    continue
                fi
                ((changed_count+=1))
                sayok "Updated: $edit_field"
            done
            if (( changed_count > 0 )); then
                _web_content_record_activity "$changed_count"
                sayok "Metadata updated. Git commit remains manual."
            else
                sayinfo "Finished editing this page. No changes saved."
            fi
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
            ask_decision --label "Move this page and change its URL?" --choices "YES|Y,NO|N" --default "NO" --var decision || { rm -f -- "$list_file" "$result_file"; return 0; }
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
    # Enter or timeout returns to the console; only A starts another selection.
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

    # fn: _web_content_manage_sections_once - Create or remove an indexed section tree.
    # Parent and section choices come from the engine, not manually typed paths.
    # Destructive actions require a preview followed by explicit confirmation.
    _web_content_manage_sections_once() {
        local result_file="" selected="" operation="" section="" parent="" slug="" title_nl="" title_en="" languages="" policy="" destination="" archive_dir="" decision=""
        local -a options=() section_options=()
        result_file="$(mktemp)" || return 1
        if ! _web_content_run_engine "$result_file" list-sections --source "$SGND_WEB_CONTENT_SOURCE"; then
            _web_content_report_errors "$result_file"; rm -f -- "$result_file"; return 1
        fi
        mapfile -t section_options < <(python3 - "$result_file" <<'PYCODE'
import json, sys
for section in json.load(open(sys.argv[1], encoding='utf-8'))['sections']:
    print(section['path'] if section['path'] else '(Website root)')
PYCODE
)
        sgnd_print
        sgnd_print_sectionheader --text "Manage sections"
        ask_selection --label "Action" --var operation --items "Add section / subsection" "Remove section" || { rm -f -- "$result_file"; return 0; }
        if [[ "$operation" == "Add section / subsection" ]]; then
            ask_selection --label "Parent section" --var selected --items "${section_options[@]}" || { rm -f -- "$result_file"; return 0; }
            parent="$selected"; [[ "$parent" == '(Website root)' ]] && parent=""
            ask --label "New section slug" --var slug --back || { rm -f -- "$result_file"; return 0; }
            ask_selection --label "Languages" --var languages --items "NL and EN" "NL only" "EN only" || { rm -f -- "$result_file"; return 0; }
            case "$languages" in "NL and EN") languages="NL,EN";; "NL only") languages="NL";; *) languages="EN";; esac
            if [[ "$languages" == *NL* ]]; then
                ask --label "Dutch section title" --var title_nl --back || { rm -f -- "$result_file"; return 0; }
            fi
            if [[ "$languages" == *EN* ]]; then
                ask --label "English section title" --var title_en --back || { rm -f -- "$result_file"; return 0; }
            fi
            sgnd_print
            sgnd_print_labeledvalue --label "Create section" --value "${parent:+$parent/}$slug" --labelwidth 20
            ask_decision --label "Create draft section index pages?" --choices "YES|Y,NO|N" --default "NO" --var decision || { rm -f -- "$result_file"; return 0; }
            if [[ "$decision" == "YES" ]]; then
                if _web_content_run_engine "$result_file" create-section --source "$SGND_WEB_CONTENT_SOURCE" --parent "$parent" --slug "$slug" --title-nl "$title_nl" --title-en "$title_en" --languages "$languages"; then
                    _web_content_record_activity 1
                    sayok "Section created. Add navigation separately if desired; Git commit remains manual."
                else _web_content_report_errors "$result_file"; fi
            fi
        else
            options=()
            for section in "${section_options[@]}"; do
                [[ "$section" != '(Website root)' ]] && options+=("$section")
            done
            if (( ${#options[@]} == 0 )); then saywarning "No sections to manage."; rm -f -- "$result_file"; return 0; fi
            ask_selection --label "Section to remove" --var section --items "${options[@]}" || { rm -f -- "$result_file"; return 0; }
            if ! _web_content_run_engine "$result_file" inspect-section --source "$SGND_WEB_CONTENT_SOURCE" --section "$section"; then
                _web_content_report_errors "$result_file"; rm -f -- "$result_file"; return 1
            fi
            local protected="" files="" subsections=""
            protected="$(python3 - "$result_file" <<'PYCODE'
import json,sys
r=json.load(open(sys.argv[1])); print('yes' if r['protected'] else 'no')
PYCODE
)"
            files="$(_web_content_result_value "$result_file" files)"
            subsections="$(_web_content_result_value "$result_file" subsections)"
            sgnd_print
            sgnd_print_sectionheader --text "Removal preview"
            sgnd_print_labeledvalue --label "Section" --value "$section" --labelwidth 20
            sgnd_print_labeledvalue --label "Files" --value "$files" --labelwidth 20
            sgnd_print_labeledvalue --label "Subsections" --value "$subsections" --labelwidth 20
            if [[ "$protected" == yes ]]; then
                sayfail "This section is in navigation. Remove its navigation entry before deleting it."
                rm -f -- "$result_file"; return 0
            fi
            ask_selection --label "What to do with contained files?" --var policy --items "Move contents" "Archive entire section" "Permanently delete everything" "Cancel" || { rm -f -- "$result_file"; return 0; }
            case "$policy" in
                "Move contents")
                    local -a targets=()
                    for selected in "${section_options[@]}"; do
                        [[ "$selected" == '(Website root)' ]] && targets+=("$selected")
                        [[ "$selected" != "$section" && "$selected" != "$section/"* && "$selected" != '(Website root)' ]] && targets+=("$selected")
                    done
                    ask_selection --label "Move contents to" --var destination --items "${targets[@]}" || { rm -f -- "$result_file"; return 0; }
                    [[ "$destination" == '(Website root)' ]] && destination=""
                    policy="move" ;;
                "Archive entire section")
                    archive_dir="${SGND_SHARE_DIR:-${HOME}/.local/share/solidgroundux}/web-content-section-archive"
                    ask --label "Archive directory" --var archive_dir --default "$archive_dir" --back || { rm -f -- "$result_file"; return 0; }
                    policy="archive" ;;
                "Permanently delete everything") policy="delete" ;;
                *) rm -f -- "$result_file"; return 0 ;;
            esac
            sgnd_print
            saywarning "This affects $files file(s). References to old URLs will not be rewritten."
            if [[ "$policy" == delete ]]; then
                local confirmation=""
                ask --label "Type the full section path to PERMANENTLY DELETE" --var confirmation --back || { rm -f -- "$result_file"; return 0; }
                if [[ "$confirmation" != "$section" ]]; then saycancel "Section path mismatch. Nothing deleted."; rm -f -- "$result_file"; return 0; fi
            fi
            ask_decision --label "Confirm $policy of $section?" --choices "YES|Y,NO|N" --default "NO" --var decision || { rm -f -- "$result_file"; return 0; }
            if [[ "$decision" == "YES" ]]; then
                if _web_content_run_engine "$result_file" remove-section --source "$SGND_WEB_CONTENT_SOURCE" --section "$section" --mode "$policy" --destination "$destination" --archive-root "$archive_dir"; then
                    _web_content_record_activity "$files"
                    sayok "Section operation completed. Regenerate and validate links; commit manually."
                    [[ "$policy" == archive ]] && sayinfo "Archive: $(_web_content_result_value "$result_file" archive)"
                else _web_content_report_errors "$result_file"; fi
            fi
        fi
        rm -f -- "$result_file"
    }

    # fn: _web_content_manage_sections - Repeat section operations on explicit request.
    _web_content_manage_sections() {
        local rc=0
        while true; do
            _web_content_manage_sections_once || return $?
            sgnd_print
            sgnd_print_sectionheader ""
            rc=0
            ask_dlg_autocontinue --seconds 5 --message "Manage another section?" --again --pause --legend "A=another; Enter/timeout=menu; P/Space=pause" || rc=$?
            [[ "$rc" == 3 ]] || return 0
        done
    }

    # fn: _web_content_manage_config - Select an existing .cfg file and open it in nano.
        # . Behavior
        #   - Uses the currently selected website repository and its config/ directory.
        #   - Lists only regular .cfg files found directly under config/.
        #   - Uses the framework selection dialogue; cancellation changes nothing.
        #   - Reports editor failures and marks website generation pending only on changes.
        #   - Does not create arbitrary files or execute paths entered by the user.
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
    # fn: _web_content_publish_profiles - Read a website-local publishing.cfg file.
        # . Behavior
        #   - Uses Python's INI parser rather than evaluating configuration as shell code.
        #   - Emits profile names or one selected profile as NUL-delimited fields.
        #   - Never stores passwords in the website repository.
    _web_content_publish_profiles() {
        local config_file="${SGND_WEB_CONTENT_SOURCE%/}/config/publishing.cfg"
        local profile="${1:-}"
        python3 - "$config_file" "$profile" <<'PYCODE'
import configparser
import sys

config = configparser.ConfigParser(interpolation=None)
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        config.read_file(stream)
except (OSError, configparser.Error) as exc:
    print("Invalid publishing configuration: {}".format(exc), file=sys.stderr)
    sys.exit(1)

profile = sys.argv[2]
if not profile:
    for name in config.sections():
        print(name)
else:
    if profile not in config:
        print("Unknown publishing profile: {}".format(profile), file=sys.stderr)
        sys.exit(1)
    values = config[profile]
    keys = ("type", "path", "host", "user", "port", "identity_file")
    for key in keys:
        value = values.get(key, "").strip()
        if "\x00" in value or "\n" in value or "\r" in value:
            print("Invalid value for {}".format(key), file=sys.stderr)
            sys.exit(1)
        sys.stdout.buffer.write(value.encode("utf-8") + b"\x00")
PYCODE
    }

    # fn: _web_content_publish_create_config - Create an editable example configuration when absent.
        # . Behavior
        #   - Never overwrites existing publication profiles.
        #   - Profile paths must point to a dedicated website directory, never a filesystem root.
        #   - SFTP needs lftp and an SSH key/agent configured outside the repository.
    _web_content_publish_create_config() {
        local config_file="${SGND_WEB_CONTENT_SOURCE%/}/config/publishing.cfg"
        local decision="NO"
        [[ ! -e "$config_file" ]] || return 0
        ask_decision --label "Create config/publishing.cfg with example profiles?" --choices "YES|Y,NO|N" --default "YES" --var decision || return 1
        [[ "$decision" == YES ]] || return 1
        cat > "$config_file" <<'CFG'
# Publishing profiles. Choose a dedicated destination directory.
# Credentials and private keys must NOT be put in this file.
# Supported types: local, rsync, sftp.
# Edit the placeholders before using the example profiles.
# For rsync: host, user, path and optionally port and identity_file.
# For sftp: host, user, path and optionally port; authenticate via SSH agent/config.

[local-example]
type = local
path = /srv/www/testadura

# [hostnet]
# type = sftp
# host = your-sftp-host.example
# user = your-username
# port = 22
# path = /remote/website/directory

# [remote-server]
# type = rsync
# host = webserver.example
# user = sysadmin
# port = 22
# path = /var/www/testadura
# identity_file = ~/.ssh/id_ed25519
CFG
        sayok "Created $config_file. Edit it using Manage Config before publishing."
    }

    # fn: _web_content_publish_safe_path - Reject dangerous destination paths before any transfer.
    _web_content_publish_safe_path() {
        local path="${1:-}"
        [[ "$path" == /* && "$path" != "/" && "$path" != *".."* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
        # Ban shell/lftp metacharacters in user-controlled remote paths; spaces are accepted.
        [[ "$path" != *'"'* && "$path" != *"'"* && "$path" != *\* && "$path" != *';'* && "$path" != *'$'* && "$path" != *'`'* && "$path" != *'!'* ]] || return 1
        [[ "${path#/}" == */* ]] || return 1
    }

    # fn: _web_content_publish - Preview and upload a generated site to a chosen destination.
        # . Behavior
        #   - Offers website-specific profiles in config/publishing.cfg.
        #   - Previews synchronization before requesting explicit confirmation.
        #   - Never deletes remote files; safe incremental publishing is the default.
        #   - For SFTP, requires lftp and SSH authentication configured on the host.
        #   - Only the generated output is transferred; repository metadata is never uploaded.
    _web_content_publish() {
        local selected="" config_file="" source="" type="" target="" host="" user="" port="" identity=""
        local decision="NO" rc=0 preview="" destination="" ssh_transport="" ssh_identity=""
        local -a profiles=() values=() command_args=() extra=()

        _web_content_select_source || return 0
        config_file="${SGND_WEB_CONTENT_SOURCE%/}/config/publishing.cfg"
        if [[ ! -e "$config_file" ]]; then
            _web_content_publish_create_config || return 0
            sayinfo "Configure a real destination in publishing.cfg, then select Publish website again."
            return 0
        fi
        [[ -f "$config_file" && ! -L "$config_file" ]] || { sayfail "Unsafe publishing configuration file: $config_file"; return 1; }
        local profile_file=""
        profile_file="$(mktemp)" || return 1
        if ! _web_content_publish_profiles > "$profile_file"; then rm -f "$profile_file"; return 1; fi
        mapfile -t profiles < "$profile_file"
        rm -f "$profile_file"
        (( ${#profiles[@]} > 0 )) || { saywarning "No profiles found in $config_file"; return 0; }
        ask_selection --label "Publishing destination" --var selected --items "${profiles[@]}" || return 0
        profile_file="$(mktemp)" || return 1
        if ! _web_content_publish_profiles "$selected" > "$profile_file"; then rm -f "$profile_file"; return 1; fi
        mapfile -d '' -t values < "$profile_file"
        rm -f "$profile_file"
        (( ${#values[@]} == 6 )) || { sayfail "Invalid publishing profile: $selected"; return 1; }
        type="${values[0],,}"; target="${values[1]}"; host="${values[2]}"; user="${values[3]}"
        port="${values[4]:-22}"; identity="${values[5]}"
        _web_content_publish_safe_path "$target" || { sayfail "Unsafe destination directory: $target"; return 1; }
        [[ "$port" =~ ^[0-9]+$ ]] && (( port > 0 && port <= 65535 )) || { sayfail "Invalid port: $port"; return 1; }
        source="${SGND_WEB_CONTENT_OUTPUT%/}"
        [[ -d "$source" && -f "$source/index.html" ]] || {
            sayfail "Generated output is missing (index.html required): $source. Run Generate website first."
            return 1
        }
        source="$(realpath -e -- "$source")" || return 1
        [[ "$source" != / && "$source" != "${SGND_WEB_CONTENT_SOURCE%/}" ]] || { sayfail "Unsafe generation output directory."; return 1; }
        if [[ -n "$(find "$source" -type l -print -quit)" ]]; then
            sayfail "Generated output contains symbolic links; refusing to publish them."
            return 1
        fi
        # Exclude previews only by intent: users must point SGND_WEB_CONTENT_OUTPUT at their public output.
        if [[ "$source" == *-preview ]]; then
            sayfail "Refusing to publish a preview output directory. Generate a public website first."
            return 1
        fi
        sgnd_print
        sgnd_print_sectionheader --text "Publication preview: $selected"
        sgnd_print_labeledvalue --label "Local output" --value "$source" --labelwidth 20
        sgnd_print_labeledvalue --label "Transport" --value "$type" --labelwidth 20
        sgnd_print_labeledvalue --label "Remote path" --value "$target" --labelwidth 20
        preview="$(mktemp)" || return 1
        case "$type" in
            local)
                command -v rsync >/dev/null 2>&1 || { sayfail "rsync is required for local publishing."; rm -f "$preview"; return 127; }
                destination="$(realpath -m -- "$target")"
                [[ "$destination" != "$source" && "$destination" != "$source/"* && "$source" != "$destination/"* ]] || {
                    sayfail "Source and destination must not overlap."; rm -f "$preview"; return 1;
                }
                # Do not create a destination until the user confirms the preview.
                command_args=(rsync -rltvi --dry-run -- "$source/" "$destination/")
                ;;
            rsync)
                command -v rsync >/dev/null 2>&1 || { sayfail "rsync is not installed."; rm -f "$preview"; return 127; }
                [[ "$host" =~ ^[a-zA-Z0-9._-]+$ && "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] || {
                    sayfail "Invalid remote host or user."; rm -f "$preview"; return 1;
                }
                ssh_transport="ssh -o BatchMode=yes -p $port"
                if [[ -n "$identity" ]]; then
                    ssh_identity="${identity/#\~\//$HOME/}"
                    [[ -r "$ssh_identity" && "$ssh_identity" != *' '* ]] || { sayfail "Identity file must exist and contain no spaces."; rm -f "$preview"; return 1; }
                    ssh_transport+=" -i $ssh_identity"
                fi
                [[ "$target" != *[[:space:]]* ]] || { sayfail "rsync remote path must not contain spaces."; rm -f "$preview"; return 1; }
                destination="${user}@${host}:${target}/"
                command_args=(rsync -rltvi --dry-run -e "$ssh_transport" -- "$source/" "$destination")
                ;;
            sftp)
                command -v lftp >/dev/null 2>&1 || { sayfail "lftp is required for SFTP publishing (install: sudo apt install lftp)."; rm -f "$preview"; return 127; }
                [[ "$host" =~ ^[a-zA-Z0-9._-]+$ && "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] || {
                    sayfail "Invalid SFTP host or user."; rm -f "$preview"; return 1;
                }
                [[ -z "$identity" ]] || { sayfail "For SFTP configure your identity in ~/.ssh/config or SSH agent, not identity_file."; rm -f "$preview"; return 1; }
                _web_content_publish_safe_path "$source" || { sayfail "SFTP source directory has unsupported special characters."; rm -f "$preview"; return 1; }
                # Input restrictions above prevent command injection into the lftp script.
                extra=("set cmd:fail-exit true" "set net:max-retries 1" "open -u \"$user\" sftp://$host:$port" "mirror --reverse --verbose --dry-run --no-perms \"$source\" \"$target\"" "bye")
                command_args=(lftp -e "$(printf '%s; ' "${extra[@]}")")
                ;;
            *) sayfail "Unsupported publication transport: $type"; rm -f "$preview"; return 1 ;;
        esac
        sayinfo "Checking publication changes (no files are written)..."
        "${command_args[@]}" > "$preview" 2>&1 || rc=$?
        if (( rc != 0 )); then
            sayfail "Publication preview failed; no files uploaded."
            while IFS= read -r line; do [[ -n "$line" ]] && sgnd_print --text "$line"; done < "$preview"
            rm -f "$preview"; return "$rc"
        fi
        while IFS= read -r line; do [[ -n "$line" ]] && sgnd_print --text "$line"; done < "$preview"
        rm -f "$preview"
        saywarning "Publishing adds or updates files only; it does NOT remove obsolete files on the destination."
        ask_decision --label "Publish generated files to $selected?" --choices "YES|Y,NO|N" --default "NO" --var decision || return 0
        [[ "$decision" == YES ]] || { saycancel "Publication cancelled."; return 0; }
        rc=0
        case "$type" in
            local)
                mkdir -p -- "$destination" || return 1
                rsync -rltvi -- "$source/" "$destination/" || rc=$?
                ;;
            rsync) rsync -rltvi -e "$ssh_transport" -- "$source/" "$destination" || rc=$? ;;
            sftp)
                extra=("set cmd:fail-exit true" "set net:max-retries 1" "open -u \"$user\" sftp://$host:$port" "mirror --reverse --verbose --no-perms \"$source\" \"$target\"" "bye")
                lftp -e "$(printf '%s; ' "${extra[@]}")" || rc=$?
                ;;
        esac
        if (( rc != 0 )); then sayfail "Publication failed (exit $rc)."; return "$rc"; fi
        sayok "Website published to $selected. Files on the destination have not been deleted."
    }

# - Action dispatch -----------------------------------------------------------------
    # fn: _run_action - Dispatch the requested command-line management action.
    _run_action() {
        local action="${1:?missing action}"
        case "$action" in
            ingest) _web_content_ingest ;;
            edit-metadata) _web_content_manage_page edit-metadata ;;
            move-page) _web_content_manage_page move-page ;;
            manage-sections) _web_content_manage_sections ;;
            manage-config) _web_content_manage_config ;;
            delete)
                # Deletion owns its closing section line and repeat/return dialog.
                _web_content_delete
                return $?
                ;;
            generate) _web_content_generate ;;
            publish) _web_content_publish ;;
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
    main() {
        local action=""
        _framework_locator || return $?
        sgnd_exe_start --autostate -- "$@" || return $?
        action="${ACTION:-status}"
        _run_action "$action"
    }
    main "$@"
