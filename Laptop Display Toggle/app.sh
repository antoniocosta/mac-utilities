# Laptop Display Toggle
# Turns the MacBook's built-in display off/on while an external display is
# connected, so the lid can stay slightly open (Touch ID keeps working) without
# the laptop screen being part of the desktop.
#
# - Refuses (with an alert) when no external display is connected.
# - While the built-in display is off, a small background watcher reacts to
#   macOS's display-change event (re-checking every 30 s as a safety net);
#   if the external display goes away it turns the built-in back on.
#   It logs to ~/Library/Logs/LaptopDisplayToggle.log.
# - The keyboard backlight is turned off with the display and restored after.
# - Changes last for the login session only: logout/reboot restores the screen.
#
# Plain Python + ctypes (no compiling), using the private CoreGraphics call
# CGSConfigureDisplayEnabled. Edit the Python below; ACTION can be
# toggle | off | on | status. Whatever this prints is shown as an alert by the
# next action (Run AppleScript).

ACTION="${1:-toggle}"

read -r -d '' LAPTOP_DISPLAY_PY <<'PYTHON'
import ctypes, os, subprocess, sys, time

CG = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
CG.CGSConfigureDisplayEnabled.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_bool]
CG.CGBeginDisplayConfiguration.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
CG.CGCompleteDisplayConfiguration.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
CG.CGCancelDisplayConfiguration.argtypes = [ctypes.c_void_p]

FOR_SESSION = 1  # kCGConfigureForSession: undone at logout
# The built-in display disappears from the online list once disabled, so
# remember its ID while it is off.
STATE_FILE = os.path.expanduser("~/Library/Caches/laptop-display-builtin-id")
# The watcher reacts to display-change events; this re-check is only a safety net.
SAFETY_CHECK_SECONDS = 30
LOG_FILE = os.path.expanduser("~/Library/Logs/LaptopDisplayToggle.log")
EXTERNALS_FILE = os.path.expanduser("~/Library/Caches/laptop-display-externals")
# Keyboard backlight state (brightness, auto-brightness) to restore later.
KEYBOARD_FILE = os.path.expanduser("~/Library/Caches/laptop-display-keyboard")
# Message left by the background watcher for the app to show on its next run.
MESSAGE_FILE = os.path.expanduser("~/Library/Caches/laptop-display-message")
APP_BUNDLE_ID = "com.apple.automator.Laptop-Display-Toggle"


def notify(message):
    # The message is printed; the next workflow action ("Run AppleScript")
    # shows it as an alert, so the alert gets this app's icon.
    print(message)


def notify_from_watcher(message):
    # The app has already quit: leave the message and reopen the app to show it.
    with open(MESSAGE_FILE, "w") as f:
        f.write(message)
    if subprocess.run(["open", "-b", APP_BUNDLE_ID], check=False).returncode != 0:
        os.remove(MESSAGE_FILE)  # app not found: plain alert instead
        subprocess.run(["osascript", "-e", 'display alert "Laptop Display Toggle" message "%s"' % message],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def pending_message():
    try:
        if time.time() - os.path.getmtime(MESSAGE_FILE) > 30:  # stale
            os.remove(MESSAGE_FILE)
            return None
        with open(MESSAGE_FILE) as f:
            message = f.read()
        os.remove(MESSAGE_FILE)
        return message
    except OSError:
        return None


def online_displays():
    ids = (ctypes.c_uint32 * 32)()
    count = ctypes.c_uint32()
    if CG.CGGetOnlineDisplayList(32, ids, ctypes.byref(count)) != 0:
        return []
    return [ids[i] for i in range(count.value)]


def builtin_active():
    return any(CG.CGDisplayIsBuiltin(d) and CG.CGDisplayIsActive(d) for d in online_displays())


def set_enabled(display_id, enabled):
    config = ctypes.c_void_p()
    if CG.CGBeginDisplayConfiguration(ctypes.byref(config)) != 0:
        return False
    if CG.CGSConfigureDisplayEnabled(config, display_id, enabled) != 0:
        CG.CGCancelDisplayConfiguration(config)
        return False
    return CG.CGCompleteDisplayConfiguration(config, FOR_SESSION) == 0


def saved_builtin_id():
    try:
        with open(STATE_FILE) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return 1  # the built-in display's usual ID


# --- Keyboard backlight -------------------------------------------------------
# KeyboardBrightnessClient (private CoreBrightness.framework, what Control
# Center uses). Signatures checked against the framework's own type encodings
# and the class-dump header in github.com/EthanRDoesMC/KBPulse.
def keyboard_client():
    try:
        objc = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
        ctypes.CDLL("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness")
    except OSError:
        return None
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]
    cls = objc.objc_getClass(b"KeyboardBrightnessClient")
    if not cls:
        return None

    def call(restype, selector, *args):
        argtypes = [type(a) for a in args]
        fn = ctypes.CFUNCTYPE(restype, ctypes.c_void_p, ctypes.c_void_p, *argtypes)(("objc_msgSend", objc))
        return fn(client, objc.sel_registerName(selector), *args)

    new = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(("objc_msgSend", objc))
    client = new(new(cls, objc.sel_registerName(b"alloc")), objc.sel_registerName(b"init"))
    return call


