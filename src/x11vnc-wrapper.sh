#!/bin/bash

X11VNC_BIN="/usr/bin/x11vnc"
LISTEN_OPTION="-localhost"
RFBPORT="5900"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

cleanup_stale_x11vnc() {
    pkill -f "x11vnc.*$RFBPORT" 2>/dev/null || true
    sleep 1
}

find_x_display() {
    # Find the lowest X display number socket
    local sock
    sock=$(find /tmp/.X11-unix/ -name "X*" -type s 2>/dev/null | sort | head -n1)
    [[ -z "$sock" ]] && return 1
    displaynum="${sock##*/X}"
    echo ":$displaynum"
    return 0
}

find_x_auth_from_process() {
    local display="$1"
    
    # Find any X server process and extract its -auth parameter
    local x_pids
    x_pids=$(pgrep -f "X.*vt|Xorg.*vt|X .*-auth|Xorg .*-auth" 2>/dev/null)
    
    for pid in $x_pids; do
        if [[ -n "$pid" && -r "/proc/$pid/cmdline" ]]; then
            local cmdline
            cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
            log_message "Found X process $pid: $cmdline"
            
            # Extract -auth parameter
            local auth_file
            auth_file=$(echo "$cmdline" | grep -oP '(?<=-auth )\S+')
            if [[ -n "$auth_file" && -f "$auth_file" ]]; then
                log_message "Testing auth file from X process: $auth_file"
                # Test if this auth file works with our display
                if XAUTHORITY="$auth_file" DISPLAY="$display" timeout 5 xauth list >/dev/null 2>&1; then
                    log_message "✅ Found working auth file from X process: $auth_file"
                    echo "$auth_file"
                    return 0
                else
                    log_message "❌ Auth file $auth_file failed xauth test"
                fi
            fi
        fi
    done
    
    return 1
}

find_gdm_auth() {
    # Find Xorg owned by gdm, match vt/tty or default :0
    local xorg_pid
    xorg_pid=$(pgrep -u gdm Xorg | head -n1)
    if [[ -n "$xorg_pid" ]]; then
        local args
        args=$(tr '\0' ' ' < "/proc/$xorg_pid/cmdline" 2>/dev/null)
        # Grab -auth parameter
        local auth_file
        auth_file=$(echo "$args" | grep -oP '(?<=-auth )\S+')
        if [[ -n "$auth_file" && -f "$auth_file" ]]; then
            echo "$auth_file"
            return 0
        fi
    fi
    return 1
}

get_active_sessions() {
    # Handle different loginctl versions
    if command -v loginctl >/dev/null 2>&1; then
        # Try with --no-header first, fall back without it
        local sessions
        sessions=$(loginctl list-sessions --no-header 2>/dev/null || loginctl list-sessions | tail -n +2)
        echo "$sessions" | awk '{print $1}' | grep -v "^$"
    fi
}

find_logged_in_user_info() {
    local display="$1"
    
    # Method 1: Use loginctl to find active X sessions
    if command -v loginctl >/dev/null 2>&1; then
        local sessions
        sessions=$(get_active_sessions)
        for session in $sessions; do
            local session_info
            session_info=$(loginctl show-session "$session" 2>/dev/null) || continue
            if echo "$session_info" | grep -q "Type=x11" && echo "$session_info" | grep -q "State=active"; then
                local username
                username=$(echo "$session_info" | grep "^Name=" | cut -d= -f2)
                local uid
                uid=$(echo "$session_info" | grep "^User=" | cut -d= -f2)
                
                # Try multiple auth file locations for this user
                local auth_candidates=(
                    "/run/user/$uid/gdm/Xauthority"
                    "/run/user/$uid/Xauthority"
                    "/home/$username/.Xauthority"
                )
                
                for auth_file in "${auth_candidates[@]}"; do
                    if [[ -f "$auth_file" ]]; then
                        # Test if this auth file works with our display
                        if XAUTHORITY="$auth_file" DISPLAY="$display" timeout 5 xauth list >/dev/null 2>&1; then
                            log_message "Found working auth file for user $username (uid: $uid): $auth_file"
                            echo "$username:$uid:$auth_file"
                            return 0
                        fi
                    fi
                done
            fi
        done
    fi
    
    # Method 2: Find users with X processes and try their auth files
    local x_processes
    x_processes=$(pgrep -a -f 'Xorg|gdm-x-session|gnome-session|kde|xfce' | grep -v root | grep -v gdm | grep -v sddm)
    if [[ -n "$x_processes" ]]; then
        local users
        users=$(echo "$x_processes" | awk '{print $2}' | sort -u)
        for user in $users; do
            local uid
            uid=$(id -u "$user" 2>/dev/null) || continue
            local auth_candidates=(
                "/run/user/$uid/gdm/Xauthority"
                "/run/user/$uid/Xauthority"
                "/home/$user/.Xauthority"
            )
            
            for auth_file in "${auth_candidates[@]}"; do
                if [[ -f "$auth_file" ]]; then
                    # Test if this auth file works with our display
                    if XAUTHORITY="$auth_file" DISPLAY="$display" timeout 5 xauth list >/dev/null 2>&1; then
                        log_message "Found working auth file for user $user (uid: $uid): $auth_file"
                        echo "$user:$uid:$auth_file"
                        return 0
                    fi
                fi
            done
        done
    fi
    
    return 1
}

