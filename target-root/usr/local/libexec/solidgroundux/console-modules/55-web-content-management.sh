# ==================================================================================
# SolidGroundUX Management Console Modules - Web Content Management
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2630700
#   Shortname   : WEB_CONTENT_MANAGEMENT
#   Source      : 55-web-content-management.sh
#   Type        : module
#   Group       : Modules
#   Subgroup    : Web Content Management
#   Purpose     : Ingest, delete, generate, validate, and prepare content for static websites
#
#   Checksum : 4571b2be25fa3918a7af3cbf72bbc988d05dda9e5e1180216401d403eba6aee5
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
        #   ```bash
        #   _sgnd_lib_guard
        #   ```
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
    # fn: _web_content_run_manage - Manage content run in the web server workflow.
        # . Purpose
        #   Run the selected Web Content Management action through its standalone manager.
        #
        # . Arguments
        #   - `$1`: Management action to execute.
        # . Usage
        #   ```bash
        #   _web_content_run_manage "status"
        #   ```
    _web_content_run_manage() {
        local action="${1:?missing action}"
        _sgnd_run_module_script "manage-web-content.sh" --action "$action"
    }

    # fn: _web_content_run_mutating_manage - Run a content-changing action and mark generation pending
        # . Purpose
        #   Run a content-changing action and mark generation pending.
        #
        # . Arguments
        #   - `$1`: Management action to execute.
        # . Behavior
        #   - Runs the requested standalone Web Content Management action.
        #   - Receives the number of changed canonical content files through a temporary
        #     activity marker written by manage-web-content.sh.
        #   - Marks Generate website with warning status whenever at least one canonical
        #     content file actually changed, including a partially successful batch.
        #   - Leaves the Generate website status unchanged when no canonical content changed.
        #
        # . Usage
        #   ```bash
        #   _web_content_run_mutating_manage "ingest"
        #   ```
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

    # fn: _web_content_mark_generation_dependencies - Persist warnings for downstream actions
        # . Purpose
        #   Mark downstream publishing and generation actions as pending after a
        #   confirmed successful upstream generation.
        #
        # . Arguments
        #   - `$@`: Registered menu-item keys to mark warning.
        #
        # . Behavior
        #   - Uses the Management Console action-result store so the warning survives
        #     menu redraws and subsequent console sessions.
        #   - Does not alter the result of the completed generation itself.
        #
        # . Usage
        #   ```bash
        #   _web_content_mark_generation_dependencies "web-content-publish-site"
        #   ```
    _web_content_mark_generation_dependencies() {
        local item_key=""
        for item_key in "$@"; do
            if declare -F sgnd_console_record_action_result >/dev/null 2>&1; then
                sgnd_console_record_action_result "$item_key" 2 ||
                    saywarning "Could not persist pending status for $item_key."
            elif declare -F sgnd_menu_set_item_status >/dev/null 2>&1; then
                sgnd_menu_set_item_status "$item_key" warning ||
                    saywarning "Could not update pending status for $item_key."
            else
                saywarning "No menu status API available for $item_key."
            fi
        done
        return 0
    }

    # fn: _web_content_run_generation_tracked - Run generation and invalidate downstream results
        # . Purpose
        #   Run documentation or website generation, then mark dependent actions
        #   as pending only when the helper confirms actual successful generation.
        #
        # . Arguments
        #   - `$1`: `documentation` or `website`.
        #
        # . Behavior
        #   - Passes a temporary completion marker to the standalone helper.
        #   - Q/Cancel and empty bundle selections do not change downstream icons.
        #   - Successful documentation generation warns GitHub Pages, website
        #     generation, and website publication.
        #   - Successful website generation warns website publication only.
        #
        # . Returns
        #   Exit status of the selected generation workflow.
        #
        # . Usage
        #   ```bash
        #   _web_content_run_generation_tracked documentation
        #   _web_content_run_generation_tracked website
        #   ```
    _web_content_run_generation_tracked() {
        local generation_kind="${1:?missing generation kind}"
        local marker_file="" rc=0

        marker_file="$(mktemp)" || {
            saywarning "Could not track generation completion; dependent menu statuses will not be updated."
            case "$generation_kind" in
                documentation) _sgnd_run_module_script "manage-bundles.sh" --generate ;;
                website) _web_content_run_manage generate ;;
                *) return 2 ;;
            esac
            return $?
        }

        case "$generation_kind" in
            documentation)
                SGND_DOC_BUNDLE_GENERATION_MARKER_FILE="$marker_file" \
                    _sgnd_run_module_script "manage-bundles.sh" --generate || rc=$?
                ;;
            website)
                SGND_WEB_CONTENT_GENERATION_MARKER_FILE="$marker_file" \
                    _web_content_run_manage generate || rc=$?
                ;;
            *)
                rm -f -- "$marker_file"
                return 2
                ;;
        esac

        if (( rc == 0 )) && grep -qx 'generated' "$marker_file"; then
            if [[ "$generation_kind" == documentation ]]; then
                _web_content_mark_generation_dependencies \
                    "web-content-documentation-github" \
                    "web-content-generate" \
                    "web-content-publish-site"
            else
                _web_content_mark_generation_dependencies "web-content-publish-site"
            fi
        fi
        rm -f -- "$marker_file"
        return "$rc"
    }

    # fn: web_content_retrieve_incoming - Call `_web_content_run_manage` with the `retrieve-incoming` action.
        # . Purpose
        #   Invoke the retrieve incoming action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_retrieve_incoming
        #   ```
    web_content_retrieve_incoming()  { _web_content_run_manage retrieve-incoming; }
    # fn: web_content_import_local - Review and explicitly copy local files into incoming.
        # . Purpose
        #   Review and explicitly copy local files into incoming.
        #
        # . Usage
        #   ```bash
        #   web_content_import_local
        #   ```
    web_content_import_local()     { _web_content_run_manage import-local; }
    # fn: web_content_configure_source - Call `_web_content_run_manage` with the `configure-source` action.
        # . Purpose
        #   Invoke the configure source action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_configure_source
        #   ```
    web_content_configure_source()  { _web_content_run_manage configure-source; }
    # fn: web_content_ingest_incoming - Call `_web_content_run_manage` with the `ingest-incoming` action.
        # . Purpose
        #   Invoke the ingest incoming action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_ingest_incoming
        #   ```
    web_content_ingest_incoming() { _web_content_run_manage ingest-incoming; }
    # fn: web_content_ingest - Call `_web_content_run_mutating_manage` with the `ingest` action.
        # . Purpose
        #   Invoke the ingest action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_ingest
        #   ```
    web_content_ingest()          { _web_content_run_mutating_manage ingest; }
    # fn: web_content_delete - Call `_web_content_run_mutating_manage` with the `delete` action.
        # . Purpose
        #   Invoke the delete action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_delete
        #   ```
    web_content_delete()          { _web_content_run_mutating_manage delete; }
    # fn: web_content_edit_metadata - Call `_web_content_run_mutating_manage` with the `edit-metadata` action.
        # . Purpose
        #   Invoke the edit metadata action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_edit_metadata
        #   ```
    web_content_edit_metadata()   { _web_content_run_mutating_manage edit-metadata; }
    # fn: web_content_move_page - Call `_web_content_run_mutating_manage` with the `move-page` action.
        # . Purpose
        #   Invoke the move page action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_move_page
        #   ```
    web_content_move_page()       { _web_content_run_mutating_manage move-page; }
    # fn: web_content_generate - Call `_web_content_run_manage` with the `generate` action.
        # . Purpose
        #   Generate the website and invalidate the last publication status only
        #   after confirmed successful generation.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_generate
        #   ```
    web_content_generate()        { _web_content_run_generation_tracked website; }
    # fn: web_content_publish - Preview and synchronize generated website files to a configured destination.
        # . Purpose
        #   Preview and synchronize generated website files to a configured destination.
        #
        # . Usage
        #   ```bash
        #   web_content_publish
        #   ```
    web_content_publish()         { _web_content_run_manage publish; }
    # fn: web_content_publish_github_pages - Push generated documentation to GitHub Pages.
        # . Purpose
        #   Push generated documentation to GitHub Pages.
        #
        # . Usage
        #   ```bash
        #   web_content_publish_github_pages
        #   ```
    web_content_publish_github_pages() { _web_content_run_manage publish-github-pages; }
    # fn: web_content_validate - Call `_web_content_run_manage` with the `validate` action.
        # . Purpose
        #   Invoke the validate action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_validate
        #   ```
    web_content_validate()        { _web_content_run_manage validate; }
    # fn: web_content_prepare_social - Call `_web_content_run_manage` with the `prepare-social` action.
        # . Purpose
        #   Invoke the prepare social action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_prepare_social
        #   ```
    web_content_prepare_social()  { _web_content_run_manage prepare-social; }
    # fn: web_content_status - Call `_web_content_run_manage` with the `status` action.
        # . Purpose
        #   Invoke the status action through the module manager.
        #
        # . Returns
        #   The status returned by the delegated action.
        #
        # . Usage
        #   ```bash
        #   web_content_status
        #   ```
    web_content_status()          { _web_content_run_manage status; }

    # fn: web_content_assemble_bundle - Open the documentation bundle manager
        # . Purpose
        #   Open the saved-bundle manager to create, select, configure, or validate bundles.
        #
        # . Returns
        #   Exit status of the standalone bundle manager.
        #
        # . Usage
        #   ```bash
        #   web_content_assemble_bundle
        #   ```
    web_content_assemble_bundle() { _sgnd_run_module_script "manage-bundles.sh"; }

    # fn: web_content_generate_bundle - Select and generate a saved documentation bundle
        # . Purpose
        #   Open a numbered bundle selector and prepare its Markdown; after successful
        #   generation, mark GitHub Pages and both website steps as pending.
        #
        # . Behavior
        #   - Uses the same generator and validation as the bundle manager did previously.
        #   - Allows Q to cancel before any generation starts.
        #
        # . Returns
        #   Exit status of the bundle generation workflow; 0 on cancellation.
        #
        # . Usage
        #   ```bash
        #   web_content_generate_bundle
        #   ```
    web_content_generate_bundle() { _web_content_run_generation_tracked documentation; }
    # fn: web_content_manage_config - Select and edit an existing website configuration file.
        # . Purpose
        #   Select and edit an existing website configuration file.
        #
        # . Usage
        #   ```bash
        #   web_content_manage_config
        #   ```
    web_content_manage_config()   { _web_content_run_mutating_manage manage-config; }

