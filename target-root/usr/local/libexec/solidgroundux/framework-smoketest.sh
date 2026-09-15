#!/usr/bin/env bash
# =====================================================================================
# SolidGroundUX - Framework Smoke Test and Validation
# -------------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Source      : framework-smoketest.sh
#   Wrapper     : sgnd-framework-smoketest
#   Type        : script
#   Group       : SolidGround Console
#   Purpose     : Validate the framework and exercise its interactive UI helpers
#
# Description:
#   Authoritative test implementation for the SolidGroundUX Management Console
#   Framework Test module. Supports individual validation suites, a complete Run All
#   pass, and the original interactive UI smoke-test menu.
#
# Design principles:
#   - Validation suites are non-destructive.
#   - Console registration is tested after explicitly loading all discovered modules,
#     avoiding false failures caused by the Management Console's lazy-loading model.
#   - Existing module validators remain owned by their respective modules and are
#     invoked rather than duplicated here.
#   - Test sections use one consistent finish and summary pattern.
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# =====================================================================================
set -uo pipefail

# - Bootstrap -----------------------------------------------------------------------
    # fn$ _framework_locator - Resolve and load the active SolidGroundUX framework
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

# - Script identity -----------------------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_DESC="SolidGroundUX framework smoke test and validation suite"
    SGND_SCRIPT_VERSION="2.1"

# - Framework integration ----------------------------------------------------------
    SGND_USING=(
        sgnd-datatable.sh
        console-helpers.sh
        sgnd-menu.sh
    )

    SGND_ARGS_SPEC=(
        "suite|s|enum|ENUM_SUITE|Test suite to run||smoke,installation,console,modules,all"
        "view-log||flag|FLAG_VIEW_LOG|Display the active SolidGroundUX logfile and exit|"
    )

    SGND_SCRIPT_EXAMPLES=(
        "Interactive smoke tests:"
        "  $SGND_SCRIPT_NAME --suite smoke"
        ""
        "Run all framework tests:"
        "  $SGND_SCRIPT_NAME --suite all"
        ""
        "Validate console registration only:"
        "  $SGND_SCRIPT_NAME --suite console"
    )

    SGND_SCRIPT_GLOBALS=()
    SGND_ON_EXIT_HANDLERS=()
    SGND_STATE_SAVE=0
    : "${ENUM_SUITE:=smoke}"

