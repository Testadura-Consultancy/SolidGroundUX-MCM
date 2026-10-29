#!/usr/bin/env bash
# SolidGroundUX SDK - Shared SSH deployment session and interactive recovery.
# Source in the caller process: exported SSH_AUTH_SOCK must reach ssh and rsync.
# Uses framework say*/ask helpers provided by the calling executable.
sgnd_ssh_agent_discover() {
    local candidate status
    for candidate in "${SSH_AUTH_SOCK:-}" "${HOME}/.ssh/solidgroundux-agent.sock"; do
        [[ -n "$candidate" && -S "$candidate" ]] || continue
        SSH_AUTH_SOCK="$candidate" ssh-add -l >/dev/null 2>&1
        status=$?
        if (( status == 0 || status == 1 )); then
            export SSH_AUTH_SOCK="$candidate"
            return 0
        fi
    done
    return 1
}

sgnd_ssh_agent_start() {
    local socket="${HOME}/.ssh/solidgroundux-agent.sock"
    sgnd_ssh_agent_discover && return 0
    command -v ssh-agent >/dev/null && command -v ssh-add >/dev/null || return 127
    install -d -m 0700 -- "${HOME}/.ssh" || return 1
    if [[ -S "$socket" ]]; then
        [[ -O "$socket" ]] || return 1
        rm -f -- "$socket" || return 1
    elif [[ -e "$socket" ]]; then
        return 1
    fi
    ssh-agent -a "$socket" -s >/dev/null || return 1
    export SSH_AUTH_SOCK="$socket"
}

# Test with BatchMode; offer recovery only at an interactive terminal.
# Inputs: remote user, hostname, port, optional private-key path.
sgnd_ssh_ensure_access() {
    local user="$1" host="$2" port="$3" key="${4:-}" selection="" rc=0
    local -a args=(ssh -o BatchMode=yes -o ConnectTimeout=8 -p "$port")
    [[ -z "$key" ]] || args+=(-i "$key")
    command -v ssh >/dev/null && command -v ssh-add >/dev/null || { sayfail "OpenSSH client tools are unavailable."; return 127; }
    sgnd_ssh_agent_discover || true
    while :; do
        rc=0
        "${args[@]}" -- "${user}@${host}" true >/dev/null 2>&1 || rc=$?
        (( rc == 0 )) && { sayok "SSH authentication verified for ${user}@${host}."; return 0; }
        saywarning "Non-interactive SSH to ${user}@${host} failed (exit $rc)."
        if [[ ! -t 0 ]]; then
            sayfail "SSH recovery needs an interactive terminal. Unlock the key or authorize it on the remote host."; return "$rc"
        fi
        ask_selection --label "SSH connection recovery" --var selection --items \
            "Start or reconnect SSH agent" "Unlock SSH private key" \
            "Install public key on remote host" "Retry SSH connection" "Cancel publishing" || return "$rc"
        case "$selection" in
            "Start or reconnect SSH agent")
                sgnd_ssh_agent_start && sayok "SSH agent ready." || sayfail "Could not start/connect SSH agent."
                ;;
            "Unlock SSH private key")
                local candidate="${key:-$HOME/.ssh/id_ed25519}"
                ask --label "Private key file" --var candidate --default "$candidate" --back || continue
                [[ -r "$candidate" ]] || { sayfail "Private key not readable: $candidate"; continue; }
                sgnd_ssh_agent_start || { sayfail "No working SSH agent."; continue; }
                ssh-add -- "$candidate" || sayfail "Could not unlock SSH key."
                ;;
            "Install public key on remote host")
                local candidate="${key:-$HOME/.ssh/id_ed25519}"
                ask --label "Private key file" --var candidate --default "$candidate" --back || continue
                [[ -r "${candidate}.pub" ]] || { sayfail "Public key not readable: ${candidate}.pub"; continue; }
                command -v ssh-copy-id >/dev/null || { sayfail "ssh-copy-id is unavailable."; continue; }
                local decision="NO"
                ask_decision --label "Install public key for ${user}@${host}" --choices "Yes|Y,No|N" --default "No" --var decision || continue
                [[ "$decision" == YES ]] || continue
                ssh-copy-id -p "$port" -i "${candidate}.pub" -- "${user}@${host}" || sayfail "Public key installation failed."
                ;;
            "Retry SSH connection") ;;
            "Cancel publishing") return "$rc" ;;
        esac
    done
}
