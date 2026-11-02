"""Install only GitHub Secrets into a temporary macOS signing keychain; clean on every exit."""
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import uuid

BUNDLE_ID = 'com.corticalabs.NecroTubeXcode'


def run(*args, capture=False):
    return subprocess.run(args, check=True, capture_output=capture, text=capture)


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def mask(value):
    print(f'::add-mask::{value}', flush=True)


def save(path, data):
    path.write_bytes(data)
    path.chmod(0o600)


def prepare(directory):
    os.umask(0o077)
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    team = os.environ['APPLE_TEAM_ID']
    key_id = os.environ['ASC_KEY_ID']
    require(re.fullmatch(r'[A-Z0-9]{10}', team), 'Invalid Apple team ID format')
    require(re.fullmatch(r'[A-Z0-9]{10}', key_id), 'Invalid App Store Connect key ID format')
    uuid.UUID(os.environ['ASC_ISSUER_ID'])
    p12 = directory / 'certificate.p12'
    profile_file = directory / 'profile.mobileprovision'
    save(p12, base64.b64decode(os.environ['APPLE_DISTRIBUTION_P12_BASE64'], validate=True))
    save(profile_file, base64.b64decode(os.environ['APPLE_PROVISIONING_PROFILE_BASE64'], validate=True))
    decoded = run('security', 'cms', '-D', '-i', str(profile_file), capture=True)
    profile = plistlib.loads(decoded.stdout.encode())
    expiry = profile['ExpirationDate'].replace(tzinfo=timezone.utc)
    require(expiry > datetime.now(timezone.utc), 'Provisioning profile has expired')
    require(team in profile.get('TeamIdentifier', []), 'Provisioning profile team does not match')
    entitlements = profile['Entitlements']
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    require(entitlements.get('application-identifier') in [f'{prefix}.{BUNDLE_ID}' for prefix in prefixes],
            'An explicit provisioning profile for this app is required')
    require(entitlements.get('com.apple.developer.team-identifier') == team, 'Entitlement team mismatch')
    require(entitlements.get('get-task-allow') is False, 'A distribution profile is required')
    require(not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'),
            'Use an App Store Connect distribution profile, not Ad Hoc or Enterprise')
    profile_uuid = str(uuid.UUID(profile['UUID'])).upper()
    mask(profile_uuid)
    keychain = directory / 'signing.keychain-db'
    password = os.environ['KEYCHAIN_PASSWORD']
    original = run('security', 'list-keychains', '-d', 'user', capture=True).stdout
    original_paths = re.findall(r'"([^"]+)"', original)
    save(directory / 'keychains.json', json.dumps(original_paths).encode())
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    # Permit only Apple's signing tools to access the imported key. No -A (all apps).
    run('security', 'import', str(p12), '-P', os.environ['APPLE_DISTRIBUTION_P12_PASSWORD'],
        '-k', str(keychain), '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, str(keychain))
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *original_paths)
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning', str(keychain), capture=True).stdout
    identities = re.findall(r'\b([0-9A-F]{40})\s+"Apple Distribution:[^"]+"', identities)
    allowed = {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
    matches = [identity for identity in identities if identity in allowed]
    require(len(matches) == 1, 'Expected one valid Apple Distribution identity matching the profile and private key')
    identity = matches[0]
    mask(identity)
    # Xcode 27 uses this directory for user-installed provisioning profiles.
    profile_directory = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
    profile_directory.mkdir(parents=True, exist_ok=True)
    installed_profile = profile_directory / f'{profile_uuid}.mobileprovision'
    require(not installed_profile.exists(), 'Refusing to replace an existing provisioning profile')
    save(directory / 'installed-profile.txt', str(installed_profile).encode())
    save(installed_profile, profile_file.read_bytes())
    private_keys = directory / 'private_keys'
    private_keys.mkdir(mode=0o700)
    key = private_keys / f'AuthKey_{key_id}.p8'
    save(key, os.environ['ASC_PRIVATE_KEY_P8'].encode())
    run('openssl', 'pkey', '-in', str(key), '-check', '-noout', capture=True)
    export = {
        'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
        'teamID': team, 'signingCertificate': identity,
        'provisioningProfiles': {BUNDLE_ID: profile_uuid},
        'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True,
    }
    save(directory / 'ExportOptions.plist', plistlib.dumps(export))
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf8') as env:
        env.write(f'SIGNING_IDENTITY={identity}\nPROFILE_UUID={profile_uuid}\n')
    p12.unlink()
    print('Distribution identity and provisioning profile validated; temporary signing prepared.')


def cleanup(directory):
    if not directory.exists():
        return
    failures = []
    keychains = directory / 'keychains.json'
    if keychains.exists():
        result = subprocess.run(['security', 'list-keychains', '-d', 'user', '-s',
                                 *json.loads(keychains.read_text())])
        if result.returncode:
            failures.append('Could not restore keychain search list')
    keychain = directory / 'signing.keychain-db'
    if keychain.exists():
        result = subprocess.run(['security', 'delete-keychain', str(keychain)])
        if result.returncode:
            failures.append('Could not delete temporary keychain')
    installed = directory / 'installed-profile.txt'
    if installed.exists():
        Path(installed.read_text()).unlink(missing_ok=True)
    shutil.rmtree(directory)
    require(not failures, '; '.join(failures))
    print('Temporary signing credentials removed.')


if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in ('prepare', 'cleanup'):
        raise SystemExit('Usage: signing.py prepare|cleanup')
    task_directory = Path(os.environ['RUNNER_TEMP']) / 'necrotube-signing'
    if sys.argv[1] == 'prepare':
        prepare(task_directory)
    else:
        cleanup(task_directory)
