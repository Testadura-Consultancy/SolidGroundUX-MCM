# ==================================================================================
# SolidGroundUX Management Console Modules - Computer Setup
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 1.2
#   Build       : 2626021
#   Checksum    : fa29201a01208bb0ebe2027e643252c20d36590cb0f586515d44891a08931063
#   Source      : 10-computer-setup.sh
#   Type        : module
#   Group       : Module Registration
#   Purpose     : Configure and validate the base computer
#
# Description:
#   Registers the normal post-clone computer setup actions. The Prepare computer
#   action orchestrates the same individual actions shown beneath it in the menu.
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
    SGND_COMPUTER_SETUP_MODULE_ID="computer-setup"
    SGND_COMPUTER_SETUP_MODULE_NAME="Computer Setup"
    SGND_COMPUTER_SETUP_MODULE_VERSION="2.0.0"
    SGND_COMPUTER_SETUP_MODULE_DESC="Prepare and validate the base computer"
    
    SGND_COMPUTER_SUDOERS_FILE="/etc/sudoers.d/solidgroundux-receiver"

    SGND_MODULE_NAME="$SGND_COMPUTER_SETUP_MODULE_NAME"
    SGND_MODULE_VERSION="$SGND_COMPUTER_SETUP_MODULE_VERSION"
    SGND_MODULE_DESC="$SGND_COMPUTER_SETUP_MODULE_DESC"

