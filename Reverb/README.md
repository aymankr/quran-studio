# Reverb - Vocal Effects App

## Overview
Reverb is an iOS application that provides real-time reverb effects for vocals. It allows users to:
- Monitor their voice with high-quality reverb effects
- Record vocals with various optimized reverb presets
- Save recordings to any location on their device

## Setup Instructions

### Adding Project Files to Xcode

If you've downloaded or cloned this repository, you'll need to add the files to your Xcode project:

1. Open the `Reverb.xcodeproj` file in Xcode
2. In the Project Navigator (left sidebar), right-click on the Reverb folder
3. Select "Add Files to 'Reverb'"
4. Navigate to the `Audio` folder and select it
5. Ensure "Create groups" is selected (not folder references)
6. Make sure "Add to targets: Reverb" is checked
7. Click "Add"

This will add all the necessary files to your Xcode project with the correct structure.

## Features

### Vocal-Optimized Reverb Presets

The app includes specialized reverb presets designed specifically for vocals:

- **Basic Presets**:
  - None: Pure dry signal
  - Small Room: Basic room ambience
  - Large Hall: Wide open sound
  - Cathedral: Massive space with long reverb tail

- **Vocal-Optimized Presets**:
  - Vocal Booth: Clean, controlled sound
  - Studio Vocal: Professional studio sound
  - Warm Vocal: Rich, warm tone
  - Intimate Vocal: Close, personal sound
  - Concert Hall: Live performance sound
  - Ambient Vocal: Atmospheric, dreamy quality

### Real-Time Monitoring

- Monitor your voice with reverb in real-time
- Zero-latency monitoring for immediate feedback
- Visualize audio levels with dynamic waveform display

### High-Quality Recording

- Record your vocals with the selected reverb effect
- Pause and resume recording
- High-quality audio (48kHz, 320kbps AAC)
- Save to any folder on your device

## Usage

1. Select a reverb preset from the available categories
2. Tap the ear icon to start monitoring
3. Press the red record button to begin recording
4. Use the pause button to pause/resume recording
5. Press the stop button (square) to end recording
6. Save your recording by tapping the save icon

## Technical Details

- Built with SwiftUI and AVFoundation
- Modular architecture for easy maintenance
- Optimized for iOS devices
- Full screen interface with responsive design 