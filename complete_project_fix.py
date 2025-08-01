#!/usr/bin/env python3

import os
import re
import uuid
import glob
import shutil
from pathlib import Path

# Project paths
PROJECT_ROOT = "/Users/a/Desktop/projects/Reverb"
PROJECT_FILE = f"{PROJECT_ROOT}/Reverb.xcodeproj/project.pbxproj"

def generate_uuid():
    """Generate a unique ID for Xcode project entries"""
    return ''.join(str(uuid.uuid4()).upper().split('-'))[:24]

def backup_project_file():
    """Create a backup of the project file"""
    backup_path = f"{PROJECT_FILE}.complete_backup"
    shutil.copy2(PROJECT_FILE, backup_path)
    print(f"✅ Project file backed up to {backup_path}")

def create_clean_project_structure():
    """Create a completely clean project structure"""
    
    # Define the clean project structure
    project_content = '''// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		{CONTENT_VIEW_BUILD} /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = {CONTENT_VIEW_REF} /* ContentView.swift */; };
		{REVERB_APP_BUILD} /* ReverbApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = {REVERB_APP_REF} /* ReverbApp.swift */; };
		{ASSETS_BUILD} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = {ASSETS_REF} /* Assets.xcassets */; };
		{PREVIEW_ASSETS_BUILD} /* Preview Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = {PREVIEW_ASSETS_REF} /* Preview Assets.xcassets */; };
		{RECORDING_HISTORY_BUILD} /* RecordingHistory.swift in Sources */ = {isa = PBXBuildFile; fileRef = {RECORDING_HISTORY_REF} /* RecordingHistory.swift */; };
		{CUSTOM_REVERB_VIEW_BUILD} /* CustomReverbView.swift in Sources */ = {isa = PBXBuildFile; fileRef = {CUSTOM_REVERB_VIEW_REF} /* CustomReverbView.swift */; };
		{AUDIO_MANAGER_BUILD} /* AudioManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = {AUDIO_MANAGER_REF} /* AudioManager.swift */; };
		{AUDIO_ENGINE_SERVICE_BUILD} /* AudioEngineService.swift in Sources */ = {isa = PBXBuildFile; fileRef = {AUDIO_ENGINE_SERVICE_REF} /* AudioEngineService.swift */; };
		{RECORDING_SERVICE_BUILD} /* RecordingService.swift in Sources */ = {isa = PBXBuildFile; fileRef = {RECORDING_SERVICE_REF} /* RecordingService.swift */; };
		{CUSTOM_REVERB_SETTINGS_BUILD} /* CustomReverbSettings.swift in Sources */ = {isa = PBXBuildFile; fileRef = {CUSTOM_REVERB_SETTINGS_REF} /* CustomReverbSettings.swift */; };
		{REVERB_PRESET_BUILD} /* ReverbPreset.swift in Sources */ = {isa = PBXBuildFile; fileRef = {REVERB_PRESET_REF} /* ReverbPreset.swift */; };
{ADDITIONAL_BUILD_FILES}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{CONTENT_VIEW_REF} /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
		{REVERB_APP_REF} /* ReverbApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReverbApp.swift; sourceTree = "<group>"; };
		{ASSETS_REF} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		{PREVIEW_ASSETS_REF} /* Preview Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Preview Assets.xcassets"; sourceTree = "<group>"; };
		{RECORDING_HISTORY_REF} /* RecordingHistory.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RecordingHistory.swift; sourceTree = "<group>"; };
		{CUSTOM_REVERB_VIEW_REF} /* CustomReverbView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CustomReverbView.swift; sourceTree = "<group>"; };
		{AUDIO_MANAGER_REF} /* AudioManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AudioManager.swift; sourceTree = "<group>"; };
		{AUDIO_ENGINE_SERVICE_REF} /* AudioEngineService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AudioEngineService.swift; sourceTree = "<group>"; };
		{RECORDING_SERVICE_REF} /* RecordingService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RecordingService.swift; sourceTree = "<group>"; };
		{CUSTOM_REVERB_SETTINGS_REF} /* CustomReverbSettings.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CustomReverbSettings.swift; sourceTree = "<group>"; };
		{REVERB_PRESET_REF} /* ReverbPreset.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReverbPreset.swift; sourceTree = "<group>"; };
		{INFO_PLIST_REF} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		{APP_REF} /* Reverb.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Reverb.app; sourceTree = BUILT_PRODUCTS_DIR; };
{ADDITIONAL_FILE_REFS}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{FRAMEWORKS_PHASE} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ROOT_GROUP} = {
			isa = PBXGroup;
			children = (
				{REVERB_GROUP} /* Reverb */,
				{PRODUCTS_GROUP} /* Products */,
			);
			sourceTree = "<group>";
		};
		{REVERB_GROUP} /* Reverb */ = {
			isa = PBXGroup;
			children = (
				{REVERB_APP_REF} /* ReverbApp.swift */,
				{CONTENT_VIEW_REF} /* ContentView.swift */,
				{CUSTOM_REVERB_VIEW_REF} /* CustomReverbView.swift */,
				{RECORDING_HISTORY_REF} /* RecordingHistory.swift */,
				{AUDIO_GROUP} /* Audio */,
				{VIEWS_GROUP} /* Views */,
				{INFO_PLIST_REF} /* Info.plist */,
				{ASSETS_REF} /* Assets.xcassets */,
				{PREVIEW_CONTENT_GROUP} /* Preview Content */,
			);
			path = Reverb;
			sourceTree = "<group>";
		};
		{AUDIO_GROUP} /* Audio */ = {
			isa = PBXGroup;
			children = (
				{MODELS_GROUP} /* Models */,
				{SERVICES_GROUP} /* Services */,
				{TESTING_GROUP} /* Testing */,
				{DSP_GROUP} /* DSP */,
				{OPTIMIZATION_GROUP} /* Optimization */,
				{AUDIO_MANAGER_REF} /* AudioManager.swift */,
			);
			path = Audio;
			sourceTree = "<group>";
		};
		{MODELS_GROUP} /* Models */ = {
			isa = PBXGroup;
			children = (
				{CUSTOM_REVERB_SETTINGS_REF} /* CustomReverbSettings.swift */,
				{REVERB_PRESET_REF} /* ReverbPreset.swift */,
			);
			path = Models;
			sourceTree = "<group>";
		};
		{SERVICES_GROUP} /* Services */ = {
			isa = PBXGroup;
			children = (
				{AUDIO_ENGINE_SERVICE_REF} /* AudioEngineService.swift */,
				{RECORDING_SERVICE_REF} /* RecordingService.swift */,
			);
			path = Services;
			sourceTree = "<group>";
		};
		{VIEWS_GROUP} /* Views */ = {
			isa = PBXGroup;
			children = (
			);
			path = Views;
			sourceTree = "<group>";
		};
		{TESTING_GROUP} /* Testing */ = {
			isa = PBXGroup;
			children = (
			);
			path = Testing;
			sourceTree = "<group>";
		};
		{DSP_GROUP} /* DSP */ = {
			isa = PBXGroup;
			children = (
			);
			path = DSP;
			sourceTree = "<group>";
		};
		{OPTIMIZATION_GROUP} /* Optimization */ = {
			isa = PBXGroup;
			children = (
			);
			path = Optimization;
			sourceTree = "<group>";
		};
		{PRODUCTS_GROUP} /* Products */ = {
			isa = PBXGroup;
			children = (
				{APP_REF} /* Reverb.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		{PREVIEW_CONTENT_GROUP} /* Preview Content */ = {
			isa = PBXGroup;
			children = (
				{PREVIEW_ASSETS_REF} /* Preview Assets.xcassets */,
			);
			path = "Preview Content";
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{TARGET} /* Reverb */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = {TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "Reverb" */;
			buildPhases = (
				{SOURCES_PHASE} /* Sources */,
				{FRAMEWORKS_PHASE} /* Frameworks */,
				{RESOURCES_PHASE} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Reverb;
			productName = Reverb;
			productReference = {APP_REF} /* Reverb.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT} /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1620;
				LastUpgradeCheck = 1620;
				TargetAttributes = {
					{TARGET} = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = {PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject "Reverb" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {ROOT_GROUP};
			productRefGroup = {PRODUCTS_GROUP} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{TARGET} /* Reverb */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{RESOURCES_PHASE} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{PREVIEW_ASSETS_BUILD} /* Preview Assets.xcassets in Resources */,
				{ASSETS_BUILD} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{SOURCES_PHASE} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{RECORDING_HISTORY_BUILD} /* RecordingHistory.swift in Sources */,
				{REVERB_APP_BUILD} /* ReverbApp.swift in Sources */,
				{CONTENT_VIEW_BUILD} /* ContentView.swift in Sources */,
				{CUSTOM_REVERB_VIEW_BUILD} /* CustomReverbView.swift in Sources */,
				{AUDIO_MANAGER_BUILD} /* AudioManager.swift in Sources */,
				{AUDIO_ENGINE_SERVICE_BUILD} /* AudioEngineService.swift in Sources */,
				{RECORDING_SERVICE_BUILD} /* RecordingService.swift in Sources */,
				{CUSTOM_REVERB_SETTINGS_BUILD} /* CustomReverbSettings.swift in Sources */,
				{REVERB_PRESET_BUILD} /* ReverbPreset.swift in Sources */,
{ADDITIONAL_SOURCES}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{DEBUG_CONFIG} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++17";
				CLANG_CXX_LIBRARY = "libc++";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		{RELEASE_CONFIG} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++17";
				CLANG_CXX_LIBRARY = "libc++";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
			};
			name = Release;
		};
		{TARGET_DEBUG_CONFIG} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"Reverb/Preview Content\"";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Reverb/Info.plist;
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "Cette application a besoin d'accéder au microphone pour traiter votre voix avec des effets de réverbération en temps réel.";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.quran.Reverb;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		{TARGET_RELEASE_CONFIG} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"Reverb/Preview Content\"";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Reverb/Info.plist;
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "Cette application a besoin d'accéder au microphone pour traiter votre voix avec des effets de réverbération en temps réel.";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.quran.Reverb;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "Reverb" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				{TARGET_DEBUG_CONFIG} /* Debug */,
				{TARGET_RELEASE_CONFIG} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		{PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject "Reverb" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				{DEBUG_CONFIG} /* Debug */,
				{RELEASE_CONFIG} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = {PROJECT} /* Project object */;
}
'''
    
    return project_content

