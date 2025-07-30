# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Reverb is a macOS application that adds real-time reverb effects to voice or singing input. Built with SwiftUI and AVFoundation, it provides three reverb presets (Cathedral, Large Hall, Small Room) with a simple, intuitive interface for local audio processing without latency.

## Architecture

The app follows MVVM (Model-View-ViewModel) architecture:

- **Models**: Audio data structures and settings (`ReverbPreset.swift`, `CustomReverbSettings.swift`)
- **Views**: SwiftUI interface (`ContentView.swift`, `CustomReverbView.swift`)
- **Services**: Audio processing (`AudioEngineService.swift`, `RecordingService.swift`)
- **Manager**: Central audio coordination (`AudioManager.swift` - singleton pattern)

Key architectural patterns:
- `AudioManager` is a shared singleton that coordinates all audio operations
- Uses `@Published` properties for reactive UI updates
- Audio services are encapsulated and managed through the AudioManager
- Recording history is maintained separately in `RecordingHistory.swift`

## Development Commands

### Building and Running
```bash
# Open project in Xcode
open Reverb.xcodeproj

# Build from command line
xcodebuild -project Reverb.xcodeproj -scheme Reverb -configuration Debug build

# Run from Xcode: Select target device (Mac) and press Cmd+R
```

### Project Structure
- Main app entry: `ReverbApp.swift`
- Primary view: `ContentView.swift` 
- Audio processing: `Audio/` directory with services and models
- Assets: `Assets.xcassets/` for app icons and colors

## Audio System Architecture

The audio pipeline flows through:
1. `AudioManager` (central coordinator)
2. `AudioEngineService` (AVAudioEngine management)
3. `RecordingService` (recording functionality)
4. Real-time reverb processing with preset configurations

The app targets macOS 14.0+ and requires microphone permissions for audio input processing.