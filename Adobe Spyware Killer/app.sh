# Adobe Spyware Killer
# Stops Adobe's background processes (Creative Cloud, sync, licensing/genuine
# checks, updaters, crash reporters, telemetry...) and keeps them from coming
# back, while leaving the Adobe apps you have open (Photoshop, Illustrator...)
# alone.
#
#   1. launchd: every Adobe launch agent (/Library/LaunchAgents,
#      ~/Library/LaunchAgents, and any com.adobe.* job in launchd's overrides) is
#      disabled and booted out, so it does not start again at login or on a
#      timer. Root daemons that start by themselves (RunAtLoad, StartInterval,
#      KeepAlive, StartCalendarInterval) get the same in the system domain.
#      On-demand helpers (MachServices only, e.g. the installer helper) stay
#      registered: they only start when an Adobe app you opened asks for them.
#   2. Finder Sync extension (Core Sync badges): set to "ignore" in pluginkit.
#   3. Processes: everything running from Adobe's background locations is
#      killed (SIGTERM, then SIGKILL), repeatedly, until nothing respawns:
#        /Applications/Utilities/Adobe *, /Applications/Adobe Creative Cloud/,
#        /Library/Application Support/Adobe/, ~/Library/Application Support/Adobe/,
#        /Library/PrivilegedHelperTools/com.adobe.*, Adobe temp folders.
#      Inside /Applications/Adobe <App>/, the apps themselves are never touched;
#      their bundled helpers are spared while that app runs and killed if they
#      linger after it quit (e.g. Acrobat's AdobeResourceSynchronizer).
#      While any Adobe app is open, AdobeIPCBroker is spared too: the apps
#      relaunch it within seconds (it is how they talk to Adobe's services).
#   Root-owned processes and daemons need an administrator password; the prompt
#   only appears when there is root work to do.
#
# Undo: hold Option while opening the app (or run this script with "restore").
# It re-enables exactly what Adobe Spyware Killer disabled (listed in the state file).
# Log: ~/Library/Logs/AdobeSpywareKiller.log
# Whatever this prints is shown as an alert by the next action (Run AppleScript).

export PATH=/usr/bin:/bin:/usr/sbin:/sbin
U=$(id -u)
LOG="$HOME/Library/Logs/AdobeSpywareKiller.log"
STATE_DIR="$HOME/Library/Application Support/Adobe Spyware Killer"
STATE="$STATE_DIR/disabled.txt"   # lines: "gui <label>" | "system <label>" | "plugin <id>"
mkdir -p "$STATE_DIR" "$(dirname "$LOG")"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# Mode: argument, or Option held at launch -> restore.
MODE="${1:-kill}"
if [ "$MODE" = kill ] && /usr/bin/python3 -c '
import ctypes, sys
cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
cg.CGEventSourceFlagsState.restype = ctypes.c_uint64
sys.exit(0 if cg.CGEventSourceFlagsState(0) & 0x80000 else 1)' 2>/dev/null; then
    MODE=restore
fi

BG_RE="^(/Applications/Utilities/Adobe |/Applications/Adobe Creative Cloud/|/Library/Application Support/Adobe/|$HOME/Library/Application Support/Adobe/|/Library/PrivilegedHelperTools/com\.adobe\.|/private/(var/folders|tmp)/.*([Aa]dobe|com\.adobe))"

# Background processes the Adobe apps need while they are open. Photoshop relaunches
# AdobeIPCBroker (its channel to Adobe's services) within 1-3 s of it being killed,
# so stopping it while an app is open is pointless; it is stopped once they quit.
NEEDED_RE="/AdobeIPCBroker\.app/"

