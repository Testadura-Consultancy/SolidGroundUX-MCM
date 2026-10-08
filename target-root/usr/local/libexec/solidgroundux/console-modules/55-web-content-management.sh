# ==================================================================================
# SolidGroundUX Management Console Modules - Web Content Management
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : -
#   Shortname   : WEB_CONTENT_MANAGEMENT
#   Source      : 55-web-content-management.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Ingest, delete, generate, validate, and prepare content for static websites
#
# Description:
#   Registers Web Content Management actions with the SolidGround Management Console.
#   Persistent workflow and user interaction are implemented by manage-web-content.sh;
#   ingestion, deletion, rendering, and validation are provided by the bundled Python WebContent package.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
set -uo pipefail

# - Library guard ------------------------------------------------------------------
    # fn$ _sgnd_lib_guard - Enforce source-only, single-load library initialization
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
    SGND_WEB_CONTENT_MODULE_ID="web-content-management"
    SGND_WEB_CONTENT_MODULE_NAME="Web Content Management"
    SGND_MODULE_ID="$SGND_WEB_CONTENT_MODULE_ID"
    SGND_MODULE_NAME="$SGND_WEB_CONTENT_MODULE_NAME"

# - Management dispatch -------------------------------------------------------------
    _web_content_run_manage() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-web-content.sh" --action "$action"
    }

    # fn: _web_content_run_mutating_manage - Run a content-changing action and mark generation pending
        # . Behavior
        #   - Runs the requested standalone Web Content Management action.
        #   - Receives the number of changed canonical content files through a temporary
        #     activity marker written by manage-web-content.sh.
        #   - Marks Generate website with warning status whenever at least one canonical
        #     content file actually changed, including a partially successful batch.
        #   - Leaves the Generate website status unchanged when no canonical content changed.
    _web_content_run_mutating_manage() {
        local action="${1:?missing action}"
        local activity_file=""
        local changed=0
        local rc=0

        activity_file="$(mktemp)" || {
            saywarning "Could not create the temporary web-content activity marker; generation status will not be updated automatically."
            _web_content_run_manage "$action"
            return $?
        }

        SGND_WEB_CONTENT_ACTIVITY_FILE="$activity_file" _web_content_run_manage "$action" || rc=$?
        if [[ -s "$activity_file" ]]; then
            read -r changed < "$activity_file" || changed=0
            if [[ "$changed" =~ ^[0-9]+$ ]] && (( changed > 0 )); then
                sgnd_menu_set_item_status "web-content-generate" "warning" ||
                    saywarning "Website generation is pending, but the Generate website menu status could not be updated."
            fi
        fi

        rm -f -- "$activity_file"
        return "$rc"
    }

    web_content_ingest()          { _web_content_run_mutating_manage ingest; }
    web_content_delete()          { _web_content_run_mutating_manage delete; }
    web_content_generate()        { _web_content_run_manage generate; }
    web_content_validate()        { _web_content_run_manage validate; }
    web_content_prepare_social()  { _web_content_run_manage prepare-social; }
    web_content_status()          { _web_content_run_manage status; }

# - Module validation contract ------------------------------------------------------
    validate_module_web_content_management() {
        local python_root=""
        if ! command -v python3 >/dev/null 2>&1; then
            SGND_MODULE_VALIDATION_MESSAGE="Python 3 is not available on this host."
            return 1
        fi
        if [[ "${SGND_FRAMEWORK_ROOT:-/}" == "/" ]]; then
            python_root="/usr/local/lib/solidgroundux/py/webcontent"
        else
            python_root="${SGND_FRAMEWORK_ROOT%/}/usr/local/lib/solidgroundux/py/webcontent"
        fi
        if [[ ! -r "$python_root/__init__.py" ]]; then
            SGND_MODULE_VALIDATION_MESSAGE="WebContent Python engine is not installed."
            return 1
        fi
        SGND_MODULE_VALIDATION_MESSAGE="Web Content Management engine is available."
        return 0
    }

# - Console registration ------------------------------------------------------------
    sgnd_menu_register_group \
        "$SGND_WEB_CONTENT_MODULE_ID" \
        "$SGND_WEB_CONTENT_MODULE_NAME" \
        "$(sgnd_header_get_field_value "${BASH_SOURCE[0]}" "Metadata" "Purpose")" \
        0 1 550

    sgnd_menu_register_item "web-content-ingest" "$SGND_WEB_CONTENT_MODULE_ID" "Ingest Markdown" "web_content_ingest" "Import one or more Markdown files, reuse remembered metadata defaults, and archive processed originals" 0 15 1
    sgnd_menu_register_item "web-content-delete" "$SGND_WEB_CONTENT_MODULE_ID" "Delete page" "web_content_delete" "Remove one or more child pages or sections from active content and archive them for recovery" 0 0 1
    sgnd_menu_register_item "web-content-generate" "$SGND_WEB_CONTENT_MODULE_ID" "Generate website" "web_content_generate" "Generate a static website from Markdown, templates, CSS, and assets" 0 15 1
    sgnd_menu_register_item "web-content-validate" "$SGND_WEB_CONTENT_MODULE_ID" "Validate website source" "web_content_validate" "Validate configuration, content metadata, templates, and CSS content styles" 0 15 1
    sgnd_menu_register_item "web-content-social" "$SGND_WEB_CONTENT_MODULE_ID" "Prepare social media drafts" "web_content_prepare_social" "Generate platform-specific social-media drafts from article metadata" 0 15 1
    sgnd_menu_register_item "web-content-status" "$SGND_WEB_CONTENT_MODULE_ID" "Show web-content status" "web_content_status" "Show engine availability and remembered source/output settings" 0 15 1

    sayinfo "Web Content Management module registered with the console."
