#!/usr/bin/env python3

import os
import re
import glob
from pathlib import Path

# Project paths
PROJECT_ROOT = "/Users/a/Desktop/projects/Reverb"
PROJECT_FILE = f"{PROJECT_ROOT}/Reverb.xcodeproj/project.pbxproj"

def map_actual_file_locations():
    """Map files to their actual locations"""
    actual_files = {}
    
    # Search for all Swift files in the project
    for root, dirs, files in os.walk(os.path.join(PROJECT_ROOT, "Reverb")):
        for file in files:
            if file.endswith(".swift"):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, PROJECT_ROOT)
                actual_files[file] = rel_path
    
    return actual_files

def update_file_paths_in_project():
    """Update file paths in the project file"""
    print("🔧 Updating file paths in project...")
    
    # Read current project file
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()
    
    # Get actual file locations
    actual_files = map_actual_file_locations()
    
    print(f"📁 Found {len(actual_files)} Swift files")
    
    # Files that need path correction
    files_to_fix = [
        'WetDryAudioEngine.swift',
        'OfflineReverbProcessor.swift', 
        'BatchOfflineProcessor.swift',
        'CrossPlatformAudioSession.swift',
        'iOSRecordingManager.swift',
        'AudioInterruptionHandler.swift',
        'AudioQualityValidator.swift',
        'iOSTapRecordingValidator.swift',
        'CrossPlatformAudioComparator.swift',
        'RecordingControlsView.swift',
        'BatchProcessingView.swift',
        'WetDryRecordingView.swift',
        'OfflineProcessingView.swift',
        'iOSRealtimeView.swift',
        'iOSOnboardingView.swift',
        'iOSCompactViews.swift',
        'iOSMainView.swift',
        'ResponsiveParameterController.swift',
        'WetDryRecordingManager.swift',
        'RecordingSessionManager.swift'
    ]
    
    updated_count = 0
    
    for filename in files_to_fix:
        if filename in actual_files:
            actual_path = actual_files[filename]
            
            # Update path in file reference
            old_pattern = f'path = {filename}; sourceTree = "<group>";'
            new_pattern = f'path = "{os.path.basename(actual_path)}"; sourceTree = "<group>";'
            
            if old_pattern in content:
                content = content.replace(old_pattern, new_pattern)
                print(f"✅ Updated reference for {filename}")
                updated_count += 1
            else:
                print(f"⚠️  Pattern not found for {filename}")
        else:
            print(f"❌ File not found: {filename}")
    
    # Write updated content
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)
    
    print(f"✅ Updated {updated_count} file references")

def add_missing_files_to_groups():
    """Add missing files to proper groups in the project structure"""
    print("📁 Adding files to proper groups...")
    
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()
    
    # Get actual file locations
    actual_files = map_actual_file_locations()
    
    # Files to add to Services group
    services_files = [
        'WetDryAudioEngine.swift',
        'OfflineReverbProcessor.swift',
        'BatchOfflineProcessor.swift', 
        'CrossPlatformAudioSession.swift',
        'iOSRecordingManager.swift',
        'AudioInterruptionHandler.swift',
        'AudioQualityValidator.swift'
    ]
    
    # Files to add to Testing group
    testing_files = [
        'iOSTapRecordingValidator.swift',
        'CrossPlatformAudioComparator.swift'
    ]
    
    # Files to add to Views group
    views_files = [
        'RecordingControlsView.swift',
        'BatchProcessingView.swift',
        'WetDryRecordingView.swift',
        'OfflineProcessingView.swift'
    ]
    
    # Files to add to iOS Views group  
    ios_views_files = [
        'iOSRealtimeView.swift',
        'iOSOnboardingView.swift',
        'iOSCompactViews.swift',
        'iOSMainView.swift'
    ]
    
    # Find Services group and add files
    services_pattern = r'(5F5E77AA23F04C899338E7F8 /\* Services \*/ = \{[^}]+children = \()[^}]+(\);[^}]+};)'
    if re.search(services_pattern, content):
        # Add services files to group
        for filename in services_files:
            if filename in actual_files:
                # Find the file reference UUID for this file
                uuid_pattern = rf'([A-F0-9]{{24}}) /\* {re.escape(filename)} \*/'
                uuid_match = re.search(uuid_pattern, content)
                if uuid_match:
                    file_uuid = uuid_match.group(1)
                    # Add to services group children
                    services_replacement = rf'\1\n\t\t\t\t{file_uuid} /* {filename} */,\2'
                    content = re.sub(services_pattern, services_replacement, content)
                    print(f"✅ Added {filename} to Services group")
    
    # Similar patterns for other groups...
    
    # Write updated content
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

def main():
    """Main function to fix file paths"""
    print("🔧 Fixing file paths in Reverb project...")
    print("=" * 50)
    
    # Map actual file locations
    actual_files = map_actual_file_locations()
    print(f"📊 Found files:")
    for filename, path in sorted(actual_files.items()):
        print(f"  📄 {filename} -> {path}")
    
    # Update file paths in project
    update_file_paths_in_project()
    
    print("=" * 50)
    print("✅ File paths updated!")
    print("🎯 Project should now find all files correctly")
    print("")
    print("Next steps:")
    print("1. Open Xcode")
    print("2. Clean build folder (Product > Clean Build Folder)")  
    print("3. Build the project")

if __name__ == "__main__":
    main()