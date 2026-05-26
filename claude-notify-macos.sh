#!/bin/bash

# Claude Code Notification Handler — macOS
# Mirrors Daniel Beal's claude-notify.sh (Linux/zenity/xdotool) for macOS.
# Uses osascript for dialogs and iTerm2 AppleScript for keystroke injection.
#
# Hook registration (in ~/.claude/settings.json):
#   "Notification": [{ "matcher": "permission_prompt|idle_prompt", "hooks": [{ "type": "command", "command": "bash ~/.claude/scripts/claude-notify-macos.sh" }] }]

DEBUG_LOG="/tmp/claude-notify-debug.log"
SCRIPT_PATH="$0"
BUNDLE_ID="com.kirylrusetski.claude-notifier"

# ============================================================================
# Settings (UserDefaults via `defaults read`)
# ============================================================================

read_setting() {
    local key="$1"
    local fallback="$2"
    local val
    val=$(defaults read "$BUNDLE_ID" "$key" 2>/dev/null)
    echo "${val:-$fallback}"
}

read_bool() {
    local key="$1"
    local fallback="$2"
    local val
    val=$(defaults read "$BUNDLE_ID" "$key" 2>/dev/null)
    if [ -z "$val" ]; then
        echo "$fallback"
    elif [ "$val" = "1" ] || [ "$val" = "true" ]; then
        echo "1"
    else
        echo "0"
    fi
}

effective_sound() {
    local override="$1"
    local fallback="$2"
    if [ -n "$override" ] && [ "$override" != "__default__" ]; then echo "$override"; return; fi
    if [ -n "$fallback" ]; then echo "$fallback"; return; fi
    read_setting defaultSound "Glass"
}

# Populates SND_ARGS array with "-sound <name>" when sounds are enabled, empty otherwise.
# Usage: set_sound_args "$sound"; then append "${SND_ARGS[@]}" to command.
# (Bash 3.2 safe — no mapfile/readarray.)
SND_ARGS=()
set_sound_args() {
    SND_ARGS=()
    [ "$SOUNDS_ENABLED" = "1" ] && SND_ARGS=(-sound "$1")
    true
}

# Pre-load settings used by multiple functions.
TITLE_SOURCE=$(read_setting titleSource "tabName")
TITLE_FIXED_TEXT=$(read_setting titleFixedText "Claude Code")

PERMISSION_ENABLED=$(read_bool permissionEnabled 1)
PERMISSION_SOUND=$(read_setting permissionSound "")
PERMISSION_ALLOW=$(read_setting permissionAllowLabel "Allow")
PERMISSION_DENY=$(read_setting permissionDenyLabel "Deny")
PERMISSION_SNOOZE=$(read_setting permissionSnoozeLabel "Snooze")
PERMISSION_MAX_WAIT=$(read_setting permissionMaxWait 1800)
PERMISSION_KEEP_FOCUS=$(read_bool permissionKeepFocus 0)
SNOOZE_DURATION=$(read_setting snoozeDurationSeconds 300)

TASK_ENABLED=$(read_bool taskCompleteEnabled 1)
TASK_MIN_DURATION=$(read_setting taskCompleteMinDuration 30)
TASK_SOUND=$(read_setting taskCompleteSound "Ping")
TASK_TIMEOUT=$(read_setting taskCompleteTimeout 10)

QUESTION_ENABLED=$(read_bool questionEnabled 1)
QUESTION_SOUND=$(read_setting questionSound "")
QUESTION_MAX_WAIT=$(read_setting questionMaxWait 1800)
QUESTION_MULTI_SELECT=$(read_setting questionMultiSelectMode "notifyOnly")
QUESTION_KEEP_FOCUS=$(read_bool questionKeepFocus 0)

TERMINAL_OVERRIDE=$(read_setting terminalOverride "auto")
SOUNDS_ENABLED=$(read_bool soundsEnabled 1)