KEYBOARD_ID = ctypes.c_ulonglong(1)  # the built-in keyboard's backlight


def keyboard_backlight_off():
    call = keyboard_client()
    if call is None or not call(ctypes.c_bool, b"isKeyboardBuiltIn:", KEYBOARD_ID):
        return False
    brightness = call(ctypes.c_float, b"brightnessForKeyboard:", KEYBOARD_ID)
    auto = call(ctypes.c_bool, b"isAutoBrightnessEnabledForKeyboard:", KEYBOARD_ID)
    with open(KEYBOARD_FILE, "w") as f:
        f.write("%f %d" % (brightness, auto))
    # Auto-brightness would raise it again in the dark, so pause it too.
    call(ctypes.c_bool, b"enableAutoBrightness:forKeyboard:", ctypes.c_bool(False), KEYBOARD_ID)
    call(ctypes.c_bool, b"setBrightness:forKeyboard:", ctypes.c_float(0.0), KEYBOARD_ID)
    return True


def keyboard_backlight_restore():
    try:
        with open(KEYBOARD_FILE) as f:
            brightness, auto = f.read().split()
        os.remove(KEYBOARD_FILE)
    except (OSError, ValueError):
        return False
    call = keyboard_client()
    if call is None:
        return False
    call(ctypes.c_bool, b"setBrightness:forKeyboard:", ctypes.c_float(float(brightness)), KEYBOARD_ID)
    call(ctypes.c_bool, b"enableAutoBrightness:forKeyboard:", ctypes.c_bool(auto == "1"), KEYBOARD_ID)
    return True