# - Module validation contract ------------------------------------------------------
    # fn: validate_module_web_content_management - Validate the web content module and record its status for the console.
        # . Purpose
        #   Validate the web content module and record its status for the console.
        #
        # . Returns
        #   A console validation status (0=pass, 1=fail, 2=warning, 3=skipped).
        #
        # . Usage
        #   ```bash
        #   validate_module_web_content_management
        #   ```
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

    # Manage saved bundles separately from the explicit generation workflow.
    sgnd_menu_register_item "web-content-documentation-bundle" "web-content-documentation" "Manage documentation bundles" "web_content_assemble_bundle" "Create, configure and validate saved documentation bundles" 0 0 1
    sgnd_menu_register_item "web-content-documentation-generate" "web-content-documentation" "Generate documentation bundle" "web_content_generate_bundle" "Select a saved bundle and generate its Markdown documentation" 0 0 1
    sgnd_menu_register_item "web-content-documentation-github" "web-content-documentation" "Push to GitHub Pages" "web_content_publish_github_pages" "Publish generated documentation from the SolidGroundUX repository main/docs directory" 0 0 1

    # Publication is explicit: ingestion never automatically publishes content.
    sgnd_menu_register_item "web-content-generate" "web-content-publish" "Generate website" "web_content_generate" "Generate a static website from Markdown, templates, CSS, and assets" 0 15 1
    sgnd_menu_register_item "web-content-publish-site" "web-content-publish" "Publish website" "web_content_publish" "Deploy generated HTML to a selected Nginx website over SSH" 0 0 1

    sayinfo "Web Content Management module registered with the console."
