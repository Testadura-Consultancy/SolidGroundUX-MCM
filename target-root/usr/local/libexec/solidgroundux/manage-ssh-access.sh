#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - manage-ssh-access
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.1
#   Build       : 2629401
#   Shortname   : MANAGE_SSH_ACCESS
#   Source      : manage-ssh-access.sh
#   Type        : script
#   Group       : Role Managers
#   Purpose     : Computer Setup action implementation
#   Checksum : d5e18c0005a09ca2218b4f3d1272d8c22951cf351fb1affe578ce4b476ecf321
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
SGND_ARGS_SPEC=("action|a|enum|ACTION|Computer Setup action||generate-key,install-key,unlock-key,test-access" )
SGND_SCRIPT_EXAMPLES=("  $SGND_SCRIPT_NAME --action generate-key" )
SGND_SCRIPT_GLOBALS=()
SGND_STATE_VARIABLES=()
SGND_ON_EXIT_HANDLERS=()
SGND_STATE_SAVE=0

# - Actions -------------------------------------------------------------------------
    # - SSH deployment access ---------------------------------------------------------
    # These are USER keys for outbound connections, not the server HOST keys above.
    # Run these actions as the intended deployment account (not with sudo).

    # fn: _computer_ssh_user_guard - Keep deployment keys and agent owned by the login user.
    _computer_ssh_user_guard() {
        if (( EUID == 0 )); then
            sayfail "SSH deployment access must run as the intended non-root user, not root."
            return 1
        fi
        [[ -d "$HOME" && -w "$HOME" ]] || { sayfail "Home directory is unavailable: $HOME"; return 1; }
        command -v ssh >/dev/null 2>&1 && command -v ssh-keygen >/dev/null 2>&1 || {
            sayfail "OpenSSH client tools (ssh and ssh-keygen) are required."
            return 127
        }
    }

    # fn: _computer_ssh_select_key - Prompt for a private key; accept only home SSH keys.
    _computer_ssh_select_key() {
        local out_var="${1:?missing variable}" key="${HOME}/.ssh/id_ed25519"
        ask --label "SSH private key" --var key --default "$key" --back || return 2
        [[ "$key" == "$HOME/.ssh/"* && "$key" != *$'\n'* && "$key" != *$'\r'* ]] || {
            sayfail "Select a private key below $HOME/.ssh/."
            return 1
        }
        printf -v "$out_var" '%s' "$key"
    }

    # fn: _computer_ssh_select_remote - Read and validate remote SSH login details.
    _computer_ssh_select_remote() {
        local user_var="${1:?missing user var}" host_var="${2:?missing host var}"
        local remote_user="${USER:-}" remote_host=""
        ask --label "Remote SSH user" --var remote_user --default "$remote_user" --back || return 2
        ask --label "Remote SSH host" --var remote_host --back || return 2
        [[ "$remote_user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ && "$remote_host" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$remote_host" != -* ]] || {
            sayfail "Invalid remote SSH user or hostname."
            return 1
        }
        printf -v "$user_var" '%s' "$remote_user"
        printf -v "$host_var" '%s' "$remote_host"
    }

    # fn: _computer_ssh_generate_user_key - Safely create a personal Ed25519 key pair.
    _computer_ssh_generate_user_key() {
        local key="" decision="NO"
        _computer_ssh_user_guard || return $?
        _computer_ssh_select_key key || return $?
        if [[ -e "$key" || -e "${key}.pub" ]]; then
            saywarning "SSH key already exists; no key will be overwritten: $key"
            return 0
        fi
        sgnd_print_sectionheader --text "Generate deployment SSH key"
        sgnd_print_labeledvalue --label "Private key" --value "$key" --labelwidth 20
        sayinfo "ssh-keygen will request a passphrase. A passphrase is recommended."
        ask_decision --label "Generate this SSH key pair?" --choices "YES|Y,NO|N" --default "NO" --var decision || return 2
        [[ "$decision" == "YES" ]] || { saycancel "SSH key generation cancelled."; return 0; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would generate a new Ed25519 key at $key."
            return 0
        fi
        install -d -m 700 -- "${HOME}/.ssh" || { sayfail "Cannot create ~/.ssh."; return 1; }
        ssh-keygen -t ed25519 -f "$key" || { sayfail "SSH key generation failed."; return 1; }
        sayok "User SSH key pair created: $key"
    }

    # fn: _computer_ssh_install_key - Copy only the public key after confirmation.
    _computer_ssh_install_key() {
        local key="" remote_user="" remote_host="" decision="NO"
        _computer_ssh_user_guard || return $?
        command -v ssh-copy-id >/dev/null 2>&1 || { sayfail "ssh-copy-id is not installed."; return 127; }
        _computer_ssh_select_key key || return $?
        [[ -r "${key}.pub" && -s "${key}.pub" ]] || { sayfail "Public key not found: ${key}.pub"; return 1; }
        _computer_ssh_select_remote remote_user remote_host || return $?
        sgnd_print_sectionheader --text "Install SSH public key"
        sgnd_print_labeledvalue --label "Public key" --value "${key}.pub" --labelwidth 20
        sgnd_print_labeledvalue --label "Remote login" --value "${remote_user}@${remote_host}" --labelwidth 20
        ask_decision --label "Install this public key on the remote host?" --choices "YES|Y,NO|N" --default "NO" --var decision || return 2
        [[ "$decision" == "YES" ]] || { saycancel "Key installation cancelled."; return 0; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would install ${key}.pub on ${remote_user}@${remote_host}."
            return 0
        fi
        ssh-copy-id -i "${key}.pub" "${remote_user}@${remote_host}" || {
            sayfail "Could not install SSH public key on ${remote_user}@${remote_host}."
            return 1
        }
        sayok "Public key installed on ${remote_user}@${remote_host}."
    }

    # fn: _computer_ssh_agent_connect - Reuse or start a user-only agent at a stable socket.
    # A fixed socket lets later processes find the agent without storing its PID or passphrase.
    _computer_ssh_agent_connect() {
        local socket="${HOME}/.ssh/solidgroundux-agent.sock" status=0
        command -v ssh-agent >/dev/null 2>&1 && command -v ssh-add >/dev/null 2>&1 || {
            sayfail "ssh-agent and ssh-add are required."
            return 127
        }
        install -d -m 700 -- "${HOME}/.ssh" || return 1
        if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
            SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ssh-add -l >/dev/null 2>&1
            status=$?
            if (( status == 0 || status == 1 )); then
                sayinfo "Reusing the current SSH agent."
                return 0
            fi
        fi
        if [[ -S "$socket" ]]; then
            SSH_AUTH_SOCK="$socket" ssh-add -l >/dev/null 2>&1
            status=$?
            if (( status == 0 || status == 1 )); then
                export SSH_AUTH_SOCK="$socket"
                sayinfo "Reusing SolidGroundUX SSH agent."
                return 0
            fi
            [[ -O "$socket" ]] || { sayfail "Cannot replace an agent socket owned by another user."; return 1; }
            rm -f -- "$socket" || return 1
        elif [[ -e "$socket" ]]; then
            sayfail "Agent socket path is occupied by a non-socket: $socket"
            return 1
        fi
        ssh-agent -a "$socket" -s >/dev/null || { sayfail "Could not start SSH agent."; return 1; }
        export SSH_AUTH_SOCK="$socket"
        sayok "SSH agent started at $socket."
    }

    # fn: _computer_ssh_unlock_key - Load the deployment key into the agent.
    _computer_ssh_unlock_key() {
        local key=""
        _computer_ssh_user_guard || return $?
        _computer_ssh_select_key key || return $?
        [[ -r "$key" ]] || { sayfail "Private key not found: $key"; return 1; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would connect to an SSH agent and load $key."
            return 0
        fi
        _computer_ssh_agent_connect || return $?
        ssh-add "$key" || { sayfail "Could not load the SSH key into the agent."; return 1; }
        sayok "Deployment SSH key loaded for this agent session."
        sayinfo "Other shells can reuse this agent with: export SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
    }

    # fn: _computer_ssh_test_access - Verify unattended SSH with the chosen identity.
    _computer_ssh_test_access() {
        local key="" remote_user="" remote_host="" result="" rc=0
        _computer_ssh_user_guard || return $?
        _computer_ssh_select_key key || return $?
        [[ -r "$key" ]] || { sayfail "Private key not found: $key"; return 1; }
        _computer_ssh_select_remote remote_user remote_host || return $?
        if [[ -z "${SSH_AUTH_SOCK:-}" && -S "${HOME}/.ssh/solidgroundux-agent.sock" ]]; then
            export SSH_AUTH_SOCK="${HOME}/.ssh/solidgroundux-agent.sock"
        fi
        sgnd_print_sectionheader --text "Test SSH deployment access"
        sayinfo "Checking passwordless SSH authentication to ${remote_user}@${remote_host}..."
        result="$(ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=8 -- "${remote_user}@${remote_host}" hostname 2>&1)" || rc=$?
        if (( rc != 0 )); then
            sayfail "SSH authentication failed (exit $rc): ${remote_user}@${remote_host}"
            [[ -z "$result" ]] || saywarning "$result"
            sayinfo "If the private key has a passphrase, first choose 'Unlock SSH key in agent'."
            return "$rc"
        fi
        sayok "Non-interactive SSH login succeeded."
        sgnd_print_labeledvalue --label "Remote hostname" --value "$result" --labelwidth 20
    }


# - Dispatch ------------------------------------------------------------------------
_run_action() {
    local action="${1:?missing action}"
    case "$action" in
        generate-key) _computer_ssh_generate_user_key ;;
        install-key) _computer_ssh_install_key ;;
        unlock-key) _computer_ssh_unlock_key ;;
        test-access) _computer_ssh_test_access ;;
        *) sayfail "Unknown Computer Setup action: $action"; return 2 ;;
    esac
}

main() {
    _framework_locator || return $?
    sgnd_exe_start -- "$@" || return $?
    _run_action "${ACTION:-}"
}
main "$@"
