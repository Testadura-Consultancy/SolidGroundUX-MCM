#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX - Framework smoke tester
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2624123
#   Checksum    : 6a65dc89e09f7d8fbcdc1136cd0d00d6ae39c0b276f682a0780a98728c019c2b
#   Source      : framework-smoketest.sh
#   Type        : script
#   Group       : SDK
#   Purpose     : Exercise and validate core SolidGroundUX framework functionality
#
# Description:
#   Standalone executable test harness for verifying foundational framework behavior.
#
#   The script:
#     - Locates and loads the SolidGroundUX bootstrap configuration
#     - Loads the framework bootstrapper and common runtime services
#     - Exercises argument parsing, state, config, UI, and messaging behavior
#     - Provides manual test routines for ask-* interaction helpers
#     - Serves as a smoke test for framework integration during development
#
# Design principles:
#   - Executable scripts explicitly bootstrap and opt into framework features
#   - Libraries are sourced only and never auto-run
#   - Test flow should stay simple, visible, and easy to extend
#   - Framework integration issues should fail early and clearly
#
# Non-goals:
#   - Full automated regression testing
#   - Fine-grained unit isolation for every library function
#   - Replacement for dedicated shell test frameworks
#
# Attribution:
#   Developers  : Mark Fieten
#   Company     : Testadura Consultancy
#   Client      : -
#   Copyright   : © 2025 - 2026 Testadura Consultancy
#   License     : Licensed under the Testadura Non-Commercial License (TD-NC) v1.1.
# ==================================================================================
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

# - Script metadata (identity) ---------------------------------------------------
    SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
    SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
    SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
    SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
    SGND_SCRIPT_DESC="Canonical executable template for Testadura scripts"
    SGND_CONSOLE_LOG_LEVEL="${SGND_CONSOLE_LOG_LEVEL:-silent}"
    : "${SGND_SCRIPT_DESC:=Canonical executable template for Testadura scripts}"
    : "${SGND_SCRIPT_VERSION:=1.0}"
    : "${SGND_SCRIPT_BUILD:=20250110}"
    : "${SGND_SCRIPT_DEVELOPERS:=Mark Fieten}"
    : "${SGND_SCRIPT_COMPANY:=Testadura Consultancy}"
    : "${SGND_SCRIPT_COPYRIGHT:=© 2025 - 2026 Testadura Consultancy}"
    : "${SGND_SCRIPT_LICENSE:=Testadura Non-Commercial License (TD-NC) v1.1.}"

# - Script metadata (framework integration) --------------------------------------
    # Libraries to source from SGND_COMMON_LIB
    SGND_USING=(
        sgnd-datatable.sh
        console-helpers.sh
        sgnd-menu.sh
    )

    # SGND_ARGS_SPEC
        # --- Example: Arguments ----------------------------------------------
        # Each entry:
        #   "name|short|type|var|help|choices"
        #
        #   name    = long option name WITHOUT leading --
        #   short   - short option name WITHOUT leading -
        #   type    = flag | value | enum
        # var: = shell variable that will be set
        #   help    = help string for auto-generated --help output
        #   choices = for enum: comma-separated values (e.g. fast,slow,auto)
        #             for flag/value: leave empty
        #
        # Notes:
        #   - -h / --help is built in, you don't need to define it here.
        #   - After parsing you can use: FLAG_VERBOSE, VAL_CONFIG, ENUM_MODE, ...
    SGND_ARGS_SPEC=(
        "load|l|flag|FLAG_LOAD|Random argument for testing|"
        "unload|u|flag|FLAG_UNLOAD|Random argument for testing|"
        "exit|x|flag|FLAG_EXIT|Random argument for testing|"
        "view-log||flag|FLAG_VIEW_LOG|Display the active SolidGroundUX logfile and exit|"
    )

    SGND_SCRIPT_EXAMPLES=(
        "$SGND_SCRIPT_NAME --load --verbose  #Some example usage"
    ) 
    
    SGND_SCRIPT_GLOBALS=(
        "system|SGND_SYS_STRING|System CFG string|"
        "system|SGND_SYS_INT|System CFG int|"
        "system|SGND_SYS_DATE|System CFG date|"

        "user|SGND_USR_STRING|User CFG string|"
        "user|SGND_USR_INT|User CFG int|"
        "user|SGND_USR_DATE|User  CFG date|"

        "both|SGND_COMMON_STRING|Common CFG string|"
        "both|SGND_COMMON_INT|Common CFG int|"
        "both|SGND_COMMON_DATE|Common  CFG date|"
    )

    : "${INP_NAME=}"
    : "${INP_STREET=}"
    : "${INP_ZIPCODE=}"
    : "${INP_CITY=}"
    : "${INP_COUNTRY=}"
    : "${INP_AGE=}"
     
    SGND_STATE_VARIABLES=(
        "INP_NAME|Name|Petrus Puk|"
        "INP_STREET|Address|Nowhere straat|"
        "INP_ZIPCODE|Postcode|5544 QU|"
        "INP_CITY|Stad||"
        "INP_COUNTRY|||"
        "INP_AGE|Leeftijd|102|sgnd_is_number"
    )

    SGND_ON_EXIT_HANDLERS=(
    )

    SGND_STATE_SAVE=1

