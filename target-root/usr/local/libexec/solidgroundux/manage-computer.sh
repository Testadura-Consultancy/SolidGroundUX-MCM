#!/usr/bin/env bash
# ==================================================================================
# SolidGroundUX Management Console Modules - manage-computer
# ----------------------------------------------------------------------------------
# Metadata:
#   Version     : 2.2
#   Build       : 2630913
#   Shortname   : MANAGE_COMPUTER
#   Source      : manage-computer.sh
#   Type        : script
#   Group       : Modules
#   Subgroup    : Computer Setup
#   Purpose     : Computer Setup action implementation
#   Checksum : 33a19c05148a52e0fdd84d292c1dff34c82083eea2e2071016597d672915aa31
# Description:
#   Standalone management actions dispatched from 10-computer-setup.sh.
#   UI, reporting and errors use the SolidGroundUX framework.
#
# Usage:
#   Run the executable from its shell command (or installed wrapper):
#   ```bash
#   manage-computer --action ssh-host-keys
#   ```
#
#   Script-specific options:
#   - `--action NAME`, `-a`: Computer Setup action (choices: `ssh-host-keys`, `ssh-service`, `sudoers`, `desktop-login`, `rdp`, `rdp-sessions`, `status`, `validate`).
#
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
        #   ```bash
        #   _framework_locator || return $?
        #   ```
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
SGND_ARGS_SPEC=("action|a|enum|ACTION|Computer Setup action||ssh-host-keys,ssh-service,sudoers,desktop-login,rdp,rdp-sessions,status,validate" )
SGND_SCRIPT_EXAMPLES=("  $SGND_SCRIPT_NAME --action ssh-host-keys" )
SGND_SCRIPT_GLOBALS=()
SGND_STATE_VARIABLES=()
SGND_ON_EXIT_HANDLERS=()
SGND_STATE_SAVE=0

# Standalone actions run in a separate shell from the console module.
# Define the sudo policy path here rather than relying on module globals.
SGND_COMPUTER_SUDOERS_FILE="/etc/sudoers.d/solidgroundux-receiver"
SGND_COMPUTER_LIGHTDM_FILE="/etc/lightdm/lightdm.conf.d/80-solidgroundux-ad-login.conf"
SGND_COMPUTER_XRDP_LAUNCHER="/usr/local/libexec/solidgroundux/xrdp-cinnamon-session.sh"
SGND_COMPUTER_RDP_UFW_STATE="/etc/solidgroundux/desktop-rdp-ufw-cidr"

