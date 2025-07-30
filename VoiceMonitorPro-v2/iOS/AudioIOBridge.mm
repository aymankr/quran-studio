#import "AudioIOBridge.h"
#import <AudioToolbox/AudioToolbox.h>

@interface AudioIOBridge() {
    AVAudioEngine *audioEngine_;
    AVAudioInputNode *inputNode_;
    AVAudioMixerNode *mainMixer_;
    AVAudioMixerNode *gainMixer_;
    AVAudioMixerNode *recordingMixer_;
    AVAudioFormat *connectionFormat_;
    
    ReverbBridge *reverbBridge_;
    AudioLevelBlock audioLevelCallback_;
    
    BOOL isEngineRunning_;
    BOOL isMonitoring_;
    float inputVolume_;
    float outputVolume_;
    BOOL isMuted_;
    
    // Audio Unit for C++ processing
    AVAudioUnit *customReverbUnit_;
    AUAudioUnit *customAU_;
    
    dispatch_queue_t audioQueue_;
}
@end

@implementation AudioIOBridge

- (instancetype)initWithReverbBridge:(ReverbBridge *)reverbBridge {
    self = [super init];
    if (self) {
        reverbBridge_ = reverbBridge;
        isEngineRunning_ = NO;
        isMonitoring_ = NO;
        inputVolume_ = 1.0f;
        outputVolume_ = 1.4f;
        isMuted_ = NO;
        
        audioQueue_ = dispatch_queue_create("com.voicemonitor.audio", 
                                           DISPATCH_QUEUE_SERIAL);
        
        [self setupAudioSession];
    }
    return self;
}

- (void)dealloc {
    [self stopEngine];
}

#pragma mark - Audio Session Setup

- (void)setupAudioSession {
#if TARGET_OS_IOS
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    // Configure for high-quality monitoring
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker |
                        AVAudioSessionCategoryOptionAllowBluetooth |
                        AVAudioSessionCategoryOptionMixWithOthers
                   error:&error];
    
    if (error) {
        NSLog(@"❌ Audio session category error: %@", error.localizedDescription);
    }
    
    // Optimal settings for quality
    [session setPreferredSampleRate:44100 error:&error];
    [session setPreferredIOBufferDuration:0.01 error:&error]; // ~1.3ms for low latency
    [session setPreferredInputNumberOfChannels:2 error:&error];
    
    [session setActive:YES error:&error];
    
    if (error) {
        NSLog(@"❌ Audio session setup error: %@", error.localizedDescription);
    } else {
        NSLog(@"✅ High-quality audio session configured");
    }
#else
    // macOS
    NSLog(@"🍎 macOS audio session ready");
    [self requestMicrophonePermission];
#endif
}

#if TARGET_OS_OSX
- (void)requestMicrophonePermission {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    
    if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"🎤 Microphone access granted: %@", granted ? @"YES" : @"NO");
                if (granted) {
                    [self setupAudioEngine];
                }
            });
        }];
    }
}
#endif

#pragma mark - Engine Setup

- (BOOL)setupAudioEngine {
    NSLog(@"🎵 Setting up high-quality audio engine with C++ backend");
    
    [self cleanupEngine];
    
    audioEngine_ = [[AVAudioEngine alloc] init];
    inputNode_ = audioEngine_.inputNode;
    mainMixer_ = audioEngine_.mainMixerNode;
    mainMixer_.outputVolume = 1.4f; // Optimized gain
    
    // Create processing chain
    gainMixer_ = [[AVAudioMixerNode alloc] init];
    gainMixer_.outputVolume = 1.3f;
    [audioEngine_ attachNode:gainMixer_];
    
    recordingMixer_ = [[AVAudioMixerNode alloc] init];
    recordingMixer_.outputVolume = 1.0f;
    [audioEngine_ attachNode:recordingMixer_];
    
    // Get audio format
    AVAudioFormat *inputFormat = [inputNode_ inputFormatForBus:0];
    if (inputFormat.sampleRate <= 0 || inputFormat.channelCount <= 0) {
        NSLog(@"❌ Invalid audio format detected");
        return NO;
    }
    
    // Create stereo format for processing
    connectionFormat_ = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:inputFormat.sampleRate
                                                                       channels:2];
    
    NSLog(@"🔗 Audio format: %.0f Hz, %u channels", connectionFormat_.sampleRate, connectionFormat_.channelCount);
    
    // Initialize C++ reverb engine
    if (![reverbBridge_ initializeWithSampleRate:connectionFormat_.sampleRate 
                                    maxBlockSize:512]) {
        NSLog(@"❌ Failed to initialize C++ reverb engine");
        return NO;
    }
    
    // Create custom audio unit for C++ processing
    [self setupCustomAudioUnit];
    
    NSError *error = nil;
    
    // Connect audio graph
    [audioEngine_ connect:inputNode_ to:gainMixer_ format:connectionFormat_];
    [audioEngine_ connect:gainMixer_ to:recordingMixer_ format:connectionFormat_];
    [audioEngine_ connect:recordingMixer_ to:mainMixer_ format:connectionFormat_];
    
    // Prepare engine
    [audioEngine_ prepare];
    
    NSLog(@"✅ High-quality audio engine with C++ backend configured");
    return YES;
}

