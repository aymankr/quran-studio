cmake_minimum_required(VERSION 3.20)
project(VoiceMonitorPro VERSION 2.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Platform detection
if(APPLE)
    set(IOS_PLATFORM TRUE)
    enable_language(OBJCXX)
endif()

# Compiler flags for optimization
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -ffast-math")
    if(IOS_PLATFORM AND CMAKE_OSX_ARCHITECTURES MATCHES "armv7")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mfpu=neon")
    endif()
endif()

# Include directories
include_directories(Shared/DSP)
include_directories(Shared/Utils)

# DSP Core Library (C++)
add_library(VoiceMonitorDSP STATIC
    Shared/DSP/ReverbEngine.cpp
    Shared/DSP/AudioBuffer.cpp
    Shared/DSP/Parameters.cpp
    Shared/DSP/CrossFeed.cpp
    Shared/DSP/FDNReverb.cpp
    Shared/Utils/AudioMath.cpp
)

# iOS Bridge (when building for iOS)
if(IOS_PLATFORM)
    add_library(VoiceMonitorBridge STATIC
        iOS/AudioBridge/ReverbBridge.mm
        iOS/AudioBridge/AudioIOBridge.mm
    )
    
    target_link_libraries(VoiceMonitorBridge VoiceMonitorDSP)
    
    # iOS Frameworks
    find_library(AVFOUNDATION_FRAMEWORK AVFoundation)
    find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox)
    find_library(ACCELERATE_FRAMEWORK Accelerate)
    
    target_link_libraries(VoiceMonitorDSP 
        ${AVFOUNDATION_FRAMEWORK}
        ${AUDIOTOOLBOX_FRAMEWORK}
        ${ACCELERATE_FRAMEWORK}
    )
endif()

# Compiler-specific optimizations
if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    target_compile_options(VoiceMonitorDSP PRIVATE 
        -Wall -Wextra -Werror
        -fno-rtti        # Reduce binary size
    )
endif()

# SIMD support detection for ARM64 and ARMv7
if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
    target_compile_definitions(VoiceMonitorDSP PRIVATE USE_ARM64=1)
elseif(CMAKE_OSX_ARCHITECTURES MATCHES "armv7")
    include(CheckCXXCompilerFlag)
    check_cxx_compiler_flag("-mfpu=neon" COMPILER_SUPPORTS_NEON)
    if(COMPILER_SUPPORTS_NEON)
        target_compile_definitions(VoiceMonitorDSP PRIVATE USE_NEON=1)
    endif()
endif()

# Add preprocessor definitions
target_compile_definitions(VoiceMonitorDSP PRIVATE
    VM_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
    VM_VERSION_MINOR=${PROJECT_VERSION_MINOR}
)

# Testing (optional, skip as requested)
# option(BUILD_TESTS "Build tests" OFF)