# Fixed notification title — matches CFBundleDisplayName baked into Info.plist.
# Tab/session context moves into -subtitle (computed once at main() entry).
NOTIF_TITLE="Claude Notifier"

# ============================================================================
# Helper Functions
# ============================================================================

log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEBUG_LOG"
}

get_tab_context() {
    if [ "$TITLE_SOURCE" = "fixed" ]; then
        echo "$TITLE_FIXED_TEXT"
        return
    fi
    # Tab-title AppleScript only works for Terminal.app; other terminals fall back to fixed text.
    if [ "$(detect_terminal)" != "terminal" ]; then
        echo "$TITLE_FIXED_TEXT"
        return
    fi
    local raw
    raw=$(python3 -c "
import subprocess, re, sys
script = '''
tell application \"Terminal\"
    set w to front window
    return custom title of selected tab of w
end tell
'''
result = subprocess.run(['osascript', '-'], input=script, capture_output=True, text=True)
title = result.stdout.strip()
# Strip leading status markers (spinner braille block U+2800-U+28FF, *, ·, •,
# en-dash, em-dash) and whitespace. Done in Python so multibyte handling is safe.
title = re.sub(r'^[\\s*·•\\u2010-\\u2015\\u2800-\\u28FF]+', '', title)
print(title)
" 2>/dev/null)
    echo "${raw:-${TITLE_FIXED_TEXT}}"
}

truncate_text() {
    local text="$1"
    local max_length="${2:-3000}"
    text=$(echo -e "$text")
    if [ ${#text} -le "$max_length" ]; then
        echo "$text"
    else
        echo "${text:0:$max_length}..."
    fi
}

detect_terminal() {
    if [ -n "$TERMINAL_OVERRIDE" ] && [ "$TERMINAL_OVERRIDE" != "auto" ]; then
        echo "$TERMINAL_OVERRIDE"
        return
    fi
    case "$__CFBundleIdentifier" in
        com.apple.Terminal)    echo "terminal" ; return ;;
        com.googlecode.iterm2) echo "iterm2"   ; return ;;
        com.mitchellh.ghostty) echo "ghostty"  ; return ;;
        net.kovidgoyal.kitty)  echo "kitty"    ; return ;;
        dev.warp.Warp-Stable)  echo "warp"     ; return ;;
    esac
    case "$TERM_PROGRAM" in
        Apple_Terminal) echo "terminal" ; return ;;
        iTerm.app)      echo "iterm2"   ; return ;;
        ghostty)        echo "ghostty"  ; return ;;
        kitty)          echo "kitty"    ; return ;;
        WarpTerminal)   echo "warp"     ; return ;;
    esac
    if pgrep -x "iTerm2" >/dev/null 2>&1; then echo "iterm2"
    elif pgrep -x "Terminal" >/dev/null 2>&1; then echo "terminal"
    else echo "unknown"; fi
}

# Focus terminal and bring it to front. Uses HOOK_TTY to target the exact tab
# in Terminal.app (Feature 12). Ghostty/Warp get focus-only (no stdin injection).
focus_terminal() {
    local term
    term=$(detect_terminal)
    case "$term" in
        terminal)
            if [ -n "$HOOK_TTY" ]; then
                osascript - "$HOOK_TTY" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set hookTTY to item 1 of argv
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is hookTTY then
                    set selected tab of w to t
                    set index of w to 1
                    activate
                    return
                end if
            end repeat
        end repeat
        activate
    end tell
end run
APPLESCRIPT
            else
                osascript -e 'tell application "Terminal" to activate' 2>/dev/null
            fi
            ;;
        iterm2)
            osascript -e 'tell application "iTerm2" to activate' 2>/dev/null
            ;;
        ghostty)
            log_debug "Focusing Ghostty (stdin injection not supported)"
            osascript -e 'tell application "Ghostty" to activate' 2>/dev/null
            ;;
        kitty)
            log_debug "Focusing kitty (use send_to_terminal to inject text)"
            osascript -e 'tell application "kitty" to activate' 2>/dev/null
            ;;
        warp)
            log_debug "Focusing Warp (stdin injection not supported)"
            osascript -e 'tell application "Warp" to activate' 2>/dev/null
            ;;
        *)
            log_debug "Unknown terminal ($term) — no focus action"
            ;;
    esac
}

