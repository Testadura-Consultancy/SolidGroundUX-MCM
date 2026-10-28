#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX MCM - Manage Documentation Bundles
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Source      : manage-bundles.sh
#   Type        : script
#   Group       : Web Content Management
#   Purpose     : Manage documentation bundles through the SolidGroundUX interface.
#
# Description:
#   MCM frontend for sgnd_doc_bundles.py and sgnd_doc_markdown.py. The Python programs
#   remain responsible for persistence, validation, and Markdown preparation.
#   Menus, tables, prompts, messages and lifecycle use the framework's public APIs.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Copyright   : (c) 2025 - 2026 Testadura Consultancy
#   License     : Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail

# - Bootstrap -------------------------------------------------------------------------
    # fn$ _framework_locator - Resolve the framework root and load executable support
        # . Purpose
        #   Locate the active installed or staged SolidGroundUX tree using the canonical
        #   executable-template path rules.
        # . Returns
        #   0 on success; 126 when the executable runtime cannot be found.
        # . Usage
        #   _framework_locator || return $?
    _framework_locator() {
        local script_file="" path_without_root="" component="" framework_root="" exe_common=""
        local index=0 root_index=-1
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
                usr|etc|var) root_index=$index ;;
            esac
        done
        if (( root_index < 0 )); then
            printf 'FATAL: Cannot determine SolidGroundUX framework root from: %s\n' "$script_file" >&2
            return 126
        fi
        if (( root_index == 0 )); then
            framework_root="/"
        else
            for (( index=0; index<root_index; index++ )); do
                framework_root+="/${path_parts[$index]}"
            done
        fi
        SGND_FRAMEWORK_ROOT="$framework_root"
        if [[ "$SGND_FRAMEWORK_ROOT" == / ]]; then
            exe_common=/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh
        else
            exe_common="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh"
            [[ -r "$exe_common" ]] || exe_common=/usr/local/lib/solidgroundux/common/sgnd-exe-common.sh
        fi
        [[ -r "$exe_common" ]] || {
            printf 'FATAL: Cannot read executable common library: %s\n' "$exe_common" >&2
            return 126
        }
        # shellcheck source=/dev/null
        source "$exe_common"
    }

# - Script identity -------------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"

# - Framework integration -------------------------------------------------------------
    # Optional libraries are loaded by sgnd_exe_start/sgnd_bootstrap in this order.
    # sgnd-menu uses the datatable API for its menu model.
    SGND_USING=(
        sgnd-datatable.sh
        sgnd-menu.sh
    )
    SGND_ARGS_SPEC=()
    SGND_SCRIPT_EXAMPLES=("  $SGND_SCRIPT_NAME")
    SGND_SCRIPT_GLOBALS=()
    SGND_STATE_VARIABLES=("SGND_DOC_ACTIVE_BUNDLE|Active documentation bundle||")
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=1

# - Local script declarations ---------------------------------------------------------
    SGND_DOC_ACTIVE_BUNDLE="${SGND_DOC_ACTIVE_BUNDLE:-}"
    SGND_BUNDLE_IDS=()
    SGND_BUNDLE_ROWS=()
    SGND_BUNDLE_SOURCE_IDS=()
    SGND_BUNDLE_SOURCE_ROWS=()
    SGND_BUNDLE_SKIP_OUTER_CONTINUE=0

