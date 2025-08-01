#!/usr/bin/env python3

import os
import shutil
import glob
from pathlib import Path

# Project paths
PROJECT_ROOT = "/Users/a/Desktop/projects/Reverb"

def ensure_directory_exists(path):
    """Create directory if it doesn't exist"""
    os.makedirs(path, exist_ok=True)

def organize_files_into_structure():
    """Organize all source files into proper directory structure"""
    
    print("📁 Organizing files into proper structure...")
    
    # Create directory structure
    directories = [
        "Reverb/Audio/Models",
        "Reverb/Audio/Services", 
        "Reverb/Audio/Testing",
        "Reverb/Audio/DSP",
        "Reverb/Audio/Optimization",
        "Reverb/Views",
        "Reverb/Views/iOS",
        "Reverb/Views/iOS/Adapters"
    ]
    
    for directory in directories:
        full_path = os.path.join(PROJECT_ROOT, directory)
        ensure_directory_exists(full_path)
        print(f"✅ Created directory: {directory}")
    
    # File mapping: source -> destination
    file_moves = {
        # Models
        "Reverb/Audio/CustomReverbSettings.swift": "Reverb/Audio/Models/CustomReverbSettings.swift",
        "Reverb/Audio/ReverbPreset.swift": "Reverb/Audio/Models/ReverbPreset.swift",
        
        # Services
        "Reverb/Audio/Services/WetDryAudioEngine.swift": "Reverb/Audio/Services/WetDryAudioEngine.swift",
        "Reverb/Audio/Services/OfflineReverbProcessor.swift": "Reverb/Audio/Services/OfflineReverbProcessor.swift",
        "Reverb/Audio/Services/BatchOfflineProcessor.swift": "Reverb/Audio/Services/BatchOfflineProcessor.swift", 
        "Reverb/Audio/Services/CrossPlatformAudioSession.swift": "Reverb/Audio/Services/CrossPlatformAudioSession.swift",
        "Reverb/Audio/Services/iOSRecordingManager.swift": "Reverb/Audio/Services/iOSRecordingManager.swift",
        "Reverb/Audio/Services/AudioInterruptionHandler.swift": "Reverb/Audio/Services/AudioInterruptionHandler.swift",
        "Reverb/Audio/Services/AudioQualityValidator.swift": "Reverb/Audio/Services/AudioQualityValidator.swift",
        
        # Testing
        "Reverb/Audio/Testing/iOSTapRecordingValidator.swift": "Reverb/Audio/Testing/iOSTapRecordingValidator.swift",
        "Reverb/Audio/Testing/CrossPlatformAudioComparator.swift": "Reverb/Audio/Testing/CrossPlatformAudioComparator.swift",
        
        # Main Audio files
        "Reverb/Audio/WetDryRecordingManager.swift": "Reverb/Audio/WetDryRecordingManager.swift",
        "Reverb/Audio/RecordingSessionManager.swift": "Reverb/Audio/RecordingSessionManager.swift",
        
        # Views
        "Reverb/Views/RecordingControlsView.swift": "Reverb/Views/RecordingControlsView.swift",
        "Reverb/Views/BatchProcessingView.swift": "Reverb/Views/BatchProcessingView.swift",
        "Reverb/Views/WetDryRecordingView.swift": "Reverb/Views/WetDryRecordingView.swift",
        "Reverb/Views/OfflineProcessingView.swift": "Reverb/Views/OfflineProcessingView.swift",
        
        # iOS Views
        "Reverb/Views/iOS/iOSRealtimeView.swift": "Reverb/Views/iOS/iOSRealtimeView.swift",
        "Reverb/Views/iOS/iOSOnboardingView.swift": "Reverb/Views/iOS/iOSOnboardingView.swift",
        "Reverb/Views/iOS/iOSCompactViews.swift": "Reverb/Views/iOS/iOSCompactViews.swift",
        "Reverb/Views/iOS/iOSMainView.swift": "Reverb/Views/iOS/iOSMainView.swift",
        
        # iOS Adapters
        "Reverb/Views/iOS/Adapters/ParameterResponseTester.swift": "Reverb/Views/iOS/Adapters/ParameterResponseTester.swift",
        "Reverb/Views/iOS/Adapters/ResponsiveParameterController.swift": "Reverb/Views/iOS/Adapters/ResponsiveParameterController.swift"
    }
    
    # Move files to correct locations
    moved_count = 0
    for source_rel, dest_rel in file_moves.items():
        source_path = os.path.join(PROJECT_ROOT, source_rel)
        dest_path = os.path.join(PROJECT_ROOT, dest_rel)
        
        if os.path.isfile(source_path):
            # Ensure destination directory exists
            dest_dir = os.path.dirname(dest_path)
            ensure_directory_exists(dest_dir)
            
            # Move file
            shutil.move(source_path, dest_path)
            print(f"📄 Moved: {source_rel} -> {dest_rel}")
            moved_count += 1
        else:
            print(f"⚠️  File not found: {source_rel}")
    
    print(f"✅ Moved {moved_count} files into organized structure")

