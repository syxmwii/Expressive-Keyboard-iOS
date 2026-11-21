"""Regenerate the checked-in Xcode project using Python's standard library."""
from pathlib import Path
import hashlib
import json
import plistlib
import struct
import zlib

root = Path(__file__).resolve().parents[1]
project = root / 'ExpressiveKeyboard.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}
def oid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(identifier, isa, **fields):
    ident = oid(identifier)
    assert ident not in objects, identifier
    objects[ident] = dict(isa=isa, **fields)
    return ident

def ref(path, file_type, source='SOURCE_ROOT'):
    return add(path, 'PBXFileReference', lastKnownFileType=file_type, name=Path(path).name,
               path=path, sourceTree=source)

app = add('application-product', 'PBXFileReference', explicitFileType='wrapper.application',
          includeInIndex=0, path='ExpressiveKeyboard.app', sourceTree='BUILT_PRODUCTS_DIR')
extension = add('extension-product', 'PBXFileReference', explicitFileType='wrapper.app-extension',
                includeInIndex=0, path='ExpressiveExtension.appex', sourceTree='BUILT_PRODUCTS_DIR')
sourcepaths = {part: sorted(str(p.relative_to(root)) for p in (root/part).glob('*.swift'))
               for part in ('Shared', 'App', 'Keyboard')}
sourcepaths['Runtime'] = ['Runtime/Bridge.c'] + sorted(str(p.relative_to(root)) for p in (root/'Runtime/quickjs').glob('*.c'))
sourcefiles = {path: ref(path, 'sourcecode.c.c' if path.endswith('.c') else 'sourcecode.swift')
               for paths in sourcepaths.values() for path in paths}
resource_folder = ref('KeyboardData', 'folder')
assets = ref('App/Assets.xcassets', 'folder.assetcatalog')
header = ref('Runtime/Bridge.h', 'sourcecode.c.h')
products = add('products', 'PBXGroup', name='Products', sourceTree='<group>', children=[app, extension])
groups = [add('group-' + part, 'PBXGroup', name=part, sourceTree='<group>',
              children=[sourcefiles[p] for p in paths] + ([header] if part == 'Runtime' else []) + ([assets] if part == 'App' else []))
          for part, paths in sourcepaths.items()]
main = add('main-group', 'PBXGroup', sourceTree='<group>', children=groups + [resource_folder, products])

def phase(target, role, files, **fields):
    sources = [add(target + role + file, 'PBXBuildFile', fileRef=file) for file in files]
    return add(target + role, 'PBX' + role + 'BuildPhase', buildActionMask=2147483647,
               files=sources, runOnlyForDeploymentPostprocessing=0, **fields)