# - Smoke-test input declarations --------------------------------------------------
    : "${INP_NAME:=}"
    : "${INP_STREET:=}"
    : "${INP_ZIPCODE:=}"
    : "${INP_CITY:=}"
    : "${INP_COUNTRY:=}"
    : "${INP_AGE:=}"

    SGND_STATE_VARIABLES=(
        "INP_NAME|Name|Petrus Puk|"
        "INP_STREET|Address|Nowhere straat|"
        "INP_ZIPCODE|Postcode|5544 QU|"
        "INP_CITY|Stad||"
        "INP_COUNTRY|||"
        "INP_AGE|Leeftijd|102|sgnd_is_number"
    )

    # fn: input_test - Run simple shell input tests
        # . Purpose
        #   Run simple shell input tests.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   input_test
    input_test() {
        sgnd_print
        ask_prompt_form --autoalign "${SGND_STATE_VARIABLES[@]}" 
    }


    # fn: ask_selection_test - Run interactive ask_selection tests
        # . Purpose
        #   Exercise single-select and multi-select ask_selection behavior.
        #
        # . Behavior
        #   - Presents one single-select list and reports the selected value.
        #   - Presents one multi-select list and reports all selected values.
        #   - Allows Q to return from either selection prompt.
        #
        # . Returns
        #   0 after both selection tests complete or are cancelled.
        #
        # . Usage
        #   ask_selection_test
    ask_selection_test() {
        local selected_theme=""
        local -a selected_groups=()
        local -a themes=(
            "Default"
            "Dark"
            "Testadura"
            "Steel Blue"
        )
        local -a groups=(
            "Domain Admins"
            "File Server Users"
            "Accounting"
            "Operations"
            "Developers"
        )

        sgnd_print
        sgnd_print_sectionheader --text "Testing ask_selection()"

        sgnd_print "Single-select test"
        ask_selection \
            --label "Theme" \
            --var selected_theme \
            --items "${themes[@]}"

        if [[ -n "$selected_theme" ]]; then
            sgnd_print "Result: selected_theme='$selected_theme'"
        else
            sgnd_print "Result: single-select cancelled"
        fi

        sgnd_print
        sgnd_print "Multi-select test (try 1,3,5 or 2-4)"
        ask_selection \
            --label "Groups" \
            --var selected_groups \
            --multi \
            --items "${groups[@]}"

        if (( ${#selected_groups[@]} > 0 )); then
            sgnd_print_labeledmultivalue \
                --label "Selected groups" \
                --items "${selected_groups[@]}"
        else
            sgnd_print "Result: multi-select cancelled"
        fi

        return 0
    }

    # fn: ask_test - Run interactive ask helper tests
        # . Purpose
        #   Run interactive ask helper tests.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   ask_test
    ask_test(){
        sgnd_print
        # -----------------------------------------------------------------------------
        # 1. ask
        # -----------------------------------------------------------------------------
        sgnd_print " 1. Testing ask()"

        TEST_NAME=""
        ask \
            --label "Your name" \
            --default "Mark" \
            --validate sgnd_validate_text \
            --var TEST_NAME \
            --labelwidth 28 \
            --pad 2 \
            --colorize both

        sgnd_print "Result: TEST_NAME=$TEST_NAME"

        # -----------------------------------------------------------------------------
        # 2. ask_datetime
        # -----------------------------------------------------------------------------
        sgnd_print " 2. Testing ask_datetime()"
        sgnd_print "Enter an absolute datetime or a shorthand such as N, D, -2h, or +30m.\n"

        TEST_DATETIME=""
        TEST_RC=0

        while true; do
            ask_datetime \
                --label "Changed after" \
                --default "-2h" \
                --var TEST_DATETIME \
                --labelwidth 28 \
                --pad 2 \
                --colorize both

            sgnd_print "Result: TEST_DATETIME='$TEST_DATETIME'"

            ask_dlg_autocontinue \
                --seconds 8 \
                --message "Press Enter to continue, or R to repeat ask_datetime." \
                --redo \
                --pause

            TEST_RC=$?
            case "$TEST_RC" in
                0)
                    break
                    ;;
                1|3)
                    sgnd_print "Repeating ask_datetime test.\n"
                    ;;
                *)
                    sgnd_print "Unexpected response rc=$TEST_RC; repeating ask_datetime test.\n"
                    ;;
            esac
        done

        # -----------------------------------------------------------------------------
        # 3. ask_decision
        # -----------------------------------------------------------------------------
        sgnd_print " 3. Testing ask_decision()"

        TEST_DECISION=""
        ask_decision \
            --label "Proceed with operation?" \
            --choices "YES|Y,NO|N" \
            --default "YES" \
            --var TEST_DECISION \
            --labelwidth 28 \
            --pad 2 

        sgnd_print "Result: TEST_DECISION='$TEST_DECISION'"

        # -----------------------------------------------------------------------------
        # 4. ask_dlg_autocontinue
        # -----------------------------------------------------------------------------
        sgnd_print " 4. Testing ask_dlg_autocontinue()"
        sgnd_print "Try Enter, R, C, P/Space, or do nothing and let it time out.\n"

        ask_dlg_autocontinue \
            --seconds 8 \
            --message "Auto-continue test" \
            --redo \
            --cancel \
            --pause

        TEST_RC=$?

        case "$TEST_RC" in
            0) sgnd_print "Result: continue\n\n" ;;
            1) sgnd_print "Result: timeout / auto-continue\n\n" ;;
            2) sgnd_print "Result: cancel\n\n" ;;
            3) sgnd_print "Result: redo\n\n" ;;
            *) sgnd_print "Result: unexpected rc=%s\n\n" "$TEST_RC" ;;
        esac

        # -----------------------------------------------------------------------------
        # 5. ask_choose
        # -----------------------------------------------------------------------------
        sgnd_print " 5. Testing ask_choose()"

        TEST_ENV=""
        ask_choose \
            --label "Environment" \
            --choices "dev,acc,prod" \
            --var TEST_ENV \
            --labelwidth 28 \
            --pad 2 

        sgnd_print "Result: TEST_ENV='$TEST_ENV'"

        # -----------------------------------------------------------------------------
        # 6. ask_choose_immediate
        # -----------------------------------------------------------------------------
        sgnd_print " 6. Testing ask_choose_immediate()"
        sgnd_print "Instant choices: B,D,Q. Other values require Enter.\n"

        TEST_ACTION=""
        ask_choose_immediate \
            --label "Action" \
            --choices "1-5,B,D,Q" \
            --instantchoices "B,D,Q" \
            --var TEST_ACTION

        sgnd_print "Result: TEST_ACTION='$TEST_ACTION'"

        # -----------------------------------------------------------------------------
        # Optional: ask_prompt_form
        # -----------------------------------------------------------------------------
        # Uncomment this block if you want to test ask_prompt_form too.
        #
        # _ask_parse_fieldspec() {
        #     local spec="${1-}"
        #     IFS='|' read -r \
        #         _ask_field_key \
        #         _ask_field_label \
        #         _ask_field_default \
        #         _ask_field_validate \
        #         <<< "$spec"
        # }
        #
        # _ask_is_ident() {
        #     [[ "${1-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
        # }
        #
        # sgnd_print " 7. Testing ask_prompt_form()"
        #
        HOSTNAME=""
        PORT=""
        
        ask_prompt_form --autoalign --pad 2 -- \
             "HOSTNAME|Host name|localhost|sgnd_validate_text" \
             "PORT|Port|8080|sgnd_validate_text"
        #
        sgnd_print "Result: HOSTNAME='$HOSTNAME', PORT='$PORT'\n"

        sgnd_print "Done.\n"
    }
        # -- Sample/demo renderers
    # fn: say_test - Run console message helper tests
        # . Purpose
        #   Run console message helper tests.
        #
        # . Behavior
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   say_test
    say_test(){
        sgnd_print
        sgnd_print_sectionheader --text "Testing say*() helpers"

        local original_loglevel="${SGND_CONSOLE_LOG_LEVEL:-silent}"
        SGND_CONSOLE_LOG_LEVEL="trace"
        sayinfo "Info message"
        saystart "Start message"
        saywarning "Warning message"
        sayfail "Failure message"
        saycancel "Cancellation message"
        sayok "All is well"
        sayend "Ended gracefully"
        saydebug "Debug message"
        justsay "Just saying"
        SGND_CONSOLE_LOG_LEVEL="$original_loglevel"
    }

    # fn: loglevel_test - Run console message visibility tests for every log level
        # . Purpose
        #   Cycle through all supported SGND_CONSOLE_LOG_LEVEL values and emit one test message
        #   for each message type.
        #
        # . Behavior
        #   - Public smoke-test entry point.
        #   - Temporarily sets SGND_CONSOLE_LOG_LEVEL to off, quiet, normal, and debug.
        #   - Emits INFO, STRT, WARN, FAIL, CNCL, OK, END, DEBUG, and EMPTY messages
        #     for each level so console filtering can be inspected visually.
        #   - Restores the original SGND_CONSOLE_LOG_LEVEL before returning.
        #
        # . Returns
        #   0 when the test sequence completes.
        #
        # . Usage
        #   loglevel_test
    loglevel_test() {
        sgnd_print
        sgnd_print_sectionheader --text "Testing loglevel visibility"
        local original_loglevel="${SGND_CONSOLE_LOG_LEVEL:-silent}"
        local level=""

        for level in silent quiet normal verbose debug trace; do
            SGND_CONSOLE_LOG_LEVEL="$level"

            printf '\n'
            printf '%s\n' '-----------------------------------------'
            printf 'SGND_CONSOLE_LOG_LEVEL=%s\n' "$SGND_CONSOLE_LOG_LEVEL"
            printf '%s\n' 'Expected visible message types depend on _say_should_print_console.'
            printf '%s\n' '-----------------------------------------'

            sayinfo "INFO message at loglevel=$SGND_CONSOLE_LOG_LEVEL"
            saystart "STRT message at loglevel=$SGND_CONSOLE_LOG_LEVEL"
            saywarning "WARN message at loglevel=$SGND_CONSOLE_LOG_LEVEL"
            sayfail "FAIL message at loglevel=$SGND_CONSOLE_LOG_LEVEL"
            saycancel "CNCL message at loglevel=$SGND_CONSOLE_LOG_LEVEL"
            sayok "OK message at loglevel=$SGND_CONSOLE_LOG_LEVEL"
            sayend "END message at loglevel=$SGND_CONSOLE_LOG_LEVEL"
            saydebug "DEBUG message at loglevel=$SGND_CONSOLE_LOG_LEVEL"
            say EMPTY "EMPTY message at loglevel=$SGND_CONSOLE_LOG_LEVEL"

            justsay "Just saying at loglevel=$SGND_CONSOLE_LOG_LEVEL"
        done

        SGND_CONSOLE_LOG_LEVEL="$original_loglevel"

        printf '\n'
        printf 'Restored SGND_CONSOLE_LOG_LEVEL=%s\n' "$SGND_CONSOLE_LOG_LEVEL"
    }

    # fn: file_loglevel_test - Run file logging tests for every log level
        # . Purpose
        #   Verify file logging and file-level filtering independently from console output.
        #
        # . DRYRUN
        #   File logging is intentionally skipped because exercising it would append test
        #   records to the active logfile. The test reports exactly what would be tested.
    file_loglevel_test() {
        local logfile=""
        local level=""
        local original_file_loglevel="${SGND_FILE_LOG_LEVEL:-silent}"

        logfile="$(_sgnd_logfile)" || {
            saywarning "Unable to resolve the active logfile"
            return 1
        }

        [[ -n "$logfile" ]] || {
            saywarning "No active logfile is available"
            return 1
        }

        sgnd_print
        sgnd_print_sectionheader --text "Testing file log levels"
        sgnd_print_labeledvalue --label "Logfile" --value "$logfile"

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "DRYRUN: Would test file log filtering for: silent, quiet, normal, verbose, debug, trace."
            sayinfo "DRYRUN: Test records would be written to '$logfile'; no records will be written."
            return 0
        fi

        for level in silent quiet normal verbose debug trace; do
            SGND_FILE_LOG_LEVEL="$level"
            printf 'Testing SGND_FILE_LOG_LEVEL=%s\n' "$level"

            case "$level" in
                silent)
                    sayfail "FILELOG silent: this line must not be written"
                    ;;
                quiet)
                    saywarning "FILELOG quiet: warning should be written"
                    sayinfo "FILELOG quiet: info must not be written"
                    ;;
                normal)
                    saystart "FILELOG normal: start should be written"
                    sayinfo "FILELOG normal: info must not be written"
                    ;;
                verbose)
                    sayinfo "FILELOG verbose: info should be written"
                    saydebug "FILELOG verbose: debug must not be written"
                    ;;
                debug)
                    saydebug "FILELOG debug: debug should be written"
                    say --type TRACE "FILELOG debug: trace must not be written"
                    ;;
                trace)
                    say --type TRACE "FILELOG trace: trace should be written"
                    ;;
            esac
        done

        SGND_FILE_LOG_LEVEL="$original_file_loglevel"
        printf 'Restored SGND_FILE_LOG_LEVEL=%s\n' "$SGND_FILE_LOG_LEVEL"
        return 0
    }

    # fn: view_log - Display the active SolidGroundUX logfile
        # . Purpose
        #   Display the logfile selected by the current SolidGroundUX logging configuration.
        #
        # . Behavior
        #   - Uses the same logfile resolver as say().
        #   - Displays the resolved path before showing the file contents.
        #   - Reports an empty or unavailable logfile without failing unexpectedly.
        #
        # . Returns
        #   0 when the logfile is displayed.
        #   1 when no readable logfile can be resolved.
        #
        # . Usage
        #   view_log
    view_log() {
        local logfile=""

        logfile="$(_sgnd_logfile)" || {
            saywarning "Unable to resolve the active logfile"
            return 1
        }

        [[ -n "$logfile" && -r "$logfile" ]] || {
            saywarning "Logfile is not readable: ${logfile:-<unresolved>}"
            return 1
        }

        sgnd_print
        sgnd_print_sectionheader --text "SolidGroundUX logfile"
        sgnd_print_labeledvalue --label "Logfile" --value "$logfile"
        sgnd_print
        sgnd_print_file "$logfile"
    }

    # fn: motd_test - Motd test
        # . Purpose
        #   Motd test.
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   motd_test
    motd_test() {
        local motd_file="$SGND_FRAMEWORK_ROOT/etc/update-motd.d/90-solidgroundux"

        sgnd_print
        sgnd_print_sectionheader --text "Testing MOTD generation"

        if [[ -r "$motd_file" ]]; then
            bash "$motd_file"
        else
            sayfail "MOTD file not readable: $motd_file"
        fi
    }

    # fn: sayprogress_test - Run transient progress line tests
        # . Purpose
        #   Exercise sayprogress with one, two, and three reserved progress slots.
        #
        # . Behavior
        #   - Runs three visual progress scenarios after each other.
        #   - Stage 1 uses one progress level: 1..15.
        #   - Stage 2 uses true nested progress: outer 1..15, inner 1..70.
        #   - Stage 3 uses true nested progress: outer 1..15, middle 1..70,
        #     inner 1..125.
        #   - Lower levels complete and restart before their parent advances.
        #   - Uses explicit slots so stacked progress rendering can be inspected.
        #
        # . Returns
        #   0 when the visual test sequence completes.
        #
        # . Usage
        #   sayprogress_test
    sayprogress_test() {
        local outer=0
        local middle=0
        local inner=0
        local outer_total=15
        local middle_total=70
        local inner_total=125

        sgnd_print
        sgnd_print_sectionheader --text "Testing sayprogress() helpers"
        sgnd_print
        saystart "Progress test 1/3: single level"

        outer_total=150
        sayprogress_begin --slots 1
        for (( outer = 1; outer <= outer_total; outer++ )); do
            sayprogress \
                --slot 0 \
                --current "$outer" \
                --total "$outer_total" \
                --label "Stage 1: single level $outer/$outer_total" \
                --type 7 \
                --padleft 0

            (( outer % 5 == 0 )) && sleep 0.05
        done
        
        sayok "Progress test 1/3 complete"
        
        sgnd_print
        saystart "Progress test 2/3: double level"

        outer_total=5
        middle_total=125
        sayprogress_begin --slots 2
        for (( outer = 1; outer <= outer_total; outer++ )); do
            sayprogress \
                --slot 0 \
                --current "$outer" \
                --total "$outer_total" \
                --label "Stage 2 outer: $outer/$outer_total" \
                --type 7 \
                --padleft 0

            for (( middle = 1; middle <= middle_total; middle++ )); do
                sayprogress \
                    --slot 1 \
                    --current "$middle" \
                    --total "$middle_total" \
                    --label "Stage 2 inner: $middle/$middle_total" \
                    --type 7 \
                    --padleft 2

                (( middle % 5 == 0 )) && sleep 0.05
            done
        done
        sayok "Progress test 2/3 complete"

        
        sgnd_print
        saystart "Progress test 3/3: triple level"

        sayprogress_begin --slots 3
        outer_total=5
        middle_total=10
        inner_total=80
        for (( outer = 1; outer <= outer_total; outer++ )); do
            sayprogress \
                --slot 0 \
                --current "$outer" \
                --total "$outer_total" \
                --label "Stage 3 outer: $outer/$outer_total" \
                --type 7 \
                --padleft 0

            for (( middle = 1; middle <= middle_total; middle++ )); do
                sayprogress \
                    --slot 1 \
                    --current "$middle" \
                    --total "$middle_total" \
                    --label "Stage 3 middle: $middle/$middle_total" \
                    --type 7 \
                    --padleft 2

                for (( inner = 1; inner <= inner_total; inner++ )); do
                    sayprogress \
                        --slot 2 \
                        --current "$inner" \
                        --total "$inner_total" \
                        --label "Stage 3 inner: $inner/$inner_total" \
                        --type 7 \
                        --padleft 4

                    (( inner % 10 == 0 )) && sleep 0.01
                done
            done
        done
        sayok "Progress test 3/3 complete"
        sgnd_print
    }

    # fn: show_colorchart - Show colorchart
        # . Purpose
        #   Show colorchart.
        #
        # . Returns
        #   Returns the underlying command or workflow status.
        #
        # . Usage
        #   show_colorchart
    show_colorchart(){
        sgnd_color_samples
    }

    # fn: show_theme - Browse and preview installed UI themes
        # . Purpose
        #   Cycle through installed SolidGroundUX themes and preview each one.
        #
        # . Behavior
        #   - Discovers numbered NN-style-*.sh files in SGND_STYLE_DIR.
        #   - Starts at the currently active theme when possible.
        #   - Uses Left/Right arrows to switch the runtime theme without saving it.
        #   - Displays sgnd_style_samples after every successful switch.
        #   - Q returns to the smoke-test menu and leaves the selected theme active.
        #
        # . Returns
        #   0 after leaving the theme browser.
        #   1 when no readable themes are found.
        #
        # . Usage
        #   show_theme
    show_theme() {
        local -a theme_files=()
        local -a theme_names=()
        local -a theme_color_groups=(
            "Message colors|MSG_CLR_INFO MSG_CLR_STRT MSG_CLR_OK MSG_CLR_WARN MSG_CLR_FAIL MSG_CLR_CNCL MSG_CLR_END MSG_CLR_EMPTY MSG_CLR_DEBUG"
            "Progress colors|PROG_BAR_CLR PROG_IND_CLR PROG_TEXT_CLR"
            "UI colors|SGND_UI_BORDER SGND_UI_LABEL SGND_UI_VALUE SGND_UI_COMMIT SGND_UI_DRYRUN SGND_UI_ENABLED SGND_UI_DISABLED SGND_UI_ON SGND_UI_OFF SGND_UI_INPUT SGND_UI_PROMPT SGND_UI_INVALID SGND_UI_VALID SGND_UI_SUCCESS SGND_UI_ERROR SGND_UI_TEXT SGND_UI_DEFAULT"
        )
        local theme_file=""
        local theme_name=""
        local current_file="${SGND_UI_STYLE##*/}"
        local key=""
        local key_tail=""
        local index=0
        local i=0
        local group_spec=""
        local group_name=""
        local group_vars=""
        local color_var=""
        local color_value=""

        while IFS= read -r -d '' theme_file; do
            theme_files+=("$(basename -- "$theme_file")")
        done < <(
            find "$SGND_STYLE_DIR" -maxdepth 1 -type f \
                -name '[0-9][0-9]-style-*.sh' \
                -print0 | LC_ALL=C sort -z
        )

        if (( ${#theme_files[@]} == 0 )); then
            saywarning "No themes found in $SGND_STYLE_DIR"
            return 1
        fi

        for theme_file in "${theme_files[@]}"; do
            theme_name="${theme_file%.sh}"
            theme_name="${theme_name#??-style-}"
            theme_names+=("$theme_name")
        done

        for i in "${!theme_files[@]}"; do
            if [[ "${theme_files[$i]}" == "$current_file" ]]; then
                index=$i
                break
            fi
        done

        while true; do
            theme_name="${theme_names[$index]}"

            sgnd_theme "$theme_name" || return $?

            printf '\033[2J\033[H'
            printf 'Theme %d/%d: %s\n' \
                "$((index + 1))" \
                "${#theme_names[@]}" \
                "$theme_name"
            printf 'Use Left/Right arrows to browse; Q returns to the menu.\n\n'

            sgnd_style_samples
            sgnd_print

            sgnd_print_sectionheader --border $DL_H

            sgnd_print "Press  $KY_LEFT or $KY_RIGHT to switch themes, or Q to return to the menu.\n"
            
            IFS= read -r -s -n1 key

            case "$key" in
                $'\e')
                    key_tail=""
                    IFS= read -r -s -n2 -t 0.1 key_tail || true

                    case "$key_tail" in
                        '[D')
                            index=$(( (index - 1 + ${#theme_names[@]}) % ${#theme_names[@]} ))
                            ;;
                        '[C')
                            index=$(( (index + 1) % ${#theme_names[@]} ))
                            ;;
                    esac
                    ;;
                q|Q)
                    break
                    ;;
                '')
                    continue
                    ;;
            esac
        done

        return 0
    }

# - Validation engine --------------------------------------------------------------
    SGND_TEST_PASS=0
    SGND_TEST_FAIL=0
    SGND_TEST_SKIP=0

    _framework_test_root_path() {
        local relative="${1:?missing path}"
        local root="${SGND_FRAMEWORK_ROOT:-/}"
        relative="${relative#/}"
        if [[ "$root" == "/" ]]; then
            printf '/%s\n' "$relative"
        else
            printf '%s/%s\n' "${root%/}" "$relative"
        fi
    }

    _framework_test_result() {
        local label="${1:?missing label}"
        local status="${2:?missing status}"
        local detail="${3:-}"
        local value="$status"

        [[ -z "$detail" ]] || value="$status - $detail"
        sgnd_print_labeledvalue --label "$label" --value "$value" --labelwidth 32

        case "$status" in
            PASS) SGND_TEST_PASS=$((SGND_TEST_PASS + 1)); return 0 ;;
            SKIP) SGND_TEST_SKIP=$((SGND_TEST_SKIP + 1)); return 0 ;;
            FAIL) SGND_TEST_FAIL=$((SGND_TEST_FAIL + 1)); return 1 ;;
        esac
        return 1
    }

    _framework_test_suite_summary() {
        local title="${1:?missing title}"
        local pass_before="${2:-0}"
        local fail_before="${3:-0}"
        local skip_before="${4:-0}"
        local passed=$((SGND_TEST_PASS - pass_before))
        local failed=$((SGND_TEST_FAIL - fail_before))
        local skipped=$((SGND_TEST_SKIP - skip_before))

        sgnd_print
        sgnd_print_sectionheader --text "$title summary"
        sgnd_print_labeledvalue --label "Passed" --value "$passed" --labelwidth 18
        sgnd_print_labeledvalue --label "Failed" --value "$failed" --labelwidth 18
        sgnd_print_labeledvalue --label "Skipped" --value "$skipped" --labelwidth 18
        sgnd_print

        if (( failed == 0 )); then
            sayok "$title passed."
            return 0
        fi

        sayfail "$title reported $failed failure(s)."
        return 1
    }

    _framework_test_validate_installation() {
        local pass_before=$SGND_TEST_PASS
        local fail_before=$SGND_TEST_FAIL
        local skip_before=$SGND_TEST_SKIP
        local path=""
        local relative=""
        local command_name=""
        local module_dir=""
        local module_count=0
        local -a required_files=(
            "/usr/local/lib/solidgroundux/common/sgnd-bootstrap.sh"
            "/usr/local/lib/solidgroundux/common/sgnd-core.sh"
            "/usr/local/lib/solidgroundux/common/sgnd-menu.sh"
            "/usr/local/lib/solidgroundux/common/ui.sh"
            "/usr/local/libexec/solidgroundux/management-console.sh"
            "/usr/local/libexec/solidgroundux/framework-smoketest.sh"
        )
        local -a required_commands=(
            "sgnd-console"
            "sgnd-framework-smoketest"
        )

        sgnd_print
        sgnd_print_sectionheader --text "Framework installation"

        for relative in "${required_files[@]}"; do
            path="$(_framework_test_root_path "$relative")"
            if [[ -r "$path" ]]; then
                _framework_test_result "$(basename "$relative")" "PASS" || true
            else
                _framework_test_result "$(basename "$relative")" "FAIL" "$path" || true
            fi
        done

        module_dir="$(_framework_test_root_path /usr/local/libexec/solidgroundux/console-modules)"
        if [[ -d "$module_dir" ]]; then
            module_count="$(find "$module_dir" -maxdepth 1 -type f -name '*.sh' -printf '.' 2>/dev/null | wc -c)"
            _framework_test_result "Console modules" "PASS" "$module_count module(s)" || true
        else
            _framework_test_result "Console modules" "FAIL" "$module_dir" || true
        fi

        for command_name in "${required_commands[@]}"; do
            path="$(_framework_test_root_path "/usr/local/bin/$command_name")"
            if [[ -x "$path" ]]; then
                _framework_test_result "$command_name" "PASS" "$path" || true
            else
                _framework_test_result "$command_name" "FAIL" "public command not executable: $path" || true
            fi
        done

        _framework_test_suite_summary "Framework installation" "$pass_before" "$fail_before" "$skip_before"
    }

    _framework_test_load_console_modules() {
        local module_dir=""
        local module_file=""
        local loaded=0

        module_dir="$(_framework_test_root_path /usr/local/libexec/solidgroundux/console-modules)"
        [[ -d "$module_dir" ]] || {
            _framework_test_result "Console module directory" "FAIL" "$module_dir" || true
            return 1
        }

        sgnd_menu_create "Framework registration test" "Temporary registration model used by framework-smoketest"

        while IFS= read -r -d '' module_file; do
            if source "$module_file"; then
                loaded=$((loaded + 1))
            else
                _framework_test_result "$(basename "$module_file")" "FAIL" "module source failed" || true
            fi
        done < <(find "$module_dir" -maxdepth 1 -type f -name '*.sh' -print0 | LC_ALL=C sort -z)

        (( loaded > 0 )) || {
            _framework_test_result "Console modules loaded" "FAIL" "no modules loaded" || true
            return 1
        }

        _framework_test_result "Console modules loaded" "PASS" "$loaded" || true
        return 0
    }

    _framework_test_validate_console() {
        local pass_before=$SGND_TEST_PASS
        local fail_before=$SGND_TEST_FAIL
        local skip_before=$SGND_TEST_SKIP
        local row=""
        local key=""
        local group=""
        local label=""
        local handler=""
        local desc=""
        local source=""
        local builtin=""
        local waitsecs=""
        local visible=""
        local indent=""
        local status=""
        local ord=""
        local group_count=0
        local item_count=0
        local -A group_keys=()
        local -A item_keys=()

        sgnd_print
        sgnd_print_sectionheader --text "Console registration"

        _framework_test_load_console_modules || {
            _framework_test_suite_summary "Console registration" "$pass_before" "$fail_before" "$skip_before"
            return 1
        }

        group_count="${#SGND_GROUP_ROWS[@]}"
        item_count="${#SGND_ITEM_ROWS[@]}"

        for row in "${SGND_GROUP_ROWS[@]}"; do
            IFS='|' read -r key label desc source builtin visible ord <<< "$row"
            if [[ -z "$key" ]]; then
                _framework_test_result "Console group" "FAIL" "empty group key" || true
                continue
            fi
            if [[ -n "${group_keys[$key]+x}" ]]; then
                _framework_test_result "Console group $key" "FAIL" "duplicate key" || true
            else
                group_keys["$key"]=1
            fi
        done

        for row in "${SGND_ITEM_ROWS[@]}"; do
            IFS='|' read -r key group label handler desc source builtin waitsecs visible indent status <<< "$row"

            if [[ -z "$key" ]]; then
                _framework_test_result "Console item" "FAIL" "empty item key" || true
                continue
            fi

            if [[ -n "${item_keys[$key]+x}" ]]; then
                _framework_test_result "Console item $key" "FAIL" "duplicate key" || true
            else
                item_keys["$key"]=1
            fi

            if [[ -z "${group_keys[$group]+x}" ]]; then
                _framework_test_result "Console item $key" "FAIL" "missing group: $group" || true
            fi

            # All modules were explicitly sourced above. A missing handler at this point
            # is therefore a real registration error, not a lazy-loading false positive.
            if [[ -n "$handler" ]] && ! declare -F "$handler" >/dev/null 2>&1; then
                _framework_test_result "Console item $key" "FAIL" "missing handler: $handler" || true
            fi
        done

        _framework_test_result "Registered groups" "PASS" "$group_count" || true
        _framework_test_result "Registered items" "PASS" "$item_count" || true

        _framework_test_suite_summary "Console registration" "$pass_before" "$fail_before" "$skip_before"
    }

    _framework_test_is_storage_configured() {
        [[ -s /etc/solidgroundux/storage.cfg ]] || grep -Eq '(^|[[:space:]])SGND_STORAGE([[:space:]]|$)' /etc/fstab 2>/dev/null
    }

    _framework_test_is_ad_server() {
        grep -Eiq '^[[:space:]]*server[[:space:]]+role[[:space:]]*=[[:space:]]*active[[:space:]]+directory[[:space:]]+domain[[:space:]]+controller' /etc/samba/smb.conf 2>/dev/null
    }

    _framework_test_is_ad_client() {
        command -v realm >/dev/null 2>&1 && [[ -n "$(realm list 2>/dev/null)" ]]
    }

    _framework_test_is_samba_file_server() {
        command -v smbd >/dev/null 2>&1 && ! _framework_test_is_ad_server
    }

    _framework_test_run_validator() {
        local label="${1:?missing label}"
        local handler="${2:?missing handler}"
        local applicable="${3:-1}"
        local skip_reason="${4:-not configured on this host}"

        if (( ! applicable )); then
            _framework_test_result "$label" "SKIP" "$skip_reason" || true
            return 0
        fi

        if ! declare -F "$handler" >/dev/null 2>&1; then
            _framework_test_result "$label" "FAIL" "validator not available: $handler" || true
            return 1
        fi

        sgnd_print
        sgnd_print_sectionheader --text "$label"
        if "$handler"; then
            _framework_test_result "$label" "PASS" || true
            return 0
        fi

        _framework_test_result "$label" "FAIL" "validator returned failure" || true
        return 1
    }

    _framework_test_validate_modules() {
        local pass_before=$SGND_TEST_PASS
        local fail_before=$SGND_TEST_FAIL
        local skip_before=$SGND_TEST_SKIP
        local applicable=0

        sgnd_print
        sgnd_print_sectionheader --text "Module validations"

        # Load all modules when this suite is run directly. When Run All follows the
        # console-registration suite the functions are already available and guards
        # prevent duplicate registration/loading.
        if ! declare -F _computer_validate >/dev/null 2>&1; then
            _framework_test_load_console_modules || {
                _framework_test_suite_summary "Module validations" "$pass_before" "$fail_before" "$skip_before"
                return 1
            }
        fi

        _framework_test_run_validator "Computer setup" "_computer_validate" 1 || true

        applicable=0
        _framework_test_is_storage_configured && applicable=1
        _framework_test_run_validator "Storage" "storage_validate_provisioning" "$applicable" "storage is not configured" || true

        applicable=0
        _framework_test_is_ad_server && applicable=1
        _framework_test_run_validator "Active Directory server" "_adsvr_validate" "$applicable" "host is not an AD domain controller" || true

        applicable=0
        _framework_test_is_ad_client && applicable=1
        _framework_test_run_validator "Active Directory client" "_adc_validate" "$applicable" "host is not joined through realmd" || true

        applicable=0
        _framework_test_is_samba_file_server && applicable=1
        _framework_test_run_validator "Samba file server" "_smb_validate" "$applicable" "standalone Samba file service is not installed" || true

        applicable=0
        command -v nginx >/dev/null 2>&1 && applicable=1
        _framework_test_run_validator "Web server" "_web_server_validate" "$applicable" "nginx is not installed" || true

        applicable=0
        [[ -x /opt/mssql/bin/sqlservr ]] && applicable=1
        _framework_test_run_validator "SQL Server" "_sqlserver_validate" "$applicable" "SQL Server is not installed" || true

        _framework_test_suite_summary "Module validations" "$pass_before" "$fail_before" "$skip_before"
    }



# - Smoke test menu -----------------------------------------------------------------
    _smoketest_show_license() {
        saydebug "$SGND_DOCS_DIR/$SGND_LICENSE_FILE"
        sgnd_print_license
    }

    _smoketest_finish_test() {
        sgnd_print
        sgnd_print_sectionheader --border "$DL_H" --maxwidth "${SGND_MENU_RENDER_WIDTH:-$(sgnd_terminal_width)}"
        sgnd_print
    }

    _smoketest_run_all_tests() {
        local failures=0

        sgnd_print
        sgnd_print_sectionheader --text "Interactive smoke tests"

        ask_test || failures=$((failures + 1))
        ask_selection_test || failures=$((failures + 1))
        input_test || failures=$((failures + 1))
        say_test || failures=$((failures + 1))
        loglevel_test || failures=$((failures + 1))
        file_loglevel_test || failures=$((failures + 1))
        motd_test || failures=$((failures + 1))
        sayprogress_test || failures=$((failures + 1))

        sgnd_print
        sgnd_print_sectionheader --text "Interactive smoke test summary"
        if (( failures == 0 )); then
            sayok "Interactive smoke tests completed."
            return 0
        fi

        sayfail "$failures interactive smoke test(s) reported failure."
        return 1
    }

    _smoketest_request_exit() {
        SGND_SMOKETEST_EXIT=1
        return 0
    }

    _smoketest_register_menu() {
        SGND_MENU_TOGGLEBAR_ENABLED=0
        sgnd_menu_create "Framework Smoke Tests" "Exercise SolidGroundUX UI and runtime helpers"

        sgnd_menu_register_group "smoke-tests" "Smoke tests" "Interactive framework helper tests" 0 1 100 || return $?
        sgnd_menu_register_item "ask"       "smoke-tests" "Ask tests"                 "ask_test"               "Exercise ask and dialog helpers" 0 15 1 || return $?
        sgnd_menu_register_item "selection" "smoke-tests" "Selection test"            "ask_selection_test"     "Exercise single and multiple ask_selection behavior" 0 15 1 || return $?
        sgnd_menu_register_item "input"     "smoke-tests" "Input test"                "input_test"             "Exercise input helpers" 0 15 1 || return $?
        sgnd_menu_register_item "say"       "smoke-tests" "Say test"                  "say_test"               "Exercise message output helpers" 0 15 1 || return $?
        sgnd_menu_register_item "loglevel"  "smoke-tests" "Log level visibility test" "loglevel_test"          "Verify console log-level filtering" 0 15 1 || return $?
        sgnd_menu_register_item "motd"      "smoke-tests" "Call MOTD"                 "motd_test"              "Render the SolidGroundUX MOTD" 0 15 1 || return $?
        sgnd_menu_register_item "progress"  "smoke-tests" "Progress dialogue test"    "sayprogress_test"       "Exercise stacked progress lines" 0 15 1 || return $?
        sgnd_menu_register_item "license"   "smoke-tests" "Show license"              "_smoketest_show_license" "Display the active SolidGroundUX license" 0 15 1 || return $?
        sgnd_menu_register_item "colors"    "smoke-tests" "Show color chart"          "show_colorchart"        "Display the current terminal color chart" 0 15 1 || return $?
        sgnd_menu_register_item "theme"     "smoke-tests" "Show theme"                "show_theme"             "Browse installed SolidGroundUX themes" 0 15 1 || return $?

        sgnd_menu_register_group "smoke-actions" "Actions" "Smoke-test actions" 0 1 900 || return $?
        sgnd_menu_register_item "filelog" "smoke-actions" "File log level test" "file_loglevel_test"       "Verify file log-level filtering" 0 15 1 || return $?
        sgnd_menu_register_item "viewlog" "smoke-actions" "View logfile"        "view_log"                 "Display the active SolidGroundUX logfile" 0 15 1 || return $?
        sgnd_menu_register_item "A"       "smoke-actions" "Run all smoke tests" "_smoketest_run_all_tests" "Run the complete interactive smoke-test sequence" 0 30 1 || return $?
        sgnd_menu_register_item "Q"       "smoke-actions" "Quit"                "_smoketest_request_exit"  "Return to the Management Console" 1 0 1 || return $?
        return 0
    }

    _smoketest_read_choice() {
        local output_var="${1:?missing output variable}"
        local choice=""

        printf '%bSelect option (auto-exit in 30s): %b' "${SGND_UI_TEXT:-}" "${RESET:-}" >/dev/tty
        if IFS= read -r -t 30 choice </dev/tty; then
            printf -v "$output_var" '%s' "$choice"
            return 0
        fi

        printf '\n' >/dev/tty
        printf -v "$output_var" '%s' ''
        return 1
    }

    _framework_test_run_smoke_menu() {
        local choice=""

        _smoketest_register_menu || return $?
        SGND_SMOKETEST_EXIT=0

        while true; do
            sgnd_menu_show_menu
            sgnd_print
            sgnd_print_sectionheader --border "$DL_H" --maxwidth "${SGND_MENU_RENDER_WIDTH:-$(sgnd_terminal_width)}"
            sgnd_print

            choice=""
            if ! _smoketest_read_choice choice; then
                sgnd_print "No selection made. Returning..."
                break
            fi

            SGND_LAST_WAITSECS=0
            sgnd_menu_dispatch "$choice" || true
            (( SGND_SMOKETEST_EXIT )) && break

            if (( ${SGND_LAST_WAITSECS:-0} > 0 )); then
                ask_dlg_autocontinue \
                    --seconds "$SGND_LAST_WAITSECS" \
                    --message "Press Enter to continue, or wait to return to the smoke-test menu."
            fi
        done

        return 0
    }

# - Aggregate runner ---------------------------------------------------------------
    _framework_test_run_all() {
        local area_failures=0
        local smoke_rc=0

        _framework_test_validate_installation || area_failures=$((area_failures + 1))
        _framework_test_validate_console || area_failures=$((area_failures + 1))
        _framework_test_validate_modules || area_failures=$((area_failures + 1))

        _smoketest_run_all_tests || {
            smoke_rc=$?
            area_failures=$((area_failures + 1))
        }

        sgnd_print
        sgnd_print_sectionheader --text "Framework test summary"
        sgnd_print_labeledvalue --label "Validation passed" --value "$SGND_TEST_PASS" --labelwidth 22
        sgnd_print_labeledvalue --label "Validation failed" --value "$SGND_TEST_FAIL" --labelwidth 22
        sgnd_print_labeledvalue --label "Validation skipped" --value "$SGND_TEST_SKIP" --labelwidth 22
        sgnd_print_labeledvalue --label "Smoke tests" --value "$([[ $smoke_rc -eq 0 ]] && printf PASS || printf FAIL)" --labelwidth 22
        sgnd_print

        if (( area_failures == 0 )); then
            sayok "All SolidGroundUX framework tests passed."
            return 0
        fi

        sayfail "$area_failures framework test area(s) reported failures."
        return 1
    }

# - Main ---------------------------------------------------------------------------
    main() {
        _framework_locator || return $?
        sgnd_exe_start -- "$@"

        if (( ${FLAG_VIEW_LOG:-0} )); then
            view_log
            return $?
        fi

        case "${ENUM_SUITE:-smoke}" in
            smoke)
                _framework_test_run_smoke_menu
                ;;
            installation)
                _framework_test_validate_installation
                ;;
            console)
                _framework_test_validate_console
                ;;
            modules)
                _framework_test_validate_modules
                ;;
            all)
                _framework_test_run_all
                ;;
            *)
                sayfail "Unknown framework test suite: ${ENUM_SUITE:-}"
                return 2
                ;;
        esac
    }

    main "$@"