def clean_empty_directories():
    """Remove empty directories"""
    print("🧹 Cleaning empty directories...")
    
    # Find all directories in Reverb/
    reverb_path = os.path.join(PROJECT_ROOT, "Reverb")
    
    for root, dirs, files in os.walk(reverb_path, topdown=False):
        for directory in dirs:
            dir_path = os.path.join(root, directory)
            try:
                # Try to remove if empty
                os.rmdir(dir_path)
                rel_path = os.path.relpath(dir_path, PROJECT_ROOT)
                print(f"🗑️  Removed empty directory: {rel_path}")
            except OSError:
                # Directory not empty, skip
                pass

def verify_file_structure():
    """Verify that files are in the correct locations"""
    print("🔍 Verifying file structure...")
    
    expected_files = [
        "Reverb/ReverbApp.swift",
        "Reverb/ContentView.swift", 
        "Reverb/CustomReverbView.swift",
        "Reverb/RecordingHistory.swift",
        "Reverb/AudioManager.swift",
        "Reverb/AudioEngineService.swift",
        "Reverb/RecordingService.swift",
        "Reverb/Audio/Models/CustomReverbSettings.swift",
        "Reverb/Audio/Models/ReverbPreset.swift",
        "Reverb/Audio/Services/AudioEngineService.swift",
        "Reverb/Audio/Services/RecordingService.swift"
    ]
    
    found_count = 0
    for file_path in expected_files:
        full_path = os.path.join(PROJECT_ROOT, file_path)
        if os.path.isfile(full_path):
            found_count += 1
            print(f"✅ Found: {file_path}")
        else:
            print(f"❌ Missing: {file_path}")
    
    print(f"📊 Found {found_count}/{len(expected_files)} core files")

def list_all_source_files():
    """List all Swift files for verification"""
    print("📋 All Swift files in project:")
    
    swift_files = []
    for root, dirs, files in os.walk(os.path.join(PROJECT_ROOT, "Reverb")):
        for file in files:
            if file.endswith(".swift"):
                rel_path = os.path.relpath(os.path.join(root, file), PROJECT_ROOT)
                swift_files.append(rel_path)
    
    swift_files.sort()
    for swift_file in swift_files:
        print(f"  📄 {swift_file}")
    
    print(f"📊 Total Swift files: {len(swift_files)}")

def main():
    """Main function to organize project files"""
    print("📁 Organizing Reverb project files...")
    print("=" * 50)
    
    # Organize files into proper structure
    organize_files_into_structure()
    
    # Clean up empty directories
    clean_empty_directories()
    
    # Verify structure
    verify_file_structure()
    
    # List all files
    list_all_source_files()
    
    print("=" * 50)
    print("✅ File organization completed!")
    print("🎯 Files are now organized in proper directories")
    print("📁 Xcode should now find all files correctly")

if __name__ == "__main__":
    main()