# - Actions -------------------------------------------------------------------------
    # fn: _computer_configure_ssh_service
        # . Purpose
        #   Enable or disable SSH and keep its runtime state aligned.
        #
        # . Returns
        #   - 0 on success; non-zero on failure.
        # . Usage
        #   ```bash
        #   _computer_configure_ssh_service
        #   ```
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
        #   Ensure OpenSSH Server is installed, generate missing SSH host keys,
        #   validate sshd, and restart SSH.
        #
        # . Behavior
        #   - Installs openssh-server when the server executable is missing.
        #   - Validates the SSH configuration using the absolute sshd path so
        #     the result does not depend on sudo's executable search path.
        #   - Regenerates missing host keys and restarts SSH after validation.
        #
        # . Returns
        #   - 0 on success; non-zero on failure.
        # . Usage
        #   ```bash
        #   _computer_generate_ssh_keys
        #   ```
    _computer_generate_ssh_keys() {
        local sshd_binary="/usr/sbin/sshd"

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            if [[ ! -x "$sshd_binary" ]]; then
                sayinfo "Dry run: Would install openssh-server."
            fi
            sayinfo "Dry run: Would generate SSH host keys and restart SSH."
            return 0
        fi

        if [[ ! -x "$sshd_binary" ]]; then
            command -v apt-get >/dev/null 2>&1 || {
                sayfail "OpenSSH Server is missing and apt-get is unavailable. Install openssh-server manually."
                return 1
            }

            sayinfo "OpenSSH Server is missing. Installing openssh-server."
            sudo apt-get update || {
                sayfail "Failed to update package lists for openssh-server."
                return 1
            }
            sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server || {
                sayfail "Failed to install openssh-server."
                return 1
            }

            [[ -x "$sshd_binary" ]] || {
                sayfail "OpenSSH Server installation completed, but $sshd_binary is still unavailable."
                return 1
            }
        fi

        sudo install -d -m 0755 -o root -g root /run/sshd || return 1
        sudo ssh-keygen -A || {
            sayfail "Failed to generate SSH host keys."
            return 1
        }

        sudo "$sshd_binary" -t || {
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
        #   - 0 on success; non-zero on failure or cancellation.
        # . Usage
        #   ```bash
        #   _computer_configure_sudoers
        #   ```
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

    # fn: _computer_has_cinnamon
        # . Purpose
        #   Detect an installed Cinnamon X11 session, including over SSH.
        # . Returns
        #   0 if Cinnamon is available; 1 otherwise.
        # . Usage
        #   ```bash
        #   _computer_has_cinnamon
        #   ```
    _computer_has_cinnamon() {
        [[ -f /usr/share/xsessions/cinnamon.desktop ]] && { [[ -x /usr/bin/cinnamon-session-cinnamon ]] || [[ -x /usr/bin/cinnamon-session ]]; }
    }

    # fn: _computer_display_manager
        # . Purpose
        #   Identify the configured display manager, not the calling SSH session.
        # . Returns
        #   Prints lightdm, gdm3, sddm, or unknown.
        # . Usage
        #   ```bash
        #   manager="$(_computer_display_manager)"
        #   ```
    _computer_display_manager() {
        local manager=""
        manager="$(cat /etc/X11/default-display-manager 2>/dev/null || true)"
        case "${manager##*/}" in
            lightdm) printf 'lightdm\n' ;;
            gdm|gdm3) printf 'gdm3\n' ;;
            sddm) printf 'sddm\n' ;;
            *) printf 'unknown\n' ;;
        esac
    }

    # fn: _computer_desktop_backend
        # . Purpose
        #   Select the installed workstation desktop and suitable RDP integration.
        # . Returns
        #   Prints cinnamon, gnome, plasma, or unsupported.
        # . Usage
        #   ```bash
        #   backend="$(_computer_desktop_backend)"
        #   ```
    _computer_desktop_backend() {
        case "$(_computer_display_manager)" in
            lightdm)
                if _computer_has_cinnamon; then printf 'cinnamon\n'; else printf 'unsupported\n'; fi
                ;;
            gdm3)
                if command -v gnome-shell >/dev/null 2>&1; then printf 'gnome\n'; else printf 'unsupported\n'; fi
                ;;
            sddm)
                if command -v plasmashell >/dev/null 2>&1; then printf 'plasma\n'; else printf 'unsupported\n'; fi
                ;;
            *) printf 'unsupported\n' ;;
        esac
    }

    # fn: _computer_configure_desktop_login
        # . Purpose
        #   Configure manual AD login and PAM home-directory creation for common display managers.
        # . Description
        #   LightDM needs a manual-login greeter drop-in. GDM has a built-in
        #   "Not listed?" login, and SDDM provides manual username entry;
        #   those greeters are preserved. Enable shared PAM mkhomedir without
        #   enabling automatic login or restarting the active display manager.
        # . Returns
        #   0 on success/cancel; 1 on error; 2 on unsupported display manager.
        # . Usage
        #   ```bash
        #   _computer_configure_desktop_login
        #   ```
    _computer_configure_desktop_login() {
        local manager=""
        local desktop=""
        local decision="No"
        local temp_file=""

        manager="$(_computer_display_manager)"
        desktop="$(_computer_desktop_backend)"
        if [[ "$desktop" == "unsupported" ]]; then
            saywarning "No supported Cinnamon/LightDM, GNOME/GDM3 or Plasma/SDDM desktop was found."
            return 2
        fi
        [[ -x /usr/sbin/pam-auth-update ]] || {
            sayfail "pam-auth-update is unavailable; this action currently supports Debian/Ubuntu PAM."
            return 1
        }

        sgnd_print
        sgnd_print_sectionheader "Desktop domain login"
        case "$desktop" in
            cinnamon) sgnd_print_labeledvalue --label "Desktop" --value "Cinnamon (X11)" --labelwidth 26 ;;
            gnome) sgnd_print_labeledvalue --label "Desktop" --value "GNOME (Wayland)" --labelwidth 26 ;;
            plasma) sgnd_print_labeledvalue --label "Desktop" --value "KDE Plasma" --labelwidth 26 ;;
        esac
        sgnd_print_labeledvalue --label "Display manager" --value "${manager^^}" --labelwidth 26
        sgnd_print_labeledvalue --label "Domain login" --value "Manual username entry" --labelwidth 26
        sgnd_print_labeledvalue --label "Home directories" --value "PAM mkhomedir" --labelwidth 26
        if command -v realm >/dev/null 2>&1 && ! realm list 2>/dev/null | grep -q '^[[:space:]]*realm-name:'; then
            sayinfo "No joined AD realm was detected. This only prepares the desktop login."
        fi
        sgnd_print

        ask_decision --label "Configure desktop domain login" \
            --choices "Yes|Y,No|N,Quit|Q" --default "No" --var decision || return $?
        [[ "${decision^^}" == "YES" ]] || { saycancel "Desktop configuration not changed."; return 0; }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would configure ${manager} manual login and enable PAM mkhomedir."
            return 0
        fi

        case "$manager" in
            lightdm)
                temp_file="$(mktemp "${TMPDIR:-/tmp}/sgnd-lightdm.XXXXXX")" || return 1
                printf '%s\n' \
                    '# Managed by SolidGroundUX Computer Setup.' \
                    '[Seat:*]' \
                    'greeter-show-manual-login=true' > "$temp_file" || { rm -f -- "$temp_file"; return 1; }
                sudo install -d -m 0755 /etc/lightdm/lightdm.conf.d || { rm -f -- "$temp_file"; return 1; }
                sudo install -m 0644 -o root -g root "$temp_file" "$SGND_COMPUTER_LIGHTDM_FILE" || {
                    rm -f -- "$temp_file"
                    return 1
                }
                rm -f -- "$temp_file"
                ;;
            gdm3)
                # GNOME already offers the "Not listed?" prompt for domain users.
                # Do not hide the local user list or change GDM autologin.
                sayinfo "At GDM, select 'Not listed?' to enter the complete domain username."
                ;;
            sddm)
                # SDDM already provides a username field. No theme-specific
                # configuration is imposed; domain UIDs need not be enumerated.
                sayinfo "SDDM greeter supports manual usernames; no SDDM override is needed."
                ;;
        esac

        if ! sudo /usr/sbin/pam-auth-update --enable mkhomedir; then
            sayfail "Desktop login configured, but enabling PAM mkhomedir failed."
            return 1
        fi
        if ! grep -q 'pam_mkhomedir.so' /etc/pam.d/common-session 2>/dev/null; then
            sayfail "PAM mkhomedir is not active in /etc/pam.d/common-session."
            return 1
        fi
        sayok "${manager^^} domain login prepared. Log out to use the greeter; no running desktop was interrupted."
    }

    # fn: _computer_validate_rdp_source
        # . Purpose
        #   Validate an explicit RFC1918 IPv4 subnet before creating an RDP firewall rule.
        # . Arguments
        #   $1 - Source subnet in IPv4/CIDR notation.
        # . Returns
        #   0 for a private subnet with prefix 8-32; 1 otherwise.
        # . Usage
        #   ```bash
        #   _computer_validate_rdp_source "192.168.1.0/24"
        #   ```
    _computer_validate_rdp_source() {
        local subnet="${1:-}"
        local address=""
        local prefix=""
        local a=0 b=0 c=0 d=0
        local octet=""
        [[ "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]] || return 1
        address="${subnet%/*}"
        prefix="${subnet##*/}"
        IFS=. read -r a b c d <<< "$address"
        for octet in "$a" "$b" "$c" "$d"; do
            [[ "$octet" != 0?* ]] || return 1
        done
        (( 10#$a <= 255 && 10#$b <= 255 && 10#$c <= 255 && 10#$d <= 255 )) || return 1
        a=$((10#$a)); b=$((10#$b)); c=$((10#$c)); d=$((10#$d)); prefix=$((10#$prefix))
        (( prefix >= 8 && prefix <= 32 )) || return 1
        if (( a == 10 && prefix >= 8 )); then return 0; fi
        if (( a == 172 && b >= 16 && b <= 31 && prefix >= 12 )); then return 0; fi
        if (( a == 192 && b == 168 && prefix >= 16 )); then return 0; fi
        return 1
    }

    # fn: _computer_rdp_set_session
        # . Purpose
        #   Select the managed Cinnamon session without overwriting xrdp's startwm.sh.
        # . Description
        #   Changes only DefaultWindowManager in the [Globals] section of sesman.ini;
        #   preserves an original backup and all other keys and sections.
        # . Returns
        #   0 on success; nonzero if xrdp configuration cannot be updated.
        # . Usage
        #   ```bash
        #   _computer_rdp_set_session
        #   ```
    _computer_rdp_set_session() {
        local file="/etc/xrdp/sesman.ini"
        local temp_file=""
        [[ -f "$file" ]] || { sayfail "Missing xrdp session manager configuration: $file"; return 1; }
        [[ -x "$SGND_COMPUTER_XRDP_LAUNCHER" ]] || {
            sayfail "Missing Cinnamon session launcher: $SGND_COMPUTER_XRDP_LAUNCHER"
            return 1
        }
        temp_file="$(mktemp "${TMPDIR:-/tmp}/sgnd-sesman.XXXXXX")" || return 1
        if ! awk -v launcher="$SGND_COMPUTER_XRDP_LAUNCHER" '
            function finalize_section() {
                if (in_globals && !written) { print "DefaultWindowManager=" launcher; written=1 }
            }
            /^\[[^]]+\][[:space:]]*$/ {
                finalize_section()
                in_globals = ($0 == "[Globals]")
                if (in_globals) seen = 1
                print
                next
            }
            in_globals && /^[[:space:]]*DefaultWindowManager[[:space:]]*=/ {
                if (!written) { print "DefaultWindowManager=" launcher; written=1 }
                next
            }
            { print }
            END { finalize_section(); if (!seen) exit 2 }
        ' "$file" > "$temp_file"; then
            rm -f -- "$temp_file"
            sayfail "Could not update xrdp session configuration."
            return 1
        fi
        sudo cp -n -- "$file" "${file}.sgnd-original" || { rm -f -- "$temp_file"; return 1; }
        sudo install -m 0644 -o root -g root "$temp_file" "$file" || { rm -f -- "$temp_file"; return 1; }
        rm -f -- "$temp_file"
    }

    # fn: _computer_sssd_map_xrdp
        # . Purpose
        #   Register xrdp-sesman as an AD remote-interactive PAM service.
        # . Description
        #   Updates only SSSD domain sections with access_provider = ad. Preserves
        #   unrelated settings and permissions, validates and rolls back on error.
        #   Never disables GPO enforcement or changes domain group membership.
        # . Returns
        #   0 on success or when no AD provider is configured; nonzero on failure.
        # . Usage
        #   ```bash
        #   _computer_sssd_map_xrdp
        #   ```
    _computer_sssd_map_xrdp() {
        local file="/etc/sssd/sssd.conf"
        local backup=""
        local edit_status=""

        sudo test -f "$file" || return 0
        command -v python3 >/dev/null 2>&1 || { sayfail "python3 is required for safe SSSD configuration editing."; return 1; }
        command -v sssctl >/dev/null 2>&1 || { sayfail "sssctl is required to validate SSSD configuration."; return 1; }
        backup="$(sudo mktemp /etc/sssd/sssd.conf.sgnd-backup.XXXXXX)" || return 1
        sudo cp -p -- "$file" "$backup" || { sudo rm -f -- "$backup"; return 1; }

        # The edit runs entirely as root; SSSD credentials never pass through a
        # world-readable temporary file or the calling user's shell variables.
        if ! edit_status="$(sudo python3 - "$file" <<'PYSSSD'
import os
import re
import stat
import sys
import tempfile

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as stream:
    original = stream.read()
lines = original.splitlines(keepends=True)
starts = [index for index, line in enumerate(lines)
          if re.match(r'^\s*\[[^]]+\]\s*(?:[#;].*)?$', line)]
starts.append(len(lines))
changed = False
for block in range(len(starts) - 2, -1, -1):
    start, end = starts[block], starts[block + 1]
    header = lines[start].strip()
    if not re.match(r'^\[domain/[^]]+\]$', header, re.I):
        continue
    content = lines[start + 1:end]
    if not any(re.match(r'^\s*access_provider\s*=\s*ad\s*(?:[#;].*)?$', line, re.I) for line in content):
        continue
    mapping_index = next((index for index, line in enumerate(content)
                          if re.match(r'^\s*ad_gpo_map_remote_interactive\s*=', line, re.I)), None)
    if content and not content[-1].endswith("\n"):
        content[-1] += "\n"
    if mapping_index is not None:
        line = content[mapping_index]
        current = line.split('=', 1)[1].split('#', 1)[0].split(';', 1)[0]
        parts = [part.strip() for part in current.split(',')]
        if any(part.lstrip('+') == 'xrdp-sesman' for part in parts):
            if '-xrdp-sesman' in parts:
                raise SystemExit('SSSD explicitly removes xrdp-sesman; refusing to override the policy')
            continue
        # Retain an optional inline comment after the setting value.
        match = re.match(r'^(.*?)(\s+[#;].*)?\n?$', line)
        setting = match.group(1).rstrip()
        comment = match.group(2) or ''
        content[mapping_index] = setting + ', +xrdp-sesman' + comment + '\n' 
    else:
        content.append('ad_gpo_map_remote_interactive = +xrdp-sesman\n')
    lines[start + 1:end] = content
    changed = True
if changed:
    metadata = os.stat(path)
    fd, temporary = tempfile.mkstemp(prefix='.sssd.conf.sgnd-', dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.writelines(lines)
        os.chown(temporary, metadata.st_uid, metadata.st_gid)
        os.chmod(temporary, stat.S_IMODE(metadata.st_mode))
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
print('updated' if changed else 'unchanged')
PYSSSD
)"; then
            sudo cp -p -- "$backup" "$file"
            sudo rm -f -- "$backup"
            sayfail "SSSD authorization mapping could not be updated."
            return 1
        fi
        if ! sudo sssctl config-check; then
            sudo cp -p -- "$backup" "$file"
            sudo rm -f -- "$backup"
            sayfail "SSSD configuration validation failed; the original file was restored."
            return 1
        fi
        if [[ "$edit_status" == "updated" ]] && systemctl is-active --quiet sssd.service 2>/dev/null; then
            if ! sudo systemctl restart sssd.service; then
                sudo cp -p -- "$backup" "$file"
                sudo systemctl restart sssd.service >/dev/null 2>&1 || true
                sudo rm -f -- "$backup"
                sayfail "SSSD restart failed; restored the previous configuration."
                return 1
            fi
        fi
        sudo rm -f -- "$backup"
        sayok "SSSD remote-interactive authorization checked for xrdp-sesman."
    }

    # fn: _computer_gnome_rdp
        # . Purpose
        #   Configure GNOME's system Remote Login rather than an Xorg session.
        # . Description
        #   Creates a service-owned TLS certificate if absent; GNOME's own
        #   interactive grdctl prompt collects RDP gateway credentials. Users
        #   subsequently authenticate again at the GDM greeter (local or AD).
        # . Arguments
        #   - $1: yes to enable or no to disable.
        # . Returns
        #   0 on success; nonzero on configuration failure.
        # . Usage
        #   ```bash
        #   _computer_gnome_rdp yes
        #   ```
    _computer_gnome_rdp() {
        local requested="${1:?missing state}"
        local certificate_dir=""
        local certificate=""
        local private_key=""
        local user_group=""
        local home_dir=""

        if [[ "$requested" == "no" ]]; then
            if command -v grdctl >/dev/null 2>&1; then
                sudo grdctl --system rdp disable || return $?
            fi
            if systemctl cat gnome-remote-desktop.service >/dev/null 2>&1; then
                sudo systemctl disable --now gnome-remote-desktop.service || return $?
            fi
            return 0
        fi

        if systemctl is-active --quiet xrdp.service 2>/dev/null; then
            sayfail "xrdp is already active on this machine. Disable it before enabling GNOME Remote Login."
            return 1
        fi
        if ! command -v grdctl >/dev/null 2>&1; then
            command -v apt-get >/dev/null 2>&1 || { sayfail "Install gnome-remote-desktop using your package manager."; return 1; }
            sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-remote-desktop || return $?
        fi
        command -v grdctl >/dev/null 2>&1 || { sayfail "grdctl is not available."; return 1; }
        command -v openssl >/dev/null 2>&1 || { sayfail "openssl is required to provision a TLS certificate."; return 1; }
        getent passwd gnome-remote-desktop >/dev/null 2>&1 || {
            sayfail "The gnome-remote-desktop system service account is missing."
            return 1
        }
        home_dir="$(getent passwd gnome-remote-desktop | cut -d: -f6)"
        user_group="$(id -gn gnome-remote-desktop)" || return $?
        [[ -n "$home_dir" && "$home_dir" == /* && "$home_dir" != "/" ]] || {
            sayfail "Invalid GNOME Remote Desktop service home directory."
            return 1
        }
        certificate_dir="$home_dir/.local/share/gnome-remote-desktop"
        private_key="$certificate_dir/tls.key"
        certificate="$certificate_dir/tls.crt"
        sudo install -d -m 0700 -o gnome-remote-desktop -g "$user_group" "$certificate_dir" || return $?
        if ! sudo test -s "$certificate" || ! sudo test -s "$private_key"; then
            sayinfo "Creating a self-signed TLS certificate for GNOME Remote Login."
            sudo -u gnome-remote-desktop openssl req -new -newkey rsa:3072 -nodes -x509 \
                -days 825 -subj "/CN=$(hostname -f)" -keyout "$private_key" \
                -out "$certificate" >/dev/null 2>&1 || { sayfail "TLS certificate generation failed."; return 1; }
        fi
        sudo chown "gnome-remote-desktop:$user_group" "$private_key" "$certificate" || return $?
        sudo chmod 0600 "$private_key" || return $?
        sudo grdctl --system rdp set-tls-key "$private_key" || return $?
        sudo grdctl --system rdp set-tls-cert "$certificate" || return $?
        sayinfo "Set the GNOME Remote Login gateway username and password when prompted."
        sayinfo "These are separate from the local or AD credentials entered later at GDM."
        sudo grdctl --system rdp set-credentials || return $?
        sudo grdctl --system rdp enable || return $?
        sudo systemctl enable --now gnome-remote-desktop.service || return $?
        sudo grdctl --system status || return $?
        sayok "GNOME Remote Login enabled. Connect with mstsc, then log in at GDM."
    }

    # fn: _computer_plasma_rdp
        # . Purpose
        #   Prepare KRDP for an existing Plasma session without claiming remote login.
        # . Description
        #   KRDP is a per-user remote desktop service and requires an active
        #   Plasma session. Users finish authentication/permissions in KDE
        #   System Settings; SDDM does not provide GNOME-style remote login.
        # . Arguments
        #   - $1: yes to prepare; no to display disable instructions.
        # . Returns
        #   0 on success; nonzero on installation failure.
        # . Usage
        #   ```bash
        #   _computer_plasma_rdp yes
        #   ```
    _computer_plasma_rdp() {
        local requested="${1:?missing state}"
        if [[ "$requested" == "no" ]]; then
            sayinfo "Disable KDE Remote Desktop in Plasma System Settings > Security & Privacy > Remote Desktop."
            sayinfo "KRDP is per-user; the current user's service is not changed from this administrator session."
            return 0
        fi
        if ! command -v krdpserver >/dev/null 2>&1; then
            command -v apt-get >/dev/null 2>&1 || { sayfail "Install the krdp package with your package manager."; return 1; }
            sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y krdp || return $?
        fi
        command -v krdpserver >/dev/null 2>&1 || { sayfail "KRDP was not installed successfully."; return 1; }
        sayinfo "Open Plasma System Settings > Security & Privacy > Remote Desktop."
        sayinfo "Enable the RDP server, configure its credentials and enable start at login."
        saywarning "KRDP shares a Plasma user session; it cannot log in at SDDM before a user session exists."
        sayinfo "For Windows mstsc, set the RDP credentials in the client before connecting."
        sayok "KRDP is installed; finish the per-user configuration in Plasma System Settings."
    }

    # fn: _computer_configure_rdp
        # . Purpose
        #   Configure the desktop-native RDP implementation and an optional scoped UFW rule.
        # . Description
        #   Cinnamon uses xrdp/Xorg, GNOME uses GDM system Remote Login, and
        #   KDE Plasma uses per-user KRDP (configuration completed in its GUI).
        #   No local graphical session or unrelated firewall rule is removed.
        # . Returns
        #   0 if configured or cancelled; nonzero on failure.
        # . Usage
        #   ```bash
        #   _computer_configure_rdp
        #   ```
    _computer_configure_rdp() {
        local enabled="No"
        local requested="No"
        local confirm="No"
        local firewall_active=0
        local cidr=""
        local managed_cidr=""
        local rule_exists=0
        local temp_file=""
        local backend=""
        local title=""
        local session=""

        backend="$(_computer_desktop_backend)"
        case "$backend" in
            cinnamon)
                title="Cinnamon Remote Desktop (RDP)"
                session="Cinnamon / Xorg (independent session)"
                systemctl is-enabled --quiet xrdp.service 2>/dev/null && enabled="Yes"
                ;;
            gnome)
                title="GNOME Remote Login (RDP)"
                session="GDM / Wayland (independent login)"
                if command -v grdctl >/dev/null 2>&1 && sudo grdctl --system status 2>/dev/null | awk '
                           /^RDP:/{rdp=1; next}
                           rdp && /^[^[:space:]]/{rdp=0}
                           rdp && $1=="Status:" && $2=="enabled"{found=1}
                           END{exit !found}'; then
                    enabled="Yes"
                fi
                ;;
            plasma)
                title="KDE Plasma Remote Desktop (RDP)"
                session="KRDP / Wayland (existing user session)"
                enabled="Configured in Plasma"
                ;;
            *)
                saywarning "RDP is not supported for this display manager and desktop combination."
                return 2
                ;;
        esac
        requested="$enabled"
        [[ "$backend" == "plasma" ]] && requested="No"
        if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
            firewall_active=1
        fi
        if [[ -r "$SGND_COMPUTER_RDP_UFW_STATE" ]]; then
            managed_cidr="$(cat "$SGND_COMPUTER_RDP_UFW_STATE" 2>/dev/null || true)"
        fi

        sgnd_print
        sgnd_print_sectionheader "$title"
        sgnd_print_labeledvalue --label "Session" --value "$session" --labelwidth 26
        sgnd_print_labeledvalue --label "RDP service" --value "$enabled" --labelwidth 26
        sgnd_print_labeledvalue --label "Firewall" --value "$( (( firewall_active == 1 )) && printf 'UFW active' || printf 'UFW not active' )" --labelwidth 26
        if [[ "$backend" == "cinnamon" ]]; then
            sgnd_print "Avoid running local and remote Cinnamon sessions simultaneously as the same user."
        elif [[ "$backend" == "plasma" ]]; then
            sayinfo "This prepares KRDP; finish enabling it from the logged-in Plasma session."
        fi
        sgnd_print
        if [[ "$backend" == "plasma" ]]; then
            ask_decision --label "Prepare KDE RDP" --choices "Yes|Y,No|N,Quit|Q" \
                --default "No" --var requested || return $?
        else
            ask_decision --label "Enable RDP" --choices "Yes|Y,No|N,Quit|Q" \
                --default "$requested" --var requested || return $?
        fi
        [[ "${requested^^}" != "QUIT" ]] || return 0
        # A No for KRDP means no changes. Disabling is done per user in KDE.
        if [[ "$backend" == "plasma" && "${requested^^}" == "NO" ]]; then
            _computer_plasma_rdp no
            return 0
        fi

        if [[ "${requested^^}" == "YES" ]]; then
            if (( firewall_active == 1 )); then
                cidr="$managed_cidr"
                ask --label "Trusted LAN source (IPv4/CIDR)" --var cidr --default "$cidr" --back || return 0
                if ! _computer_validate_rdp_source "$cidr"; then
                    sayfail "Enter a private LAN IPv4/CIDR, e.g. 192.168.1.0/24 (not Anywhere)."
                    return 1
                fi
                if sudo ufw status 2>/dev/null | grep -Eq '^3389(/tcp)?[[:space:]]+ALLOW([[:space:]]+IN)?[[:space:]]+Anywhere([[:space:]]|$)'; then
                    sayfail "UFW already permits RDP from Anywhere. Remove that unrestricted rule first."
                    return 1
                fi
            else
                saywarning "No active UFW firewall. RDP may be reachable from other networks."
                sayinfo "No firewall will be enabled automatically, to avoid interrupting SSH."
            fi
        fi

        sgnd_print_labeledvalue --label "Action" --value "$( [[ "${requested^^}" == YES ]] && printf 'Prepare/enable RDP' || printf 'Disable RDP' )" --labelwidth 26
        if (( firewall_active == 1 )) && [[ "${requested^^}" == YES ]]; then
            sgnd_print_labeledvalue --label "Allow from" --value "$cidr" --labelwidth 26
        fi
        ask_decision --label "Apply RDP configuration" \
            --choices "Yes|Y,No|N,Quit|Q" --default "No" --var confirm || return $?
        [[ "${confirm^^}" == "YES" ]] || { saycancel "RDP configuration not changed."; return 0; }

        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would ${requested,,} ${backend} RDP and manage the scoped firewall rule if applicable."
            return 0
        fi

        if [[ "${requested^^}" == "NO" ]]; then
            case "$backend" in
                cinnamon)
                    if systemctl cat xrdp.service >/dev/null 2>&1; then
                        sudo systemctl disable --now xrdp.service || return $?
                    fi
                    ;;
                gnome) _computer_gnome_rdp no || return $? ;;
            esac
            if [[ -n "$managed_cidr" ]] && _computer_validate_rdp_source "$managed_cidr" && command -v ufw >/dev/null 2>&1; then
                sudo ufw --force delete allow from "$managed_cidr" to any port 3389 proto tcp || return $?
                sudo rm -f -- "$SGND_COMPUTER_RDP_UFW_STATE" || return $?
            fi
            sayok "RDP disabled. The local desktop and unrelated firewall rules were preserved."
            return 0
        fi

        case "$backend" in
            cinnamon)
                if ! command -v apt-get >/dev/null 2>&1; then
                    sayfail "apt-get is unavailable. Install xrdp and xorgxrdp manually."
                    return 1
                fi
                if ! dpkg-query -W -f='${Status}' xrdp 2>/dev/null | grep -q 'install ok installed' ||
                   ! dpkg-query -W -f='${Status}' xorgxrdp 2>/dev/null | grep -q 'install ok installed'; then
                    sayinfo "Installing xrdp and xorgxrdp."
                    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y xrdp xorgxrdp || return $?
                fi
                [[ -f /etc/xrdp/xrdp.ini ]] && grep -q '^\[Xorg\]' /etc/xrdp/xrdp.ini || {
                    sayfail "xrdp Xorg session definition is missing."
                    return 1
                }
                _computer_rdp_set_session || return $?
                _computer_sssd_map_xrdp || return $?
                # xrdp may need access to its packaged TLS private key.
                if id xrdp >/dev/null 2>&1 && getent group ssl-cert >/dev/null 2>&1 &&
                   [[ "$(readlink -f /etc/xrdp/key.pem 2>/dev/null || true)" == /etc/ssl/private/* ]] &&
                   ! id -nG xrdp | grep -qw ssl-cert; then
                    sudo usermod -aG ssl-cert xrdp || return $?
                fi
                ;;
            gnome) _computer_gnome_rdp yes || return $? ;;
            plasma) _computer_plasma_rdp yes || return $? ;;
        esac

        if (( firewall_active == 1 )); then
            if ! sudo ufw status 2>/dev/null | awk -v cidr="$cidr" '
                $1 ~ /^3389(\/tcp)?$/ && $2 == "ALLOW" && index($0, cidr) { found=1 }
                END { exit !found }
            '; then
                sudo ufw allow from "$cidr" to any port 3389 proto tcp comment 'SolidGroundUX RDP' || return $?
                rule_exists=0
            else
                rule_exists=1
            fi
            if (( rule_exists == 0 )); then
                sudo install -d -m 0755 /etc/solidgroundux || return $?
                temp_file="$(mktemp "${TMPDIR:-/tmp}/sgnd-rdp-cidr.XXXXXX")" || return 1
                printf '%s\n' "$cidr" > "$temp_file"
                sudo install -m 0644 -o root -g root "$temp_file" "$SGND_COMPUTER_RDP_UFW_STATE" || {
                    rm -f -- "$temp_file"
                    return 1
                }
                rm -f -- "$temp_file"
            fi
            if [[ -n "$managed_cidr" && "$managed_cidr" != "$cidr" ]]; then
                sudo ufw --force delete allow from "$managed_cidr" to any port 3389 proto tcp || return $?
                if (( rule_exists == 1 )); then
                    sudo rm -f -- "$SGND_COMPUTER_RDP_UFW_STATE" || return $?
                fi
            fi
        fi
        if [[ "$backend" == "cinnamon" ]]; then
            sudo systemctl enable --now xrdp.service || return $?
            if systemctl cat xrdp-sesman.service >/dev/null 2>&1; then
                sudo systemctl restart xrdp-sesman.service || return $?
            fi
            sudo systemctl restart xrdp.service || return $?
            systemctl is-active --quiet xrdp.service || { sayfail "xrdp service did not start."; return 1; }
            sayok "Cinnamon RDP enabled. Choose Xorg on the RDP login screen."
        fi
    }

    # fn: _computer_rdp_choose_session
        # . Purpose
        #   Display logind sessions and optionally select one by number.
        # . Description
        #   Include remote, local graphical and SSH sessions: GNOME Remote Login
        #   and XRDP create logind sessions, but logind does not label every
        #   remote desktop session consistently. Service and Remote are shown
        #   rather than guessing. No sessions are modified by this function.
        # . Arguments
        #   - `$1`: `list` to only display, or `select` to prompt for a session.
        #   - `$2`: Output variable name, required when selecting.
        # . Returns
        #   0 on display/selection; 1 on cancellation, no sessions or failure.
        # . Usage
        #   ```bash
        #   _computer_rdp_choose_session list
        #   _computer_rdp_choose_session select selected_session
        #   ```
    _computer_rdp_choose_session() {
        local mode="${1:-list}"
        local result_var="${2:-}"
        local sessions=""
        local sid=""
        local uid=""
        local username=""
        local remainder=""
        local info=""
        local key=""
        local value=""
        local type=""
        local service=""
        local state=""
        local display=""
        local remote=""
        local count=0
        local choice=""
        local -a session_ids=()

        [[ "$mode" == "list" || "$mode" == "select" ]] || return 2
        if [[ "$mode" == "select" && ! "$result_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            return 2
        fi
        command -v loginctl >/dev/null 2>&1 || { sayfail "loginctl is unavailable."; return 1; }
        sessions="$(loginctl list-sessions --no-legend --no-pager 2>/dev/null)" || {
            sayfail "Could not list logind sessions."
            return 1
        }

        sgnd_print
        sgnd_print_sectionheader "Logind sessions"
        sgnd_print --text "Includes RDP, local graphical and SSH sessions; check the service before terminating." --pad 2
        while read -r sid uid username remainder; do
            [[ -n "$sid" && "$uid" =~ ^[0-9]+$ ]] || continue
            info="$(loginctl show-session "$sid" --no-pager -p Type -p Service -p State -p Display -p Remote 2>/dev/null)" || continue
            type=""; service=""; state=""; display=""; remote=""
            while IFS='=' read -r key value; do
                case "$key" in
                    Type) type="$value" ;;
                    Service) service="$value" ;;
                    State) state="$value" ;;
                    Display) display="$value" ;;
                    Remote) remote="$value" ;;
                esac
            done <<< "$info"
            session_ids+=("$sid")
            count=$((count + 1))
            sgnd_print --text "$count. $sid - $username (UID $uid), ${type:-unknown}, ${state:-unknown}" --pad 2
            sgnd_print --text "   Service: ${service:-unknown}; Display: ${display:-none}; Remote: ${remote:-unknown}" --pad 2
        done <<< "$sessions"

        if (( count == 0 )); then
            sayinfo "No active logind sessions were found."
            return 1
        fi
        if [[ "$mode" == "list" ]]; then
            return 0
        fi

        sgnd_print --text "Q. Back" --pad 2
        while :; do
            choice=""
            ask --label "Session number" --var choice || return 1
            [[ "${choice^^}" == "Q" ]] && return 1
            if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && (( choice <= count )); then
                printf -v "$result_var" '%s' "${session_ids[choice-1]}"
                return 0
            fi
            saywarning "Select 1-$count or Q."
        done
    }

    # fn: _computer_rdp_terminate_session
        # . Purpose
        #   Terminate one selected logind session after explicit confirmation.
        # . Description
        #   A session may be remote, local or SSH. A second lookup is made
        #   before termination so a disappeared session is not acted upon.
        # . Returns
        #   0 on success/cancellation; 1 when termination fails.
        # . Usage
        #   ```bash
        #   _computer_rdp_terminate_session
        #   ```
    _computer_rdp_terminate_session() {
        local session_id=""
        local detail=""
        local name=""
        local service=""
        local confirm=""

        _computer_rdp_choose_session select session_id || return 0
        detail="$(loginctl show-session "$session_id" --no-pager -p Name -p Service 2>/dev/null)" || {
            saywarning "Session $session_id has already ended."
            return 0
        }
        name="$(awk -F= '$1=="Name" { print substr($0, 6); exit }' <<< "$detail")"
        service="$(awk -F= '$1=="Service" { print substr($0, 9); exit }' <<< "$detail")"
        sgnd_print_labeledvalue --label "Session" --value "$session_id" --labelwidth 20
        sgnd_print_labeledvalue --label "User" --value "${name:-unknown}" --labelwidth 20
        sgnd_print_labeledvalue --label "Service" --value "${service:-unknown}" --labelwidth 20
        saywarning "This will close the session and may discard unsaved work."
        confirm=""
        ask_decision --label "Terminate this session" --choices "Yes|Y,No|N,Quit|Q" --var confirm || return 0
        [[ "${confirm^^}" == "YES" ]] || { saycancel "Session unchanged."; return 0; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would terminate session $session_id."
            return 0
        fi
        if ! sudo loginctl terminate-session "$session_id"; then
            sayfail "Could not terminate session $session_id."
            return 1
        fi
        sayok "Session $session_id terminated."
    }

    # fn: _computer_rdp_terminate_user
        # . Purpose
        #   Clear all sessions and remaining user processes for a selected user.
        # . Description
        #   This is broader than terminating a single RDP session: it ends
        #   graphical applications, SSH logins and the user's systemd services.
        #   Uses numeric UIDs returned by logind, not manually entered names.
        #   Only proceeds after a separate, explicit confirmation.
        # . Returns
        #   0 on success/cancellation; 1 on failure.
        # . Usage
        #   ```bash
        #   _computer_rdp_terminate_user
        #   ```
    _computer_rdp_terminate_user() {
        local users=""
        local uid=""
        local username=""
        local rest=""
        local count=0
        local choice=""
        local confirm=""
        local target_uid=""
        local target_name=""
        local current_name=""
        local -a uids=()
        local -a names=()

        users="$(loginctl list-users --no-legend --no-pager 2>/dev/null)" || {
            sayfail "Could not list logged-in users."
            return 1
        }
        sgnd_print
        sgnd_print_sectionheader "Users with logind state"
        while read -r uid username rest; do
            [[ "$uid" =~ ^[0-9]+$ && -n "$username" ]] || continue
            uids+=("$uid")
            names+=("$username")
            count=$((count + 1))
            sgnd_print --text "$count. $username (UID $uid)" --pad 2
        done <<< "$users"
        if (( count == 0 )); then
            sayinfo "No users with logind state were found."
            return 0
        fi
        sgnd_print --text "Q. Back" --pad 2
        while :; do
            choice=""
            ask --label "User number" --var choice || return 0
            [[ "${choice^^}" == "Q" ]] && return 0
            if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && (( choice <= count )); then
                target_uid="${uids[choice-1]}"
                target_name="${names[choice-1]}"
                break
            fi
            saywarning "Select 1-$count or Q."
        done

        # Recheck the selected UID and account before a potentially destructive action.
        current_name="$(loginctl show-user "$target_uid" --no-pager -p Name 2>/dev/null)" || {
            saywarning "User $target_name no longer has logind state."
            return 0
        }
        [[ "$current_name" == "Name=$target_name" ]] || {
            saywarning "The selected logind user has changed; nothing was terminated."
            return 0
        }
        if [[ "$target_uid" == "0" ]]; then
            saywarning "Root user sessions cannot be terminated from this menu."
            return 0
        fi
        saywarning "All sessions, SSH logins, applications and user services for $target_name will be terminated."
        if [[ "$target_uid" == "$(id -u)" ]]; then
            saywarning "You selected your own account; this console session will be terminated too."
        fi
        confirm=""
        ask_decision --label "Terminate all sessions and processes for $target_name" \
            --choices "Yes|Y,No|N,Quit|Q" --var confirm || return 0
        [[ "${confirm^^}" == "YES" ]] || { saycancel "User sessions unchanged."; return 0; }
        if (( ${FLAG_DRYRUN:-0} == 1 )); then
            sayinfo "Dry run: Would terminate all sessions and processes for $target_name."
            return 0
        fi
        if ! sudo loginctl terminate-user "$target_uid"; then
            sayfail "Could not terminate user sessions for $target_name."
            return 1
        fi
        sayok "Terminated logind sessions and user processes for $target_name."
    }

    # fn: _computer_manage_rdp_sessions
        # . Purpose
        #   Present an optional interactive menu for inspecting and clearing sessions.
        # . Description
        #   Read-only listing is available without changes. Single-session and
        #   whole-user cleanup are explicit, confirmed actions. Works with
        #   Cinnamon XRDP and GNOME Remote Login because both use logind.
        # . Returns
        #   0 when leaving normally; 1 on failure.
        # . Usage
        #   ```bash
        #   _computer_manage_rdp_sessions
        #   ```
    _computer_manage_rdp_sessions() {
        local choice=""
        command -v loginctl >/dev/null 2>&1 || { sayfail "loginctl is unavailable."; return 1; }
        while :; do
            sgnd_print
            sgnd_print_sectionheader "Manage Remote Desktop Sessions"
            sgnd_print --text "1. List active sessions" --pad 2
            sgnd_print --text "2. Terminate one session" --pad 2
            sgnd_print --text "3. Terminate all sessions and processes for a user" --pad 2
            sgnd_print --text "Q. Back" --pad 2
            sgnd_print
            choice=""
            ask --label "Selection" --var choice || return 0
            case "${choice^^}" in
                1) _computer_rdp_choose_session list || true ;;
                2) _computer_rdp_terminate_session || return $? ;;
                3) _computer_rdp_terminate_user || return $? ;;
                Q) return 0 ;;
                *) saywarning "Select 1-3 or Q." ;;
            esac
        done
    }

    # fn: _computer_status
        # . Purpose
        #   Display the current Computer Setup state without changing the machine.
        #
        # . Returns
        #   - 0 after displaying available status information.
        # . Usage
        #   ```bash
        #   _computer_status "<dns_servers>" "<dns_servers>"
        #   ```
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
        local rdp_enabled="not installed"
        local rdp_active="not installed"

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
        local backend=""
        local desktop_manager=""
        local desktop_login="Not configured"
        backend="$(_computer_desktop_backend)"
        desktop_manager="$(_computer_display_manager)"
        if [[ "$backend" != "unsupported" ]]; then
            sgnd_print_labeledvalue --label "Desktop backend" --value "$backend / $desktop_manager" --labelwidth 24
            case "$desktop_manager" in
                lightdm)
                    if [[ -s "$SGND_COMPUTER_LIGHTDM_FILE" ]] && grep -q '^greeter-show-manual-login=true' "$SGND_COMPUTER_LIGHTDM_FILE"; then
                        desktop_login="Configured"
                    fi
                    ;;
                gdm3)
                    desktop_login="Built into GDM greeter"
                    ;;
                sddm)
                    desktop_login="Built into SDDM greeter"
                    ;;
            esac
            sgnd_print_labeledvalue --label "Manual AD login" --value "$desktop_login" --labelwidth 24
            sgnd_print_labeledvalue --label "PAM home creation" --value "$( grep -q 'pam_mkhomedir.so' /etc/pam.d/common-session 2>/dev/null && printf 'Enabled' || printf 'Disabled' )" --labelwidth 24
            case "$backend" in
                cinnamon)
                    if systemctl cat xrdp.service >/dev/null 2>&1; then
                        rdp_enabled="$(systemctl is-enabled xrdp.service 2>/dev/null || true)"
                        rdp_active="$(systemctl is-active xrdp.service 2>/dev/null || true)"
                    fi
                    ;;
                gnome)
                    if command -v grdctl >/dev/null 2>&1; then
                        rdp_enabled="$(sudo grdctl --system status 2>/dev/null | awk '/^RDP:/{section=1; next} section && /^[^[:space:]]/{section=0} section && /Status:/{print $2; exit}')"
                        [[ -n "$rdp_enabled" ]] || rdp_enabled="Not configured"
                    fi
                    if systemctl cat gnome-remote-desktop.service >/dev/null 2>&1; then
                        rdp_active="$(systemctl is-active gnome-remote-desktop.service 2>/dev/null || true)"
                    fi
                    ;;
                plasma)
                    rdp_enabled="Per-user KRDP"
                    rdp_active="Check from Plasma session"
                    ;;
            esac
            sgnd_print_labeledvalue --label "RDP enabled" --value "${rdp_enabled:-unknown}" --labelwidth 24
            sgnd_print_labeledvalue --label "RDP active" --value "${rdp_active:-unknown}" --labelwidth 24
        fi
        return 0
    }

    # fn: _computer_validate
        # . Purpose
        #   Validate the principal Computer Setup outcomes without changing the machine.
        #
        # . Returns
        #   - 0 when all required checks pass; 1 otherwise.
        # . Usage
        #   ```bash
        #   _computer_validate
        #   ```
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

        # Desktop configuration is optional; check system-managed RDP only.
        # KRDP is intentionally per-user and cannot be verified from this shell.
        case "$(_computer_desktop_backend)" in
            cinnamon)
                if systemctl is-enabled --quiet xrdp.service 2>/dev/null; then
                    if systemctl is-active --quiet xrdp.service && [[ -x "$SGND_COMPUTER_XRDP_LAUNCHER" ]]; then
                        sgnd_print_labeledvalue --label "Cinnamon RDP" --value "Passed"
                    else
                        sgnd_print_labeledvalue --label "Cinnamon RDP" --value "Failed"
                        failures=$((failures + 1))
                    fi
                fi
                ;;
            gnome)
                if systemctl is-enabled --quiet gnome-remote-desktop.service 2>/dev/null; then
                    if systemctl is-active --quiet gnome-remote-desktop.service &&
                       command -v grdctl >/dev/null 2>&1 &&
                       sudo grdctl --system status 2>/dev/null | awk '
                           /^RDP:/{rdp=1; next}
                           rdp && /^[^[:space:]]/{rdp=0}
                           rdp && $1=="Status:" && $2=="enabled"{found=1}
                           END{exit !found}'; then
                        sgnd_print_labeledvalue --label "GNOME RDP" --value "Passed"
                    else
                        sgnd_print_labeledvalue --label "GNOME RDP" --value "Failed"
                        failures=$((failures + 1))
                    fi
                fi
                ;;
        esac
        sgnd_print
        if (( failures == 0 )); then
            sayok "Computer setup validation passed."
            return 0
        fi

        sayfail "$failures computer setup validation check(s) failed."
        return 1
    }


# - Dispatch ------------------------------------------------------------------------
# fn: _run_action - Dispatch the requested management action to its implementation.
    # . Purpose
    #   Dispatch the requested management action to its implementation.
    #
    # . Arguments
    #   - `$1`: Management action to execute.
    # . Usage
    #   ```bash
    #   _run_action "status"
    #   ```
_run_action() {
    local action="${1:?missing action}"
    case "$action" in
        ssh-host-keys) _computer_generate_ssh_keys ;;
        ssh-service) _computer_configure_ssh_service ;;
        sudoers) _computer_configure_sudoers ;;
        desktop-login) _computer_configure_desktop_login ;;
        rdp) _computer_configure_rdp ;;
        rdp-sessions) _computer_manage_rdp_sessions ;;
        status) _computer_status ;;
        validate) _computer_validate ;;
        *) sayfail "Unknown Computer Setup action: $action"; return 2 ;;
    esac
}

# fn: main - Dispatch command-line options to the appropriate management workflow.
    # . Purpose
    #   Dispatch command-line options to the appropriate management workflow.
    #
    # . Usage
    #   ```bash
    #   main "$@"
    #   ```
main() {
    _framework_locator || return $?
    sgnd_exe_start -- "$@" || return $?
    _run_action "${ACTION:-}"
}
main "$@"
