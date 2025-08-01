#!/usr/bin/env python3

import os
import uuid
from pathlib import Path

# Project paths
PROJECT_ROOT = "/Users/a/Desktop/projects/Reverb"
PROJECT_FILE = f"{PROJECT_ROOT}/Reverb.xcodeproj/project.pbxproj"

def generate_uuid():
    """Generate a unique ID for Xcode project entries"""
    return ''.join(str(uuid.uuid4()).upper().split('-'))[:24]

def create_minimal_working_project():
    """Create a minimal working project with only essential files"""
    
    print("🔧 Creating minimal working Reverb project...")
    
    # Only include files that actually exist and are essential
    essential_files = [
        "Reverb/ReverbApp.swift",
        "Reverb/ContentView.swift", 
        "Reverb/CustomReverbView.swift",
        "Reverb/RecordingHistory.swift",
        "Reverb/Audio/AudioManager.swift",
        "Reverb/Audio/Services/AudioEngineService.swift",
        "Reverb/Audio/Services/RecordingService.swift",
        "Reverb/Audio/Models/CustomReverbSettings.swift",
        "Reverb/Audio/Models/ReverbPreset.swift"
    ]
    
    # Generate UUIDs for all components
    uuids = {}
    components = [
        'PROJECT', 'ROOT_GROUP', 'REVERB_GROUP', 'PRODUCTS_GROUP', 'PREVIEW_CONTENT_GROUP',
        'AUDIO_GROUP', 'MODELS_GROUP', 'SERVICES_GROUP',
        'TARGET', 'SOURCES_PHASE', 'RESOURCES_PHASE', 'FRAMEWORKS_PHASE',
        'PROJECT_CONFIG_LIST', 'TARGET_CONFIG_LIST',
        'DEBUG_CONFIG', 'RELEASE_CONFIG', 'TARGET_DEBUG_CONFIG', 'TARGET_RELEASE_CONFIG',
        'APP_REF', 'INFO_PLIST_REF', 'ASSETS_REF', 'PREVIEW_ASSETS_REF'
    ]
    
    for component in components:
        uuids[component] = generate_uuid()
    
    # Generate UUIDs for files
    file_uuids = {}
    build_uuids = {}
    for file_path in essential_files:
        filename = os.path.basename(file_path)
        file_uuids[filename] = generate_uuid()
        if filename.endswith('.swift'):
            build_uuids[filename] = generate_uuid()
    
    # Add resource files
    file_uuids['Assets.xcassets'] = uuids['ASSETS_REF']
    file_uuids['Preview Assets.xcassets'] = uuids['PREVIEW_ASSETS_REF']
    file_uuids['Info.plist'] = uuids['INFO_PLIST_REF']
    
    build_uuids['Assets.xcassets'] = generate_uuid()
    build_uuids['Preview Assets.xcassets'] = generate_uuid()
    
    # Create minimal project content
    project_content = f'''// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
'''
    
    # Add build files
    for filename in essential_files:
        name = os.path.basename(filename)
        if name.endswith('.swift'):
            project_content += f'\t\t{build_uuids[name]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuids[name]} /* {name} */; }};\n'
    
    project_content += f'\t\t{build_uuids["Assets.xcassets"]} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {file_uuids["Assets.xcassets"]} /* Assets.xcassets */; }};\n'
    project_content += f'\t\t{build_uuids["Preview Assets.xcassets"]} /* Preview Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {file_uuids["Preview Assets.xcassets"]} /* Preview Assets.xcassets */; }};\n'
    
    project_content += '''/* End PBXBuildFile section */

/* Begin PBXFileReference section */
'''
    
    # Add file references
    for file_path in essential_files:
        filename = os.path.basename(file_path)
        project_content += f'\t\t{file_uuids[filename]} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'
    
    project_content += f'\t\t{file_uuids["Assets.xcassets"]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};\n'
    project_content += f'\t\t{file_uuids["Preview Assets.xcassets"]} /* Preview Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Preview Assets.xcassets"; sourceTree = "<group>"; }};\n'
    project_content += f'\t\t{file_uuids["Info.plist"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};\n'
    project_content += f'\t\t{uuids["APP_REF"]} /* Reverb.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Reverb.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
    
    project_content += f'''/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{uuids["FRAMEWORKS_PHASE"]} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{uuids["ROOT_GROUP"]} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{uuids["REVERB_GROUP"]} /* Reverb */,
\t\t\t\t{uuids["PRODUCTS_GROUP"]} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{uuids["REVERB_GROUP"]} /* Reverb */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{file_uuids["ReverbApp.swift"]} /* ReverbApp.swift */,
\t\t\t\t{file_uuids["ContentView.swift"]} /* ContentView.swift */,
\t\t\t\t{file_uuids["CustomReverbView.swift"]} /* CustomReverbView.swift */,
\t\t\t\t{file_uuids["RecordingHistory.swift"]} /* RecordingHistory.swift */,
\t\t\t\t{uuids["AUDIO_GROUP"]} /* Audio */,
\t\t\t\t{file_uuids["Info.plist"]} /* Info.plist */,
\t\t\t\t{file_uuids["Assets.xcassets"]} /* Assets.xcassets */,
\t\t\t\t{uuids["PREVIEW_CONTENT_GROUP"]} /* Preview Content */,
\t\t\t);
\t\t\tpath = Reverb;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{uuids["AUDIO_GROUP"]} /* Audio */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{uuids["MODELS_GROUP"]} /* Models */,
\t\t\t\t{uuids["SERVICES_GROUP"]} /* Services */,
\t\t\t\t{file_uuids["AudioManager.swift"]} /* AudioManager.swift */,
\t\t\t);
\t\t\tpath = Audio;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{uuids["MODELS_GROUP"]} /* Models */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{file_uuids["CustomReverbSettings.swift"]} /* CustomReverbSettings.swift */,
\t\t\t\t{file_uuids["ReverbPreset.swift"]} /* ReverbPreset.swift */,
\t\t\t);
\t\t\tpath = Models;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{uuids["SERVICES_GROUP"]} /* Services */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{file_uuids["AudioEngineService.swift"]} /* AudioEngineService.swift */,
\t\t\t\t{file_uuids["RecordingService.swift"]} /* RecordingService.swift */,
\t\t\t);
\t\t\tpath = Services;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{uuids["PRODUCTS_GROUP"]} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{uuids["APP_REF"]} /* Reverb.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{uuids["PREVIEW_CONTENT_GROUP"]} /* Preview Content */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{file_uuids["Preview Assets.xcassets"]} /* Preview Assets.xcassets */,
\t\t\t);
\t\t\tpath = "Preview Content";
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{uuids["TARGET"]} /* Reverb */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {uuids["TARGET_CONFIG_LIST"]} /* Build configuration list for PBXNativeTarget "Reverb" */;
\t\t\tbuildPhases = (
\t\t\t\t{uuids["SOURCES_PHASE"]} /* Sources */,
\t\t\t\t{uuids["FRAMEWORKS_PHASE"]} /* Frameworks */,
\t\t\t\t{uuids["RESOURCES_PHASE"]} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Reverb;
\t\t\tproductName = Reverb;
\t\t\tproductReference = {uuids["APP_REF"]} /* Reverb.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{uuids["PROJECT"]} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1620;
\t\t\t\tLastUpgradeCheck = 1620;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{uuids["TARGET"]} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {uuids["PROJECT_CONFIG_LIST"]} /* Build configuration list for PBXProject "Reverb" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {uuids["ROOT_GROUP"]};
\t\t\tproductRefGroup = {uuids["PRODUCTS_GROUP"]} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{uuids["TARGET"]} /* Reverb */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{uuids["RESOURCES_PHASE"]} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{build_uuids["Preview Assets.xcassets"]} /* Preview Assets.xcassets in Resources */,
\t\t\t\t{build_uuids["Assets.xcassets"]} /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{uuids["SOURCES_PHASE"]} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
'''
    
    # Add sources
    for file_path in essential_files:
        filename = os.path.basename(file_path)
        if filename.endswith('.swift'):
            project_content += f'\t\t\t\t{build_uuids[filename]} /* {filename} in Sources */,\n'
    
    project_content += f'''\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{uuids["DEBUG_CONFIG"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++17";
\t\t\t\tCLANG_CXX_LIBRARY = "libc++";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{uuids["RELEASE_CONFIG"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++17";
\t\t\t\tCLANG_CXX_LIBRARY = "libc++";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{uuids["TARGET_DEBUG_CONFIG"]} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "\"Reverb/Preview Content\"";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Reverb/Info.plist;
\t\t\t\tINFOPLIST_KEY_NSMicrophoneUsageDescription = "Cette application a besoin d'accéder au microphone pour traiter votre voix avec des effets de réverbération en temps réel.";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.quran.Reverb;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{uuids["TARGET_RELEASE_CONFIG"]} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "\"Reverb/Preview Content\"";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = Reverb/Info.plist;
\t\t\t\tINFOPLIST_KEY_NSMicrophoneUsageDescription = "Cette application a besoin d'accéder au microphone pour traiter votre voix avec des effets de réverbération en temps réel.";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.quran.Reverb;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{uuids["TARGET_CONFIG_LIST"]} /* Build configuration list for PBXNativeTarget "Reverb" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{uuids["TARGET_DEBUG_CONFIG"]} /* Debug */,
\t\t\t\t{uuids["TARGET_RELEASE_CONFIG"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{uuids["PROJECT_CONFIG_LIST"]} /* Build configuration list for PBXProject "Reverb" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{uuids["DEBUG_CONFIG"]} /* Debug */,
\t\t\t\t{uuids["RELEASE_CONFIG"]} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {uuids["PROJECT"]} /* Project object */;
}}
'''
    
    return project_content

def main():
    """Main function to create minimal working project"""
    print("🔧 Creating minimal working Reverb project...")
    print("=" * 60)
    
    # Create backup
    backup_path = f"{PROJECT_FILE}.minimal_backup"
    with open(PROJECT_FILE, 'r') as src:
        content = src.read()
    with open(backup_path, 'w') as dst:
        dst.write(content)
    print(f"✅ Backed up to {backup_path}")
    
    # Create minimal project
    minimal_content = create_minimal_working_project()
    
    # Write minimal project
    with open(PROJECT_FILE, 'w') as f:
        f.write(minimal_content)
    
    print("✅ Created minimal working project!")
    print("=" * 60)
    print("📱 Project contains only essential files:")
    print("  • ReverbApp.swift")
    print("  • ContentView.swift")
    print("  • CustomReverbView.swift")  
    print("  • RecordingHistory.swift")
    print("  • AudioManager.swift")
    print("  • AudioEngineService.swift")
    print("  • RecordingService.swift")
    print("  • CustomReverbSettings.swift")
    print("  • ReverbPreset.swift")
    print("")
    print("🎯 This should build successfully!")
    print("💡 You can add more files later once the base builds")

if __name__ == "__main__":
    main()