# - Module actions -----------------------------------------------------------------
    # fn: _computer_set_identity
        # . Purpose
        #   Run the canonical SolidGroundUX identity workflow.
        #
        # . Returns
        #   Exit status from set-identity.sh.
        # . Usage
        #   _computer_set_identity "<args...>"
    _computer_set_identity() {
        _sgnd_run_module_script "set-identity.sh" "$@"
    }

    # fn: _computer_configure_ssh_service
        # . Purpose
        #   Enable or disable SSH and keep its runtime state aligned.
        #
        # . Returns
        #   0 on success; non-zero on failure.
        # . Usage
        #   _computer_configure_ssh_service
    _computer_configure_ssh_service() {
        local ssh_unit="ssh.service"
        local enabled="N"
        local requested="N"

        if ! systemctl cat "$ssh_unit" >/dev/null 2>&1; then
            ssh_unit="sshd.service"
        fi

        if ! systemctl cat "$ssh_unit" >/dev/null 2>&1; then
            sayfail "No SSH service unit was found."
            return 1
        fi

        if systemctl is-enabled "$ssh_unit" >/dev/null 2>&1; then
            enabled="Y"
        fi
        requested="$enabled"

        ask --label "Enable SSH service (Y/N)" --var requested --default "$requested" --labelwidth 32

        case "${requested^^}" in
            Y|YES)
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "Dry run: Would enable and start $ssh_unit."
                    return 0
                fi

                sudo systemctl enable --now "$ssh_unit" || return $?
                sayok "SSH service enabled and started."
                ;;
            *)
                if (( ${FLAG_DRYRUN:-0} == 1 )); then
                    sayinfo "Dry run: Would disable and stop $ssh_unit."
                    return 0
                fi

                sudo systemctl disable --now "$ssh_unit" || return $?
                sayok "SSH service disabled and stopped."
                ;;
        esac
    }

    # fn: _computer_generate_ssh_keys
        # . Purpose
        #   Generate missing SSH host keys, validate sshd, and restart SSH.
        #
        # . Returns
        #   0 on success; non-zero on failure.
        # . Usage
        #   _computer_generate_ssh_keys
    _computer_generate_ssh_keys() {
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would generate SSH host keys and restart SSH."
            return 0
        fi

        sudo install -d -m 0755 -o root -g root /run/sshd || return 1
        sudo ssh-keygen -A || {
            sayfail "Failed to generate SSH host keys."
            return 1
        }

        sudo sshd -t || {
            sayfail "SSH configuration validation failed."
            return 1
        }

        sudo systemctl restart ssh.service 2>/dev/null || \
            sudo systemctl restart sshd.service || {
                sayfail "Failed to restart SSH service."
                return 1
            }

        sayok "SSH host keys are present and SSH configuration is valid."
    }

    # fn: _computer_configure_sudoers
        # . Purpose
        #   Grant the selected administrator passwordless access to trusted
        #   SolidGroundUX administration executables.
        #
        # . Returns
        #   0 on success; non-zero on failure or cancellation.
        # . Usage
        #   _computer_configure_sudoers
    _computer_configure_sudoers() {
        local admin_user="${SUDO_USER:-${USER:-sysadmin}}"
        local temp_file=""
        local decision="No"

        ask --label "SolidGroundUX administrator" --var admin_user --default "$admin_user" --labelwidth 32

        id "$admin_user" >/dev/null 2>&1 || {
            sayfail "User does not exist: $admin_user"
            return 1
        }

        sgnd_print
        sgnd_print "This grants $admin_user passwordless sudo access to trusted"
        sgnd_print "SolidGroundUX administration tools beneath:"
        sgnd_print "  /usr/local/libexec/solidgroundux"
        sgnd_print

        ask_decision \
            --label "Configure SolidGroundUX sudo access for $admin_user?" \
            --choices "Yes|Y,No|N" \
            --default "No" \
            --var decision || return $?

        [[ "${decision^^}" == "YES" ]] || {
            saycancel "Sudo configuration cancelled."
            return 0
        }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would create $SGND_COMPUTER_SUDOERS_FILE for $admin_user."
            return 0
        fi

        command -v visudo >/dev/null 2>&1 || {
            sayfail "visudo is unavailable. Install the sudo package first."
            return 1
        }

        temp_file="$(mktemp "${TMPDIR:-/tmp}/solidgroundux-sudoers.XXXXXX")" || return 1

        printf '%s\n' \
            '# SolidGroundUX sudo policy' \
            '# Passwordless elevation for trusted framework administration tools.' \
            'Cmnd_Alias SGND_ADMIN = /usr/local/libexec/solidgroundux/*' \
            "$admin_user ALL=(root) NOPASSWD: SGND_ADMIN" \
            > "$temp_file" || {
                rm -f -- "$temp_file"
                return 1
            }

        visudo -cf "$temp_file" >/dev/null || {
            rm -f -- "$temp_file"
            sayfail "Generated sudoers configuration is invalid."
            return 1
        }

        sudo install -m 0440 -o root -g root "$temp_file" "$SGND_COMPUTER_SUDOERS_FILE" || {
            rm -f -- "$temp_file"
            return 1
        }
        rm -f -- "$temp_file"

        sudo visudo -cf "$SGND_COMPUTER_SUDOERS_FILE" >/dev/null || {
            sayfail "Installed sudoers configuration failed validation."
            return 1
        }

        sayok "SolidGroundUX passwordless sudo access configured for $admin_user."
    }

    # fn: _computer_prepare
        # . Purpose
        #   Run the normal post-clone computer setup sequence.
        #
        # . Behavior
        #   - Runs the same four actions registered beneath Prepare computer.
        #   - Persists the result of each individual step through the console tracker.
        #   - Stops on the first failed step.
        #
        # . Returns
        #   0 when all steps succeed; otherwise the failing step status.
        # . Usage
        #   _computer_prepare
    _computer_prepare() {
        sgnd_console_run_tracked "setnetid" _computer_set_identity || return $?
        sgnd_console_run_tracked "sshkeys" _computer_generate_ssh_keys || return $?
        sgnd_console_run_tracked "sshcfg" _computer_configure_ssh_service || return $?
        sgnd_console_run_tracked "sudoers" _computer_configure_sudoers || return $?

        sayok "Computer preparation completed successfully."
        return 0
    }


    # fn: _computer_status
        # . Purpose
        #   Display the current Computer Setup state without changing the machine.
        #
        # . Returns
        #   0 after displaying available status information.
        # . Usage
        #   _computer_status "<dns_servers>" "<dns_servers>"
    _computer_status() {
        local hostname_short=""
        local fqdn=""
        local primary_ip=""
        local default_route=""
        local dns_servers=""
        local search_domain=""
        local ssh_unit="ssh.service"
        local ssh_enabled="not installed"
        local ssh_active="not installed"
        local host_key_count=0
        local sudo_state="not configured"

        hostname_short="$(hostname -s 2>/dev/null || true)"
        fqdn="$(hostname -f 2>/dev/null || true)"
        primary_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')"
        default_route="$(ip -4 route show default 2>/dev/null | awk 'NR==1 { print $0 }')"

        if command -v resolvectl >/dev/null 2>&1; then
            dns_servers="$(resolvectl dns 2>/dev/null | awk '{$1=$1; print}' | paste -sd '; ' -)"
            search_domain="$(resolvectl domain 2>/dev/null | awk '{$1=$1; print}' | paste -sd '; ' -)"
        elif [[ -r /etc/resolv.conf ]]; then
            dns_servers="$(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf | paste -sd ', ' -)"
            search_domain="$(awk '/^[[:space:]]*(search|domain)[[:space:]]+/ {$1=""; sub(/^[[:space:]]+/, ""); print; exit}' /etc/resolv.conf)"
        fi

        if ! systemctl cat "$ssh_unit" >/dev/null 2>&1; then
            ssh_unit="sshd.service"
        fi

        if systemctl cat "$ssh_unit" >/dev/null 2>&1; then
            ssh_enabled="$(systemctl is-enabled "$ssh_unit" 2>/dev/null || true)"
            ssh_active="$(systemctl is-active "$ssh_unit" 2>/dev/null || true)"
            [[ -n "$ssh_enabled" ]] || ssh_enabled="unknown"
            [[ -n "$ssh_active" ]] || ssh_active="unknown"
        fi

        host_key_count="$(find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*_key' 2>/dev/null | wc -l)"

        if [[ -s "$SGND_COMPUTER_SUDOERS_FILE" ]]; then
            if command -v visudo >/dev/null 2>&1 && sudo visudo -cf "$SGND_COMPUTER_SUDOERS_FILE" >/dev/null 2>&1; then
                sudo_state="configured / valid"
            else
                sudo_state="configured / invalid"
            fi
        fi

        sgnd_print
        sgnd_print_sectionheader "Computer Setup Status"
        sgnd_print_labeledvalue --label "Hostname" --value "${hostname_short:-unknown}" --labelwidth 24
        sgnd_print_labeledvalue --label "FQDN" --value "${fqdn:-unknown}" --labelwidth 24
        sgnd_print_labeledvalue --label "Primary IPv4" --value "${primary_ip:-unknown}" --labelwidth 24
        sgnd_print_labeledvalue --label "Default route" --value "${default_route:-none}" --labelwidth 24
        sgnd_print_labeledvalue --label "DNS servers" --value "${dns_servers:-unknown}" --labelwidth 24
        sgnd_print_labeledvalue --label "Search domain" --value "${search_domain:-none}" --labelwidth 24
        sgnd_print_labeledvalue --label "SSH unit" --value "$ssh_unit" --labelwidth 24
        sgnd_print_labeledvalue --label "SSH enabled" --value "$ssh_enabled" --labelwidth 24
        sgnd_print_labeledvalue --label "SSH active" --value "$ssh_active" --labelwidth 24
        sgnd_print_labeledvalue --label "SSH host keys" --value "$host_key_count" --labelwidth 24
        sgnd_print_labeledvalue --label "SolidGround sudo" --value "$sudo_state" --labelwidth 24
        return 0
    }

    # fn: _computer_validate
        # . Purpose
        #   Validate the principal Computer Setup outcomes without changing the machine.
        #
        # . Returns
        #   0 when all required checks pass; 1 otherwise.
        # . Usage
        #   _computer_validate
    _computer_validate() {
        local failures=0
        local hostname_short=""
        local primary_ip=""
        local ssh_unit="ssh.service"
        local host_key_count=0

        hostname_short="$(hostname -s 2>/dev/null || true)"
        primary_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')"

        sgnd_print
        sgnd_print_sectionheader "Computer setup validation"

        if [[ -n "$hostname_short" && "$hostname_short" != "localhost" ]]; then
            sgnd_print_labeledvalue --label "Hostname" --value "Passed"
        else
            sgnd_print_labeledvalue --label "Hostname" --value "Failed"
            failures=$((failures + 1))
        fi

        if [[ -n "$primary_ip" && "$primary_ip" != 127.* ]]; then
            sgnd_print_labeledvalue --label "Primary IPv4" --value "Passed ($primary_ip)"
        else
            sgnd_print_labeledvalue --label "Primary IPv4" --value "Failed"
            failures=$((failures + 1))
        fi

        if ! systemctl cat "$ssh_unit" >/dev/null 2>&1; then
            ssh_unit="sshd.service"
        fi

        if systemctl is-enabled --quiet "$ssh_unit" 2>/dev/null && systemctl is-active --quiet "$ssh_unit" 2>/dev/null; then
            sgnd_print_labeledvalue --label "SSH service" --value "Passed"
        else
            sgnd_print_labeledvalue --label "SSH service" --value "Failed"
            failures=$((failures + 1))
        fi

        host_key_count="$(find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*_key' 2>/dev/null | wc -l)"
        if (( host_key_count > 0 )); then
            sgnd_print_labeledvalue --label "SSH host keys" --value "Passed ($host_key_count)"
        else
            sgnd_print_labeledvalue --label "SSH host keys" --value "Failed"
            failures=$((failures + 1))
        fi

        if [[ -s "$SGND_COMPUTER_SUDOERS_FILE" ]] && sudo visudo -cf "$SGND_COMPUTER_SUDOERS_FILE" >/dev/null 2>&1; then
            sgnd_print_labeledvalue --label "SolidGround sudo" --value "Passed"
        else
            sgnd_print_labeledvalue --label "SolidGround sudo" --value "Failed"
            failures=$((failures + 1))
        fi

        sgnd_print
        if (( failures == 0 )); then
            sayok "Computer setup validation passed."
            return 0
        fi

        sayfail "$failures computer setup validation check(s) failed."
        return 1
    }

    # fn: _prepare-template.sh
        # . Purpose
        #   Prepare a template computer for cloning.
        #
        # . Returns
        #   0 on success; non-zero on failure.
    _prepare_template() {
        _sgnd_run_public_command "sgnd-prepare-template"
    }

