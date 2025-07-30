#!/bin/bash

# Build script for VoiceMonitorPro-v2 iOS
# This script compiles the C++ DSP library and prepares it for Xcode integration

set -e  # Exit on any error

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
CMAKE_BUILD_TYPE="${1:-Release}"  # Default to Release, override with Debug if needed

echo "🎵 Building VoiceMonitorPro-v2 C++ DSP Library"
echo "📁 Project root: $PROJECT_ROOT"
echo "🏗️ Build type: $CMAKE_BUILD_TYPE"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# iOS-specific CMake configuration
echo "⚙️ Configuring CMake for iOS..."

cmake "$PROJECT_ROOT" \
    -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM="" \
    -DCMAKE_CXX_FLAGS="-std=c++14 -fno-exceptions -fno-rtti" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# Build the library
echo "🔨 Building C++ DSP library..."
make -j$(sysctl -n hw.ncpu) VoiceMonitorDSP

if [ -f "libVoiceMonitorDSP.a" ]; then
    echo "✅ C++ DSP library built successfully: libVoiceMonitorDSP.a"
    
    # Copy library and headers to iOS project location
    IOS_LIB_DIR="$PROJECT_ROOT/iOS/Libs"
    mkdir -p "$IOS_LIB_DIR"
    
    cp libVoiceMonitorDSP.a "$IOS_LIB_DIR/"
    
    # Copy headers
    IOS_HEADERS_DIR="$PROJECT_ROOT/iOS/Headers"
    mkdir -p "$IOS_HEADERS_DIR"
    
    cp "$PROJECT_ROOT/Shared/DSP"/*.hpp "$IOS_HEADERS_DIR/"
    cp "$PROJECT_ROOT/Shared/Utils"/*.hpp "$IOS_HEADERS_DIR/"
    
    echo "📚 Headers copied to: $IOS_HEADERS_DIR"
    echo "📦 Library copied to: $IOS_LIB_DIR"
    
    # Create Xcode project if it doesn't exist
    XCODE_PROJECT="$PROJECT_ROOT/VoiceMonitorPro.xcodeproj"
    if [ ! -d "$XCODE_PROJECT" ]; then
        echo "🔨 Generating Xcode project..."
        cmake "$PROJECT_ROOT" -G Xcode \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
            -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
            -B "$PROJECT_ROOT/XcodeBuild"
    fi
    
    echo ""
    echo "🎉 Build completed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Open your Xcode project"
    echo "2. Add libVoiceMonitorDSP.a to your target's Link Binary With Libraries"
    echo "3. Add $IOS_HEADERS_DIR to your Header Search Paths"
    echo "4. Import ReverbBridge.h in your Swift files"
    echo "5. Replace AudioEngineService with AudioIOBridge"
    
else
    echo "❌ Build failed - library not found"
    exit 1
fi