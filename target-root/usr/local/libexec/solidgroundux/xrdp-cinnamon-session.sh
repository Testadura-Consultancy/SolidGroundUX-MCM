#!/bin/sh
# ==================================================================================
# SolidGroundUX Management Console Modules - Cinnamon RDP session launcher
# ----------------------------------------------------------------------------------
# Metadata:
#   Source      : xrdp-cinnamon-session.sh
#   Type        : script
#   Group       : Modules
#   Subgroup    : Computer Setup
#   Purpose     : Start a Cinnamon X11 session for xrdp-sesman
# Description:
#   Invoked by xrdp-sesman's DefaultWindowManager. Runs in the logging-in user's
#   session and intentionally does not initialize the management-console framework.
#   The original distribution-owned /etc/xrdp/startwm.sh is left intact.
# Usage:
#   The script is invoked automatically by xrdp-sesman, not by the console user.
#   ```sh
#   /usr/local/libexec/solidgroundux/xrdp-cinnamon-session.sh
#   ```
# ==================================================================================
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi
export XDG_CURRENT_DESKTOP=X-Cinnamon
export XDG_SESSION_DESKTOP=cinnamon
export DESKTOP_SESSION=cinnamon
export XDG_SESSION_TYPE=x11
# Temporary diagnostic logging. Remove after the domain login failure is resolved.
# Preserve the release's desktop selection and Xsession invocation.
umask 077
LOGFILE="${HOME}/xrdp-cinnamon-debug.log"
if ! (: >> "$LOGFILE") 2>/dev/null; then
    # If logging cannot be enabled, preserve the original session behavior.
    if [ -x /usr/bin/cinnamon-session-cinnamon ]; then
        exec /etc/X11/Xsession /usr/bin/cinnamon-session-cinnamon
    fi
    exec /etc/X11/Xsession /usr/bin/cinnamon-session
fi

exec >> "$LOGFILE" 2>&1
printf '\n=== XRDP Cinnamon start: %s ===\n' "$(date -Is)"
id
printf 'HOME=%s\nDISPLAY=%s\nXDG_RUNTIME_DIR=%s\nXDG_SESSION_TYPE=%s\nDBUS_SESSION_BUS_ADDRESS=%s\n' \
    "$HOME" "${DISPLAY:-}" "${XDG_RUNTIME_DIR:-}" "${XDG_SESSION_TYPE:-}" "${DBUS_SESSION_BUS_ADDRESS:-}"
if [ -x /usr/bin/cinnamon-session-cinnamon ]; then
    printf '%s\n' 'Launching /usr/bin/cinnamon-session-cinnamon through Xsession'
    /etc/X11/Xsession /usr/bin/cinnamon-session-cinnamon
else
    printf '%s\n' 'Launching fallback /usr/bin/cinnamon-session through Xsession'
    /etc/X11/Xsession /usr/bin/cinnamon-session
fi
result=$?
printf '=== XRDP Cinnamon exit: %s, status=%s ===\n' "$(date -Is)" "$result"
exit "$result"
