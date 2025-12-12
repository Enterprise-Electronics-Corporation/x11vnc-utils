#!/bin/bash

X0VNCSERVER_BIN="/usr/bin/x0vncserver"
LISTEN_OPTION="-localhost"
RFBPORT="5900"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

send_notification() {
    local title="$1"
    local message="$2"
    
    log_message "Attempting to send notification: $title"
    
    # Get all graphical sessions and their users
    loginctl list-sessions --no-legend | while read session_id uid user seat tty; do
        # Skip if no user or if it's root, system user, or display manager
        [ -z "$user" ] && continue
        [ "$user" = "root" ] && continue
        [ "$user" = "sddm" ] && continue
        [ "$user" = "gdm" ] && continue
        [ "$user" = "lightdm" ] && continue
        [ "$user" = "_sddm" ] && continue
        
        # Skip system users (uid < 1000 typically, but be explicit with display managers)
        if [ "$uid" -lt 1000 ] 2>/dev/null; then
            log_message "Skipping system user session $session_id (user: $user, uid: $uid)"
            continue
        fi
        
        # Check if this is a graphical session (x11 or wayland)
        # Note: Some systems report "unspecified" type for active sessions, so we also check
        # if a runtime directory exists as a sign of an active user session
        session_type=$(loginctl show-session "$session_id" -p Type --value 2>/dev/null || echo "")
        
        # Skip clearly non-graphical types (tty without X, services, etc)
        if [ "$session_type" = "tty" ] && ! pgrep -a -f "Xorg|gdm-x-session|gnome-session|kde|xfce" | grep -q "$user"; then
            log_message "Skipping non-graphical session $session_id (type: $session_type) for user $user"
            continue
        fi
        
        log_message "Found session $session_id for user $user (uid: $uid, type: $session_type)"
        
        # The user's runtime directory
        user_runtime_dir="/run/user/$uid"
        
        # Check if the user's runtime directory exists (sign of active session)
        if [ ! -d "$user_runtime_dir" ]; then
            log_message "Runtime directory $user_runtime_dir does not exist for user $user"
            continue
        fi
        
        # Check if the D-Bus socket exists
        if [ ! -S "$user_runtime_dir/bus" ]; then
            log_message "D-Bus socket not found at $user_runtime_dir/bus for user $user"
            continue
        fi
        
        # Method 1: Use systemd-run --machine to run in the user's session context
        # This is the most reliable method as it properly inherits the user's
        # systemd session including D-Bus and display server access
        log_message "Trying systemd-run --machine method for user $user..."
        if systemd-run --machine="$user@.host" --user --pipe --wait --quiet \
            /usr/bin/notify-send -u critical "$title" "$message" 2>&1; then
            log_message "✅ Successfully sent notification to user $user via systemd-run --machine"
            continue
        else
            log_message "systemd-run --machine method failed for user $user (exit code: $?)"
        fi
        
        # Method 2: Try machinectl shell which also runs in the user's context (skip if not available)
        if command -v machinectl >/dev/null 2>&1; then
            log_message "Trying machinectl shell method for user $user..."
            if machinectl shell --uid="$user" .host /usr/bin/notify-send -u critical "$title" "$message" 2>&1; then
                log_message "✅ Successfully sent notification to user $user via machinectl"
                continue
            else
                log_message "machinectl method failed for user $user"
            fi
        fi
        
        # Method 3: Try su with login shell which may inherit PAM session
        log_message "Trying su -l method for user $user..."
        if su -l "$user" -c "notify-send -u critical '$title' '$message'" 2>&1; then
            log_message "✅ Successfully sent notification to user $user via su -l"
            continue
        else
            log_message "su -l method failed for user $user"
        fi
        
        # Method 4: Fallback - use wall to send message to all terminals
        log_message "All notification methods failed, falling back to wall for user $user"
        echo "$title: $message" | wall 2>/dev/null || true
        
    done
}

cleanup_stale_x0vncserver() {
    pkill -f "x0vncserver.*$RFBPORT" 2>/dev/null || true
    sleep 1
}