def configs(target, settings):
    ids = []
    for name in ('Debug', 'Release'):
        flags = settings.copy()
        if target == 'project':
            flags.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if name == 'Debug' else '-O',
                         DEBUG_INFORMATION_FORMAT='dwarf' if name == 'Debug' else 'dwarf-with-dsym',
                         GCC_OPTIMIZATION_LEVEL=0 if name == 'Debug' else 's')
            if name == 'Debug':
                flags['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
                flags['ENABLE_TESTABILITY'] = 'YES'
        ids.append(add(target + name, 'XCBuildConfiguration', buildSettings=flags, name=name))
    return add(target + 'config-list', 'XCConfigurationList', buildConfigurations=ids,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

sdk = configs('project', dict(
    SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='17.0', TARGETED_DEVICE_FAMILY='1,2',
    SWIFT_VERSION='5.0', CLANG_ENABLE_MODULES='YES', CLANG_ENABLE_OBJC_ARC='YES',
    GCC_C_LANGUAGE_STANDARD='gnu11', CODE_SIGN_STYLE='Automatic', CURRENT_PROJECT_VERSION=3,
    MARKETING_VERSION='1.0.2', EXPRESSIVE_BUNDLE_ID='org.expressive.keyboard.ios',
    EXPRESSIVE_APP_GROUP='', ENABLE_USER_SCRIPT_SANDBOXING='YES',
    SUPPORTED_PLATFORMS='iphoneos iphonesimulator', GCC_PREPROCESSOR_DEFINITIONS=['$(inherited)', 'CONFIG_VERSION=\\"2026-06-04\\"'],
    SWIFT_OBJC_BRIDGING_HEADER='Runtime/Bridge.h', OTHER_LDFLAGS=['$(inherited)', '-lsqlite3', '-lz'],
    SWIFT_ENABLE_BARE_SLASH_REGEX='YES',
))
def target_config(name, bundle, folder):
    return configs(name, dict(
        PRODUCT_NAME=name, PRODUCT_BUNDLE_IDENTIFIER=bundle, INFOPLIST_FILE=f'{folder}/Info.plist',
        GENERATE_INFOPLIST_FILE='NO',
        LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
        **(dict(ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon') if folder == 'App'
           else dict(SKIP_INSTALL='YES', APPLICATION_EXTENSION_API_ONLY='YES'))
    ))

tn_app, tn_ext = 'ExpressiveKeyboard', 'ExpressiveExtension'
embedded = add('embed-extension-buildfile', 'PBXBuildFile', fileRef=extension,
               settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
embed = add('embed-phase', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647,
            dstPath='', dstSubfolderSpec=13, files=[embedded], name='Embed App Extensions', runOnlyForDeploymentPostprocessing=0)
proxy = add('extension-proxy', 'PBXContainerItemProxy', containerPortal=oid('root-project'),
            proxyType=1, remoteGlobalIDString=oid(tn_ext), remoteInfo=tn_ext)
dependency = add('extension-dependency', 'PBXTargetDependency', target=oid(tn_ext), targetProxy=proxy)
for name, folder, product, resources, bundle, kind in (
    (tn_app, 'App', app, [assets], '$(EXPRESSIVE_BUNDLE_ID)', 'application'),
    (tn_ext, 'Keyboard', extension, [resource_folder], '$(EXPRESSIVE_BUNDLE_ID).keyboard', 'app-extension')
):
    phases = [
        phase(name, 'Sources', [sourcefiles[p] for part in (folder, 'Shared', 'Runtime') for p in sourcepaths[part]]),
        phase(name, 'Frameworks', []),
        phase(name, 'Resources', resources),
    ]
    if folder == 'App':
        phases.append(embed)
    add(name, 'PBXNativeTarget', buildConfigurationList=target_config(name, bundle, folder),
        buildPhases=phases, buildRules=[], dependencies=[dependency] if folder == 'App' else [], name=name,
        productName=name, productReference=product, productType='com.apple.product-type.' + kind)

rootid = add('root-project', 'PBXProject', attributes={
    'LastSwiftUpdateCheck': 1600, 'LastUpgradeCheck': 1600,
    'TargetAttributes': {oid(name): {'CreatedOnToolsVersion': '16.0', 'SystemCapabilities': {
        'com.apple.ApplicationGroups.iOS': {'enabled': 1}
    }} for name in (tn_app, tn_ext)}
}, buildConfigurationList=sdk, compatibilityVersion='Xcode 14.0', developmentRegion='en',
            hasScannedForEncodings=0, knownRegions=['en', 'ru', 'Base'], mainGroup=main,
            productRefGroup=products, projectDirPath='', projectRoot='', targets=[oid(tn_app), oid(tn_ext)])

def print_plist(value, level=0):
    indent = '\t' * level
    if isinstance(value, dict):
        return '{\n' + ''.join(indent+'\t'+json.dumps(key)+' = '+print_plist(x, level+1)+';\n' for key,x in value.items()) + indent + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(indent+'\t'+print_plist(x, level+1)+',\n' for x in value) + indent + ')'
    return json.dumps(value, ensure_ascii=False)

document = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=rootid)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n' + print_plist(document) + '\n')
shared_schemes = project/'xcshareddata/xcschemes'
shared_schemes.mkdir(parents=True, exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{oid(tn_app)}" BuildableName="{tn_app}.app" BlueprintName="{tn_app}" ReferencedContainer="container:{project.name}"/>'
(shared_schemes/f'{tn_app}.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
    <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
        <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries>
    </BuildAction>
    <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
        <BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable>
    </LaunchAction>
    <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
    <AnalyzeAction buildConfiguration="Debug"/>
    <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')

def plist(path, values):
    with (root/path).open('wb') as output:
        plistlib.dump(values, output)

common_info = dict(CFBundleDevelopmentRegion='$(DEVELOPMENT_LANGUAGE)', CFBundleExecutable='$(EXECUTABLE_NAME)',
                   CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)', CFBundleInfoDictionaryVersion='6.0',
                   CFBundleName='$(PRODUCT_NAME)', CFBundleDisplayName='Expressive Keyboard',
                   CFBundleShortVersionString='$(MARKETING_VERSION)', CFBundleVersion='$(CURRENT_PROJECT_VERSION)',
                   ExpressiveAppGroup='$(EXPRESSIVE_APP_GROUP)')
plist('App/Info.plist', dict(common_info, CFBundlePackageType='APPL', UILaunchScreen={},
      NSMicrophoneUsageDescription='Records dictation when you tap Record.',
      NSSpeechRecognitionUsageDescription='Converts your dictation to text.',
      UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
      **{'UISupportedInterfaceOrientations~ipad': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
                                                   'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']}))
plist('Keyboard/Info.plist', dict(common_info, CFBundlePackageType='XPC!', NSExtension={
    'NSExtensionPointIdentifier': 'com.apple.keyboard-service',
    'NSExtensionPrincipalClass': '$(PRODUCT_MODULE_NAME).KeyboardController',
    'NSExtensionAttributes': {'IsASCIICapable': True, 'PrefersRightToLeft': False, 'PrimaryLanguage': 'en-US', 'RequestsOpenAccess': True}
}))
for part in ('App', 'Keyboard'):
    plist(f'{part}/Group.entitlements', {'com.apple.security.application-groups': ['$(EXPRESSIVE_APP_GROUP)']})

app_assets = root/'App/Assets.xcassets'
icons = app_assets/'AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
(app_assets/'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2))
(icons/'Contents.json').write_text(json.dumps({'images': [{'filename': 'Icon.png', 'idiom': 'universal', 'platform': 'ios',
 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2))
rectangles = [(x, y, 93, 83, 22) for y, start, count in [(333, 228, 5), (442, 228, 5), (551, 282, 4)] for x in range(start, start+count*119, 119)]
rectangles += [(294, 660, 430, 70, 28)]
def inside(x, y, left, top, w, h, radius):
    if not left <= x <= left+w or not top <= y <= top+h:
        return False
    cx, cy = max(left+radius, min(x, left+w-radius)), max(top+radius, min(y, top+h-radius))
    return (x-cx)**2 + (y-cy)**2 <= radius**2

def pixels():
    for y in range(1024):
        row = bytearray([0])
        for x in range(1024):
            hue = (x+y) / 2048
            color = (int(60 + 86 * hue), int(37 + 53 * hue), int(112 + 91 * hue))
            if inside(x, y, 169, 270, 686, 514, 132):
                color = (206, 185, 255)
            if inside(x, y, 180, 281, 664, 492, 120):
                color = (85, 61, 145)
            if 330 <= y <= 732 and any(inside(x,y,*rect) for rect in rectangles):
                color = (250, 244, 255) if y < 650 else (232, 213, 255)
            row.extend(color)
        yield row

def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
(icons/'Icon.png').write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1024,1024,8,2,0,0,0))
 + chunk(b'IDAT', zlib.compress(b''.join(pixels()), 9)) + chunk(b'IEND', b''))