# Send text + Return to the current terminal session (Apple Terminal or iTerm2).
send_to_iterm2() {
    local text="$1"
    log_debug "Sending to terminal: $text"
    python3 -c "
import subprocess
script = '''
tell application \"Terminal\"
    activate
    tell front window
        do script \"$text\" in selected tab
    end tell
end tell
'''
subprocess.run(['osascript', '-'], input=script, capture_output=True, text=True)
" 2>/dev/null || osascript <<APPLESCRIPT 2>/dev/null
tell application "iTerm2"
    activate
    tell current session of current window
        write text "$text"
    end tell
end tell
APPLESCRIPT
}

# Dispatch text to the active terminal. Kitty uses its remote-control API;
# all others fall through to send_to_iterm2 (Terminal.app + iTerm2) or focus-only.
send_to_terminal() {
    local text="$1"
    local term
    term=$(detect_terminal)
    case "$term" in
        terminal|iterm2)
            send_to_iterm2 "$text"
            ;;
        kitty)
            log_debug "Sending to kitty via remote control: $text"
            kitty @ send-text -- "${text}\r" 2>/dev/null \
                || { log_debug "kitty remote control unavailable — set allow_remote_control yes in kitty.conf"; focus_terminal; }
            ;;
        ghostty|warp|*)
            log_debug "Terminal ($term) does not support stdin injection — focusing only"
            focus_terminal
            ;;
    esac
}

# Capture the currently-frontmost app, inject keystroke into the terminal, then
# restore focus to whatever was in front before. Clicking a notification action
# button doesn't change frontmost, so we read it after the click and before the
# terminal activates.
send_and_restore() {
    local text="$1"
    local prev_bundle
    prev_bundle=$(osascript -e 'tell application "System Events" to bundle identifier of (first process where it is frontmost)' 2>/dev/null)
    log_debug "Keep-focus: prev_bundle=$prev_bundle"
    send_to_terminal "$text"
    # Skip restore if the user was already in the terminal or in the notifier itself.
    case "$prev_bundle" in
        ""|com.apple.Terminal|com.googlecode.iterm2|com.mitchellh.ghostty|net.kovidgoyal.kitty|dev.warp.Warp-Stable|"$BUNDLE_ID")
            return
            ;;
    esac
    # Let the keystroke land before stealing focus back.
    sleep 0.15
    osascript -e "tell application id \"$prev_bundle\" to activate" 2>/dev/null
}

# Dispatch a keystroke either with or without restoring prior focus, based on
# the per-surface keepFocus setting. $1=text, $2="1" to keep focus, "0" to focus terminal.
deliver_keystroke() {
    local text="$1"
    local keep_focus="$2"
    if [ "$keep_focus" = "1" ]; then
        send_and_restore "$text"
    else
        send_to_terminal "$text"
    fi
}

# Polls transcript in background; sends SIGTERM to $1 (pid) when transcript grows past $2 (line count).
# Exits when the pid is gone. Returns the poll subshell's pid via stdout.
start_transcript_poll() {
    local pid="$1"
    local lines_before="$2"
    (
        while kill -0 "$pid" 2>/dev/null; do
            sleep 1
            local current
            current=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
            if [ "$current" -gt "$lines_before" ]; then
                log_debug "Transcript grew ($lines_before → $current lines) — sending SIGTERM to notifier $pid"
                kill "$pid" 2>/dev/null
                break
            fi
        done
    ) &
    echo $!
}

