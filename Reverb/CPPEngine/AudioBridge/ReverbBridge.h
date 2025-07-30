#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C bridge for the C++ ReverbEngine
/// Provides thread-safe interface between Swift and C++ DSP code
@interface ReverbBridge : NSObject

/// Reverb preset types matching the Swift implementation
typedef NS_ENUM(NSInteger, ReverbPresetType) {
    ReverbPresetTypeClean = 0,
    ReverbPresetTypeVocalBooth = 1,
    ReverbPresetTypeStudio = 2,
    ReverbPresetTypeCathedral = 3,
    ReverbPresetTypeCustom = 4
};

/// Initialization
- (instancetype)init;

/// Engine lifecycle
- (BOOL)initializeWithSampleRate:(double)sampleRate maxBlockSize:(int)maxBlockSize;
- (void)reset;
- (void)cleanup;

/// Core processing - designed to be called from audio thread
- (void)processAudioWithInputs:(const float * const * _Nonnull)inputs
                       outputs:(float * const * _Nonnull)outputs
                   numChannels:(int)numChannels
                    numSamples:(int)numSamples;

/// Preset management (thread-safe)
- (void)setPreset:(ReverbPresetType)preset;
- (ReverbPresetType)currentPreset;

/// Parameter control (thread-safe, uses atomic operations)
- (void)setWetDryMix:(float)wetDryMix;          // 0-100%
- (void)setDecayTime:(float)decayTime;          // 0.1-8.0 seconds
- (void)setPreDelay:(float)preDelay;            // 0-200 ms
- (void)setCrossFeed:(float)crossFeed;          // 0.0-1.0
- (void)setRoomSize:(float)roomSize;            // 0.0-1.0
- (void)setDensity:(float)density;              // 0-100%
- (void)setHighFreqDamping:(float)damping;      // 0-100%
- (void)setLowFreqDamping:(float)damping;       // 0-100% (AD 480 feature)
- (void)setStereoWidth:(float)width;            // 0.0-2.0 (AD 480 feature)
- (void)setPhaseInvert:(BOOL)invert;            // L/R phase inversion (AD 480 feature)
- (void)setBypass:(BOOL)bypass;

/// Parameter getters (thread-safe)
- (float)wetDryMix;
- (float)decayTime;
- (float)preDelay;
- (float)crossFeed;
- (float)roomSize;
- (float)density;
- (float)highFreqDamping;
- (float)lowFreqDamping;        // AD 480 feature
- (float)stereoWidth;           // AD 480 feature
- (BOOL)phaseInvert;            // AD 480 feature
- (BOOL)isBypassed;

/// Performance monitoring
- (double)cpuUsage;
- (BOOL)isInitialized;

/// Apply preset configurations matching your current Swift presets
- (void)applyCleanPreset;
- (void)applyVocalBoothPreset;
- (void)applyStudioPreset;
- (void)applyCathedralPreset;

/// Custom preset with all parameters
- (void)applyCustomPresetWithWetDryMix:(float)wetDryMix
                             decayTime:(float)decayTime
                              preDelay:(float)preDelay
                             crossFeed:(float)crossFeed
                              roomSize:(float)roomSize
                               density:(float)density
                         highFreqDamping:(float)highFreqDamping;

@end

NS_ASSUME_NONNULL_END