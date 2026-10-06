# Wacom Restart Driver
# Restarts the Wacom driver when the tablet hangs or stops responding.
#
# Uses launchd (the services' own launch agents in /Library/LaunchAgents), no
# AppleScript "tell application" (which could hang for minutes waiting on an
# unresponsive driver):
#   1. kill the per-device drivers (WacomTabletDriver, WacomTouchDriver),
#      SIGTERM then SIGKILL if they don't quit (a hung process may not);
#   2. launchctl kickstart -k the launch agents: com.wacom.DataStoreMgr (settings
#      store), Wacom_IOManager (talks to the hardware) and com.wacom.wacomtablet
#      (TabletDriver, which relaunches the per-device drivers);
#   3. wait until WacomTabletDriver is running again.
# Whatever this prints is shown as an alert by the next action (Run AppleScript).

U=$(id -u)

for p in WacomTabletDriver WacomTouchDriver; do pkill -x "$p"; done
sleep 0.5
for p in WacomTabletDriver WacomTouchDriver; do pkill -9 -x "$p"; done

restarted=()
for service in com.wacom.DataStoreMgr Wacom_IOManager com.wacom.wacomtablet; do
    if launchctl kickstart -k "gui/$U/$service" 2>/dev/null; then
        restarted+=("$service")
    fi
done

for _ in $(seq 1 40); do  # up to 10 s
    pgrep -x WacomTabletDriver >/dev/null && break
    sleep 0.25
done

if pgrep -x WacomTabletDriver >/dev/null; then
    echo "Wacom driver restarted."
    echo ""
    echo "- Restarted: ${restarted[*]:-none}"
    echo "- WacomTabletDriver is running again."
else
    echo "The Wacom driver did not come back."
    echo ""
    echo "- Restarted: ${restarted[*]:-none}"
    echo "- WacomTabletDriver is not running."
    echo "- Try unplugging and replugging the tablet, or log out and back in."
fi