handle_snooze() {
    local original_json="$1"
    log_debug "Snooze activated - will re-trigger in ${SNOOZE_DURATION}s"
    nohup bash -c "sleep $SNOOZE_DURATION && echo $(printf '%q' "$original_json") | $SCRIPT_PATH" > /dev/null 2>&1 &
    local snooze_sound
    snooze_sound=$(effective_sound "$PERMISSION_SOUND")
    if [ "$SOUNDS_ENABLED" = "1" ]; then
        osascript -e "display notification \"Notification snoozed for $((SNOOZE_DURATION / 60)) minutes\" with title \"$NOTIF_TITLE\" sound name \"$snooze_sound\"" 2>/dev/null
    else
        osascript -e "display notification \"Notification snoozed for $((SNOOZE_DURATION / 60)) minutes\" with title \"$NOTIF_TITLE\"" 2>/dev/null
    fi
}

# Reverse lines of a file (macOS: tail -r, no tac).
reverse_file() {
    tail -r "$1"
}

parse_session_log() {
    local transcript_path="$1"
    local tool_name="" tool_input="" thinking=""

    if [ ! -f "$transcript_path" ]; then
        log_debug "ERROR: Transcript file not found: $transcript_path"
        echo '{"tool_name":"","tool_input":{},"thinking":""}'
        return
    fi

    log_debug "Parsing transcript file: $transcript_path"

    local found_tool=false
    local found_thinking=false
    local line_count=0

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        line_count=$((line_count + 1))

        if [ "$found_tool" = false ]; then
            local has_tool_use
            has_tool_use=$(echo "$line" | jq -r '.message.content[]? | select(.type == "tool_use") | .name' 2>/dev/null)
            if [ -n "$has_tool_use" ]; then
                tool_name="$has_tool_use"
                tool_input=$(echo "$line" | jq -c '.message.content[] | select(.type == "tool_use") | .input' 2>/dev/null)
                found_tool=true
                log_debug "Found tool_use at line $line_count: tool=$tool_name"
            fi
        fi

        if [ "$found_tool" = true ] && [ "$found_thinking" = false ]; then
            local has_thinking
            has_thinking=$(echo "$line" | jq -r '.message.content[]? | select(.type == "thinking") | .thinking' 2>/dev/null)
            if [ -n "$has_thinking" ]; then
                thinking="$has_thinking"
                found_thinking=true
                log_debug "Found thinking context (${#thinking} chars)"
                break
            fi
        fi

        if [ "$line_count" -gt 100 ]; then
            log_debug "Reached line limit (100), stopping search"
            break
        fi
    done < <(reverse_file "$transcript_path")

    if [ "$found_tool" = false ]; then
        log_debug "WARNING: No tool_use found in transcript"
    fi

    jq -n \
        --arg tn "$tool_name" \
        --argjson ti "${tool_input:-{\}}" \
        --arg th "$thinking" \
        '{tool_name: $tn, tool_input: $ti, thinking: $th}'
}

# ============================================================================
# Workflow Handlers
# ============================================================================

handle_stop() {
    log_debug "Handling stop event"

    if [ "$TASK_ENABLED" != "1" ]; then
        log_debug "Task-complete notifications disabled — skipping"
        return
    fi

    local start_file="/tmp/claude-task-start"
    if [ ! -f "$start_file" ]; then
        log_debug "No start time file — skipping stop notification"
        return
    fi

    local start now elapsed
    start=$(cat "$start_file")
    now=$(date +%s)
    elapsed=$((now - start))
    rm -f "$start_file"

    log_debug "Elapsed: ${elapsed}s"
    if [ "$elapsed" -lt "$TASK_MIN_DURATION" ]; then
        log_debug "Task too short (${elapsed}s < ${TASK_MIN_DURATION}s) — skipping notification"
        return
    fi

    local task_sound
    task_sound=$(effective_sound "$TASK_SOUND" "Ping")

    local CN="$HOME/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier"
    if [ -x "$CN" ]; then
        local stop_args=(-title "$NOTIF_TITLE" -message "Task complete" -timeout "$TASK_TIMEOUT")
        [ -n "$NOTIF_CONTEXT" ] && stop_args+=(-subtitle "❋ $NOTIF_CONTEXT")
        set_sound_args "$task_sound"
        "$CN" "${stop_args[@]}" "${SND_ARGS[@]}" 2>/dev/null &
    else
        if [ "$SOUNDS_ENABLED" = "1" ]; then
            osascript -e "display notification \"Task complete\" with title \"$NOTIF_TITLE\" sound name \"$task_sound\"" 2>/dev/null
        else
            osascript -e "display notification \"Task complete\" with title \"$NOTIF_TITLE\"" 2>/dev/null
        fi
        log_debug "claude-notifier not found, fell back to osascript"
    fi

    log_debug "Stop notification sent"
}

