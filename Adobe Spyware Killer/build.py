"""Build 'Adobe Spyware Killer.app' (Automator: Run Shell Script -> Run AppleScript
alert) from app.sh, in place. The existing app beside this script
is the skeleton; the very first build bootstraps from ../Wacom Restart Driver."""
import os, plistlib, shutil, subprocess, tempfile, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Adobe Spyware Killer"
TARGET = os.path.join(HERE, NAME + ".app")
SCRIPT = os.path.join(HERE, "app.sh")
BOOTSTRAP = os.path.join(HERE, "..", "Wacom Restart Driver", "Wacom Restart Driver.app")
# The Creative Cloud app icon, badged by make_icon.swift (also shown in the alert).
ICON = "/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app/Contents/Resources/CreativeCloudApp.icns"

skeleton = os.path.join(tempfile.mkdtemp(), "skeleton.app")
shutil.copytree(TARGET if os.path.exists(TARGET) else BOOTSTRAP, skeleton)
shutil.rmtree(TARGET, ignore_errors=True)
shutil.copytree(skeleton, TARGET)
shutil.rmtree(os.path.join(TARGET, "Contents", "_CodeSignature"), ignore_errors=True)
c = os.path.join(TARGET, "Contents")

info_path = os.path.join(c, "Info.plist")
with open(info_path, "rb") as f:
    info = plistlib.load(f)
info.update(CFBundleIdentifier="com.apple.automator.Adobe-Spyware-Killer", CFBundleName=NAME,
            CFBundleShortVersionString="1.0", CFBundleIconFile="ApplicationStub")
info.pop("CFBundleIconName", None)
with open(info_path, "wb") as f:
    plistlib.dump(info, f)

wflow_path = os.path.join(c, "document.wflow")
with open(wflow_path, "rb") as f:
    wflow = plistlib.load(f)
actions = {a["action"]["ActionName"]: a["action"] for a in wflow["actions"]}
shell, applescript = actions["Run Shell Script"], actions["Run AppleScript"]
with open(SCRIPT) as f:
    shell["ActionParameters"]["COMMAND_STRING"] = f.read()
applescript["ActionParameters"]["source"] = (
    'on run {input, parameters}\n'
    '\tset AppleScript\'s text item delimiters to linefeed\n'
    '\tset msg to (input as text)\n'
    '\tif msg is not "" then\n'
    '\t\tactivate\n'
    '\t\tif msg starts with "Some Adobe processes came back" then\n'
    '\t\t\tdisplay alert "' + NAME + '" message msg as critical\n'
    '\t\telse\n'
    '\t\t\tdisplay alert "' + NAME + '" message msg\n'
    '\t\tend if\n'
    '\tend if\n'
    '\treturn input\n'
    'end run')
for a in (shell, applescript):
    for k in ("InputUUID", "OutputUUID", "UUID"):
        a[k] = str(uuid.uuid4()).upper()
wflow["actions"] = [{"action": shell, "isViewVisible": 1}, {"action": applescript, "isViewVisible": 1}]
wflow["connectors"] = {str(uuid.uuid4()).upper(): {
    "from": "%s - %s" % (shell["UUID"], shell["UUID"]),
    "to": "%s - %s" % (applescript["UUID"], applescript["UUID"])}}
with open(wflow_path, "wb") as f:
    plistlib.dump(wflow, f)

res = os.path.join(c, "Resources")
if os.path.exists(ICON):
    # Creative Cloud icon with a red "prohibited" sign on top (make_icon.swift).
    subprocess.run(["swift", os.path.join(HERE, "make_icon.swift"), ICON,
                    os.path.join(res, "ApplicationStub.icns")], check=True)
else:
    print("note: Creative Cloud icon not found, keeping the current icon")
if os.path.exists(os.path.join(res, "Assets.car")):  # holds the Automator icon
    os.remove(os.path.join(res, "Assets.car"))
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", TARGET], check=True)
print(TARGET)
