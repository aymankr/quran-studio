#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "ReverbBridge.h"

NS_ASSUME_NONNULL_BEGIN

/// Block for audio level monitoring
typedef void(^AudioLevelBlock)(float level);

/// AVAudioEngine integration bridge for the C++ reverb engine
/// This class replaces your current AudioEngineService with the C++ backend
@interface AudioIOBridge : NSObject

/// Initialization
- (instancetype)initWithReverbBridge:(ReverbBridge *)reverbBridge;

/// Engine lifecycle
- (BOOL)setupAudioEngine;
- (BOOL)startEngine;
- (void)stopEngine;
- (void)resetEngine;

/// Monitoring control
- (void)setMonitoring:(BOOL)enabled;
- (BOOL)isMonitoring;

/// Volume control (optimized for quality)
- (void)setInputVolume:(float)volume;   // 0.1 - 3.0 (optimized range)
- (void)setOutputVolume:(float)volume isMuted:(BOOL)muted;  // 0.0 - 2.5
- (float)inputVolume;

/// Audio level monitoring
- (void)setAudioLevelCallback:(AudioLevelBlock)callback;

/// Reverb preset control (forwards to ReverbBridge)
- (void)setReverbPreset:(ReverbPresetType)preset;
- (ReverbPresetType)currentReverbPreset;

/// Parameter forwarding methods
- (void)setWetDryMix:(float)wetDryMix;
- (void)setDecayTime:(float)decayTime;
- (void)setPreDelay:(float)preDelay;
- (void)setCrossFeed:(float)crossFeed;
- (void)setRoomSize:(float)roomSize;
- (void)setDensity:(float)density;
- (void)setHighFreqDamping:(float)damping;
- (void)setBypass:(BOOL)bypass;

/// Recording support
- (AVAudioMixerNode * _Nullable)getRecordingMixer;
- (AVAudioFormat * _Nullable)getRecordingFormat;

/// Engine state
- (BOOL)isEngineRunning;
- (BOOL)isInitialized;

/// Performance monitoring
- (double)cpuUsage;

/// Advanced configuration
- (void)setPreferredBufferSize:(NSTimeInterval)bufferDuration;
- (void)setPreferredSampleRate:(double)sampleRate;

/// Diagnostics
- (void)printDiagnostics;

@end

NS_ASSUME_NONNULL_END