handle_askuserquestion_workflow() {
    local tool_input="$1"
    local thinking="$2"
    local cwd="$3"

    log_debug "Handling AskUserQuestion workflow"

    if [ "$QUESTION_ENABLED" != "1" ]; then
        log_debug "Question notifications disabled — focusing terminal"
        focus_terminal
        return
    fi

    local multi_select
    multi_select=$(echo "$tool_input" | jq -r '.questions[0].multiSelect // false')

    if [ "$multi_select" = "true" ]; then
        log_debug "Multi-select — mode=$QUESTION_MULTI_SELECT"
        if [ "$QUESTION_MULTI_SELECT" = "focusTerminal" ]; then
            focus_terminal
            return
        fi
        local q_sound
        q_sound=$(effective_sound "$QUESTION_SOUND")
        local CN="$HOME/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier"
        local ms_subtitle="${NOTIF_CONTEXT:+❋ $NOTIF_CONTEXT · }Question"
        if [ -x "$CN" ]; then
            set_sound_args "$q_sound"
            "$CN" \
                -title "$NOTIF_TITLE" \
                -subtitle "$ms_subtitle" \
                -message "Multi-select question requires terminal input" \
                "${SND_ARGS[@]}" \
                -timeout 10 \
                2>/dev/null &
        else
            if [ "$SOUNDS_ENABLED" = "1" ]; then
                osascript -e "display notification \"Multi-select question requires terminal input\" with title \"$NOTIF_TITLE\" sound name \"$q_sound\"" 2>/dev/null
            else
                osascript -e "display notification \"Multi-select question requires terminal input\" with title \"$NOTIF_TITLE\"" 2>/dev/null
            fi
        fi
        focus_terminal
        return
    fi

    local question
    question=$(echo "$tool_input" | jq -r '.questions[0].question // "No question text"')
    local num_options
    num_options=$(echo "$tool_input" | jq -r '.questions[0].options | length')

    # Build repeated -action flags and a parallel array for label→index lookup.
    local action_args=()
    local option_labels=()
    for i in $(seq 0 $((num_options - 1))); do
        local label
        label=$(echo "$tool_input" | jq -r ".questions[0].options[$i].label")
        option_labels+=("$label")
        action_args+=(-action "$label")
    done

    local q_sound
    q_sound=$(effective_sound "$QUESTION_SOUND")
    local q_subtitle="${NOTIF_CONTEXT:+❋ $NOTIF_CONTEXT · }Question"

    local CN="$HOME/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier"

    local result
    if [ -x "$CN" ]; then
        local tmpout
        tmpout=$(mktemp)
        local transcript_before
        transcript_before=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
        set_sound_args "$q_sound"
        "$CN" \
            -title "$NOTIF_TITLE" \
            -subtitle "$q_subtitle" \
            -message "$question" \
            "${action_args[@]}" \
            "${SND_ARGS[@]}" \
            -max-wait "$QUESTION_MAX_WAIT" \
            > "$tmpout" 2>/dev/null &
        local cn_pid=$!
        local poll_pid
        poll_pid=$(start_transcript_poll "$cn_pid" "$transcript_before")
        trap "kill $cn_pid $poll_pid 2>/dev/null; rm -f $tmpout" EXIT INT TERM
        wait $cn_pid
        kill $poll_pid 2>/dev/null
        result=$(cat "$tmpout")
        rm -f "$tmpout"
        trap - EXIT INT TERM
        log_debug "AskUserQuestion notification result: $result"
    else
        local dialog_buttons
        dialog_buttons=$(printf '"%s", ' "${option_labels[@]}" | sed 's/, $//')
        result=$(osascript <<APPLESCRIPT 2>/dev/null
set dlgResult to button returned of (display dialog "$question" with title "$NOTIF_TITLE — Question" buttons {"Go to Terminal", $dialog_buttons} default button 3)
return dlgResult
APPLESCRIPT
)
        log_debug "AskUserQuestion dialog result: $result"
    fi

    if [ -z "$result" ] || [ "$result" = "@CONTENTCLICKED" ] || [ "$result" = "@TIMEOUT" ] || [ "$result" = "@DISMISSED" ] || [ "$result" = "@EXTERNALLY_RESOLVED" ]; then
        focus_terminal
    elif [ "$result" = "@DENIED" ] || [ "$result" = "@ERROR" ]; then
        log_debug "Notification failed ($result) — falling back to terminal"
        focus_terminal
    else
        # Map the clicked label back to its option number (1-indexed).
        local selection=""
        for i in "${!option_labels[@]}"; do
            if [ "${option_labels[$i]}" = "$result" ]; then
                selection=$((i + 1))
                break
            fi
        done
        if [ -n "$selection" ]; then
            deliver_keystroke "$selection" "$QUESTION_KEEP_FOCUS"
        else
            log_debug "Could not map label to option number: $result"
            focus_terminal
        fi
    fi
}

