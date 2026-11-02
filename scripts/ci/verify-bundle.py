"""Check the actual iOS app produced by Xcode, including localized purpose strings."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def read_plist(file):
    with file.open('rb') as stream:
        try:
            return plistlib.load(stream)
        except plistlib.InvalidFileException:
            pass
    # Xcode may retain OpenStep .strings instead of writing binary plists.
    return json.loads(subprocess.check_output(
        ['plutil', '-convert', 'json', '-o', '-', str(file)], text=True))


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def verify(app):
    info = read_plist(app / 'Info.plist')
    require(info.get('CFBundleShortVersionString') == '1.1', 'Unexpected marketing version')
    require(info.get('CFBundleVersion') == '3', 'Unexpected build number')
    require(info.get('CFBundleIdentifier') == 'com.corticalabs.NecroTubeXcode', 'Unexpected bundle ID')
    require(info.get('CFBundleDevelopmentRegion') == 'en', 'English development fallback missing')
    require(info.get('UIPrefersShowingLanguageSettings') is True, 'Language setting must be a true boolean')
    languages = ('fr', 'en', 'es', 'de', 'it', 'pt', 'ja', 'km', 'zh', 'ar', 'ro')
    keys = ('NSCameraUsageDescription', 'NSMicrophoneUsageDescription', 'NSPhotoLibraryAddUsageDescription')
    tables = {}
    for language in languages:
        directory = app / f'{language}.lproj'
        tables[language] = read_plist(directory / 'Localizable.strings')
        privacy = read_plist(directory / 'InfoPlist.strings')
        require(set(privacy) >= set(keys), f'{language}: missing privacy descriptions in built bundle')
        for key in keys:
            require(bool(privacy[key].strip()), f'{language}: empty {key}')
            if language == 'en':
                require(info.get(key) == privacy[key], f'English plist fallback mismatch: {key}')
        lexicon = 'words_ar' if language == 'ar' else language
        require((app / f'{lexicon}.txt').is_file(), f'Missing bundled lexicon: {language}')
    for language, table in tables.items():
        require(set(table) == set(tables['en']), f'{language}: localized UI key mismatch in built bundle')
    require(len(tables['en']) >= 146, 'Expected all localization corrections in the built app')
    require((app / info['CFBundleExecutable']).is_file(), 'App executable missing')
    print('Built bundle verified: NecroTube 1.1 (3), 11 localizations, permissions and lexicons.')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: verify-bundle.py /path/to/NecroTubeXcode.app')
    verify(Path(sys.argv[1]))
