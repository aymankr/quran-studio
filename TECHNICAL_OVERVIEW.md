# Reverb - Technical Overview & Architecture

## Project Description
Reverb is a macOS application that adds real-time reverb effects to voice or singing input. Built with SwiftUI and AVFoundation, it provides professional-grade reverb processing with ultra-low latency for live performance and recording applications.

## Core Technologies

### 1. Swift & SwiftUI Framework
- **SwiftUI**: Modern declarative UI framework for macOS interface
- **Swift**: Primary language for application logic and UI
- **AVFoundation**: Core audio framework for real-time audio processing
- **AVAudioEngine**: High-performance audio processing graph

### 2. C++ Audio Engine (Current Implementation)
- **Namespace**: `VoiceMonitor`
- **Architecture**: Professional C++ DSP core with Objective-C++ bridges
- **Threading**: Thread-safe atomic parameters for real-time audio

## Audio Processing Architecture

### Core Audio Components

#### 1. AVAudioEngine Pipeline
```
Input → GainMixer → (CleanBypass OR Reverb) → RecordingMixer → MainMixer → Output
```

#### 2. Audio Nodes
- **AVAudioInputNode**: Microphone input capture
- **AVAudioMixerNode**: 
  - `gainMixer_`: Input level control (Volume: 1.3)
  - `cleanBypassMixer_`: Clean signal path (Volume: 1.2)  
  - `recordingMixer_`: Recording output (Volume: 1.0)
  - `mainMixer_`: Final output mix (Volume: 1.4)
- **AVAudioUnitReverb**: Built-in reverb processing
- **AVAudioOutputNode**: Speaker/headphone output

#### 3. Audio Session Configuration
- **Sample Rate**: 48kHz (professional quality)
- **Buffer Duration**: 64/48000 ≈ 1.33ms (ultra-low latency like AD 480)
- **Channels**: Stereo input/output
- **Category**: PlayAndRecord with monitoring capabilities

### Advanced DSP Engine (C++ Implementation)

#### 1. FDN Reverb Engine (`FDNReverb.hpp`)
**Core Algorithm**: Feedback Delay Network (FDN)
- **Delay Lines**: 8 parallel delay lines with modulation
- **Delay Lengths**: Prime-number based to avoid flutter echoes
- **Interpolation**: Linear interpolation for smooth modulation
- **Matrix**: Householder feedback matrix for natural reverb decay

**Components**:
- **DelayLine**: Circular buffer with interpolated read
- **AllPassFilter**: Diffusion processing (gain: 0.7)
- **DampingFilter**: Separate HF/LF damping (Butterworth 2nd order)
- **ModulatedDelay**: Chorus-like modulation for natural sound
- **CrossFeedProcessor**: Professional stereo imaging

#### 2. ReverbEngine (`ReverbEngine.hpp`)
**Main Controller**: High-level reverb processor
- **Thread Safety**: Atomic parameters for real-time updates
- **CPU Monitoring**: Performance tracking
- **Preset Management**: Clean, VocalBooth, Studio, Cathedral presets

**Parameters**:
```cpp
std::atomic<float> wetDryMix{35.0f};        // 0-100%
std::atomic<float> decayTime{2.0f};         // 0.1-8.0 seconds  
std::atomic<float> preDelay{75.0f};         // 0-200 ms
std::atomic<float> crossFeed{0.5f};         // 0.0-1.0
std::atomic<float> roomSize{0.82f};         // 0.0-1.0
std::atomic<float> density{70.0f};          // 0-100%
std::atomic<float> highFreqDamping{50.0f};  // 0-100%
std::atomic<float> lowFreqDamping{20.0f};   // 0-100% (AD 480 feature)
std::atomic<float> stereoWidth{1.0f};       // 0.0-2.0 (AD 480 feature)
std::atomic<bool> phaseInvert{false};       // L/R phase inversion
```

#### 3. CrossFeed Engine (`CrossFeed.hpp`)
**Stereo Enhancement**: AD 480-style stereo processing
- **Cross-feed**: Controlled left/right channel mixing
- **Phase Inversion**: Professional L/R phase control
- **Stereo Width**: Variable stereo field (0.0 = mono, 2.0 = wide)

## Bridge Architecture (Objective-C++)

### 1. ReverbBridge (`ReverbBridge.h/mm`)
**Purpose**: C++ to Objective-C bridge for reverb engine
- **Thread Safety**: Serial dispatch queue for parameter updates
- **Preset Management**: Clean, VocalBooth, Studio, Cathedral
- **Real-time Processing**: Direct audio buffer processing

### 2. AudioIOBridge (`AudioIOBridge.h/mm`)
**Purpose**: Complete audio I/O management
- **Engine Lifecycle**: Start/stop audio engine
- **Monitoring Control**: Real-time audio monitoring
- **Preset Routing**: Dynamic audio path based on preset
- **Volume Management**: Balanced gain staging

