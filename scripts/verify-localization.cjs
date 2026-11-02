// Source/resource audit only. Run: node scripts/verify-localization.cjs
// This does not replace plutil, an Xcode build or device permission tests.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const languages = ['fr', 'en', 'es', 'de', 'it', 'pt', 'ja', 'km', 'zh', 'ar', 'ro'];
const privacyKeys = ['NSCameraUsageDescription', 'NSMicrophoneUsageDescription', 'NSPhotoLibraryAddUsageDescription'];

function parseStrings(file) {
    const text = read(file).replace(/\/\*[\s\S]*?\*\//g, '');
    const pair = /\s*("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;/gy;
    const result = new Map();
    let position = 0;
    while (text.slice(position).trim()) {
        pair.lastIndex = position;
        const match = pair.exec(text);
        assert(match, `${file}: invalid strings syntax at ${position}`);
        const key = JSON.parse(match[1]);
        const value = JSON.parse(match[2]);
        assert(!result.has(key), `${file}: duplicate key ${key}`);
        assert(value.trim(), `${file}: empty value ${key}`);
        assert(!value.includes('\uFFFD'), `${file}: invalid Unicode ${key}`);
        assert(!/[\u00C2\u00C3][\u0080-\u00BF]/u.test(value), `${file}: possible encoding corruption ${key}`);
        result.set(key, value);
        position = pair.lastIndex;
    }
    return result;
}

const files = new Map();
for (const language of languages) {
    const directory = `NecroTubeXcode/Resources/${language}.lproj`;
    files.set(language, {
        ui: parseStrings(`${directory}/Localizable.strings`),
        info: parseStrings(`${directory}/InfoPlist.strings`),
    });
}
const english = files.get('en');
const placeholders = text => text.match(/%(?:\d+\$)?[@difgus]/g) ?? [];
for (const [language, { ui, info }] of files) {
    assert.deepEqual([...ui.keys()].sort(), [...english.ui.keys()].sort(), `${language}: UI key mismatch`);
    assert.deepEqual([...info.keys()].sort(), [...privacyKeys].sort(), `${language}: privacy key mismatch`);
    for (const [key, value] of ui) {
        assert.deepEqual(placeholders(value), placeholders(english.ui.get(key)), `${language}: placeholders for ${key}`);
    }
    if (language !== 'en') {
        for (const key of privacyKeys) assert.notEqual(info.get(key), english.info.get(key), `${language}: untranslated privacy key`);
    }
    const lexicon = `NecroTubeXcode/Resources/Lexicons/${language === 'ar' ? 'words_ar' : language}.txt`;
    assert(read(lexicon).trim(), `${language}: missing or empty lexicon`);
    console.log(`${language}: ${ui.size} UI keys, ${info.size} purpose strings, lexicon present; OK`);
}

const appLanguage = read('NecroTubeXcode/Core/Models/AppLanguage.swift');
const enumLanguages = [...appLanguage.matchAll(/\b\w+ = "([a-z]{2})"/g)].map(match => match[1]);
assert.deepEqual(enumLanguages.sort(), [...languages].sort(), 'AppLanguage and resources differ');
const resourceLanguages = fs.readdirSync(path.join(root, 'NecroTubeXcode/Resources'))
    .filter(name => name.endsWith('.lproj')).map(name => name.slice(0, -6));
assert.deepEqual(resourceLanguages.sort(), [...languages].sort(), 'Unexpected or missing localization folders');

const project = read('NecroTubeXcode.xcodeproj/project.pbxproj');
const knownRegions = project.match(/knownRegions = \(([\s\S]*?)\);/)[1].match(/\b[a-zA-Z]+\b/g);
assert.deepEqual(knownRegions.filter(region => region !== 'Base').sort(), [...languages].sort());
assert(project.includes('developmentRegion = en;'), 'English development fallback missing');
assert(project.includes('isa = PBXFileSystemSynchronizedRootGroup;'), 'Review resource target integration');
assert(project.includes('fileSystemSynchronizedGroups = ('), 'Synchronized group is not attached to target');
assert(!project.includes('membershipExceptions'), 'Review synchronized group exclusions');

const configurations = [...project.matchAll(/\/\* (Debug|Release) configuration for PBXNativeTarget "NecroTubeXcode" \*\/ = \{[\s\S]*?buildSettings = \{([\s\S]*?)\n\t\t\t\};/g)];
assert.equal(configurations.length, 2, 'Expected main target Debug and Release configurations');
for (const [, name, settings] of configurations) {
    assert(/MARKETING_VERSION = 1\.1;/.test(settings), `${name}: version must be 1.1`);
    assert(/CURRENT_PROJECT_VERSION = 3;/.test(settings), `${name}: build must be 3`);
    assert(settings.includes('GENERATE_INFOPLIST_FILE = YES;'));
    assert(settings.includes('INFOPLIST_KEY_UIPrefersShowingLanguageSettings = YES;'), `${name}: language settings visibility missing`);
    for (const key of privacyKeys) {
        const match = settings.match(new RegExp(`INFOPLIST_KEY_${key} = ("[^"\r\n]*");`));
        assert(match, `${name}: missing ${key}`);
        assert.equal(JSON.parse(match[1]), english.info.get(key), `${name}: inconsistent English fallback ${key}`);
    }
}

function swiftFiles(directory) {
    return fs.readdirSync(path.join(root, directory), { withFileTypes: true }).flatMap(entry => {
        const file = `${directory}/${entry.name}`;
        return entry.isDirectory() ? swiftFiles(file) : file.endsWith('.swift') ? [file] : [];
    });
}
const invariantLabels = new Set(['NecroTube', 'EVP', ' \u00B5T']);
let localizedCalls = 0;
for (const file of swiftFiles('NecroTubeXcode')) {
    const source = read(file);
    for (const match of source.matchAll(/String\(localized:\s*("(?:[^"\\]|\\.)*")/g)) {
        const key = JSON.parse(match[1]);
        assert(english.ui.has(key), `${file}: missing localized key ${key}`);
        localizedCalls++;
    }
    // Interpolations, dynamic labels and framework-generated strings require manual review.
    for (const match of source.matchAll(/\b(?:Text|Button|Label|Toggle|ContentUnavailableView|accessibilityLabel|alert|confirmationDialog|navigationTitle)\(\s*("(?:[^"\\]|\\.)*")/g)) {
        if (match[1].includes('\\(')) continue;
        const key = JSON.parse(match[1]);
        if (!key || invariantLabels.has(key)) continue;
        assert(english.ui.has(key), `${file}: missing static UI key ${key}`);
    }
}
console.log(`Main target Debug/Release: 1.1 (3); regions, fallbacks and ${localizedCalls} localized calls OK.`);
console.log('Static audit passed. Xcode compilation, archived bundle inspection and iPhone tests are still required.');