- (void)setupCustomAudioUnit {
    // Install tap on recording mixer to process through C++ engine
    [recordingMixer_ removeTapOnBus:0];
    
    __weak typeof(self) weakSelf = self;
    [recordingMixer_ installTapOnBus:0 
                          bufferSize:512 
                              format:connectionFormat_ 
                               block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        [strongSelf processAudioBuffer:buffer];
    }];
}

- (void)processAudioBuffer:(AVAudioPCMBuffer *)buffer {
    if (!reverbBridge_ || ![reverbBridge_ isInitialized]) {
        return;
    }
    
    // Get audio data
    float **channelData = buffer.floatChannelData;
    int numChannels = (int)buffer.format.channelCount;
    int numSamples = (int)buffer.frameLength;
    
    if (!channelData || numSamples == 0) {
        return;
    }
    
    // Process through C++ reverb engine
    [reverbBridge_ processAudioWithInputs:(const float **)channelData
                                  outputs:channelData
                              numChannels:numChannels
                               numSamples:numSamples];
    
    // Calculate audio level for monitoring
    [self calculateAudioLevel:channelData numChannels:numChannels numSamples:numSamples];
}

- (void)calculateAudioLevel:(float **)channelData numChannels:(int)numChannels numSamples:(int)numSamples {
    if (!audioLevelCallback_) return;
    
    float totalLevel = 0.0f;
    
    for (int ch = 0; ch < numChannels; ch++) {
        float channelLevel = 0.0f;
        float *samples = channelData[ch];
        
        // Calculate RMS level
        for (int i = 0; i < numSamples; i++) {
            float sample = fabsf(samples[i]);
            channelLevel += sample * sample;
        }
        
        channelLevel = sqrtf(channelLevel / numSamples);
        totalLevel += channelLevel;
    }
    
    float averageLevel = totalLevel / numChannels;
    float displayLevel = fminf(1.0f, fmaxf(0.0f, averageLevel * 2.0f)); // Scale for display
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->audioLevelCallback_) {
            self->audioLevelCallback_(displayLevel);
        }
    });
}

#pragma mark - Engine Control

- (BOOL)startEngine {
    if (isEngineRunning_) {
        return YES;
    }
    
    if (!audioEngine_) {
        [self setupAudioEngine];
    }
    
    NSError *error = nil;
    
#if TARGET_OS_IOS
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) {
        NSLog(@"❌ Failed to activate audio session: %@", error.localizedDescription);
        return NO;
    }
#endif
    
    [audioEngine_ startAndReturnError:&error];
    if (error) {
        NSLog(@"❌ Failed to start audio engine: %@", error.localizedDescription);
        return NO;
    }
    
    isEngineRunning_ = YES;
    NSLog(@"🎵 High-quality audio engine started successfully");
    
    return YES;
}

- (void)stopEngine {
    if (audioEngine_ && audioEngine_.isRunning) {
        [recordingMixer_ removeTapOnBus:0];
        [audioEngine_ stop];
        isEngineRunning_ = NO;
        NSLog(@"🛑 Audio engine stopped");
    }
}

- (void)resetEngine {
    [self stopEngine];
    [reverbBridge_ reset];
    usleep(100000); // 100ms delay
    [self setupAudioEngine];
}

- (void)cleanupEngine {
    if (audioEngine_ && audioEngine_.isRunning) {
        [recordingMixer_ removeTapOnBus:0];
        [audioEngine_ stop];
    }
    isEngineRunning_ = NO;
}

#pragma mark - Monitoring Control

- (void)setMonitoring:(BOOL)enabled {
    if (enabled) {
        if ([self startEngine]) {
            isMonitoring_ = YES;
            [self applyOptimalGains];
            NSLog(@"🎵 High-quality monitoring started");
        }
    } else {
        [self stopEngine];
        isMonitoring_ = NO;
        NSLog(@"🔇 Monitoring stopped");
    }
}

- (BOOL)isMonitoring {
    return isMonitoring_;
}

- (void)applyOptimalGains {
    gainMixer_.outputVolume = 1.3f;
    mainMixer_.outputVolume = isMuted_ ? 0.0f : outputVolume_;
    recordingMixer_.outputVolume = 1.0f;
    inputNode_.volume = inputVolume_;
}

#pragma mark - Volume Control