## Audio Processing Features

### 1. Professional Reverb Algorithms
- **FDN (Feedback Delay Network)**: Industry-standard reverb algorithm
- **Modulated Delays**: Natural reverb tail without metallic artifacts
- **HF/LF Damping**: Separate high and low frequency damping
- **Pre-delay**: Configurable early reflection timing

### 2. Ultra-Low Latency (AD 480 Inspired)
- **Buffer Size**: 64 samples at 48kHz = 1.33ms latency
- **Real-time Processing**: Lock-free atomic operations
- **Optimized Pipeline**: Minimal processing overhead

### 3. Professional Audio Features
- **Stereo Enhancement**: Configurable stereo width and cross-feed
- **Phase Control**: Left/right phase inversion capability  
- **Dynamic Routing**: Preset-based audio path switching
- **CPU Monitoring**: Real-time performance tracking

## Current Preset System

### 1. Clean Preset
- **Wet/Dry**: 0% (completely dry)
- **Use Case**: Direct monitoring without reverb
- **Audio Path**: Input → Gain → CleanBypass → Output

### 2. Reverb Presets (VocalBooth, Studio, Cathedral)
- **Wet/Dry**: 35-75% reverb mix
- **Decay Times**: 0.9s - 2.8s
- **Audio Path**: Input → Gain → Reverb → Output

## File Structure

### Swift Files
- `ReverbApp.swift`: Application entry point
- `ContentView.swift`: Main UI interface
- `CustomReverbView.swift`: Detailed reverb controls
- `AudioManager.swift`: Swift audio management (legacy)
- `AudioEngineService.swift`: AVAudioEngine wrapper
- `ReverbPreset.swift`: Preset data models

### C++ Audio Engine
- `Shared/DSP/ReverbEngine.hpp`: Main reverb controller
- `Shared/DSP/FDNReverb.hpp`: Core FDN reverb algorithm
- `Shared/DSP/CrossFeed.hpp`: Stereo enhancement
- `Shared/Utils/AudioMath.hpp`: DSP utility functions

### Objective-C++ Bridges  
- `CPPEngine/AudioBridge/ReverbBridge.h/mm`: Reverb engine bridge
- `CPPEngine/AudioBridge/AudioIOBridge.h/mm`: Complete I/O bridge

### Audio Management
- `Audio/AudioManagerCPP.swift`: C++ backend integration
- `Audio/AudioManagerSimple.swift`: Simplified audio management
- `Audio/Services/AudioEngineService.swift`: AVAudioEngine service

## Performance Characteristics

### 1. Latency Optimization
- **Total Latency**: ~1.33ms (64 samples @ 48kHz)
- **Processing**: Real-time C++ DSP core
- **Threading**: Lock-free audio thread with parameter updates

### 2. CPU Efficiency
- **Atomic Operations**: Thread-safe parameter changes
- **Optimized Algorithms**: Professional DSP implementations
- **Memory Management**: RAII and smart pointers in C++

### 3. Audio Quality
- **Sample Rate**: 48kHz professional quality
- **Bit Depth**: 32-bit float internal processing
- **Dynamic Range**: Professional audio specifications
- **THD+N**: Optimized for transparent audio processing

## Technical Specifications

### Audio Format
- **Sample Rate**: 48,000 Hz
- **Channels**: 2 (Stereo)
- **Bit Depth**: 32-bit float
- **Buffer Size**: 64 samples (1.33ms)

### System Requirements
- **Platform**: macOS 14.0+
- **Architecture**: ARM64/x86_64 universal
- **Permissions**: Microphone access required
- **Audio**: Professional audio interface recommended

### Development Tools
- **Xcode**: Latest version for macOS development
- **Swift**: 5.0+ for application logic
- **C++**: 17+ for DSP engine
- **Objective-C++**: Bridge implementation

## Application Architecture & Workflow

### 1. Application Startup Flow
```
ReverbApp.swift (Entry Point)
    ↓
ContentView.swift (Main UI)
    ↓  
AudioManagerCPP.swift (Audio Controller)
    ↓
AudioIOBridge.mm (C++ Integration)
    ↓
ReverbEngine.hpp (DSP Processing)
```

### 2. Audio Pipeline Architecture

#### Initialization Sequence
1. **App Launch**: `ReverbApp.swift` creates main window
2. **UI Setup**: `ContentView.swift` initializes user interface
3. **Audio Manager**: `AudioManagerCPP.swift` creates audio backend
4. **Bridge Creation**: `AudioIOBridge.mm` sets up C++ integration
5. **Engine Init**: `ReverbEngine.hpp` initializes DSP components
6. **Session Config**: AVAudioSession configured for 48kHz/1.33ms latency

