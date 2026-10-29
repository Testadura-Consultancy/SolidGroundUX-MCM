# ==================================================================================
# SolidGroundUX Management Console Modules - Web Content Management
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2630201
#   Shortname   : WEB_CONTENT_MANAGEMENT
#   Source      : 55-web-content-management.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Ingest, delete, generate, validate, and prepare content for static websites
#
#   Checksum : ce5878438c978675419f1e34c1ce212166e97e4ec7f6e11157cc6ed46601628e
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

    web_content_retrieve_incoming()  { _web_content_run_manage retrieve-incoming; }
    # fn: web_content_import_local - Review and explicitly copy local files into incoming.
    web_content_import_local()     { _web_content_run_manage import-local; }
    web_content_configure_source()  { _web_content_run_manage configure-source; }
    web_content_ingest_incoming() { _web_content_run_manage ingest-incoming; }
    web_content_ingest()          { _web_content_run_mutating_manage ingest; }
    web_content_delete()          { _web_content_run_mutating_manage delete; }
    web_content_edit_metadata()   { _web_content_run_mutating_manage edit-metadata; }
    web_content_move_page()       { _web_content_run_mutating_manage move-page; }
    web_content_generate()        { _web_content_run_manage generate; }
    # fn: web_content_publish - Preview and synchronize generated website files to a configured destination.
    web_content_publish()         { _web_content_run_manage publish; }
    web_content_validate()        { _web_content_run_manage validate; }
    web_content_prepare_social()  { _web_content_run_manage prepare-social; }
    web_content_status()          { _web_content_run_manage status; }

    # fn$ web_content_assemble_bundle - Open the documentation bundle manager
        # Returns:
        #   Exit status of the standalone bundle manager.
        # Usage:
        #   web_content_assemble_bundle
    web_content_assemble_bundle() { _sgnd_run_module_script "manage-bundles.sh"; }
    # fn: web_content_manage_config - Select and edit an existing website configuration file.
    web_content_manage_config()   { _web_content_run_mutating_manage manage-config; }

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
    # Workflow order: stage and ingest, manage content, validate, then generate/publish.
    # Keep the legacy ingest action callable for compatibility, but do not expose a
    # second ingest path in the menu: all new content goes through Incoming review.
    sgnd_menu_register_group "web-content-ingestion" "Ingestion" "Acquire and review staged content" 0 1 550
    sgnd_menu_register_group "web-content-manage" "Manage" "Pages and repository configuration" 0 1 551
    sgnd_menu_register_group "web-content-validation" "Validation" "Source validation and status" 0 1 552
    sgnd_menu_register_group "web-content-documentation" "SolidGroundUX Documentation" "Manage documentation bundles" 0 1 553
    sgnd_menu_register_group "web-content-publish" "Publish" "Website generation and publication" 0 1 554

    # Ingestion: staging does not modify canonical content until review confirms it.
    sgnd_menu_register_item "web-content-retrieve" "web-content-ingestion" "Retrieve Incoming" "web_content_retrieve_incoming" "Retrieve staged files from the configured SSH source server" 0 15 1
    sgnd_menu_register_item "web-content-import-local" "web-content-ingestion" "Import local files to Incoming" "web_content_import_local" "Copy local files, directories or ZIP archives to Incoming without changing content" 0 0 1
    sgnd_menu_register_item "web-content-ingest-incoming" "web-content-ingestion" "Review and ingest Incoming package" "web_content_ingest_incoming" "Preview and explicitly accept staged files, directories or ZIP contents" 0 0 1

    # Manage: page metadata and structure; sections are derived from content folders.
    sgnd_menu_register_item "web-content-metadata" "web-content-manage" "Edit page metadata" "web_content_edit_metadata" "Browse pages and update front matter without changing Markdown body" 0 0 1
    sgnd_menu_register_item "web-content-move" "web-content-manage" "Move / rename" "web_content_move_page" "Move a page to another existing section or change its URL slug" 0 0 1
    sgnd_menu_register_item "web-content-delete" "web-content-manage" "Delete page" "web_content_delete" "Remove pages or sections from active content and archive them for recovery" 0 0 1
    sgnd_menu_register_item "web-content-source-config" "web-content-manage" "Configure source server" "web_content_configure_source" "Persist SSH host, user, port and remote incoming directory" 0 0 1
    sgnd_menu_register_item "web-content-config" "web-content-manage" "Manage Config" "web_content_manage_config" "Select and edit an existing website configuration file" 0 0 1

    # Validate before generating and publishing the website.
    sgnd_menu_register_item "web-content-validate" "web-content-validation" "Validate website source" "web_content_validate" "Validate configuration, content metadata, templates, and CSS styles" 0 15 1
    sgnd_menu_register_item "web-content-status" "web-content-validation" "Show web-content status" "web_content_status" "Show engine availability and remembered source/output settings" 0 15 1

    # Documentation bundles produce Markdown inputs for the existing WCM workflow.
    sgnd_menu_register_item "web-content-documentation-bundle" "web-content-documentation" "Assemble documentation bundle" "web_content_assemble_bundle" "Generate a Markdown version of documentation based on one or more repositories" 0 0 1

    # Publication is explicit: ingestion never automatically publishes content.
    sgnd_menu_register_item "web-content-generate" "web-content-publish" "Generate website" "web_content_generate" "Generate a static website from Markdown, templates, CSS, and assets" 0 15 1
    sgnd_menu_register_item "web-content-publish-site" "web-content-publish" "Publish website" "web_content_publish" "Preview and upload generated files using a configured publishing profile" 0 0 1

    sayinfo "Web Content Management module registered with the console."