summarize_bash() {
    local cmd="$1"
    local first_token
    first_token=$(echo "$cmd" | awk '{print $1}' | xargs basename 2>/dev/null)

    case "$first_token" in
        bq)
            local sql
            sql=$(echo "$cmd" | grep -oE 'SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|MERGE' | head -1)
            local table
            table=$(echo "$cmd" | grep -oE '[a-z0-9_-]+\.[a-z0-9_-]+\.[a-z0-9_-]+' | head -1)
            if [ -n "$sql" ] && [ -n "$table" ]; then
                echo "Run BigQuery: $sql … from $table"
            elif [ -n "$table" ]; then
                echo "Run BigQuery query on $table"
            else
                echo "Run BigQuery query"
            fi
            ;;
        git)
            local subcmd
            subcmd=$(echo "$cmd" | awk '{print $2}')
            echo "git $subcmd"
            ;;
        gh)
            local subcmd
            subcmd=$(echo "$cmd" | awk '{print $2" "$3}' | sed 's/^ *//;s/ *$//')
            echo "GitHub CLI: $subcmd"
            ;;
        curl|wget)
            local url
            url=$(echo "$cmd" | grep -oE 'https?://[^ ]+' | head -1 | sed 's|/[^/]*$|/…|')
            echo "HTTP request: ${url:-$first_token}"
            ;;
        npm|yarn|pnpm)
            local subcmd
            subcmd=$(echo "$cmd" | awk '{print $2}')
            echo "$first_token $subcmd"
            ;;
        python3|python)
            if echo "$cmd" | grep -q '\-c '; then
                echo "Run Python snippet"
            else
                local script
                script=$(echo "$cmd" | awk '{print $2}' | xargs basename 2>/dev/null)
                echo "Run Python: $script"
            fi
            ;;
        osascript)
            echo "Run AppleScript"
            ;;
        swiftc)
            echo "Compile Swift"
            ;;
        codesign)
            echo "Code-sign binary"
            ;;
        brew)
            local subcmd
            subcmd=$(echo "$cmd" | awk '{print $2}')
            echo "Homebrew: $subcmd"
            ;;
        rm)
            local target
            target=$(echo "$cmd" | awk '{print $NF}' | xargs basename 2>/dev/null)
            echo "Delete: $target"
            ;;
        mkdir|touch)
            local target
            target=$(echo "$cmd" | awk '{print $NF}' | xargs basename 2>/dev/null)
            echo "$first_token: $target"
            ;;
        find)
            local dir
            dir=$(echo "$cmd" | awk '{print $2}')
            echo "Find files in $dir"
            ;;
        grep)
            local pattern
            pattern=$(echo "$cmd" | awk '{print $2}')
            echo "Search: $pattern"
            ;;
        *)
            local rest
            rest=$(echo "$cmd" | cut -c$((${#first_token}+2))- | cut -c1-60)
            if [ -n "$rest" ]; then
                echo "$first_token $rest"
            else
                echo "$first_token"
            fi
            ;;
    esac
}

summarize_permission() {
    local tool_name="$1"
    local tool_input="$2"

    case "$tool_name" in
        Bash)
            local desc cmd
            desc=$(echo "$tool_input" | jq -r '.description // empty')
            if [ -n "$desc" ]; then
                echo "$desc"
            else
                cmd=$(echo "$tool_input" | jq -r '.command // "Unknown command"')
                summarize_bash "$cmd"
            fi
            ;;
        Write)
            local file_path
            file_path=$(echo "$tool_input" | jq -r '.file_path // "unknown"')
            echo "Write $(basename "$file_path") in $(dirname "$file_path" | sed "s|$HOME|~|")"
            ;;
        Edit)
            local file_path
            file_path=$(echo "$tool_input" | jq -r '.file_path // "unknown"')
            echo "Edit $(basename "$file_path") in $(dirname "$file_path" | sed "s|$HOME|~|")"
            ;;
        WebSearch)
            local query
            query=$(echo "$tool_input" | jq -r '.query // "unknown"')
            echo "Search: $query"
            ;;
        Skill)
            local skill
            skill=$(echo "$tool_input" | jq -r '.skill // "unknown"')
            echo "Run skill: $skill"
            ;;
        Agent)
            local desc
            desc=$(echo "$tool_input" | jq -r '.description // empty')
            if [ -n "$desc" ]; then
                echo "Spawn agent: $desc"
            else
                echo "Spawn agent"
            fi
            ;;
        ExitPlanMode)
            echo "Exit plan mode"
            ;;
        *)
            echo "$tool_name"
            ;;
    esac
}