def turn_off():
    builtin = next((d for d in online_displays() if CG.CGDisplayIsBuiltin(d)), None)
    if builtin is None or not CG.CGDisplayIsActive(builtin):
        notify("The built-in display is already off.")
        return
    externals = active_externals()
    if not externals:
        notify("No external display connected. The built-in display stays on.")
        return
    with open(STATE_FILE, "w") as f:
        f.write(str(builtin))
    # Remember the real external displays: when the last one is unplugged,
    # macOS invents a placeholder "external" display, which must not count.
    with open(EXTERNALS_FILE, "w") as f:
        f.write(" ".join(str(d) for d in externals))
    if not set_enabled(builtin, False):
        notify("Could not turn off the built-in display.")
        return
    # Background watcher: turns the built-in display back on if the external
    # one is disconnected. Detached so this app can quit right away.
    subprocess.Popen([sys.executable, "-c", os.environ["LAPTOP_DISPLAY_PY"], "watch"],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    keyboard = keyboard_backlight_off()
    notify("\n".join([
        "Built-in display off.",
        "",
        "- Built-in display: off (external display is the only screen)",
        "- Keyboard backlight: " + ("off" if keyboard else "unchanged"),
        "- Touch ID: still available (the lid is open)",
        "- Microphone and camera: unchanged",
        "- If the external display is unplugged, the built-in display",
        "  turns back on automatically.",
        "",
        "Run again to turn the built-in display back on.",
    ]))


def turn_on(message="Built-in display on."):
    if builtin_active():
        keyboard_backlight_restore()  # in case it was turned on some other way
        notify("The built-in display is already on.")
        return True
    for display_id in dict.fromkeys([saved_builtin_id(), 1]):  # saved ID, then the usual one
        if set_enabled(display_id, True):
            keyboard = keyboard_backlight_restore()
            for path in (STATE_FILE, EXTERNALS_FILE):
                try:
                    os.remove(path)
                except OSError:
                    pass
            notify("\n".join([
                message,
                "",
                "- Built-in display: on",
                "- Keyboard backlight: " + ("restored" if keyboard else "unchanged"),
            ]))
            return True
    notify("Could not turn on the built-in display.")
    return False


def log(message):
    with open(LOG_FILE, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + message + "\n")


def describe_displays():
    return ", ".join(
        "%d:%s%s%s%s(vendor %x model %x)" % (d, "built-in" if CG.CGDisplayIsBuiltin(d) else "external",
                         "" if CG.CGDisplayIsOnline(d) else ",offline",
                         ",active" if CG.CGDisplayIsActive(d) else ",inactive",
                         ",asleep" if CG.CGDisplayIsAsleep(d) else "",
                         CG.CGDisplayVendorNumber(d), CG.CGDisplayModelNumber(d))
        for d in online_displays()) or "none"


def active_externals():
    return [d for d in online_displays()
            if not CG.CGDisplayIsBuiltin(d) and CG.CGDisplayIsActive(d)]


def saved_externals():
    try:
        with open(EXTERNALS_FILE) as f:
            return {int(x) for x in f.read().split()}
    except (OSError, ValueError):
        return set()


def external_present(saved):
    # Only the external displays that were connected when the built-in display
    # was turned off count (not the placeholder macOS adds after an unplug).
    return any(d in saved for d in active_externals())


def watch():
    """Turn the built-in display back on when the watched external display goes away.

    Reacts to macOS's display-change event (CGDisplayRegisterReconfigurationCallback).
    Apple's Quartz Display Services guide: the callback runs for changes made by
    others (e.g. unplugging a display) only while "your application is listening
    for events in the event-processing thread", so this runs a minimal, invisible
    NSApplication event loop. A re-check every SAFETY_CHECK_SECONDS is a safety net.
    Logs to ~/Library/Logs/LaptopDisplayToggle.log.
    """
    global notify
    notify = notify_from_watcher  # the app has quit by now
    objc = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
    appkit = ctypes.CDLL("/System/Library/Frameworks/AppKit.framework/AppKit")
    cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]
    cf.CFRunLoopGetMain.restype = ctypes.c_void_p
    cf.CFRunLoopStop.argtypes = [ctypes.c_void_p]

    def msg(restype, *argtypes):  # typed objc_msgSend
        return ctypes.CFUNCTYPE(restype, ctypes.c_void_p, ctypes.c_void_p, *argtypes)(("objc_msgSend", objc))

    sel = objc.sel_registerName
    app = msg(ctypes.c_void_p)(objc.objc_getClass(b"NSApplication"), sel(b"sharedApplication"))
    msg(ctypes.c_bool, ctypes.c_long)(app, sel(b"setActivationPolicy:"), 2)  # prohibited: no Dock icon, no UI
    msg(None)(app, sel(b"finishLaunching"))
    next_event = msg(ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_bool)
    send_event = msg(None, ctypes.c_void_p)
    date_in = msg(ctypes.c_void_p, ctypes.c_double)
    nsdate = objc.objc_getClass(b"NSDate")
    default_mode = ctypes.c_void_p.in_dll(appkit, "NSDefaultRunLoopMode")

    @ctypes.CFUNCTYPE(None, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p)
    def on_display_change(display, flags, user_info):
        if flags & 1:  # kCGDisplayBeginConfigurationFlag: change about to happen
            return
        log("event: display %d changed (flags %#x)" % (display, flags))
        cf.CFRunLoopStop(cf.CFRunLoopGetMain())  # wake the loop below to check now

    CG.CGDisplayRegisterReconfigurationCallback.argtypes = [type(on_display_change), ctypes.c_void_p]
    CG.CGDisplayRegisterReconfigurationCallback(on_display_change, None)

    saved = saved_externals()
    log("watcher started (pid %d): %s; watching external display(s) %s"
        % (os.getpid(), describe_displays(), sorted(saved)))
    last = None
    while True:
        # Wait for an event (display changes arrive here) or the safety-net timeout.
        until = date_in(nsdate, sel(b"dateWithTimeIntervalSinceNow:"), SAFETY_CHECK_SECONDS)
        event = next_event(app, sel(b"nextEventMatchingMask:untilDate:inMode:dequeue:"),
                           0xFFFFFFFFFFFFFFFF, until, default_mode, True)
        if event:
            send_event(app, sel(b"sendEvent:"), event)
        now = describe_displays()
        if now != last:
            log("displays: " + now)
            last = now
        if builtin_active():  # turned back on by the user (or macOS)
            keyboard_backlight_restore()
            log("built-in display is on; watcher exits")
            return
        if not external_present(saved):
            log("watched external display(s) gone; turning the built-in display on")
            if turn_on("External display disconnected. Built-in display back on."):
                log("built-in display turned on; watcher exits")
                return
            log("turning on failed; retrying in %d s" % SAFETY_CHECK_SECONDS)


def status():
    for d in online_displays():
        print(d, "built-in" if CG.CGDisplayIsBuiltin(d) else "external",
              "active" if CG.CGDisplayIsActive(d) else "inactive")
    if not builtin_active():
        print("built-in display: off")


action = sys.argv[1] if len(sys.argv) > 1 else "toggle"
if action == "toggle":
    message = pending_message()  # reopened by the watcher just to show this
    if message:
        notify(message)
    elif builtin_active():
        turn_off()
    else:
        turn_on()
elif action == "off":
    turn_off()
elif action == "on":
    turn_on()
elif action == "watch":
    watch()
elif action == "status":
    status()
else:
    sys.exit("usage: toggle | off | on | status")
PYTHON

export LAPTOP_DISPLAY_PY
/usr/bin/python3 -c "$LAPTOP_DISPLAY_PY" "$ACTION"