run_vnc_with_notifications() {
    local username="$1"
    local display="$2"
    local auth_file="$3"
    
    local logfile="/tmp/x0vncserver_${display}.log"
    local lastline=0
    
    log_message "Starting x0vncserver monitoring for $username on $display"
    
    # Start x0vncserver in background and capture its output
    sudo -u "$username" \
        env DISPLAY="$display" XAUTHORITY="$auth_file" \
        $X0VNCSERVER_BIN -display "$display" -SecurityTypes=None -AlwaysShared -rfbport $RFBPORT $LISTEN_OPTION >"$logfile" 2>&1 &
    
    local vnc_pid=$!
    log_message "x0vncserver started with PID $vnc_pid"
    
    # Monitor the logfile for connection messages
    # x0vncserver logs connection events like: "Got connection from 192.168.1.100"
    while kill -0 $vnc_pid 2>/dev/null; do
        # Check for new log entries indicating connections
        if [[ -f "$logfile" ]]; then
            # Look for connection messages in the log
            local new_lines
            new_lines=$(tail -n +$((lastline + 1)) "$logfile" 2>/dev/null | grep -i "connection\|accepted")
            
            if [[ -n "$new_lines" ]]; then
                # Extract connection info if available
                local conn_info
                conn_info=$(echo "$new_lines" | head -n1)
                log_message "📡 VNC Connection detected: $conn_info"
                
                # Send notification about the connection
                send_notification "VNC Client Connected" "A user has connected to your VNC session"
            fi
            
            # Update lastline count
            lastline=$(wc -l < "$logfile" 2>/dev/null || echo 0)
        fi
        
        sleep 1
    done
    
    # x0vncserver exited, clean up log
    rm -f "$logfile"
    log_message "🔁 x0vncserver exited (PID $vnc_pid), restarting after crash or logout"
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
    log_message "=== x0vncserver service starting ==="
    cleanup_stale_x0vncserver

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
        log_message "✅ User $username logged in, running x0vncserver as user $username with auth $auth_file"
        
        # Verify the user exists
        if ! id "$username" >/dev/null 2>&1; then
            log_message "❌ User $username not found, falling back to X process auth detection"
        else
            # Run x0vncserver as the logged-in user and monitor for connections
            run_vnc_with_notifications "$username" "$DISPLAY" "$auth_file"
        fi
    fi
    
    # No user logged in, try to get auth from the actual X process
    AUTH_FILE=$(find_x_auth_from_process "$DISPLAY")
    if [[ -n "$AUTH_FILE" ]]; then
        log_message "✅ Using auth file from X process: $AUTH_FILE on DISPLAY $DISPLAY"
        # Run x0vncserver and monitor for connections (running as root)
        run_vnc_with_notifications "root" "$DISPLAY" "$AUTH_FILE"
    fi
    
    # Fallback to GDM detection
    if pgrep -x gdm >/dev/null 2>&1; then
        AUTH_FILE=$(find_gdm_auth)
        if [[ -n "$AUTH_FILE" ]]; then
            log_message "✅ GDM greeter: using XAUTHORITY $AUTH_FILE on DISPLAY $DISPLAY"
            log_message "ℹ️  GDM greeter mode - VNC available for login"
            # Run x0vncserver and monitor for connections (running as root for greeter)
            run_vnc_with_notifications "root" "$DISPLAY" "$AUTH_FILE"
        fi
    fi

    # Last resort - x0vncserver requires XAUTHORITY to be set; if we can't find it, we'll try without explicit auth
    log_message "⚠️  No valid Xauthority found, attempting x0vncserver with DISPLAY=$DISPLAY only"
    # Create a temporary empty auth file for this attempt
    local temp_auth=$(mktemp)
    trap "rm -f $temp_auth" EXIT
    run_vnc_with_notifications "root" "$DISPLAY" "$temp_auth"

    log_message "🔁 Restarting after crash or logout"
    sleep 2
done