handle_permission_workflow() {
    local tool_name="$1"
    local tool_input="$2"
    local thinking="$3"
    local cwd="$4"

    log_debug "Handling permission workflow for: $tool_name"

    if [ "$PERMISSION_ENABLED" != "1" ]; then
        log_debug "Permission notifications disabled — focusing terminal"
        focus_terminal
        return
    fi

    local summary
    summary=$(summarize_permission "$tool_name" "$tool_input")
    log_debug "Summary: $summary"

    local perm_sound
    perm_sound=$(effective_sound "$PERMISSION_SOUND")
    local perm_subtitle="${NOTIF_CONTEXT:+❋ $NOTIF_CONTEXT · }$tool_name"

    local CN="$HOME/.claude/scripts/claude-notifier.app/Contents/MacOS/claude-notifier"

    local result
    if [ -x "$CN" ]; then
        local tmpout
        tmpout=$(mktemp)
        local transcript_before
        transcript_before=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
        set_sound_args "$perm_sound"
        "$CN" \
            -title "$NOTIF_TITLE" \
            -subtitle "$perm_subtitle" \
            -message "$summary" \
            -action "$PERMISSION_ALLOW" -action "$PERMISSION_DENY" -action "$PERMISSION_SNOOZE" \
            "${SND_ARGS[@]}" \
            -max-wait "$PERMISSION_MAX_WAIT" \
            > "$tmpout" 2>/dev/null &
        local cn_pid=$!
        local poll_pid
        poll_pid=$(start_transcript_poll "$cn_pid" "$transcript_before")
        trap "kill $cn_pid $poll_pid 2>/dev/null; rm -f $tmpout" EXIT INT TERM
        wait $cn_pid
        kill $poll_pid 2>/dev/null
        result=$(cat "$tmpout")
        rm -f "$tmpout"
        trap - EXIT INT TERM
        log_debug "Permission notification result: $result"
    else
        result=$(osascript <<APPLESCRIPT 2>/dev/null
set dlgResult to button returned of (display dialog "$summary" with title "$NOTIF_TITLE — $tool_name" buttons {"$PERMISSION_DENY", "$PERMISSION_SNOOZE", "$PERMISSION_ALLOW"} default button "$PERMISSION_ALLOW")
return dlgResult
APPLESCRIPT
)
        log_debug "Permission dialog result: $result"
    fi

    case "$result" in
        "$PERMISSION_ALLOW")
            deliver_keystroke "1" "$PERMISSION_KEEP_FOCUS"
            ;;
        "$PERMISSION_DENY")
            deliver_keystroke "2" "$PERMISSION_KEEP_FOCUS"
            ;;
        "$PERMISSION_SNOOZE")
            handle_snooze "$INPUT"
            ;;
        @DENIED|@ERROR)
            log_debug "Notification failed ($result) — falling back to terminal"
            focus_terminal
            ;;
        *)
            focus_terminal
            ;;
    esac
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_debug "=== Script started ==="

    INPUT=$(cat)
    HOOK_TTY="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"
    NOTIF_CONTEXT=$(get_tab_context)
    log_debug "Received input: $INPUT"
    log_debug "Hook TTY: $HOOK_TTY"

    HOOK_EVENT_NAME=$(echo "$INPUT" | jq -r '.data.hook_event_name // .hook_event_name // empty')
    if [ "$HOOK_EVENT_NAME" = "PreToolUse" ]; then
        log_debug "Called from PreToolUse hook - exiting with code 5"
        exit 5
    fi
    if [ "$HOOK_EVENT_NAME" = "Stop" ]; then
        handle_stop
        exit 0
    fi

    NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // .data.notification_type // empty')
    log_debug "Notification type: $NOTIFICATION_TYPE"

    case "$NOTIFICATION_TYPE" in
        permission_prompt)
            log_debug "Processing $NOTIFICATION_TYPE"
            ;;
        *)
            log_debug "Ignoring notification type: $NOTIFICATION_TYPE"
            exit 0
            ;;
    esac

    TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .data.transcript_path // empty')
    CWD=$(echo "$INPUT" | jq -r '.cwd // .data.cwd // empty')
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .data.session_id // empty')

    log_debug "Transcript: $TRANSCRIPT_PATH"
    log_debug "CWD: $CWD"
    log_debug "Session: $SESSION_ID"

    if [ -z "$TRANSCRIPT_PATH" ]; then
        log_debug "ERROR: No transcript path provided"
        osascript -e 'display notification "Cannot determine context — no transcript path" with title "Claude Code" sound name "Sosumi"' 2>/dev/null
        exit 1
    fi

    TOOL_INFO=$(parse_session_log "$TRANSCRIPT_PATH")
    TOOL_NAME=$(echo "$TOOL_INFO" | jq -r '.tool_name')
    TOOL_INPUT=$(echo "$TOOL_INFO" | jq -c '.tool_input')
    THINKING=$(echo "$TOOL_INFO" | jq -r '.thinking')

    log_debug "Tool name: '$TOOL_NAME'"

    case "$TOOL_NAME" in
        AskUserQuestion)
            handle_askuserquestion_workflow "$TOOL_INPUT" "$THINKING" "$CWD"
            ;;
        *)
            handle_permission_workflow "$TOOL_NAME" "$TOOL_INPUT" "$THINKING" "$CWD"
            ;;
    esac

    log_debug "=== Script completed ==="
}

main
