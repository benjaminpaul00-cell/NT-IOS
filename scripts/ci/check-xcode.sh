#!/bin/bash
set -euo pipefail

# The hosted xcode-27 image supplies the selected, stable Xcode 27 toolchain.
# Fail instead of silently lowering the app's deployment target or using a beta.
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
python3 - <<'PY'
import re
import subprocess

version = subprocess.check_output(['xcodebuild', '-version'], text=True)
match = re.search(r'^Xcode (\d+)(?:\.(\d+))?', version)
if not match or int(match[1]) != 27 or re.search(r'beta|release candidate|\bRC\b', version, re.I):
    raise SystemExit('Stable Xcode 27 is required; the project is not downgraded by CI.')
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], text=True).strip()
if int(sdk.split('.')[0]) < 27:
    raise SystemExit('An iOS 27 or later SDK is required.')
print('Compatible Xcode/iOS SDK selected.')
PY
