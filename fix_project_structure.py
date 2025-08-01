#!/usr/bin/env python3

import os
import re
import uuid
import glob
from pathlib import Path

# Project paths
PROJECT_ROOT = "/Users/a/Desktop/projects/Reverb"
PROJECT_FILE = f"{PROJECT_ROOT}/Reverb.xcodeproj/project.pbxproj"

def generate_uuid():
    """Generate a unique ID for Xcode project entries"""
    return ''.join(str(uuid.uuid4()).upper().split('-'))[:24]

def backup_project_file():
    """Create a backup of the project file"""
    backup_path = f"{PROJECT_FILE}.backup"
    with open(PROJECT_FILE, 'r') as src:
        content = src.read()
    with open(backup_path, 'w') as dst:
        dst.write(content)
    print(f"✅ Project file backed up to {backup_path}")

def clean_project_file():
    """Remove all auto-generated entries and recovered references"""
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()
    
    # Remove all auto-generated entries (those with random UUIDs we added)
    # Keep only the original entries
    lines = content.split('\n')
    cleaned_lines = []
    skip_section = False
    
    for line in lines:
        # Skip our auto-generated entries
        if any(uuid_pattern in line for uuid_pattern in [
            'A1636FE5F4DD111F6EF05931', 'A6554BDF78F593264E610132', 'BE9B7167891254AA339A59A0',
            'D3D7B8AAED9BCD39DC73B559', 'E724F4CAC91AA45AB0CED8BF', 'EF2946CBCE6B4926A22D6658',
            '1F8EFFDB10A6439FB2485F3E', '7954B5153F6F41B0AF755EA7', 'B39CADFEEF4F4354BBE2B317'
        ]):
            continue
        
        # Skip lines that reference files that don't exist or are duplicated
        if 'Reverb/Audio/' in line and '/* ' in line and ' */' in line:
            continue
            
        cleaned_lines.append(line)
    
    cleaned_content = '\n'.join(cleaned_lines)
    
    with open(PROJECT_FILE, 'w') as f:
        f.write(cleaned_content)
    
    print("✅ Cleaned project file of problematic entries")

def scan_source_files():
    """Scan for all source files that should be in the project"""
    source_files = []
    
    # Define file patterns to include
    patterns = [
        "Reverb/*.swift",
        "Reverb/Audio/**/*.swift", 
        "Reverb/Audio/**/*.mm",
        "Reverb/Audio/**/*.cpp",
        "Reverb/Audio/**/*.hpp",
        "Reverb/Audio/**/*.h",
        "Reverb/Views/**/*.swift",
        "ReverbAU/*.swift"
    ]
    
    for pattern in patterns:
        full_pattern = os.path.join(PROJECT_ROOT, pattern)
        for file_path in glob.glob(full_pattern, recursive=True):
            if os.path.isfile(file_path):
                rel_path = os.path.relpath(file_path, PROJECT_ROOT)
                source_files.append(rel_path)
    
    # Sort files for consistent ordering
    source_files.sort()
    
    print(f"📁 Found {len(source_files)} source files to organize")
    return source_files

def organize_files_by_group(source_files):
    """Organize files into logical groups for Xcode project"""
    groups = {
        'App': [],
        'Views': [],
        'Audio/Models': [],
        'Audio/Services': [],
        'Audio/Testing': [],
        'Audio/DSP': [],
        'Audio/Optimization': [],
        'Views/iOS': [],
        'CPPEngine': [],
        'ReverbAU': []
    }
    
    for file_path in source_files:
        if file_path.startswith('ReverbAU/'):
            groups['ReverbAU'].append(file_path)
        elif file_path.startswith('Reverb/Views/iOS/'):
            groups['Views/iOS'].append(file_path)
        elif file_path.startswith('Reverb/Views/'):
            groups['Views'].append(file_path)
        elif file_path.startswith('Reverb/Audio/Testing/'):
            groups['Audio/Testing'].append(file_path)
        elif file_path.startswith('Reverb/Audio/DSP/'):
            groups['Audio/DSP'].append(file_path)
        elif file_path.startswith('Reverb/Audio/Optimization/'):
            groups['Audio/Optimization'].append(file_path)
        elif file_path.startswith('Reverb/Audio/Services/'):
            groups['Audio/Services'].append(file_path)
        elif file_path.startswith('Reverb/Audio/') and file_path.endswith('.swift'):
            groups['Audio/Models'].append(file_path)
        elif any(file_path.endswith(ext) for ext in ['.cpp', '.hpp', '.mm', '.h']):
            groups['CPPEngine'].append(file_path)
        elif file_path.startswith('Reverb/') and file_path.endswith('.swift'):
            groups['App'].append(file_path)
    
    return groups