# - Backend access --------------------------------------------------------------------
    # fn: _bundle_python - Call the existing bundle Python CLI without changing its API
        # . Arguments
        #   $@ - Command and arguments from the original doc-bundles.sh implementation.
        # . Output
        #   Prints successful backend output to stdout; errors to stderr via sayfail.
        # . Returns
        #   The backend exit status, or 1/127 on missing files or interpreter.
        # . Usage
        #   _bundle_python list-json
    _bundle_python() {
        local script="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/py/sgnd_doc_bundles.py"
        local output="" rc=0
        [[ "$SGND_FRAMEWORK_ROOT" == / ]] && script=/usr/local/lib/solidgroundux/py/sgnd_doc_bundles.py
        [[ -r "$script" ]] || { sayfail "Bundle manager not found: $script" >&2; return 1; }
        command -v python3 >/dev/null 2>&1 || { sayfail 'Python 3 is not installed'; return 127; }
        output="$(python3 "$script" "$@" 2>&1)" || rc=$?
        if (( rc != 0 )); then
            output="${output#ERROR: }"
            sayfail "${output:-Bundle operation failed}" >&2
            return "$rc"
        fi
        [[ -z "$output" ]] || printf '%s\n' "$output"
        return 0
    }

    # fn: _bundle_markdown_python - Invoke the existing Markdown generator and report JSON
        # . Arguments
        #   $1 - Bundle identifier.
        # . Output
        #   JSON summary from the Markdown generator.
        # . Returns
        #   Generator status, or 1/127 if unavailable.
        # . Usage
        #   _bundle_markdown_python "$SGND_DOC_ACTIVE_BUNDLE"
    _bundle_markdown_python() {
        local script="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/py/sgnd_doc_markdown.py"
        local docs_root="${SGND_FRAMEWORK_ROOT%/}/usr/local/share/doc-sources"
        local output="" rc=0
        local -a args=()
        if [[ "$SGND_FRAMEWORK_ROOT" == / ]]; then
            script=/usr/local/lib/solidgroundux/py/sgnd_doc_markdown.py
            docs_root=/usr/local/share/doc-sources
        fi
        [[ -r "$script" ]] || { sayfail "Markdown generator not found: $script" >&2; return 1; }
        command -v python3 >/dev/null 2>&1 || { sayfail 'Python 3 is not installed'; return 127; }
        args=("$script" "$1")
        [[ ! -d "$docs_root" ]] || args+=(--doc-sources "$docs_root")
        output="$(python3 "${args[@]}" 2>&1)" || rc=$?
        if (( rc != 0 )); then
            output="${output#ERROR: }"
            sayfail "${output:-Markdown preparation failed}" >&2
            return "$rc"
        fi
        printf '%s\n' "$output"
    }