while true; do
    log_message "=== x11vnc service starting ==="
    cleanup_stale_x11vnc

    # Wait up to 30s for a display socket
    for _ in {1..30}; do
        DISPLAY=$(find_x_display)
        [[ -n "$DISPLAY" ]] && break
        sleep 1
    done

    if [[ -z "$DISPLAY" ]]; then
        log_message "❌ No X server socket found in /tmp/.X11-unix/"
        sleep 10
        continue
    fi

    export DISPLAY
    log_message "Using DISPLAY $DISPLAY"

    # Check if someone is logged in first
    USER_INFO=$(find_logged_in_user_info "$DISPLAY")
    
    if [[ -n "$USER_INFO" ]]; then
        # Someone is logged in - run as that user
        IFS=':' read -r username uid auth_file <<< "$USER_INFO"
        log_message "✅ User $username logged in, running x11vnc as user $username with auth $auth_file"
        
        # Verify the user exists
        if ! id "$username" >/dev/null 2>&1; then
            log_message "❌ User $username not found, falling back to X process auth detection"
        else
            # Run x11vnc as the logged-in user
            exec sudo -u "$username" \
                env DISPLAY="$DISPLAY" XAUTHORITY="$auth_file" \
                $X11VNC_BIN -display "$DISPLAY" -nopw -forever -shared -rfbport $RFBPORT $LISTEN_OPTION
        fi
    fi
    
    # No user logged in, try to get auth from the actual X process
    AUTH_FILE=$(find_x_auth_from_process "$DISPLAY")
    if [[ -n "$AUTH_FILE" ]]; then
        log_message "✅ Using auth file from X process: $AUTH_FILE on DISPLAY $DISPLAY"
        exec $X11VNC_BIN -auth "$AUTH_FILE" -display "$DISPLAY" -nopw -forever -shared -rfbport $RFBPORT $LISTEN_OPTION
    fi
    
    # Fallback to GDM detection
    if pgrep -x gdm >/dev/null 2>&1; then
        AUTH_FILE=$(find_gdm_auth)
        if [[ -n "$AUTH_FILE" ]]; then
            log_message "✅ GDM greeter: using -auth $AUTH_FILE on DISPLAY $DISPLAY"
            exec $X11VNC_BIN -auth "$AUTH_FILE" -display "$DISPLAY" -nopw -forever -shared -rfbport $RFBPORT $LISTEN_OPTION -noshm
        fi
    fi

    # Last resort - try -auth guess
    log_message "⚠️  No valid Xauthority found, trying -auth guess on DISPLAY $DISPLAY"
    $X11VNC_BIN -auth guess -display "$DISPLAY" -nopw -forever -shared -rfbport $RFBPORT $LISTEN_OPTION || {
        log_message "❌ x11vnc failed, restarting in 10 seconds"
        sleep 10
    }

    log_message "🔁 Restarting after crash or logout"
    sleep 2
done