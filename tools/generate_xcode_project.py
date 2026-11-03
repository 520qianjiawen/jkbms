"""Generate a clean, standalone iOS Xcode project for JKBMS."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]

def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)

def main():
    objects = []
    def obj(name, body):
        key = identifier(name)
        objects.append(f'{key} = {{ {body} }};')
        return key

    references, source_builds, resource_builds = [], [], []

    # Sources
    for path in sorted((ROOT / 'Sources').rglob('*.swift')):
        relative = str(path.relative_to(ROOT))
        ref = obj('file:' + relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;')
        references.append(ref)
        source_builds.append(obj('build:' + relative, f'isa = PBXBuildFile; fileRef = {ref};'))

    # Resources
    res_items = [
        ('Assets.xcassets', 'folder.assetcatalog'),
        ('PrivacyInfo.xcprivacy', 'text.xml'),
        ('Sources/JKBMSCore/Resources/original', 'folder')
    ]
    for relative, kind in res_items:
        p = ROOT / relative
        if p.exists():
            ref = obj('file:' + relative, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;')
            references.append(ref)
            resource_builds.append(obj('build:' + relative, f'isa = PBXBuildFile; fileRef = {ref};'))

    product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "JKBMS.app"; sourceTree = BUILT_PRODUCTS_DIR;')
    products_group = obj('products', f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
    group = obj('mainGroup', f'isa = PBXGroup; children = ({",".join(references)},{products_group},); sourceTree = "<group>";')
    sources = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(source_builds)},); runOnlyForDeploymentPostprocessing = 0;')
    resources = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0;')
    frameworks = obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')

    common = '''
        ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
        CODE_SIGN_STYLE = Automatic;
        CURRENT_PROJECT_VERSION = 237;
        GENERATE_INFOPLIST_FILE = YES;
        INFOPLIST_KEY_CFBundleDisplayName = "极空BMS原生版";
        INFOPLIST_KEY_CFBundleIdentifier = "com.cavon.jkbms.native";
        INFOPLIST_KEY_CFBundleShortVersionString = "0.2.3";
        INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "极空BMS使用蓝牙连接您的电池管理系统，进行数据采集和参数配置";
        INFOPLIST_KEY_NSBluetoothPeripheralUsageDescription = "极空BMS使用蓝牙连接您的电池管理系统，进行数据采集和参数配置";
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
        INFOPLIST_KEY_UILaunchScreen_Generation = YES;
        INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
        INFOPLIST_KEY_UIUserInterfaceStyle = Dark;
        IPHONEOS_DEPLOYMENT_TARGET = 17.0;
        MARKETING_VERSION = 0.2.3;
        PRODUCT_BUNDLE_IDENTIFIER = "com.cavon.jkbms.native";
        PRODUCT_NAME = JKBMS;
        SDKROOT = iphoneos;
        SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
        SUPPORTS_MACCATALYST = NO;
        SWIFT_VERSION = 5.0;
        TARGETED_DEVICE_FAMILY = "1,2";
    '''

    project_configurations, target_configurations = [], []
    for name in ['Debug', 'Release']:
        debug = name == 'Debug'
        project_configurations.append(obj('project:' + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; }};'))
        settings = common.strip() + (' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; DEBUG_INFORMATION_FORMAT = dwarf;' if debug else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; SWIFT_COMPILATION_MODE = wholemodule; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
        target_configurations.append(obj('target:' + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ {settings} }};'))

    project_list = obj('projectConfigurationList', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configurations)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target_list = obj('targetConfigurationList', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configurations)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {target_list}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = JKBMS; productName = JKBMS; productReference = {product}; productType = "com.apple.product-type.application";')

    project = obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en, Base, "zh-Hans",); mainGroup = {group}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')

    destination = ROOT / 'JKBMS.xcodeproj'
    destination.mkdir(exist_ok=True)
    (destination / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n    archiveVersion = 1;\n    classes = {};\n    objectVersion = 56;\n    objects = {\n' + '\n'.join(objects) + f'\n    }};\n    rootObject = {project};\n}}\n', encoding='utf-8')

    scheme_dir = destination / 'xcshareddata/xcschemes'
    scheme_dir.mkdir(parents=True, exist_ok=True)
    buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="JKBMS.app" BlueprintName="JKBMS" ReferencedContainer="container:JKBMS.xcodeproj"/>'
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
    (scheme_dir / 'JKBMS.xcscheme').write_text(scheme, encoding='utf-8')
    print(f"Generated {destination}")

if __name__ == '__main__':
    main()