- (void)setInputVolume:(float)volume {
    // Optimized range for quality: 0.1 - 3.0
    float optimizedVolume = fmaxf(0.1f, fminf(3.0f, volume * 0.8f));
    inputVolume_ = optimizedVolume;
    
    if (inputNode_) {
        inputNode_.volume = optimizedVolume;
    }
    
    if (gainMixer_) {
        gainMixer_.volume = fmaxf(1.0f, optimizedVolume * 0.7f);
    }
    
    NSLog(@"🎵 Input volume: %.2f (optimized: %.2f)", volume, optimizedVolume);
}

- (void)setOutputVolume:(float)volume isMuted:(BOOL)muted {
    isMuted_ = muted;
    
    if (muted) {
        outputVolume_ = 0.0f;
    } else {
        // Optimized range: 0.0 - 2.5
        outputVolume_ = fmaxf(0.0f, fminf(2.5f, volume * 0.9f));
    }
    
    if (mainMixer_) {
        mainMixer_.outputVolume = isEngineRunning_ ? outputVolume_ : 0.0f;
    }
    
    NSLog(@"🔊 Output volume: %.2f (muted: %@)", outputVolume_, muted ? @"YES" : @"NO");
}

- (float)inputVolume {
    return inputVolume_;
}

#pragma mark - Audio Level Monitoring

- (void)setAudioLevelCallback:(AudioLevelBlock)callback {
    audioLevelCallback_ = [callback copy];
}

#pragma mark - Reverb Control (Forwarding)

- (void)setReverbPreset:(ReverbPresetType)preset {
    [reverbBridge_ setPreset:preset];
}

- (ReverbPresetType)currentReverbPreset {
    return [reverbBridge_ currentPreset];
}

- (void)setWetDryMix:(float)wetDryMix {
    [reverbBridge_ setWetDryMix:wetDryMix];
}

- (void)setDecayTime:(float)decayTime {
    [reverbBridge_ setDecayTime:decayTime];
}

- (void)setPreDelay:(float)preDelay {
    [reverbBridge_ setPreDelay:preDelay];
}

- (void)setCrossFeed:(float)crossFeed {
    [reverbBridge_ setCrossFeed:crossFeed];
}

- (void)setRoomSize:(float)roomSize {
    [reverbBridge_ setRoomSize:roomSize];
}

- (void)setDensity:(float)density {
    [reverbBridge_ setDensity:density];
}

- (void)setHighFreqDamping:(float)damping {
    [reverbBridge_ setHighFreqDamping:damping];
}

- (void)setBypass:(BOOL)bypass {
    [reverbBridge_ setBypass:bypass];
}

#pragma mark - Recording Support

- (AVAudioMixerNode *)getRecordingMixer {
    return recordingMixer_;
}

- (AVAudioFormat *)getRecordingFormat {
    return connectionFormat_;
}

#pragma mark - Engine State

- (BOOL)isEngineRunning {
    return isEngineRunning_ && audioEngine_.isRunning;
}

- (BOOL)isInitialized {
    return audioEngine_ != nil && [reverbBridge_ isInitialized];
}

- (double)cpuUsage {
    return [reverbBridge_ cpuUsage];
}

#pragma mark - Advanced Configuration

- (void)setPreferredBufferSize:(NSTimeInterval)bufferDuration {
#if TARGET_OS_IOS
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setPreferredIOBufferDuration:bufferDuration error:&error];
    if (error) {
        NSLog(@"❌ Failed to set buffer duration: %@", error.localizedDescription);
    }
#endif
}

- (void)setPreferredSampleRate:(double)sampleRate {
#if TARGET_OS_IOS
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setPreferredSampleRate:sampleRate error:&error];
    if (error) {
        NSLog(@"❌ Failed to set sample rate: %@", error.localizedDescription);
    }
#endif
}

#pragma mark - Diagnostics

- (void)printDiagnostics {
    NSLog(@"🔍 === AUDIO BRIDGE DIAGNOSTICS ===");
    NSLog(@"Engine running: %@", [self isEngineRunning] ? @"YES" : @"NO");
    NSLog(@"Monitoring: %@", isMonitoring_ ? @"YES" : @"NO");
    NSLog(@"C++ engine initialized: %@", [reverbBridge_ isInitialized] ? @"YES" : @"NO");
    NSLog(@"Current preset: %ld", (long)[reverbBridge_ currentPreset]);
    NSLog(@"Input volume: %.2f", inputVolume_);
    NSLog(@"Output volume: %.2f (muted: %@)", outputVolume_, isMuted_ ? @"YES" : @"NO");
    NSLog(@"CPU usage: %.2f%%", [self cpuUsage]);
    
    if (connectionFormat_) {
        NSLog(@"Format: %.0f Hz, %u channels", connectionFormat_.sampleRate, connectionFormat_.channelCount);
    }
    
    NSLog(@"=== END DIAGNOSTICS ===");
}

@end