# - Input and view helpers ------------------------------------------------------------
    # fn: _bundle_prompt - Read a value using the framework's ask facility
        # . Arguments
        #   $1 label, $2 default, $3 output variable, $4 optional validator, $5 width.
        # . Returns
        #   ask status (Q with --back returns 1).
        # . Usage
        #   _bundle_prompt 'Bundle title' '' title _bundle_validate_nonempty
    _bundle_prompt() {
        local prompt_label="$1" prompt_default="${2:-}" prompt_target="$3"
        local validator="${4:-}" width="${5:-25}"
        local -a options=(--label "$prompt_label" --var "$prompt_target" --default "$prompt_default" --labelwidth "$width" --back)
        [[ -z "$validator" ]] || options+=(--validate "$validator")
        ask "${options[@]}"
    }

    # fn$ _bundle_validate_nonempty - Reject empty required values
        # . Returns
        #   0 for nonempty input, 1 otherwise.
        # . Usage
        #   _bundle_validate_nonempty "value"
    _bundle_validate_nonempty() { [[ -n "${1//[[:space:]]/}" ]]; }
    # fn$ _bundle_validate_directory - Validate an existing source directory
        # . Returns
        #   0 if directory exists.
        # . Usage
        #   _bundle_validate_directory /tmp
    _bundle_validate_directory() { [[ -d "$1" ]]; }
    # fn$ _bundle_validate_output - Require an absolute output directory
        # . Returns
        #   0 for absolute paths.
        # . Usage
        #   _bundle_validate_output /tmp/docs
    _bundle_validate_output() { [[ "$1" == /* ]]; }
    # fn$ _bundle_validate_overwrite - Accept supported overwrite policies
        # . Returns
        #   0 for replace or fail.
        # . Usage
        #   _bundle_validate_overwrite replace
    _bundle_validate_overwrite() { [[ "$1" == replace || "$1" == fail ]]; }
    # fn$ _bundle_validate_chapter0 - Accept optional existing introduction file
        # . Returns
        #   0 if empty, '-', or an existing file.
        # . Usage
        #   _bundle_validate_chapter0 '-'
    _bundle_validate_chapter0() { [[ -z "$1" || "$1" == '-' || -f "$1" ]]; }
    # fn$ _bundle_validate_position - Require a positive one-based position
        # . Returns
        #   0 for positive integers.
        # . Usage
        #   _bundle_validate_position 2
    _bundle_validate_position() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

    # fn: _bundle_require_active - Reject an operation without a selected bundle
        # . Returns
        #   0 if a bundle is selected; 1 otherwise.
        # . Usage
        #   _bundle_require_active || return $?
    _bundle_require_active() {
        [[ -n "${SGND_DOC_ACTIVE_BUNDLE:-}" ]] && return 0
        sayfail 'Select a bundle first.' >&2
        return 1
    }

    # fn: _bundle_render_table - Render a framework datatable with a named section
        # . Arguments
        #   $1 section title, $2 schema, $3 table array name.
        # . Returns
        #   The status from sgnd_dt_print_table.
        # . Usage
        #   _bundle_render_table 'Bundles' 'No|Identifier' SGND_BUNDLE_ROWS
    _bundle_render_table() {
        sgnd_print
        sgnd_print_sectionheader "$1" --padend 0
        sgnd_dt_print_table "$2" "$3" 1
    }

    # fn: _bundle_read_bundle_table - Populate a datatable from list-json
        # . Behavior
        #   Preserves original JSON CLI and numbered selection semantics.
        # . Outputs (globals)
        #   SGND_BUNDLE_IDS and SGND_BUNDLE_ROWS.
        # . Returns
        #   0 on success; nonzero if the backend or JSON response fails.
        # . Usage
        #   _bundle_read_bundle_table
    _bundle_read_bundle_table() {
        local raw="" encoded="" id="" title="" count="" row="" number=0
        raw="$(_bundle_python list-json)" || return $?
        encoded="$(printf '%s' "$raw" | python3 -c '
import json, sys
items = json.load(sys.stdin)
for item in items:
    def clean(value):
        return str(value).replace("\n", " ").replace("|", "/").replace("\x1f", " ").replace("\r", " ")
    print("\x1f".join((clean(item["id"]), clean(item["title"]), str(len(item["products"])))))
' 2>&1)" || { sayfail "Could not read bundle list: $encoded" >&2; return 1; }
        SGND_BUNDLE_IDS=()
        SGND_BUNDLE_ROWS=()
        while IFS=$'\x1f' read -r id title count; do
            [[ -n "$id" ]] || continue
            ((number+=1))
            SGND_BUNDLE_IDS+=("$id")
            sgnd_dt_append 'No|Identifier|Title|Products' SGND_BUNDLE_ROWS \
                "$number" "$id" "${title:--}" "$count" || return $?
        done <<< "$encoded"
        return 0
    }

    # fn: _bundle_read_sources_table - Populate a datatable from a bundle's products
        # . Outputs (globals)
        #   SGND_BUNDLE_SOURCE_IDS and SGND_BUNDLE_SOURCE_ROWS.
        # . Returns
        #   0 on success; nonzero if backend or JSON parsing fails.
        # . Usage
        #   _bundle_read_sources_table
    _bundle_read_sources_table() {
        local raw="" encoded="" id="" title="" directory="" number=0
        raw="$(_bundle_python show "$SGND_DOC_ACTIVE_BUNDLE")" || return $?
        encoded="$(printf '%s' "$raw" | python3 -c '
import json, sys
item = json.load(sys.stdin)
for source in item["products"]:
    def clean(value):
        return str(value).replace("\n", " ").replace("|", "/").replace("\x1f", " ").replace("\r", " ")
    print("\x1f".join((clean(source["id"]), clean(source["title"]), clean(source["source_dir"]))))
' 2>&1)" || { sayfail "Could not read sources: $encoded" >&2; return 1; }
        SGND_BUNDLE_SOURCE_IDS=()
        SGND_BUNDLE_SOURCE_ROWS=()
        while IFS=$'\x1f' read -r id title directory; do
            [[ -n "$id" ]] || continue
            ((number+=1))
            SGND_BUNDLE_SOURCE_IDS+=("$id")
            sgnd_dt_append 'No|Identifier|Chapter|Directory' SGND_BUNDLE_SOURCE_ROWS \
                "$number" "$id" "${title:--}" "$directory" || return $?
        done <<< "$encoded"
        return 0
    }

    # fn: _bundle_choose_row - Resolve a numbered selection from a provided ID array
        # . Arguments
        #   $1 output variable, $2 nameref array variable.
        # . Returns
        #   0 on selection; 1 for Q/cancellation.
        # . Usage
        #   _bundle_choose_row selected SGND_BUNDLE_IDS
    _bundle_choose_row() {
        local output_var="$1" array_name="$2" choice="" index=0
        local -n candidates="$array_name"
        if (( ${#candidates[@]} == 0 )); then
            saywarning 'No entries to select.'
            return 1
        fi
        while true; do
            _bundle_prompt 'Number (Q=back)' '' choice _bundle_validate_position 18 || return 1
            index=$((10#$choice - 1))
            if (( index < ${#candidates[@]} )); then
                printf -v "$output_var" '%s' "${candidates[$index]}"
                return 0
            fi
            saywarning "Invalid selection: $choice"
        done
    }

    # fn: _bundle_continue - Print a spacer and wait for Enter before returning to the menu
        # . Returns
        #   0 after the prompt completes.
        # . Usage
        #   _bundle_continue
    _bundle_continue() {
        local reply=""
        sgnd_print
        ask --label 'Enter to continue' --var reply --default '' --labelwidth 18 || return 0
        sgnd_clear
        return 0
    }

# - Bundle actions --------------------------------------------------------------------
    # fn: _bundle_list - List saved documentation bundles as a datatable
        # . Returns
        #   Backend or table rendering status.
        # . Usage
        #   _bundle_list
    _bundle_list() {
        _bundle_read_bundle_table || return $?
        _bundle_render_table 'Saved documentation bundles' 'No|Identifier|Title|Products' SGND_BUNDLE_ROWS
        if (( ${#SGND_BUNDLE_IDS[@]} == 0 )); then
            sayinfo 'No bundles have been saved.'
        fi
    }

    # fn: _bundle_select - Select a bundle by its displayed table number
        # . Returns
        #   0 on selection or cancellation; nonzero on loading error.
        # . Usage
        #   _bundle_select
    _bundle_select() {
        local selected=""
        _bundle_list || return $?
        (( ${#SGND_BUNDLE_IDS[@]} > 0 )) || return 0
        _bundle_choose_row selected SGND_BUNDLE_IDS || { saycancel 'Bundle selection cancelled'; return 0; }
        SGND_DOC_ACTIVE_BUNDLE="$selected"
        sayok "Active bundle: $selected"
    }

    # fn: _bundle_create - Create a saved bundle through the existing CLI
        # . Returns
        #   Backend status, or 0 when an input is cancelled.
        # . Usage
        #   _bundle_create
    _bundle_create() {
        local name="" title=""
        _bundle_prompt 'Bundle identifier' '' name _bundle_validate_nonempty || { saycancel 'Create bundle cancelled'; return 0; }
        _bundle_prompt 'Bundle title' "$name" title _bundle_validate_nonempty || { saycancel 'Create bundle cancelled'; return 0; }
        name="${name// /-}"
        _bundle_python create "$name" "$title" || return $?
        SGND_DOC_ACTIVE_BUNDLE="$name"
        sayok "Created bundle: $name"
    }

    # fn: _bundle_configure - Modify the bundle configuration using original CLI fields
        # . Returns
        #   Backend status, or 0 on cancellation.
        # . Usage
        #   _bundle_configure
    _bundle_configure() {
        local raw="" decoded="" title="" output_dir="" overwrite="" chapter0="" entry="" field="" previous=""
        local -a current=() rows=()
        _bundle_require_active || return $?
        raw="$(_bundle_python show "$SGND_DOC_ACTIVE_BUNDLE")" || return $?
        decoded="$(printf '%s' "$raw" | python3 -c '
import json, sys
item = json.load(sys.stdin)
for key in ("title", "output_dir", "overwrite", "chapter0"):
    print(str(item.get(key, "")).replace("\n", " ").replace("\r", " "))
' 2>&1)" || { sayfail "Could not parse bundle configuration: $decoded" >&2; return 1; }
        mapfile -t current <<< "$decoded"
        title="${current[0]:-}"
        output_dir="${current[1]:-}"
        overwrite="${current[2]:-replace}"
        chapter0="${current[3]:-}"
        sgnd_print
        sgnd_print_sectionheader 'Configure bundle' --padend 0
        sgnd_print_labeledvalue --label 'Bundle' --value "$SGND_DOC_ACTIVE_BUNDLE" --labelwidth 25
        sgnd_print 'Enter Q to cancel an input. Use - to clear Chapter 0.'
        for field in title output_dir overwrite chapter0; do
            entry=""
            case "$field" in
                title)      _bundle_prompt 'Bundle title' "$title" entry _bundle_validate_nonempty 27 || { saycancel 'Configuration cancelled'; return 0; } ;;
                output_dir) _bundle_prompt 'Output directory' "$output_dir" entry _bundle_validate_output 27 || { saycancel 'Configuration cancelled'; return 0; } ;;
                overwrite)  _bundle_prompt 'Overwrite policy' "$overwrite" entry _bundle_validate_overwrite 27 || { saycancel 'Configuration cancelled'; return 0; } ;;
                chapter0)   _bundle_prompt 'Chapter 0 Markdown file' "$chapter0" entry _bundle_validate_chapter0 27 || { saycancel 'Configuration cancelled'; return 0; } ;;
            esac
            [[ "$field" == chapter0 && "$entry" == - ]] && entry=""
            previous="${!field}"
            [[ "$entry" == "$previous" ]] && continue
            _bundle_python set "$SGND_DOC_ACTIVE_BUNDLE" "$field" "$entry" >/dev/null || return $?
            printf -v "$field" '%s' "$entry"
        done
        rows=()
        sgnd_dt_append 'Setting|Value' rows 'Identifier' "$SGND_DOC_ACTIVE_BUNDLE" || return $?
        sgnd_dt_append 'Setting|Value' rows 'Title' "${title//|//}" || return $?
        sgnd_dt_append 'Setting|Value' rows 'Output directory' "${output_dir//|//}" || return $?
        sgnd_dt_append 'Setting|Value' rows 'Overwrite policy' "$overwrite" || return $?
        sgnd_dt_append 'Setting|Value' rows 'Chapter 0' "${chapter0//|//}" || return $?
        _bundle_render_table 'Bundle configuration' 'Setting|Value' rows
    }

    # fn: _bundle_validate - Validate the active bundle
        # . Returns
        #   Backend status, or 1 if no bundle is selected.
        # . Usage
        #   _bundle_validate
    _bundle_validate() {
        _bundle_require_active || return $?
        _bundle_python validate "$SGND_DOC_ACTIVE_BUNDLE"
    }

    # fn: _bundle_delete - Confirm and delete a saved bundle
        # . Returns
        #   Backend status, or 0 when cancelled.
        # . Usage
        #   _bundle_delete
    _bundle_delete() {
        local confirmation=""
        _bundle_require_active || return $?
        _bundle_prompt 'Type Delete to confirm removal' '' confirmation || { saycancel 'Deletion cancelled'; return 0; }
        if [[ "$confirmation" != Delete ]]; then
            saycancel 'Deletion cancelled'
            return 0
        fi
        _bundle_python delete "$SGND_DOC_ACTIVE_BUNDLE" || return $?
        SGND_DOC_ACTIVE_BUNDLE=''
        sayok 'Bundle deleted.'
    }

    # fn: _bundle_generate - Validate bundle and prepare the Markdown WWW root
        # . Returns
        #   Generator or summary-rendering status.
        # . Usage
        #   _bundle_generate
    _bundle_generate() {
        local raw="" parsed="" label="" value=""
        local -a rows=()
        _bundle_require_active || return $?
        _bundle_python validate "$SGND_DOC_ACTIVE_BUNDLE" >/dev/null || return $?
        sgnd_print
        sgnd_print_sectionheader 'Prepare Markdown' --padend 0
        sgnd_print_labeledvalue --label 'Bundle' --value "$SGND_DOC_ACTIVE_BUNDLE" --labelwidth 20
        raw="$(_bundle_markdown_python "$SGND_DOC_ACTIVE_BUNDLE")" || return $?
        parsed="$(printf '%s' "$raw" | python3 -c '
import json, sys
item = json.load(sys.stdin)
for key, title in (("output", "Output directory"), ("products", "Products"),
                   ("files", "Source files"), ("functions", "Functions"),
                   ("declarations", "Declarations"), ("lines", "Lines")):
    value = str(item.get(key, 0)).replace("|", "/").replace("\n", " ")
    print(title + "\x1f" + value)
' 2>&1)" || { sayfail "Could not parse Markdown summary: $parsed" >&2; return 1; }
        rows=()
        while IFS=$'\x1f' read -r label value; do
            [[ -n "$label" ]] || continue
            sgnd_dt_append 'Metric|Value' rows "$label" "$value" || return $?
        done <<< "$parsed"
        _bundle_render_table 'Markdown prepared' 'Metric|Value' rows
    }

# - Source management -----------------------------------------------------------------
    # fn: _bundle_sources_table - Display the ordered product/source datatable
        # . Returns
        #   0 on success; backend/table status otherwise.
        # . Usage
        #   _bundle_sources_table
    _bundle_sources_table() {
        _bundle_read_sources_table || return $?
        _bundle_render_table 'Sources in bundle' 'No|Identifier|Chapter|Directory' SGND_BUNDLE_SOURCE_ROWS
        if (( ${#SGND_BUNDLE_SOURCE_IDS[@]} == 0 )); then
            sayinfo 'No sources have been configured.'
        fi
    }

    # fn: _bundle_source_add - Add a source repository to the active bundle
        # . Returns
        #   Backend status, or 0 on cancellation.
        # . Usage
        #   _bundle_source_add
    _bundle_source_add() {
        local id="" title="" source=""
        _bundle_prompt 'Product identifier' '' id _bundle_validate_nonempty || { saycancel 'Add source cancelled'; return 0; }
        _bundle_prompt 'Chapter title' '' title _bundle_validate_nonempty || { saycancel 'Add source cancelled'; return 0; }
        _bundle_prompt 'Source directory' '' source _bundle_validate_directory || { saycancel 'Add source cancelled'; return 0; }
        _bundle_python add-product "$SGND_DOC_ACTIVE_BUNDLE" "$id" "$title" "$source"
    }

    # fn: _bundle_source_edit - Edit the chapter title and source directory
        # . Returns
        #   Backend status, or 0 on cancellation.
        # . Usage
        #   _bundle_source_edit
    _bundle_source_edit() {
        local selected="" raw="" encoded="" title="" source=""
        local -a values=()
        _bundle_sources_table || return $?
        _bundle_choose_row selected SGND_BUNDLE_SOURCE_IDS || { saycancel 'Edit source cancelled'; return 0; }
        raw="$(_bundle_python show "$SGND_DOC_ACTIVE_BUNDLE")" || return $?
        encoded="$(printf '%s' "$raw" | python3 -c '
import json,sys
for item in json.load(sys.stdin)["products"]:
    if item["id"] == sys.argv[1]:
        print(item["title"]); print(item["source_dir"]); break
' "$selected" 2>&1)" || { sayfail "Could not read source: $encoded" >&2; return 1; }
        mapfile -t values <<< "$encoded"
        if (( ${#values[@]} != 2 )); then
            sayfail "Unknown source: $selected" >&2
            return 1
        fi
        _bundle_prompt 'Chapter title' "${values[0]}" title _bundle_validate_nonempty || { saycancel 'Edit source cancelled'; return 0; }
        _bundle_prompt 'Source directory' "${values[1]}" source _bundle_validate_directory || { saycancel 'Edit source cancelled'; return 0; }
        _bundle_python edit-product "$SGND_DOC_ACTIVE_BUNDLE" "$selected" --title "$title" --source-dir "$source"
    }

    # fn: _bundle_source_move - Reorder a source repository chapter
        # . Returns
        #   Backend status, or 0 on cancellation.
        # . Usage
        #   _bundle_source_move
    _bundle_source_move() {
        local selected="" position=""
        _bundle_sources_table || return $?
        _bundle_choose_row selected SGND_BUNDLE_SOURCE_IDS || { saycancel 'Move source cancelled'; return 0; }
        _bundle_prompt 'New chapter position (1-based)' '' position _bundle_validate_position || { saycancel 'Move source cancelled'; return 0; }
        _bundle_python move-product "$SGND_DOC_ACTIVE_BUNDLE" "$selected" "$position"
    }

    # fn: _bundle_source_remove - Remove a source repository from the bundle
        # . Returns
        #   Backend status, or 0 on cancellation.
        # . Usage
        #   _bundle_source_remove
    _bundle_source_remove() {
        local selected=""
        _bundle_sources_table || return $?
        _bundle_choose_row selected SGND_BUNDLE_SOURCE_IDS || { saycancel 'Remove source cancelled'; return 0; }
        _bundle_python remove-product "$SGND_DOC_ACTIVE_BUNDLE" "$selected"
    }

# - Active bundle status --------------------------------------------------------------
    # fn: _bundle_print_active_summary - Show active bundle below the title bar
        # . Returns
        #   0, including when no bundle is selected.
        # . Usage
        #   _bundle_print_active_summary
    _bundle_print_active_summary() {
        local raw="" name="" title="" output_dir="" overwrite="" chapter0="" source="" color="" reset="" encoded=""
        local -a lines=()
        color="$(sgnd_sgr "${SGND_UI_VALUE:-yellow}")"
        reset="${RESET:-$'\e[0m'}"
        if [[ -z "${SGND_DOC_ACTIVE_BUNDLE:-}" ]]; then
            sgnd_print_labeledvalue --label 'Active bundle' --value "${color}None${reset}" --labelwidth 19
            sgnd_print
            return 0
        fi
        raw="$(_bundle_python show "$SGND_DOC_ACTIVE_BUNDLE")" || {
            sgnd_print_labeledvalue --label 'Active bundle' --value "${color}${SGND_DOC_ACTIVE_BUNDLE}${reset}" --labelwidth 19
            sgnd_print
            return 0
        }
        encoded="$(printf '%s' "$raw" | python3 -c '
import json, sys
bundle = json.load(sys.stdin)
def clean(value):
    return str(value if value is not None else "").replace("\n", " ").replace("\r", " ")
for key in ("id", "title", "output_dir", "overwrite", "chapter0"):
    print(clean(bundle.get(key, "")))
for product in bundle.get("products", []):
    print(clean(product.get("title") or product.get("id") or "?"))
' 2>&1)" || {
            sayfail "Could not read active bundle summary: $encoded" >&2
            return 1
        }
        mapfile -t lines <<< "$encoded"
        name="${lines[0]:-$SGND_DOC_ACTIVE_BUNDLE}"
        title="${lines[1]:-}"
        output_dir="${lines[2]:-}"
        overwrite="${lines[3]:-}"
        chapter0="${lines[4]:-}"
        sgnd_print_labeledvalue --label 'Active bundle' --value "${color}${name}${reset}" --labelwidth 19
        sgnd_print_labeledvalue --label 'Title' --value "${title:--}" --labelwidth 19
        sgnd_print_labeledvalue --label 'Output directory' --value "${output_dir:--}" --labelwidth 19
        sgnd_print_labeledvalue --label 'Overwrite policy' --value "${overwrite:--}" --labelwidth 19
        sgnd_print_labeledvalue --label 'Chapter 0' --value "${chapter0:-(Automatically generated)}" --labelwidth 19
        if (( ${#lines[@]} <= 5 )); then
            sgnd_print_labeledvalue --label 'Sources' --value '(None)' --labelwidth 19
        else
            sgnd_print_labeledvalue --label 'Sources' --value "${color}- ${lines[5]}${reset}" --labelwidth 19
            for source in "${lines[@]:6}"; do
                sgnd_print "                      ${color}- ${source}${reset}"
            done
        fi
        sgnd_print
    }

    # fn: _bundle_show_menu - Render framework menu with a status block after its title
        # . Purpose
        #   Keep the framework menu model, paging, item numbering and dispatch intact.
        #   There is currently no public framework after-title render callback.
        # . Returns
        #   Framework rendering status.
        # . Usage
        #   _bundle_show_menu
    _bundle_show_menu() {
        local idx="" group_key="" builtin=0
        _sgnd_console_refresh_model_cache
        _sgnd_console_collect_group_render_indexes
        _sgnd_console_collect_visible_item_indexes
        SGND_RENDER_KEY_WIDTH="$(_sgnd_console_display_key_width)"
        SGND_RENDER_LABEL_WIDTH="$(_sgnd_console_calc_label_width)"
        _sgnd_console_render_menu_title
        _bundle_print_active_summary
        _sgnd_console_render_page_header
        _sgnd_console_render_menu_body_paged
        for idx in "${SGND_GROUP_RENDER_INDEXES[@]}"; do
            builtin="${SGND_GROUP_CACHE_BUILTIN[$idx]}"
            (( builtin )) || continue
            group_key="${SGND_GROUP_CACHE_KEY[$idx]}"
            _sgnd_console_render_group "$group_key"
        done
        if _sgnd_flag_is_on "${SGND_MENU_SHOW_TOGGLEBAR:-1}"; then
            _sgnd_console_render_togglebar
        fi
    }

# - Framework menus -------------------------------------------------------------------
    # fn: _bundle_register_main_menu - Register bundle actions through sgnd-menu
        # . Returns
        #   Status of menu registration.
        # . Usage
        #   _bundle_register_main_menu
    _bundle_register_main_menu() {
        sgnd_menu_create 'Documentation Bundles' ' ' || return $?
        SGND_MENU_SHOW_TOGGLEBAR=0
        SGND_CURRENT_MODULE_SOURCE='manage-bundles'
        SGND_MENU_ACTIVE_SOURCE="$SGND_CURRENT_MODULE_SOURCE"
        sgnd_menu_register_group 'bundle-selection' 'Selection' '' 0 1 10 || return $?
        sgnd_menu_register_item 'bundle-list' 'bundle-selection' 'List bundles' '_bundle_list' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'bundle-select' 'bundle-selection' 'Select bundle' '_bundle_select' '' 0 0 1 0 || return $?
        sgnd_menu_register_group 'bundle-management' 'Bundle management' '' 0 1 20 || return $?
        sgnd_menu_register_item 'bundle-create' 'bundle-management' 'Create bundle' '_bundle_create' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'bundle-configure' 'bundle-management' 'Configure bundle' '_bundle_configure' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'bundle-sources' 'bundle-management' 'Manage sources' '_bundle_manage_sources' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'bundle-validate' 'bundle-management' 'Validate bundle' '_bundle_validate' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'bundle-delete' 'bundle-management' 'Delete bundle' '_bundle_delete' '' 0 0 1 0 || return $?
        sgnd_menu_register_group 'bundle-generation' 'Generation' '' 0 1 30 || return $?
        sgnd_menu_register_item 'bundle-generate' 'bundle-generation' 'Prepare Markdown' '_bundle_generate' '' 0 0 1 0
    }

    # fn: _bundle_register_sources_menu - Register the source-management submenu
        # . Returns
        #   Status of menu registration.
        # . Usage
        #   _bundle_register_sources_menu
    _bundle_register_sources_menu() {
        sgnd_menu_create 'Manage sources' ' ' || return $?
        SGND_MENU_SHOW_TOGGLEBAR=0
        SGND_CURRENT_MODULE_SOURCE='manage-bundles'
        SGND_MENU_ACTIVE_SOURCE="$SGND_CURRENT_MODULE_SOURCE"
        sgnd_menu_register_group 'source-management' 'Source management' '' 0 1 10 || return $?
        sgnd_menu_register_item 'source-add' 'source-management' 'Add source' '_bundle_source_add' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'source-edit' 'source-management' 'Edit source' '_bundle_source_edit' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'source-move' 'source-management' 'Move source' '_bundle_source_move' '' 0 0 1 0 || return $?
        sgnd_menu_register_item 'source-remove' 'source-management' 'Remove source' '_bundle_source_remove' '' 0 0 1 0
    }

    # fn: _bundle_manage_sources - Show nested source menu with per-action continue
        # . Returns
        #   0 when user returns to bundle menu; nonzero on menu construction failure.
        # . Usage
        #   _bundle_manage_sources
    _bundle_manage_sources() {
        local choice="" rc=0
        _bundle_require_active || return $?
        # Inner actions have already shown their own continue prompt on return.
        SGND_BUNDLE_SKIP_OUTER_CONTINUE=1
        while true; do
            _bundle_sources_table || { _bundle_continue || true; return 1; }
            _bundle_register_sources_menu || return $?
            _bundle_show_menu || return $?
            sgnd_print '   Q) Back to bundles'
            sgnd_print
            printf 'Selection : ' >/dev/tty
            sgnd_menu_read_choice choice || return $?
            case "$choice" in
                EXIT|ESC) return 0 ;;
                RESET|REDRAW|'<'|'>'|L|l) continue ;;
            esac
            rc=0
            sgnd_menu_dispatch "$choice" || rc=$?
            _bundle_continue
        done
    }

# - Main ------------------------------------------------------------------------------
    # fn: main - Start SolidGroundUX and manage documentation bundles
        # . Arguments
        #   $@ Framework/script arguments.
        # . Returns
        #   0 on normal exit; nonzero for bootstrap or menu failures.
        # . Usage
        #   main "$@"
    main() {
        local choice="" rc=0
        _framework_locator || return $?
        sgnd_exe_start --autostate -- "$@" || return $?
        while true; do
            _bundle_register_main_menu || return $?
            _bundle_show_menu || return $?
            sgnd_print
            printf 'Selection : ' >/dev/tty
            sgnd_menu_read_choice choice || return $?
            case "$choice" in
                EXIT|ESC) return 0 ;;
                RESET|REDRAW|'<'|'>'|L|l) continue ;;
            esac
            SGND_BUNDLE_SKIP_OUTER_CONTINUE=0
            rc=0
            sgnd_menu_dispatch "$choice" || rc=$?
            if (( SGND_BUNDLE_SKIP_OUTER_CONTINUE )); then
                continue
            fi
            _bundle_continue
        done
    }

    main "$@"
