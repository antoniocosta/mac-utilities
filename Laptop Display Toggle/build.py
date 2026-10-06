"""Build 'Laptop Display Toggle.app' as an Automator application (Run Shell Script ->
Run AppleScript alert) from app.sh, in place: the existing app
beside this script is the skeleton (stub, Info.plist, AppleScript action)."""
import os, plistlib, shutil, subprocess, uuid

import tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(HERE, "Laptop Display Toggle.app")
SKELETON = os.path.join(tempfile.mkdtemp(), "skeleton.app")
shutil.copytree(TARGET, SKELETON)
SCRIPT = os.path.join(HERE, "app.sh")

shutil.rmtree(TARGET, ignore_errors=True)
c = os.path.join(TARGET, "Contents")
os.makedirs(os.path.join(c, "MacOS"))
os.makedirs(os.path.join(c, "Resources"))
shutil.copy2(os.path.join(SKELETON, "Contents/MacOS/Automator Application Stub"), os.path.join(c, "MacOS"))
for f in ["ApplicationStub.icns", "InfoPlist.loctable"]:
    shutil.copy2(os.path.join(SKELETON, "Contents/Resources", f), os.path.join(c, "Resources"))

with open(os.path.join(SKELETON, "Contents/Info.plist"), "rb") as f:
    info = plistlib.load(f)
info["CFBundleIdentifier"] = "com.apple.automator.Laptop-Display-Toggle"
info["CFBundleName"] = "Laptop Display Toggle"
info["CFBundleShortVersionString"] = "1.0"
with open(os.path.join(c, "Info.plist"), "wb") as f:
    plistlib.dump(info, f)

with open(SCRIPT) as f:
    command = f.read()

A = "/System/Library/Automator/Run Shell Script.action"
action = {
    "AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.string"]},
    "AMActionVersion": "2.0.3",
    "AMApplication": ["Automator"],
    "AMParameterProperties": {k: {} for k in
                              ["COMMAND_STRING", "CheckedForUserDefaultShell", "inputMethod", "shell", "source"]},
    "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
    "ActionBundlePath": A,
    "ActionName": "Run Shell Script",
    "ActionParameters": {
        "COMMAND_STRING": command,
        "CheckedForUserDefaultShell": True,
        "inputMethod": 1,  # pass input as arguments
        "shell": "/bin/bash",
        "source": "",
    },
    "BundleIdentifier": "com.apple.RunShellScript",
    "CFBundleVersion": "2.0.3",
    "CanShowSelectedItemsWhenRun": False,
    "CanShowWhenRun": True,
    "Category": ["AMCategoryUtilities"],
    "Class Name": "RunShellScriptAction",
    "InputUUID": str(uuid.uuid4()).upper(),
    "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
    "OutputUUID": str(uuid.uuid4()).upper(),
    "UUID": str(uuid.uuid4()).upper(),
    "UnlocalizedApplications": ["Automator"],
    "arguments": {
        "0": {"default value": 0, "name": "inputMethod", "required": "0", "type": "0", "uuid": "0"},
        "1": {"default value": False, "name": "CheckedForUserDefaultShell", "required": "0", "type": "0", "uuid": "1"},
        "2": {"default value": "", "name": "source", "required": "0", "type": "0", "uuid": "2"},
        "3": {"default value": "", "name": "COMMAND_STRING", "required": "0", "type": "0", "uuid": "3"},
        "4": {"default value": "/bin/sh", "name": "shell", "required": "0", "type": "0", "uuid": "4"},
    },
    "conversionLabel": 0,
    "isViewVisible": 1,
    "location": "309.000000:600.000000",
    "nibPath": A + "/Contents/Resources/Base.lproj/main.nib",
}
wflow = {
    "AMApplicationBuild": "526",
    "AMApplicationVersion": "2.10",
    "AMDocumentVersion": "2",
    "actions": [{"action": action, "isViewVisible": 1}],
    "connectors": {},
    "workflowMetaData": {"workflowTypeIdentifier": "com.apple.Automator.application"},
}

# Second action: show the shell script's output as an alert. Shown by the app
# itself, so the alert carries the app's icon.
with open(os.path.join(SKELETON, "Contents/document.wflow"), "rb") as f:
    applescript = next(a["action"] for a in plistlib.load(f)["actions"]
                       if a["action"]["ActionName"] == "Run AppleScript")
applescript["ActionParameters"]["source"] = (
    'on run {input, parameters}\n'
    '\tset AppleScript\'s text item delimiters to linefeed\n'
    '\tset msg to (input as text)\n'
    '\tif msg is not "" then\n'
    '\t\tactivate\n'
    '\t\tdisplay alert "Laptop Display Toggle" message msg\n'
    '\tend if\n'
    '\treturn input\n'
    'end run')
applescript["InputUUID"] = str(uuid.uuid4()).upper()
applescript["OutputUUID"] = str(uuid.uuid4()).upper()
applescript["UUID"] = str(uuid.uuid4()).upper()
applescript["location"] = "309.000000:900.000000"
wflow["actions"].append({"action": applescript, "isViewVisible": 1})
wflow["connectors"][str(uuid.uuid4()).upper()] = {
    "from": "%s - %s" % (action["UUID"], action["UUID"]),
    "to": "%s - %s" % (applescript["UUID"], applescript["UUID"]),
}

# App icon: a MacBook (also used by the alert).
ICON = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/com.apple.macbookpro-16-2021-space-gray.icns"
shutil.copyfile(ICON, os.path.join(c, "Resources", "ApplicationStub.icns"))
info.pop("CFBundleIconName", None)
with open(os.path.join(c, "Info.plist"), "wb") as f:
    plistlib.dump(info, f)
with open(os.path.join(c, "document.wflow"), "wb") as f:
    plistlib.dump(wflow, f)

subprocess.run(["codesign", "--force", "--deep", "--sign", "-", TARGET], check=True)
print(TARGET)