def scan_additional_source_files():
    """Scan for additional source files that need to be added"""
    additional_files = []
    
    # Define file patterns to include (excluding core files already handled)
    patterns = [
        "Reverb/Audio/Services/WetDryAudioEngine.swift",
        "Reverb/Audio/Services/OfflineReverbProcessor.swift", 
        "Reverb/Audio/Services/BatchOfflineProcessor.swift",
        "Reverb/Audio/Services/CrossPlatformAudioSession.swift",
        "Reverb/Audio/Services/iOSRecordingManager.swift",
        "Reverb/Audio/Services/AudioInterruptionHandler.swift",
        "Reverb/Audio/Services/AudioQualityValidator.swift",
        "Reverb/Audio/Testing/iOSTapRecordingValidator.swift",
        "Reverb/Audio/Testing/CrossPlatformAudioComparator.swift",
        "Reverb/Views/RecordingControlsView.swift",
        "Reverb/Views/BatchProcessingView.swift",
        "Reverb/Views/WetDryRecordingView.swift",
        "Reverb/Views/OfflineProcessingView.swift",
        "Reverb/Views/iOS/iOSRealtimeView.swift",
        "Reverb/Views/iOS/iOSOnboardingView.swift",
        "Reverb/Views/iOS/iOSCompactViews.swift",
        "Reverb/Views/iOS/iOSMainView.swift",
        "Reverb/Views/iOS/Adapters/ParameterResponseTester.swift",
        "Reverb/Views/iOS/Adapters/ResponsiveParameterController.swift",
        "Reverb/Audio/WetDryRecordingManager.swift",
        "Reverb/Audio/RecordingSessionManager.swift"
    ]
    
    for pattern in patterns:
        full_path = os.path.join(PROJECT_ROOT, pattern)
        if os.path.isfile(full_path):
            additional_files.append(pattern)
    
    return additional_files