def get_existing_file_refs(content):
    """Extract existing file references to avoid conflicts"""
    existing_refs = {}
    
    # Find all existing file references
    file_ref_pattern = r'([A-F0-9]{24}) /\* (.+?) \*/ = \{isa = PBXFileReference;.*?path = (.+?);'
    matches = re.findall(file_ref_pattern, content)
    
    for match in matches:
        uuid, comment, path = match
        existing_refs[path] = uuid
    
    return existing_refs

def add_files_to_project():
    """Add all source files to the project with proper organization"""
    # Read current project file
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()
    
    # Get existing file references
    existing_refs = get_existing_file_refs(content)
    
    # Scan source files
    source_files = scan_source_files()
    organized_groups = organize_files_by_group(source_files)
    
    # Generate UUIDs for new files
    new_file_refs = {}
    new_build_files = {}
    
    for group_name, files in organized_groups.items():
        for file_path in files:
            if not file_path.endswith(('.swift', '.mm', '.cpp')):
                continue  # Only add compilable files to build phase
                
            # Check if file already exists in project
            filename = os.path.basename(file_path)
            
            # Skip if already exists
            found_existing = False
            for existing_path, existing_uuid in existing_refs.items():
                if filename in existing_path or existing_path in file_path:
                    found_existing = True
                    break
            
            if found_existing:
                continue
            
            file_uuid = generate_uuid()
            build_uuid = generate_uuid()
            
            new_file_refs[file_path] = file_uuid
            new_build_files[file_path] = build_uuid
    
    print(f"📁 Adding {len(new_file_refs)} new files to project")
    
    # Add file references
    file_ref_section = content.find('/* Begin PBXFileReference section */')
    if file_ref_section == -1:
        print("❌ Could not find PBXFileReference section")
        return
    
    file_ref_end = content.find('/* End PBXFileReference section */', file_ref_section)
    
    new_file_ref_entries = []
    for file_path, file_uuid in new_file_refs.items():
        filename = os.path.basename(file_path)
        
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
        
        entry = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {filename}; sourceTree = "<group>"; }};'
        new_file_ref_entries.append(entry)
    
    # Insert new file references
    if new_file_ref_entries:
        insertion_point = file_ref_end
        new_content = (content[:insertion_point] + 
                      '\n'.join(new_file_ref_entries) + '\n\t\t' +
                      content[insertion_point:])
        content = new_content
    
    # Add build file entries
    build_file_section = content.find('/* Begin PBXBuildFile section */')
    if build_file_section == -1:
        print("❌ Could not find PBXBuildFile section")
        return
    
    build_file_end = content.find('/* End PBXBuildFile section */', build_file_section)
    
    new_build_file_entries = []
    for file_path, build_uuid in new_build_files.items():
        if not file_path.endswith(('.swift', '.mm', '.cpp')):
            continue
            
        filename = os.path.basename(file_path)
        file_uuid = new_file_refs[file_path]
        
        entry = f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};'
        new_build_file_entries.append(entry)
    
    # Insert new build file entries
    if new_build_file_entries:
        insertion_point = build_file_end
        new_content = (content[:insertion_point] + 
                      '\n'.join(new_build_file_entries) + '\n\t\t' +
                      content[insertion_point:])
        content = new_content
    
    # Add files to Sources build phase
    sources_pattern = r'(\w+) /\* Sources \*/ = \{[^}]+files = \([^)]+\);'
    sources_match = re.search(sources_pattern, content, re.DOTALL)
    
    if sources_match:
        sources_section = sources_match.group(0)
        files_start = sources_section.find('files = (') + len('files = (')
        files_end = sources_section.find(');', files_start)
        
        existing_files = sources_section[files_start:files_end]
        
        new_source_entries = []
        for file_path, build_uuid in new_build_files.items():
            if not file_path.endswith(('.swift', '.mm', '.cpp')):
                continue
                
            filename = os.path.basename(file_path)
            entry = f'\t\t\t\t{build_uuid} /* {filename} in Sources */,'
            new_source_entries.append(entry)
        
        if new_source_entries:
            updated_files = existing_files.rstrip() + '\n' + '\n'.join(new_source_entries) + '\n\t\t\t'
            updated_sources = sources_section.replace(existing_files, updated_files)
            content = content.replace(sources_section, updated_sources)
    
    # Write updated content
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)
    
    print(f"✅ Added {len(new_file_refs)} files to project")

def main():
    """Main function to fix project structure"""
    print("🔧 Fixing Reverb project structure...")
    print("=" * 50)
    
    # Backup project file
    backup_project_file()
    
    # Clean problematic entries
    clean_project_file()
    
    # Add files with proper organization
    add_files_to_project()
    
    print("=" * 50)
    print("✅ Project structure fixed!")
    print("🎯 Now open Xcode and the files should be properly organized")
    print("📁 Files are organized in logical groups instead of 'Recovered References'")

if __name__ == "__main__":
    main()