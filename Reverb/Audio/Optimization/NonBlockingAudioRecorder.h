//
//  NonBlockingAudioRecorder.h
//  Reverb
//
//  High-performance non-blocking audio recorder
//  Optimized for concurrent wet/dry recording without dropping samples
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief High-performance non-blocking audio recorder for concurrent recording
 * 
 * This recorder is designed to handle multiple concurrent recording streams
 * without blocking the main audio thread or dropping samples.
 */
@interface NonBlockingAudioRecorder : NSObject

// Recording state
@property (nonatomic, readonly) BOOL isRecording;
@property (nonatomic, readonly) NSTimeInterval recordingDuration;
@property (nonatomic, readonly) NSString* outputFilePath;

// Performance metrics
@property (nonatomic, readonly) NSUInteger droppedFrames;
@property (nonatomic, readonly) double averageCPULoad;

// Initialization
- (instancetype)initWithRecording:(NSURL*)recordingURL
                           format:(AVAudioFormat*)format
                       bufferSize:(AVAudioFrameCount)bufferSize;

// Legacy initializer
- (instancetype)initWithOutputPath:(NSString*)outputPath
                        sampleRate:(double)sampleRate
                          channels:(NSUInteger)channels
                        bufferSize:(NSUInteger)bufferSize;

// Recording control
- (BOOL)startRecording;
- (BOOL)stopRecording;
- (BOOL)pauseRecording;
- (BOOL)resumeRecording;

// Audio processing - called from audio thread
- (void)processAudioBuffer:(const float*)audioData
                numFrames:(NSUInteger)numFrames
                timestamp:(NSTimeInterval)timestamp;

// Write audio buffer (for compatibility)
- (BOOL)writeAudioBuffer:(AVAudioPCMBuffer*)buffer;

// Configuration
- (void)setGain:(float)gain;
- (void)setQuality:(NSUInteger)quality; // 0=low, 1=medium, 2=high

@end

NS_ASSUME_NONNULL_END