# - Console registration ---------------------------------------------------------
    # Provides the base post-clone computer setup workflow, including machine
    # identity, SSH, SolidGround sudo access, status, validation, and preparation
    # for cloning.
    #
    # . Menu items
    # ! Prepare computer
    #   > Run the normal post-clone setup sequence.
    #   > Handler: _computer_prepare
    #
    # ! Set computer identity
    #   > Configure hostname, network identity, DNS, and search domain.
    #   > Handler: _computer_set_identity
    #
    # ! Generate SSH host keys
    #   > Generate missing host keys, validate sshd, and restart SSH.
    #   > Handler: _computer_generate_ssh_keys
    #
    # ! Configure SSH service
    #   > Enable or disable the SSH service.
    #   > Handler: _computer_configure_ssh_service
    #
    # ! Setup SolidGround sudo access
    #   > Allow the administrator to run trusted SolidGroundUX tools without a password.
    #   > Handler: _computer_configure_sudoers
    #
    # ! Show computer status
    #   > Show identity, network, SSH, host-key, and SolidGround sudo state.
    #   > Handler: _computer_status
    #
    # ! Validate computer setup
    #   > Validate identity, SSH, host keys, and SolidGround sudo access.
    #   > Handler: _computer_validate
    #
    # ! Prepare for cloning
    #   > Prepare a template computer for cloning.
    #   > Handler: _prepare_template
    #   > Command: sgnd-prepare-template
    sgnd_menu_register_group \
        "$SGND_COMPUTER_SETUP_MODULE_ID" \
        "$SGND_COMPUTER_SETUP_MODULE_NAME" \
        "$SGND_COMPUTER_SETUP_MODULE_DESC" \
        0 1 100

    sgnd_menu_register_item "preparepc" "$SGND_COMPUTER_SETUP_MODULE_ID" "Prepare computer" "_computer_prepare" "Run the normal post-clone setup sequence" 0 15 1 0
    sgnd_menu_register_item "setnetid" "$SGND_COMPUTER_SETUP_MODULE_ID" "Set computer identity" "_computer_set_identity" "Configure hostname, network identity, DNS, and search domain" 0 15 1 1
   
    sgnd_menu_register_item "sshkeys" "$SGND_COMPUTER_SETUP_MODULE_ID" "Generate SSH host keys" "_computer_generate_ssh_keys" "Generate missing host keys, validate sshd, and restart SSH" 0 15 1 1
    sgnd_menu_register_item "sshcfg" "$SGND_COMPUTER_SETUP_MODULE_ID" "Configure SSH service" "_computer_configure_ssh_service" "Enable or disable the SSH service" 0 15 1 1
   
    sgnd_menu_register_item "sudoers" "$SGND_COMPUTER_SETUP_MODULE_ID" "Setup SolidGround sudo access" "_computer_configure_sudoers" "Allow the administrator to run trusted SolidGroundUX tools without a password" 0 15 1 1
    sgnd_menu_register_item "pcstatus" "$SGND_COMPUTER_SETUP_MODULE_ID" "Show computer status" "_computer_status" "Show identity, network, SSH, host-key, and SolidGround sudo state" 0 30 1 0
    sgnd_menu_register_item "pcvalidate" "$SGND_COMPUTER_SETUP_MODULE_ID" "Validate computer setup" "_computer_validate" "Validate identity, SSH, host keys, and SolidGround sudo access" 0 15 1 0
    sgnd_menu_register_item "preptemplate" "$SGND_COMPUTER_SETUP_MODULE_ID" "Prepare for cloning" "_prepare_template" "Prepare a template computer for cloning" 0 15 1 0

    sayinfo "Computer Setup module registered with the console."
