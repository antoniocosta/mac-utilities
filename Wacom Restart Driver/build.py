"""Rewrite 'Wacom Restart Driver.app' as Run Shell Script -> Run AppleScript (alert),
in place (its current workflow is the template). Keeps the app's own
Info.plist and stub. The shell step is app.sh."""
import os, plistlib, subprocess, uuid, copy

ROOT = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(ROOT, "Wacom Restart Driver.app")
TEMPLATE = os.path.join(TARGET, "Contents/document.wflow")  # rebuilt in place
SCRIPT = os.path.join(ROOT, "app.sh")

with open(TEMPLATE, "rb") as f:
    wflow = plistlib.load(f)
actions = {a["action"]["ActionName"]: a["action"] for a in wflow["actions"]}
shell, applescript = actions["Run Shell Script"], actions["Run AppleScript"]
wflow["actions"] = [{"action": shell, "isViewVisible": 1}, {"action": applescript, "isViewVisible": 1}]
with open(SCRIPT) as f:
    shell["ActionParameters"]["COMMAND_STRING"] = f.read()
applescript["ActionParameters"]["source"] = (
    'on run {input, parameters}\n'
    '\tset AppleScript\'s text item delimiters to linefeed\n'
    '\tset msg to (input as text)\n'
    '\tif msg is not "" then\n'
    '\t\tactivate\n'
    '\t\tif msg starts with "Wacom driver restarted" then\n'
    '\t\t\tdisplay alert "Wacom Restart Driver" message msg\n'
    '\t\telse\n'
    '\t\t\tdisplay alert "Wacom Restart Driver" message msg as critical\n'
    '\t\tend if\n'
    '\tend if\n'
    '\treturn input\n'
    'end run')
for a in (shell, applescript):
    for k in ("InputUUID", "OutputUUID", "UUID"):
        a[k] = str(uuid.uuid4()).upper()
wflow["connectors"] = {str(uuid.uuid4()).upper(): {
    "from": "%s - %s" % (shell["UUID"], shell["UUID"]),
    "to": "%s - %s" % (applescript["UUID"], applescript["UUID"])}}
with open(os.path.join(TARGET, "Contents/document.wflow"), "wb") as f:
    plistlib.dump(wflow, f)
# App icon (also shown in the alert): the one System Settings uses for the
# "Wacom Tablet" settings pane.
import shutil
ICON = "/Library/PreferencePanes/WacomTablet.prefpane/Contents/Resources/Professional.icns"
res = os.path.join(TARGET, "Contents/Resources")
shutil.copyfile(ICON, os.path.join(res, "ApplicationStub.icns"))
if os.path.exists(os.path.join(res, "Assets.car")):  # holds the Automator icon
    os.remove(os.path.join(res, "Assets.car"))
info_path = os.path.join(TARGET, "Contents/Info.plist")
with open(info_path, "rb") as f:
    info = plistlib.load(f)
info.pop("CFBundleIconName", None)
info["CFBundleIconFile"] = "ApplicationStub"
with open(info_path, "wb") as f:
    plistlib.dump(info, f)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", TARGET], check=True)
print(TARGET)
