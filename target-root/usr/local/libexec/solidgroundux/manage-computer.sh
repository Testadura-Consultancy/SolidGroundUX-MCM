#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - manage-computer
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2627501
#   Shortname   : MANAGE_COMPUTER
#   Source      : manage-computer.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Computer Setup action implementation
# Description:
#   Standalone management actions dispatched from 10-computer-setup.sh.
#   UI, reporting and errors use the SolidGroundUX framework.
# ==================================================================================
set -uo pipefail

# - Bootstrap -----------------------------------------------------------------------
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
# - Script identity and framework integration ---------------------------------------
SGND_SCRIPT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
SGND_SCRIPT_DIR="$(cd -- "$(dirname -- "$SGND_SCRIPT_FILE")" && pwd)"
SGND_SCRIPT_BASE="$(basename -- "$SGND_SCRIPT_FILE")"
SGND_SCRIPT_NAME="${SGND_SCRIPT_BASE%.sh}"
SGND_USING=()
SGND_ARGS_SPEC=("action|a|enum|ACTION|Computer Setup action||ssh-host-keys,ssh-service,sudoers,status,validate" )
SGND_SCRIPT_EXAMPLES=("  $SGND_SCRIPT_NAME --action ssh-host-keys" )
SGND_SCRIPT_GLOBALS=()
SGND_STATE_VARIABLES=()
SGND_ON_EXIT_HANDLERS=()
SGND_STATE_SAVE=0

# - Actions -------------------------------------------------------------------------
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


# - Dispatch ------------------------------------------------------------------------
_run_action() {
    local action="${1:?missing action}"
    case "$action" in
        ssh-host-keys) _computer_generate_ssh_keys ;;
        ssh-service) _computer_configure_ssh_service ;;
        sudoers) _computer_configure_sudoers ;;
        status) _computer_status ;;
        validate) _computer_validate ;;
        *) sayfail "Unknown Computer Setup action: $action"; return 2 ;;
    esac
}

main() {
    _framework_locator || return $?
    sgnd_exe_start -- "$@" || return $?
    _run_action "${ACTION:-}"
}
main "$@"