#### Real-Time Audio Flow
```
Microphone Input (AVAudioInputNode)
    ↓
GainMixer (Volume: 1.3) - Input level control
    ↓
Preset-Based Routing:
    ├─ Clean Mode: CleanBypassMixer (Volume: 1.2)
    └─ Reverb Mode: AVAudioUnitReverb + C++ Processing
    ↓
RecordingMixer (Volume: 1.0) - Recording tap point
    ↓  
MainMixer (Volume: 1.4) - Final mix
    ↓
AVAudioOutputNode (Speakers/Headphones)
```

### 3. State Management Architecture

#### Swift UI State
- **@Published Properties**: Reactive UI updates
- **@State Variables**: Local UI state management
- **@AppStorage**: Persistent user preferences
- **ObservableObject**: MVVM pattern implementation

#### Audio State Synchronization
```swift
SwiftUI Interface
    ↓ (User Input)
AudioManagerCPP.swift
    ↓ (Method Calls)
AudioIOBridge.mm
    ↓ (Objective-C++ Bridge)
ReverbBridge.mm
    ↓ (Thread-Safe Updates)
ReverbEngine.hpp (std::atomic parameters)
```

### 4. Threading Architecture

#### Main Thread (UI)
- SwiftUI interface updates
- User interaction handling
- State binding updates
- Preset selection

#### Audio Thread (Real-Time)
- C++ DSP processing (`processBlock`)
- AVAudioEngine callback
- Lock-free parameter reading
- Ultra-low latency processing

#### Parameter Update Thread
- Serial dispatch queue: `com.voicemonitor.audio`
- Thread-safe parameter updates
- Atomic write operations
- No audio thread blocking

### 5. Memory Management Strategy

#### Swift Side (ARC)
- Automatic Reference Counting
- Strong/weak reference management
- ObservableObject lifecycle

#### C++ Side (RAII)
- Smart pointers (`std::unique_ptr`)
- Automatic resource cleanup
- Exception-safe resource management
- Stack-based object lifecycle

#### Bridge Management
- Objective-C++ automatic memory management
- C++ object lifetime tied to Objective-C objects
- Proper cleanup in `dealloc` methods

### 6. Data Flow Architecture

#### Parameter Updates
```
UI Slider Change
    ↓
@Published property updates
    ↓
SwiftUI view refresh
    ↓
AudioManager method call
    ↓
Bridge parameter setter
    ↓
std::atomic<float>.store()
    ↓
Audio thread reads atomic value
    ↓
DSP processing with new parameter
```

#### Preset Changes
```
UI Preset Selection
    ↓
AudioManager.updateReverbPreset()
    ↓
AudioIOBridge.setCurrentPreset()
    ↓
Audio path reconfiguration
    ↓
ReverbBridge.setPreset()
    ↓
Parameter bulk update
    ↓
Real-time processing adjustment
```

### 7. Audio Session Management

#### Session Configuration
```objc
AVAudioSession *session = [AVAudioSession sharedInstance];
[session setCategory:AVAudioSessionCategoryPlayAndRecord 
         withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker |
                    AVAudioSessionCategoryOptionAllowBluetooth |
                    AVAudioSessionCategoryOptionMixWithOthers];
[session setPreferredSampleRate:48000];
[session setPreferredIOBufferDuration:64.0/48000.0]; // 1.33ms
```

#### Engine Lifecycle
1. **Startup**: `startEngine` creates and connects audio nodes
2. **Monitoring**: `setMonitoring:YES` enables real-time processing  
3. **Processing**: Continuous audio callback execution
4. **Shutdown**: `stopEngine` deallocates resources cleanly

### 8. Error Handling & Recovery

#### Swift Error Handling
- Optional chaining for safe property access
- Guard statements for early return
- Error propagation through Result types

#### C++ Exception Safety
- RAII for automatic cleanup
- Exception-safe constructors
- Strong exception safety guarantee

#### Audio System Recovery
- Automatic engine restart on audio interruption
- Format change adaptation
- Device change handling

### 9. Performance Monitoring

#### Real-Time Metrics
```cpp
// CPU usage calculation in ReverbEngine
auto startTime = std::chrono::high_resolution_clock::now();
// ... audio processing ...
auto endTime = std::chrono::high_resolution_clock::now();
double cpuUsage = (processingTime / blockTime) * 100.0;
```

#### Monitoring Points
- Audio processing CPU usage
- Buffer underrun detection
- Memory allocation tracking
- Real-time constraint validation

### 10. Plugin Architecture Design

#### Modular Components
- **ReverbEngine**: Core processing module
- **FDNReverb**: Interchangeable reverb algorithm
- **CrossFeed**: Stereo enhancement module
- **AudioIOBridge**: Hardware abstraction layer

#### Extension Points
- New reverb algorithms can replace FDNReverb
- Additional effects can be inserted in processing chain
- Different UI themes can be implemented
- Various audio backends can be supported

This technical overview represents the current state of the Reverb application after the git reset to commit 633f3738980c9f5d606b763cd256634573995b5b ("C++ DSP"). The system provides professional-grade audio processing with ultra-low latency suitable for live performance applications.