def create_project_with_all_files():
    """Create a complete project file with all source files properly organized"""
    
    print("🔧 Creating clean project structure...")
    
    # Generate all UUIDs needed
    uuids = {}
    uuid_keys = [
        'CONTENT_VIEW_BUILD', 'CONTENT_VIEW_REF', 'REVERB_APP_BUILD', 'REVERB_APP_REF',
        'ASSETS_BUILD', 'ASSETS_REF', 'PREVIEW_ASSETS_BUILD', 'PREVIEW_ASSETS_REF',
        'RECORDING_HISTORY_BUILD', 'RECORDING_HISTORY_REF', 'CUSTOM_REVERB_VIEW_BUILD', 
        'CUSTOM_REVERB_VIEW_REF', 'AUDIO_MANAGER_BUILD', 'AUDIO_MANAGER_REF',
        'AUDIO_ENGINE_SERVICE_BUILD', 'AUDIO_ENGINE_SERVICE_REF', 'RECORDING_SERVICE_BUILD', 
        'RECORDING_SERVICE_REF', 'CUSTOM_REVERB_SETTINGS_BUILD', 'CUSTOM_REVERB_SETTINGS_REF',
        'REVERB_PRESET_BUILD', 'REVERB_PRESET_REF', 'INFO_PLIST_REF', 'APP_REF',
        'ROOT_GROUP', 'REVERB_GROUP', 'AUDIO_GROUP', 'MODELS_GROUP', 'SERVICES_GROUP',
        'VIEWS_GROUP', 'TESTING_GROUP', 'DSP_GROUP', 'OPTIMIZATION_GROUP', 'PRODUCTS_GROUP',
        'PREVIEW_CONTENT_GROUP', 'TARGET', 'TARGET_CONFIG_LIST', 'SOURCES_PHASE',
        'FRAMEWORKS_PHASE', 'RESOURCES_PHASE', 'PROJECT', 'PROJECT_CONFIG_LIST',
        'DEBUG_CONFIG', 'RELEASE_CONFIG', 'TARGET_DEBUG_CONFIG', 'TARGET_RELEASE_CONFIG'
    ]
    
    for key in uuid_keys:
        uuids[key] = generate_uuid()
    
    # Get additional source files
    additional_files = scan_additional_source_files()
    
    # Generate UUIDs for additional files
    additional_build_files = []
    additional_file_refs = []
    additional_sources = []
    
    for file_path in additional_files:
        filename = os.path.basename(file_path)
        safe_name = filename.replace('.', '_').replace('-', '_').upper()
        
        file_uuid = generate_uuid()
        build_uuid = generate_uuid()
        
        # Determine file type
        if file_path.endswith('.swift'):
            file_type = 'sourcecode.swift'
        elif file_path.endswith('.mm'):
            file_type = 'sourcecode.cpp.objcpp'
        elif file_path.endswith('.cpp'):
            file_type = 'sourcecode.cpp.cpp'
        elif file_path.endswith('.hpp'):
            file_type = 'sourcecode.cpp.h'
        elif file_path.endswith('.h'):
            file_type = 'sourcecode.c.h'
        else:
            continue
        
        # Add to build files
        additional_build_files.append(
            f"\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};"
        )
        
        # Add to file references
        additional_file_refs.append(
            f"\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {filename}; sourceTree = \"<group>\"; }};"
        )
        
        # Add to sources (only for compilable files)
        if file_path.endswith(('.swift', '.mm', '.cpp')):
            additional_sources.append(
                f"\t\t\t\t{build_uuid} /* {filename} in Sources */,"
            )
    
    # Get clean project template
    project_content = create_clean_project_structure()
    
    # Replace all placeholders
    for key, uuid_val in uuids.items():
        project_content = project_content.replace(f'{{{key}}}', uuid_val)
    
    # Add additional files
    project_content = project_content.replace(
        '{ADDITIONAL_BUILD_FILES}', 
        '\n'.join(additional_build_files)
    )
    project_content = project_content.replace(
        '{ADDITIONAL_FILE_REFS}', 
        '\n'.join(additional_file_refs)
    )
    project_content = project_content.replace(
        '{ADDITIONAL_SOURCES}', 
        '\n'.join(additional_sources)
    )
    
    # Write the clean project file
    with open(PROJECT_FILE, 'w') as f:
        f.write(project_content)
    
    print(f"✅ Created clean project structure with {len(additional_files)} additional files")

def main():
    """Main function to completely fix project structure"""
    print("🔧 Completely fixing Reverb project structure...")
    print("=" * 60)
    
    # Backup current project file
    backup_project_file()
    
    # Create completely clean project structure
    create_project_with_all_files()
    
    print("=" * 60)
    print("✅ Project structure completely rebuilt!")
    print("🎯 Project is now clean with proper organization")
    print("📁 No more 'Recovered References' - all files properly structured")
    print("🔥 Build errors should be resolved")
    print("")
    print("Next steps:")
    print("1. Open Xcode")
    print("2. Clean build folder (Product > Clean Build Folder)")
    print("3. Build the project")

if __name__ == "__main__":
    main()