# Print "pid<TAB>uid<TAB>path" for every Adobe background process to stop.
scan() {
    ps -axo pid=,uid=,comm= | awk -v bg="$BG_RE" -v needed="$NEEDED_RE" '
    {
        pid = $1; uid = $2
        path = $0; sub(/^ *[0-9]+ +[0-9]+ /, "", path)
        n++; P[n] = pid; UID_[n] = uid; X[n] = path
        # main executable of a top-level app in /Applications/Adobe <App>/
        if (match(path, /^\/Applications\/Adobe [^\/]+\/[^\/]+\.app\/Contents\/MacOS\/[^\/]+$/)) {
            d = path; sub(/^\/Applications\/Adobe [^\/]+\//, "", d)
            dir = substr(path, 1, length(path) - length(d))
            if (dir != "/Applications/Adobe Creative Cloud/") RUNNING[dir] = 1
        }
    }
    END {
        for (i = 1; i <= n; i++) {
            p = X[i]
            if (p ~ bg) {
                # needed by open apps (they relaunch it within seconds): spare while any runs
                if (length(RUNNING) > 0 && p ~ needed) continue
                print P[i] "\t" UID_[i] "\t" p; continue
            }
            if (p ~ /^\/Applications\/Adobe [^\/]+\//) {
                if (p ~ /^\/Applications\/Adobe [^\/]+\/[^\/]+\.app\/Contents\/MacOS\/[^\/]+$/) continue  # an app
                d = p; sub(/^\/Applications\/Adobe [^\/]+\//, "", d)
                dir = substr(p, 1, length(p) - length(d))
                if (!(dir in RUNNING)) print P[i] "\t" UID_[i] "\t" p    # helper of a closed app
            }
        }
    }'
}

# Short display name: "/x/Core Sync.app/Contents/MacOS/Core Sync" -> "Core Sync".
pname() { basename "$1"; }

# Adobe apps currently open (for the report).
open_apps() {
    ps -axo comm= | grep -E '^/Applications/Adobe [^/]+/[^/]+\.app/Contents/MacOS/[^/]+$' \
        | grep -v '^/Applications/Adobe Creative Cloud/' \
        | sed -E 's#^/Applications/Adobe [^/]+/([^/]+)\.app/.*#\1#' | sort -u
}

# Labels of all Adobe launchd jobs in the gui domain (agents).
gui_labels() {
    {
        for f in /Library/LaunchAgents/com.adobe*.plist "$HOME"/Library/LaunchAgents/com.adobe*.plist; do
            [ -f "$f" ] && plutil -extract Label raw -o - "$f" 2>/dev/null && echo
        done
        launchctl print-disabled "gui/$U" 2>/dev/null | sed -nE 's/^[[:space:]]*"(com\.adobe[^"]*)" => enabled.*/\1/p'
    } | grep -v '^$' | sort -u
}

gui_disabled() { launchctl print-disabled "gui/$U" 2>/dev/null | grep -qF "\"$1\" => disabled"; }
sys_disabled() { launchctl print-disabled system 2>/dev/null | grep -qF "\"$1\" => disabled"; }

# Root daemons that start by themselves: "label<TAB>plist".
sys_autostart() {
    for f in /Library/LaunchDaemons/com.adobe*.plist; do
        [ -f "$f" ] || continue
        if plutil -p "$f" 2>/dev/null | grep -qE '"(RunAtLoad" => (true|1)|StartInterval"|KeepAlive"|StartCalendarInterval")'; then
            printf '%s\t%s\n' "$(plutil -extract Label raw -o - "$f")" "$f"
        fi
    done
}

remember() { grep -qxF "$1" "$STATE" 2>/dev/null || echo "$1" >> "$STATE"; }

# ------------------------------------------------------------- list (dry run) ----
if [ "$MODE" = list ]; then
    echo "Would stop:"; scan | awk -F'\t' '{print "  [uid " $2 "] " $3}'
    echo "Agents (gui/$U):"; gui_labels | while read -r l; do
        gui_disabled "$l" && echo "  $l (already disabled)" || echo "  $l"; done
    echo "Self-starting root daemons:"; sys_autostart | while IFS=$'\t' read -r l f; do
        sys_disabled "$l" && echo "  $l (already disabled)" || echo "  $l"; done
    echo "Extensions:"; pluginkit -mAv 2>/dev/null | awk -F'\t' -v bg="$BG_RE" '$4 ~ bg {print "  " $1 " " $4}'
    echo "Open Adobe apps (left alone):"; open_apps | sed 's/^/  /'
    exit 0
fi

# ---------------------------------------------------------------- restore ----
if [ "$MODE" = restore ]; then
    log "restore"
    out=(); root_cmds=""; root_labels=(); keep=()
    while IFS= read -r line; do
        kind=${line%% *}; what=${line#* }
        case "$kind" in
            gui) launchctl enable "gui/$U/$what" && out+=("re-enabled $what") || keep+=("$line") ;;
            plugin) pluginkit -e use -i "$what" && out+=("re-enabled the Finder extension $what") || keep+=("$line") ;;
            system) root_cmds+="launchctl enable system/$what;"; root_labels+=("$what") ;;
        esac
    done < <(cat "$STATE" 2>/dev/null)
    if [ -n "$root_cmds" ]; then
        if err=$(osascript -e "do shell script \"$root_cmds\" with administrator privileges with prompt \"Adobe Spyware Killer needs an administrator password to re-enable Adobe's system daemons.\"" 2>&1); then
            for l in "${root_labels[@]}"; do out+=("re-enabled $l (root)"); done
        else
            log "root restore failed: $err"
            for l in "${root_labels[@]}"; do keep+=("system $l"); done
            out+=("NOT re-enabled (administrator password cancelled): ${root_labels[*]}")
        fi
    fi
    if [ ${#keep[@]} -gt 0 ]; then printf '%s\n' "${keep[@]}" > "$STATE"; else rm -f "$STATE"; fi
    if [ ${#out[@]} -eq 0 ]; then
        echo "Nothing to restore: Adobe Spyware Killer had not disabled anything."
    else
        echo "Adobe background services restored."
        echo "They start again at the next login (or when you open Creative Cloud)."
        echo
        printf -- '• %s\n' "${out[@]}"
    fi
    for l in "${out[@]}"; do log "  $l"; done
    exit 0
fi

# ------------------------------------------------------------------- kill ----
log "kill (open Adobe apps: $(open_apps | paste -sd, -))"
disabled=(); killed_names=""; notes=()

# 1. launchd agents (gui domain, no root needed)
while IFS= read -r label; do
    [ -n "$label" ] || continue
    if ! gui_disabled "$label"; then
        launchctl disable "gui/$U/$label" && { disabled+=("$label"); remember "gui $label"; }
    fi
    launchctl bootout "gui/$U/$label" 2>/dev/null
done < <(gui_labels)

# 2. Finder Sync / other extensions living in Adobe's background folders
while IFS=$'\t' read -r id path; do
    [ -n "$id" ] || continue
    pluginkit -e ignore -i "$id" && { disabled+=("Finder extension $id"); remember "plugin $id"; }
done < <(pluginkit -mAv 2>/dev/null | awk -F'\t' -v bg="$BG_RE" '
    $1 ~ /^\+/ { id = $1; sub(/^\+ */, "", id); sub(/\(.*/, "", id); gsub(/ /, "", id)
                 if ($4 ~ bg) print id "\t" $4 }')

# 3. kill my processes until nothing respawns
kill_round() {   # $1 = uid filter: "me" or "other"; prints killed paths
    local list
    if [ "$1" = me ]; then list=$(scan | awk -F'\t' -v u="$U" '$2 == u')
    else list=$(scan | awk -F'\t' -v u="$U" '$2 != u'); fi
    [ -n "$list" ] || return 1
    pids=$(printf '%s\n' "$list" | cut -f1)
    kill -TERM $pids 2>/dev/null
    for _ in 1 2 3 4; do
        sleep 0.5
        alive=""; for p in $pids; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
        [ -n "$alive" ] || break
    done
    [ -n "$alive" ] && kill -KILL $alive 2>/dev/null
    printf '%s\n' "$list" | cut -f3
    return 0
}

for round in 1 2 3 4 5 6 7 8; do
    k=$(kill_round me) || break
    killed_names+="$k"$'\n'
    sleep 1
done

# 4. root work (only if needed): root/other-user processes, self-starting daemons
root_script=$(mktemp -t adobespywarekiller)
{
    echo 'export PATH=/usr/bin:/bin:/usr/sbin:/sbin'
    while IFS=$'\t' read -r label plist; do
        [ -n "$label" ] || continue
        if ! sys_disabled "$label"; then
            echo "launchctl disable 'system/$label' && echo 'DISABLED $label'"
        fi
        echo "launchctl bootout 'system/$label' 2>/dev/null"
    done < <(sys_autostart)
} > "$root_script"
others=$(scan | awk -F'\t' -v u="$U" '$2 != u')
need_root=0
grep -q "DISABLED" "$root_script" && need_root=1
[ -n "$others" ] && need_root=1
if [ $need_root = 1 ]; then
    {
        echo 'for r in 1 2 3 4; do'
        echo '  pids=$(ps -axo pid=,uid=,comm= | awk -v u='"$U"' -v bg="$1" '"'"'{p=$0; sub(/^ *[0-9]+ +[0-9]+ /,"",p); if ($2 != u && p ~ bg) print $1 "\t" p}'"'"')'
        echo '  [ -n "$pids" ] || break'
        echo '  printf "%s\n" "$pids" | cut -f2 | sed "s/^/KILLED /"'
        echo '  kill -TERM $(printf "%s\n" "$pids" | cut -f1) 2>/dev/null; sleep 1'
        echo '  kill -KILL $(printf "%s\n" "$pids" | cut -f1) 2>/dev/null; sleep 1'
        echo 'done'
    } >> "$root_script"
    esc_bg=$(printf '%s' "$BG_RE" | sed 's/\\/\\\\\\\\/g; s/"/\\"/g')
    if root_out=$(osascript -e "do shell script \"/bin/bash '$root_script' '$esc_bg'\" with administrator privileges with prompt \"Adobe Spyware Killer needs an administrator password to stop Adobe's background services that run as root.\"" 2>&1); then
        while IFS= read -r l; do
            case "$l" in
                DISABLED\ *) disabled+=("${l#DISABLED } (root)"); remember "system ${l#DISABLED }" ;;
                KILLED\ *) killed_names+="${l#KILLED }"$'\n' ;;
            esac
        done < <(printf '%s\n' "$root_out" | tr '\r' '\n')
    else
        notes+=("Root part skipped (administrator password cancelled): $(printf '%s\n' "$others" | cut -f3 | while read -r p; do pname "$p"; done | sort -u | paste -sd, - | sed 's/,/, /g')")
        log "root part skipped: $root_out"
    fi
fi
rm -f "$root_script"

# 5. respawn check
sleep 3
back=$(scan | cut -f3 | while IFS= read -r p; do pname "$p"; done | sort -u)

# ----------------------------------------------------------------- report ----
names=$(printf '%s' "$killed_names" | grep -v '^$' | while IFS= read -r p; do pname "$p"; done | sort -u)
apps=$(open_apps)
if [ -n "$back" ]; then echo "Some Adobe processes came back:"; printf '%s\n' "$back" | sed 's/^/• /'; echo
elif [ -z "$names" ] && [ ${#disabled[@]} -eq 0 ]; then echo "Nothing to do: no Adobe background processes to stop."
else echo "Adobe background processes stopped."; fi
if [ -n "$names" ]; then echo; echo "Stopped:"; printf '%s\n' "$names" | sed 's/^/• /'; fi
if [ ${#disabled[@]} -gt 0 ]; then echo; echo "Kept from starting again:"; printf '• %s\n' "${disabled[@]}"; fi
for n in "${notes[@]}"; do echo; echo "$n"; done
if [ -n "$apps" ]; then echo; echo "Left running (your apps): $(printf '%s\n' "$apps" | paste -sd, - | sed 's/,/, /g')"; fi
if [ -n "$apps" ]; then
    kept=$(ps -axo comm= | grep -E "$NEEDED_RE" | while IFS= read -r p; do pname "$p"; done | sort -u | paste -sd, - | sed 's/,/, /g')
    [ -n "$kept" ] && echo "Left running while they are open (they need it): $kept"
fi
echo; echo "Undo: hold Option while opening Adobe Spyware Killer."
{ printf '%s\n' "$names" | sed 's/^/  stopped /'; printf '  disabled %s\n' "${disabled[@]}"; printf '%s\n' "$back" | sed 's/^/  came back /'; } | grep -v '^  [a-z ]*$' >> "$LOG"
exit 0   # Automator shows any non-zero exit status as an error
