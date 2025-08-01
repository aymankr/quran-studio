//
//  OptimizedAudioBridge.h
//  Reverb
//
//  High-performance Objective-C++ bridge for iOS audio processing
//  Minimizes overhead between Swift/ObjC and C++ audio engine
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief High-performance Objective-C++ bridge for real-time audio processing
 * 
 * This bridge is specifically optimized for iOS to minimize overhead between
 * the Objective-C/Swift UI layer and the C++ audio processing core.
 */
@interface OptimizedAudioBridge : NSObject

// Performance metrics (read-only)
@property (nonatomic, readonly) double cpuUsage;
@property (nonatomic, readonly) double averageCPULoad;
@property (nonatomic, readonly) double peakCPULoad;

// Initialization with optimized settings
- (instancetype)initWithSampleRate:(double)sampleRate 
                        bufferSize:(NSUInteger)bufferSize
                          channels:(NSUInteger)channels;

// Engine control - minimal overhead
- (BOOL)startAudioEngine;
- (BOOL)stopAudioEngine;

// Parameter updates - thread-safe atomic operations
- (void)setWetDryMix:(float)wetDry;
- (void)setInputGain:(float)gain;
- (void)setOutputGain:(float)gain;
- (void)setReverbPreset:(NSUInteger)presetIndex;

// Extended reverb parameters
- (void)setReverbDecay:(float)decay;
- (void)setReverbSize:(float)size;
- (void)setDampingHF:(float)dampingHF;
- (void)setDampingLF:(float)dampingLF;

// Level monitoring for UI (called on main thread only)
- (float)getInputLevel;
- (float)getOutputLevel;

// Recording support
- (BOOL)startRecording:(NSString *)filename;
- (BOOL)stopRecording;
- (BOOL)isRecording;

// Performance optimization controls
- (void)optimizeForLowLatency:(BOOL)enabled;
- (void)enableCPUThrottling:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END