# - Local script Declarations ----------------------------------------------------
    : "${SGND_SYS_STRING:=system-default}"
    : "${SGND_SYS_INT:=0}"
    : "${SGND_SYS_DATE:=1970-01-01}"

    : "${SGND_USR_STRING:=user-default}"
    : "${SGND_USR_INT:=0}"
    : "${SGND_USR_DATE:=1970-01-01}"

    : "${SGND_COMMON_STRING:=common-default}"
    : "${SGND_COMMON_INT:=0}"
    : "${SGND_COMMON_DATE:=1970-01-01}"

    : "${STATE_VAR1:=State VAR1}"
    : "${STATE_VAR2:=4}"
    : "${STATE_VAR3:=2025-01-01}"
    
# - Local script functions -------------------------------------------------------
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
        # . Behavior
        #   - Resolves and displays the active logfile path.
        #   - Cycles through every supported SGND_FILE_LOG_LEVEL value.
        #   - Writes representative messages for each level so filtering can be inspected.
        #   - Finishes with SGND_FILE_LOG_LEVEL set to silent.
        #   - Saves the final silent setting in the framework state file when available.
        #
        # Outputs (globals):
        #   SGND_FILE_LOG_LEVEL
        #
        # Side effects:
        #   Appends test records to the active SolidGroundUX logfile.
        #   Updates SGND_FRAMEWORK_STATEFILE when framework state is available.
        #
        # . Returns
        #   0 when the test sequence completes.
        #   1 when no logfile can be resolved or the final state cannot be saved.
        #
        # . Usage
        #   file_loglevel_test
    file_loglevel_test() {
        local logfile=""
        local level=""

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

        SGND_FILE_LOG_LEVEL="silent"

        if [[ -n "${SGND_FRAMEWORK_STATEFILE:-}" ]]; then
            sgnd_state_set \
                --file "$SGND_FRAMEWORK_STATEFILE" \
                SGND_FILE_LOG_LEVEL \
                "$SGND_FILE_LOG_LEVEL" || return 1
        fi

        printf 'Finished with SGND_FILE_LOG_LEVEL=%s\n' "$SGND_FILE_LOG_LEVEL"
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
            sayerror "MOTD file not readable: $motd_file"
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
        sgdn_print
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
# - Main -------------------------------------------------------------------------
    # main MUST BE LAST function in script
        # Main entry point for the executable script.
        #
        # Execution flow:
        #   1) Invoke sgnd_bootstrap to initialize the framework environment, parse
        #      framework-level arguments, and optionally load UI, state, and config.
        #   2) Abort immediately if bootstrap reports an error condition.
        #   3) Enact framework builtin arguments (help, showargs, state reset, etc.).
        #      Info-only builtins terminate execution; mutating builtins may continue.
        #   4) Continue with script-specific logic.
        #
        # Bootstrap options:
        #   The script author explicitly selects which framework features to enable.
        #   None are required; include only what this script needs.
        #
        #   --state        Enable persistent state loading/saving.
        #   --needroot     Require execution as root.
        #   --cannotroot   Require execution as non-root.
        #   --console      Enable logging to console output.
        #   --             End of bootstrap options; remaining args are script arguments.
        # Notes:
        #   - Builtin argument handling is centralized in sgnd_builtinarg_handler.
        #   - Scripts may override builtin handling, but doing so transfers
        #     responsibility for correct behavior to the script author.
    # fn: _smoketest_show_license - Display the active SolidGroundUX license
        # Returns:
        #   Returns the underlying license renderer status.
        #
        # Usage:
        #   _smoketest_show_license
    _smoketest_show_license() {
        saydebug "$SGND_DOCS_DIR/$SGND_LICENSE_FILE"
        sgnd_print_license
    }

    # fn: _smoketest_run_all_tests - Run the complete smoke-test sequence
        # . Purpose
        #   Execute the principal framework smoke tests in their normal menu order.
        #
        # . Behavior
        #   - Runs ask, input, say, console log-level, file log-level, MOTD, and
        #     progress tests sequentially.
        #   - Leaves display-only license, color-chart, theme, and logfile actions
        #     available as individual menu choices.
        #
        # . Returns
        #   Returns 0 after the sequence completes.
        #
        # . Usage
        #   _smoketest_run_all_tests
    _smoketest_run_all_tests() {
        ask_test
        input_test
        say_test
        loglevel_test
        file_loglevel_test
        motd_test
        sayprogress_test
        return 0
    }

    # fn: _smoketest_request_exit - Mark the interactive smoke-test menu for exit
        # . Purpose
        #   Request termination of the current smoke-test menu loop.
        #
        # Outputs (globals):
        #   SGND_SMOKETEST_EXIT
        #
        # . Returns
        #   0 always.
        #
        # . Usage
        #   _smoketest_request_exit
    _smoketest_request_exit() {
        SGND_SMOKETEST_EXIT=1
        return 0
    }

    # fn: _smoketest_register_menu - Register the smoke-test menu through the public menu API
        # . Purpose
        #   Build the framework smoke-test menu using the reusable sgnd-menu API.
        #
        # . Behavior
        #   - Disables management-console togglebar chrome for this standalone menu.
        #   - Creates the menu model once for the current process.
        #   - Registers the numbered test actions in their historical order.
        #   - Registers the additional smoke-test actions as numbered items.
        #   - Keeps Q as the literal-key quit action.
        #
        # . Returns
        #   0 when all menu groups and items are registered successfully.
        #   Non-zero when menu creation or registration fails.
        #
        # . Usage
        #   _smoketest_register_menu
    _smoketest_register_menu() {
        SGND_MENU_SHOW_TOGGLEBAR=0

        sgnd_menu_create \
            "SolidGroundUX - Framework Unit Test Menu" \
            "Exercise and validate core SolidGroundUX framework functionality" || return $?

        sgnd_menu_register_group \
            "smoke-tests" \
            "Framework Tests" \
            "Run individual framework smoke tests" \
            0 1 100 || return $?

        sgnd_menu_register_item "ask"      "smoke-tests" "Ask tests"                 "ask_test"               "Exercise ask and dialog helpers" 0 15 1 || return $?
        sgnd_menu_register_item "selection" "smoke-tests" "Selection test"             "ask_selection_test"     "Exercise single and multiple ask_selection behavior" 0 15 1 || return $?
        sgnd_menu_register_item "input"    "smoke-tests" "Input test"                "input_test"             "Exercise input helpers" 0 15 1 || return $?
        sgnd_menu_register_item "say"      "smoke-tests" "Say test"                  "say_test"               "Exercise message output helpers" 0 15 1 || return $?
        sgnd_menu_register_item "loglevel" "smoke-tests" "Log level visibility test" "loglevel_test"          "Verify console log-level filtering" 0 15 1 || return $?
        sgnd_menu_register_item "motd"     "smoke-tests" "Call MOTD"                  "motd_test"              "Render the SolidGroundUX MOTD" 0 15 1 || return $?
        sgnd_menu_register_item "progress" "smoke-tests" "Progress dialogue test"     "sayprogress_test"       "Exercise one, two, and three stacked progress lines" 0 15 1 || return $?
        sgnd_menu_register_item "license"  "smoke-tests" "Show license"               "_smoketest_show_license" "Display the active SolidGroundUX license" 0 15 1 || return $?
        sgnd_menu_register_item "colors"   "smoke-tests" "Show color chart"           "show_colorchart"        "Display the current terminal color chart" 0 15 1 || return $?
        sgnd_menu_register_item "theme"    "smoke-tests" "Show theme"                 "show_theme"             "Display the active SolidGroundUX theme" 0 15 1 || return $?

        sgnd_menu_register_group \
            "smoke-actions" \
            "Smoke Test Actions" \
            "Logging and aggregate smoke-test actions" \
            1 1 900 || return $?

        sgnd_menu_register_item "filelog" "smoke-actions" "File log level test" "file_loglevel_test"       "Verify file log-level filtering" 0 15 1 || return $?
        sgnd_menu_register_item "viewlog" "smoke-actions" "View logfile"        "view_log"                 "Display the active SolidGroundUX logfile" 0 15 1 || return $?
        sgnd_menu_register_item "runall"  "smoke-actions" "Run all tests"       "_smoketest_run_all_tests" "Run the principal framework smoke-test sequence" 0 15 1 || return $?
        sgnd_menu_register_item "Q"       "smoke-actions" "Quit"                "_smoketest_request_exit"  "Exit the framework smoke tester" 1 0 1 || return $?

        return 0
    }

    # fn: _smoketest_read_choice - Read one smoke-test choice with auto-exit timeout
        # . Purpose
        #   Preserve the smoke test's 30-second inactivity timeout while allowing
        #   complete menu selections such as 11, 12, and 13 to be entered.
        #
        # . Arguments
        #   $1  OUTPUT_VAR - Variable receiving the selected menu choice.
        #
        # . Returns
        #   0 when a selection was read.
        #   1 when the 30-second timeout expires.
        #
        # . Usage
        #   _smoketest_read_choice choice
    _smoketest_read_choice() {
        local output_var="${1:?missing output variable}"
        local choice=""

        printf '%bSelect option (auto-exit in 30s): %b' \
            "${SGND_UI_TEXT:-}" \
            "${RESET:-}" >/dev/tty

        if IFS= read -r -t 30 choice </dev/tty; then
            printf -v "$output_var" '%s' "$choice"
            return 0
        fi

        printf '\n' >/dev/tty
        printf -v "$output_var" '%s' ''
        return 1
    }

    # fn: main - Run the SolidGroundUX framework smoke test
        # . Purpose
        #   Initialize the framework and run the interactive smoke-test menu.
        #
        # . Behavior
        #   - Starts through the canonical executable framework path.
        #   - Supports direct logfile viewing through --view-log.
        #   - Builds and renders the test menu through the public sgnd-menu API.
        #   - Suppresses management-console status/legend chrome and renders one final
        #     double separator before the selection prompt.
        #   - Preserves the historical 30-second inactivity auto-exit behavior.
        #
        # . Arguments
        #   $@  Framework and script-specific command-line arguments.
        #
        # . Returns
        #   Exits with the framework startup status or selected test status.
        #
        # . Usage
        #   main "$@"
    main() {
        local choice=""

        # -- Startup
            _framework_locator || exit $?
            sgnd_exe_start -- "$@"

            if (( ${FLAG_VIEW_LOG:-0} )); then
                view_log
                return $?
            fi

        # -- Main script logic
            _smoketest_register_menu || return $?

            SGND_SMOKETEST_EXIT=0

            while true; do
                sgnd_menu_show_menu
                sgnd_print_sectionheader --border "$DL_H" --maxwidth "${SGND_MENU_RENDER_WIDTH:-$(sgnd_terminal_width)}"

                choice=""
                if ! _smoketest_read_choice choice; then
                    sgnd_print "No selection made. Exiting..."
                    break
                fi

                # The timed reader is smoke-test-specific input policy; selection execution
                # is delegated to the public menu dispatcher.
                SGND_LAST_WAITSECS=0
                sgnd_menu_dispatch "$choice" || true

                (( SGND_SMOKETEST_EXIT )) && break

                if (( ${SGND_LAST_WAITSECS:-0} > 0 )); then
                    ask_dlg_autocontinue \
                        --seconds "$SGND_LAST_WAITSECS" \
                        --message "Press Enter to continue, or wait to return to the smoke-test menu."
                fi
            done
    }

    # Entrypoint: sgnd_bootstrap will split framework args from script args.
    main "$@"
