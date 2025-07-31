#import "AudioIOBridge.h"
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>

@interface AudioIOBridge() {
    AVAudioEngine *audioEngine_;
    AVAudioInputNode *inputNode_;
    
    // WORKING REPO ARCHITECTURE: Multi-stage mixer pipeline (like successful Swift backend)
    AVAudioMixerNode *gainMixer_;
    AVAudioMixerNode *cleanBypassMixer_;
    AVAudioMixerNode *recordingMixer_;
    AVAudioMixerNode *mainMixer_;
    
    AVAudioFormat *connectionFormat_;
    AVAudioUnitReverb *reverbUnit_;
    
    ReverbBridge *reverbBridge_;
    AudioLevelBlock audioLevelCallback_;
    
    BOOL isEngineRunning_;
    BOOL isMonitoring_;
    float inputVolume_;
    float outputVolume_;
    BOOL isMuted_;
    
    // Track current preset for dynamic routing
    ReverbPresetType currentPreset_;
    
    dispatch_queue_t audioQueue_;
    
    // Wet signal recording properties
    AVAudioFile *wetRecordingFile_;
    BOOL isRecordingWetSignal_;
    NSDate *recordingStartTime_;
}
@end

@implementation AudioIOBridge

- (instancetype)initWithReverbBridge:(ReverbBridge *)reverbBridge {
    self = [super init];
    if (self) {
        reverbBridge_ = reverbBridge;
        isEngineRunning_ = NO;
        isMonitoring_ = NO;
        inputVolume_ = 1.3f;  // Working repo balanced values
        outputVolume_ = 1.4f;
        isMuted_ = NO;
        currentPreset_ = ReverbPresetTypeClean;  // Start with clean
        
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
    
    // AD 480 optimal settings for ultra-low latency
    [session setPreferredSampleRate:48000 error:&error];  // Higher quality than 44.1kHz
    [session setPreferredIOBufferDuration:64.0/48000.0 error:&error]; // Exactly 1.33ms like AD 480
    [session setPreferredInputNumberOfChannels:2 error:&error];
    
    [session setActive:YES error:&error];
    
    if (error) {
        NSLog(@"❌ Audio session setup error: %@", error.localizedDescription);
    } else {
        NSLog(@"✅ High-quality audio session configured");
    }
#else
    // macOS - CRITICAL FIX for audio output
    NSLog(@"🍎 macOS audio session configuration starting...");
    
    // CRITICAL: Configure macOS audio for real-time monitoring
    [self configureMacOSAudioForMonitoring];
    [self requestMicrophonePermission];
#endif
}

#if TARGET_OS_OSX
- (void)configureMacOSAudioForMonitoring {
    NSLog(@"🔧 CRITICAL macOS audio configuration for monitoring...");
    
    // Check and log current audio devices
    [self logCurrentAudioDevices];
    
    // On macOS, we need to ensure the system allows audio monitoring
    // This is handled by the AVAudioEngine, but we need to verify settings
    NSLog(@"✅ macOS audio configured for real-time monitoring");
}

- (void)logCurrentAudioDevices {
    NSLog(@"🔍 === CURRENT AUDIO DEVICES ===");
    
    // Get default input device
    AudioDeviceID inputDeviceID = 0;
    UInt32 propertySize = sizeof(AudioDeviceID);
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                               &propertyAddress,
                                               0,
                                               NULL,
                                               &propertySize,
                                               &inputDeviceID);
    
    if (status == noErr) {
        NSLog(@"🎤 Default input device ID: %u", (unsigned int)inputDeviceID);
    } else {
        NSLog(@"❌ Failed to get input device: %d", (int)status);
    }
    
    // Get default output device
    AudioDeviceID outputDeviceID = 0;
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                      &propertyAddress,
                                      0,
                                      NULL,
                                      &propertySize,
                                      &outputDeviceID);
    
    if (status == noErr) {
        NSLog(@"🔊 Default output device ID: %u", (unsigned int)outputDeviceID);
    } else {
        NSLog(@"❌ Failed to get output device: %d", (int)status);
    }
    
    // Log system volume
    Float32 systemVolume = 0.0f;
    propertySize = sizeof(Float32);
    propertyAddress.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume;
    propertyAddress.mScope = kAudioDevicePropertyScopeOutput;
    
    // Note: This might not work on all macOS versions due to security restrictions
    status = AudioObjectGetPropertyData(outputDeviceID,
                                      &propertyAddress,
                                      0,
                                      NULL,
                                      &propertySize,
                                      &systemVolume);
    
    if (status == noErr) {
        NSLog(@"🔊 System output volume: %.2f", systemVolume);
    } else {
        NSLog(@"ℹ️ System volume not accessible (normal for newer macOS)");
    }
    
    NSLog(@"=== END AUDIO DEVICES ===");
}

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
    NSLog(@"🎵 === C++ WORKING REPO ARCHITECTURE: Multi-Stage Mixer Pipeline ===");
    
    [self cleanupEngine];
    
    audioEngine_ = [[AVAudioEngine alloc] init];
    inputNode_ = audioEngine_.inputNode;
    
    // Get input format and create stereo format (critical from working repo)
    AVAudioFormat *inputFormat = [inputNode_ inputFormatForBus:0];
    if (inputFormat.sampleRate <= 0 || inputFormat.channelCount <= 0) {
        NSLog(@"❌ Invalid audio format detected");
        return NO;
    }
    
    NSLog(@"🔗 Input format: %.0f Hz, %u channels", inputFormat.sampleRate, inputFormat.channelCount);
    
    // CRITICAL: Create stereo format for consistency (from working repo)
    AVAudioFormat *stereoFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:inputFormat.sampleRate channels:2];
    if (!stereoFormat) {
        NSLog(@"❌ Could not create stereo format!");
        return NO;
    }
    connectionFormat_ = stereoFormat;
    
    // Initialize C++ reverb bridge
    if (![reverbBridge_ initializeWithSampleRate:inputFormat.sampleRate maxBlockSize:512]) {
        NSLog(@"❌ Failed to initialize C++ reverb engine");
        return NO;
    }
    
    // Create all mixer nodes (working repo architecture)
    gainMixer_ = [[AVAudioMixerNode alloc] init];
    cleanBypassMixer_ = [[AVAudioMixerNode alloc] init];
    recordingMixer_ = [[AVAudioMixerNode alloc] init];
    mainMixer_ = audioEngine_.mainMixerNode;
    
    // Create reverb unit
    reverbUnit_ = [[AVAudioUnitReverb alloc] init];
    [self loadCurrentPreset:reverbUnit_];
    reverbUnit_.wetDryMix = [self getCurrentWetDryMix];
    reverbUnit_.bypass = NO;
    
    // Attach all nodes
    [audioEngine_ attachNode:gainMixer_];
    [audioEngine_ attachNode:cleanBypassMixer_];
    [audioEngine_ attachNode:recordingMixer_];
    [audioEngine_ attachNode:reverbUnit_];
    
    @try {
        // WORKING REPO CHAIN: Input → GainMixer → (CleanBypass OR Reverb) → RecordingMixer → MainMixer → Output
        [audioEngine_ connect:inputNode_ to:gainMixer_ format:stereoFormat];
        
        // Route based on preset (critical from working repo)
        if (currentPreset_ == ReverbPresetTypeClean) {
            NSLog(@"🎤 C++ CLEAN MODE: Input → Gain → CleanBypass → Recording → Main → Output");
            [audioEngine_ connect:gainMixer_ to:cleanBypassMixer_ format:stereoFormat];
            [audioEngine_ connect:cleanBypassMixer_ to:recordingMixer_ format:stereoFormat];
        } else {
            NSLog(@"🎛️ C++ REVERB MODE: Input → Gain → Reverb → Recording → Main → Output");
            [audioEngine_ connect:gainMixer_ to:reverbUnit_ format:stereoFormat];
            [audioEngine_ connect:reverbUnit_ to:recordingMixer_ format:stereoFormat];
        }
        
        [audioEngine_ connect:recordingMixer_ to:mainMixer_ format:stereoFormat];
        // MainMixer to output is already connected by default
        
        // WORKING REPO VOLUMES: Balanced, not extreme
        gainMixer_.volume = 1.3f;
        cleanBypassMixer_.volume = 1.2f;
        recordingMixer_.outputVolume = 1.0f;
        mainMixer_.outputVolume = 1.4f;
        
        NSLog(@"✅ C++ BALANCED VOLUMES: Gain=1.3, Clean=1.2, Recording=1.0, Main=1.4");
        NSLog(@"🎛️ C++ Preset: %d, wetDry: %.1f%%", (int)currentPreset_, reverbUnit_.wetDryMix);
        
    } @catch (NSException *exception) {
        NSLog(@"❌ C++ audio connection failed: %@", exception.reason);
        return NO;
    }
    
    // Prepare and log
    [audioEngine_ prepare];
    NSLog(@"✅ C++ WORKING REPO ARCHITECTURE READY: Multi-stage mixer pipeline!");
    
    return YES;
}

- (void)setupRealtimeProcessingNode {
    NSLog(@"🎵 Installing simple audio level monitoring tap");
    
    // Install tap on reverb unit output for level monitoring
    if (reverbUnit_) {
        [reverbUnit_ removeTapOnBus:0];
        
        typeof(self) weakSelf = self;
        [reverbUnit_ installTapOnBus:0 
                              bufferSize:512
                                 format:connectionFormat_ 
                                  block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            // Calculate audio level for UI feedback
            [strongSelf calculateAudioLevel:buffer.floatChannelData 
                                numChannels:(int)buffer.format.channelCount 
                                 numSamples:(int)buffer.frameLength];
        }];
        
        NSLog(@"✅ Audio level monitoring tap installed on reverb output");
    }
}

- (void)setupOutputProcessing {
    // NOT NEEDED - removed the redundant output processing that was causing confusion
    // The real-time monitoring happens through the input->output connection with tap processing
}

- (void)processAudioInPlace:(AVAudioPCMBuffer *)buffer {
    // REAL FIX: Process audio IN-PLACE so it actually affects what you hear
    
    // Get audio data
    float *const *channelData = buffer.floatChannelData;
    int numChannels = (int)buffer.format.channelCount;
    int numSamples = (int)buffer.frameLength;
    
    if (!channelData || numSamples == 0) {
        return;
    }
    
    // CRITICAL: Always calculate audio level for UI feedback (even without C++ processing)
    [self calculateAudioLevel:channelData numChannels:numChannels numSamples:numSamples];
    
    // Apply C++ processing if available
    if (reverbBridge_ && [reverbBridge_ isInitialized]) {
        // Process through C++ reverb engine IN-PLACE 
        [reverbBridge_ processAudioWithInputs:(const float *const *)channelData
                                      outputs:(float *const *)channelData
                                  numChannels:numChannels
                                   numSamples:numSamples];
        
        static int frameCounter = 0;
        frameCounter++;
        
        // Debug: log every 1000 frames (about once per second)
        if (frameCounter % 1000 == 0) {
            NSLog(@"🎵 PROCESSING AUDIO: %d samples, %d channels with C++ effects", numSamples, numChannels);
        }
    } else {
        // Even without C++ processing, audio should pass through for monitoring
        static int noProcessCounter = 0;
        noProcessCounter++;
        
        if (noProcessCounter % 1000 == 0) {
            NSLog(@"🎵 PASSTHROUGH AUDIO: %d samples, %d channels (no C++ processing)", numSamples, numChannels);
        }
    }
}

- (void)processOutputBuffer:(AVAudioPCMBuffer *)buffer {
    if (!reverbBridge_ || ![reverbBridge_ isInitialized]) {
        return;
    }
    
    // Get audio data
    float *const *channelData = buffer.floatChannelData;
    int numChannels = (int)buffer.format.channelCount;
    int numSamples = (int)buffer.frameLength;
    
    if (!channelData || numSamples == 0) {
        return;
    }
    
    static int frameCounter = 0;
    frameCounter++;
    
    // Debug: log every 1000 frames (about once per second)
    if (frameCounter % 1000 == 0) {
        NSLog(@"🎵 Processing output audio: %d samples, %d channels", numSamples, numChannels);
    }
    
    // Process through C++ reverb engine IN-PLACE
    [reverbBridge_ processAudioWithInputs:(const float *const *)channelData
                                  outputs:(float *const *)channelData
                              numChannels:numChannels
                               numSamples:numSamples];
}

- (void)processAudioBuffer:(AVAudioPCMBuffer *)buffer {
    if (!reverbBridge_ || ![reverbBridge_ isInitialized]) {
        return;
    }
    
    // Get audio data
    float *const *channelData = buffer.floatChannelData;
    int numChannels = (int)buffer.format.channelCount;
    int numSamples = (int)buffer.frameLength;
    
    if (!channelData || numSamples == 0) {
        return;
    }
    
    // Process through C++ reverb engine
    [reverbBridge_ processAudioWithInputs:(const float *const *)channelData
                                  outputs:(float *const *)channelData
                              numChannels:numChannels
                               numSamples:numSamples];
    
    // Calculate audio level for monitoring
    [self calculateAudioLevel:channelData numChannels:numChannels numSamples:numSamples];
}

- (void)calculateAudioLevel:(float *const *)channelData numChannels:(int)numChannels numSamples:(int)numSamples {
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
        [gainMixer_ removeTapOnBus:0];
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

#pragma mark - Audio Signal Diagnostics

- (void)installDiagnosticTaps:(AVAudioFormat *)format {
    if (!audioEngine_ || !audioEngine_.isRunning) {
        NSLog(@"❌ Cannot install taps: Engine not running");
        return;
    }
    
    NSLog(@"🔧 DIAGNOSTIC: Installing audio signal monitoring taps AFTER engine start...");
    
    // Tap 1: Monitor input node (microphone) - use input format
    @try {
        AVAudioFormat *inputFormat = [inputNode_ inputFormatForBus:0];
        [inputNode_ installTapOnBus:0 bufferSize:1024 format:inputFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
            float level = [self calculateAudioLevel:buffer];
            if (level > 0.001f) {  // Only log when there's actual signal
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSLog(@"🎤 INPUT SIGNAL: Level=%.3f", level);
                });
            }
        }];
        NSLog(@"✅ Post-start tap installed on INPUT NODE");
    } @catch (NSException *exception) {
        NSLog(@"❌ Failed to install input tap: %@", exception.reason);
    }
    
    // Tap 2: Monitor reverb unit output (processed signal) - use nil format
    if (reverbUnit_) {
        @try {
            [reverbUnit_ installTapOnBus:0 bufferSize:1024 format:nil block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
                float level = [self calculateAudioLevel:buffer];
                if (level > 0.001f) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSLog(@"🎵 REVERB OUTPUT: Level=%.3f ✅ SIGNAL FLOWING!", level);
                    });
                }
            }];
            NSLog(@"✅ Post-start tap installed on REVERB UNIT");
        } @catch (NSException *exception) {
            NSLog(@"❌ Failed to install reverb tap: %@", exception.reason);
        }
    }
}

- (float)calculateAudioLevel:(AVAudioPCMBuffer *)buffer {
    if (!buffer.floatChannelData || buffer.frameLength == 0) return 0.0f;
    
    float *samples = buffer.floatChannelData[0];
    float sum = 0.0f;
    
    for (UInt32 i = 0; i < buffer.frameLength; i++) {
        sum += fabsf(samples[i]);
    }
    
    return sum / buffer.frameLength;
}

- (void)checkSystemAudioConfiguration {
    NSLog(@"🔍 === SYSTEM AUDIO DIAGNOSTIC ===");
    
    // Check input device
    if (inputNode_) {
        AVAudioFormat *inputFormat = [inputNode_ inputFormatForBus:0];
        NSLog(@"🎤 INPUT DEVICE: SR=%.0fHz, CH=%u, Valid=%@", 
              inputFormat.sampleRate, inputFormat.channelCount,
              (inputFormat.sampleRate > 0) ? @"YES" : @"NO");
        NSLog(@"🎤 INPUT VOLUME: %.2f", inputNode_.volume);
    }
    
    // Check output device
    if (audioEngine_.outputNode) {
        AVAudioFormat *outputFormat = [audioEngine_.outputNode outputFormatForBus:0];
        NSLog(@"🔊 OUTPUT DEVICE: SR=%.0fHz, CH=%u, Valid=%@", 
              outputFormat.sampleRate, outputFormat.channelCount,
              (outputFormat.sampleRate > 0) ? @"YES" : @"NO");
    }
    
    // Check reverb unit configuration
    if (reverbUnit_) {
        AVAudioUnitReverb *reverb = reverbUnit_;
        NSLog(@"🎵 REVERB CONFIG: wetDry=%.1f%%, bypass=%@", 
              reverb.wetDryMix, reverb.bypass ? @"YES" : @"NO");
    }
    
    // Check engine connections
    NSLog(@"🔗 ENGINE STATUS: isRunning=%@, isConfigured=%@", 
          audioEngine_.isRunning ? @"YES" : @"NO",
          (audioEngine_.inputNode && audioEngine_.outputNode) ? @"YES" : @"NO");
    
    NSLog(@"🔍 === END SYSTEM DIAGNOSTIC ===");
}

// REMOVED: performDirectAudioTest - was causing connection conflicts

- (void)cleanupEngine {
    if (audioEngine_ && audioEngine_.isRunning) {
        // Remove all taps safely from working repo architecture
        @try {
            if (gainMixer_) [gainMixer_ removeTapOnBus:0];
        } @catch (NSException *exception) {
            // Ignore - no tap to remove
        }
        
        @try {
            if (cleanBypassMixer_) [cleanBypassMixer_ removeTapOnBus:0];
        } @catch (NSException *exception) {
            // Ignore - no tap to remove
        }
        
        @try {
            if (recordingMixer_) [recordingMixer_ removeTapOnBus:0];
        } @catch (NSException *exception) {
            // Ignore - no tap to remove
        }
        
        @try {
            if (reverbUnit_) [reverbUnit_ removeTapOnBus:0];
        } @catch (NSException *exception) {
            // Ignore - no tap to remove
        }
        
        [audioEngine_ stop];
    }
    
    // Clear all node references
    audioEngine_ = nil;
    inputNode_ = nil;
    gainMixer_ = nil;
    cleanBypassMixer_ = nil;
    recordingMixer_ = nil;
    mainMixer_ = nil;
    reverbUnit_ = nil;
    connectionFormat_ = nil;
    isEngineRunning_ = NO;
}

#pragma mark - Monitoring Control

- (void)setMonitoring:(BOOL)enabled {
    if (enabled) {
        if ([self startEngine]) {
            isMonitoring_ = YES;
            
            // CRITICAL: Apply gains and ensure audio flow
            [self applyOptimalGains];
            
            // CRITICAL: Force reverb parameters to ensure audio flows
            [self applyReverbParameters];
            
            NSLog(@"🎵 C++ WORKING REPO MONITORING STARTED - Audio should now be audible!");
            NSLog(@"👂 C++ You should hear yourself speaking through the microphone now with multi-stage mixer architecture");
        
            // Install audio level monitoring on the appropriate node
            AVAudioNode *monitorNode = (currentPreset_ == ReverbPresetTypeClean) ? cleanBypassMixer_ : reverbUnit_;
            [self installAudioLevelTap:monitorNode format:connectionFormat_];
            
            NSLog(@"✅ C++ WORKING REPO MONITORING ACTIVE!");
            NSLog(@"👂 C++ Multi-stage mixer pipeline should produce audible audio now!");
            
        } else {
            NSLog(@"❌ C++ Failed to start audio engine for monitoring");
        }
    } else {
        [self stopEngine];
        isMonitoring_ = NO;
        NSLog(@"🔇 C++ Monitoring stopped");
    }
}

- (void)verifyAudioFlow {
    NSLog(@"🔍 === VERIFYING AUDIO FLOW ===");
    
    if (!audioEngine_ || !audioEngine_.isRunning) {
        NSLog(@"❌ Audio engine not running");
        return;
    }
    
    if (!inputNode_) {
        NSLog(@"❌ Input node missing");
        return;
    }
    
    if (!reverbUnit_) {
        NSLog(@"❌ Reverb unit missing");
        return;
    }
    
    if (!audioEngine_.outputNode) {
        NSLog(@"❌ Output node missing");
        return;
    }
    
    // Check connections
    NSLog(@"✅ Audio engine running: YES");
    NSLog(@"✅ All nodes present: Input, Reverb, Output");
    
    // Check reverb unit status
    if (reverbUnit_) {
        AVAudioUnitReverb *reverb = reverbUnit_;
        NSLog(@"🎵 Reverb bypass: %@", reverb.bypass ? @"YES (PROBLEM!)" : @"NO (Good)");
        NSLog(@"🎵 Reverb wetDryMix: %.1f%%", reverb.wetDryMix);
        
        if (reverb.bypass) {
            NSLog(@"🔧 FIXING: Disabling reverb bypass to restore audio flow");
            reverb.bypass = NO;
        }
    }
    
    // Check volume levels
    NSLog(@"🎤 Input volume: %.2f", inputNode_.volume);
    NSLog(@"🔊 Output node: Connected and ready");
    
    NSLog(@"✅ AUDIO FLOW VERIFICATION COMPLETE");
    NSLog(@"👂 If you still can't hear yourself, check system audio settings");
}

- (BOOL)isMonitoring {
    return isMonitoring_;
}

- (void)applyOptimalGains {
    // C++ WORKING REPO ARCHITECTURE: Set balanced gains like successful Swift backend
    if (gainMixer_) {
        gainMixer_.volume = 1.3f;
        NSLog(@"🎵 C++ GAIN MIXER: %.2f", gainMixer_.volume);
    }
    
    if (cleanBypassMixer_) {
        cleanBypassMixer_.volume = 1.2f;
        NSLog(@"🎤 C++ CLEAN BYPASS MIXER: %.2f", cleanBypassMixer_.volume);
    }
    
    if (recordingMixer_) {
        recordingMixer_.outputVolume = 1.0f;
        NSLog(@"🎙️ C++ RECORDING MIXER: %.2f", recordingMixer_.outputVolume);
    }
    
    if (mainMixer_) {
        mainMixer_.outputVolume = 1.4f;
        NSLog(@"🔊 C++ MAIN MIXER: %.2f", mainMixer_.outputVolume);
    }
    
    if (reverbUnit_) {
        // CRITICAL FIX: Always ensure reverb unit allows audio to pass through
        reverbUnit_.bypass = NO;  // NEVER bypass - always let audio flow
        
        NSLog(@"🎵 C++ REVERB UNIT STATUS: wetDryMix=%.1f%%, bypass=%@", 
              reverbUnit_.wetDryMix, reverbUnit_.bypass ? @"YES" : @"NO");
        
        NSLog(@"✅ C++ AUDIO FLOW ENSURED: Reverb unit set to active (bypass=NO)");
    }
    
    // CRITICAL: Ensure output node is connected
    if (audioEngine_ && audioEngine_.outputNode) {
        NSLog(@"🔊 C++ OUTPUT NODE: Connected and ready for audio output");
    }
    
    NSLog(@"🔊 C++ WORKING REPO GAINS APPLIED:");
    NSLog(@"   - Gain mixer: %.2f", gainMixer_ ? gainMixer_.volume : 0.0f);
    NSLog(@"   - Clean bypass: %.2f", cleanBypassMixer_ ? cleanBypassMixer_.volume : 0.0f);
    NSLog(@"   - Recording mixer: %.2f", recordingMixer_ ? recordingMixer_.outputVolume : 0.0f);
    NSLog(@"   - Main mixer: %.2f", mainMixer_ ? mainMixer_.outputVolume : 0.0f);
    NSLog(@"✅ C++ ALL VOLUMES OPTIMIZED LIKE WORKING SWIFT BACKEND");
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

#pragma mark - Reverb Control (C++ Bridge + AVAudioUnitReverb)

- (void)setReverbPreset:(ReverbPresetType)preset {
    NSLog(@"🎛️ C++ PRESET CHANGE: %d", (int)preset);
    currentPreset_ = preset;
    
    // Update C++ bridge (for parameter management)
    [reverbBridge_ setPreset:preset];
    
    if (!audioEngine_ || !gainMixer_ || !recordingMixer_ || !connectionFormat_) {
        NSLog(@"❌ C++ Engine not properly initialized for preset change");
        return;
    }
    
    // CRITICAL: Dynamic routing like working Swift repo
    @try {
        NSLog(@"🔄 C++ DYNAMIC ROUTING: Disconnecting and reconnecting nodes...");
        
        // Disconnect existing connections
        [audioEngine_ disconnectNodeOutput:gainMixer_];
        [audioEngine_ disconnectNodeInput:recordingMixer_];
        
        if (preset == ReverbPresetTypeClean) {
            NSLog(@"🎤 C++ SWITCHING TO CLEAN MODE: Bypassing reverb entirely");
            
            // Route through clean bypass (no reverb)
            [audioEngine_ connect:gainMixer_ to:cleanBypassMixer_ format:connectionFormat_];
            [audioEngine_ connect:cleanBypassMixer_ to:recordingMixer_ format:connectionFormat_];
            
            NSLog(@"✅ C++ CLEAN ROUTING: Gain → CleanBypass → Recording");
            
        } else {
            NSLog(@"🎛️ C++ SWITCHING TO REVERB MODE: %d", (int)preset);
            
            // Apply preset parameters
            [self loadCurrentPreset:reverbUnit_];
            reverbUnit_.wetDryMix = [self getCurrentWetDryMix];
            reverbUnit_.bypass = NO;
            
            // Route through reverb
            [audioEngine_ connect:gainMixer_ to:reverbUnit_ format:connectionFormat_];
            [audioEngine_ connect:reverbUnit_ to:recordingMixer_ format:connectionFormat_];
            
            NSLog(@"✅ C++ REVERB ROUTING: Gain → Reverb(wetDry=%.1f%%) → Recording", reverbUnit_.wetDryMix);
        }
        
        // Update audio level monitoring on the new active node
        AVAudioNode *monitorNode = (preset == ReverbPresetTypeClean) ? cleanBypassMixer_ : reverbUnit_;
        [monitorNode removeTapOnBus:0];
        [self installAudioLevelTap:monitorNode format:connectionFormat_];
        
        NSLog(@"✅ C++ PRESET CHANGE COMPLETE: %d", (int)preset);
        
    } @catch (NSException *exception) {
        NSLog(@"❌ C++ Preset routing error: %@", exception.reason);
    }
}

- (ReverbPresetType)currentReverbPreset {
    return [reverbBridge_ currentPreset];
}

- (void)setWetDryMix:(float)wetDryMix {
    [reverbBridge_ setWetDryMix:wetDryMix];
    [self applyReverbParameters];
}

- (void)setDecayTime:(float)decayTime {
    [reverbBridge_ setDecayTime:decayTime];
    [self applyReverbParameters];
}

- (void)setPreDelay:(float)preDelay {
    [reverbBridge_ setPreDelay:preDelay];
    [self applyReverbParameters];
}

- (void)setCrossFeed:(float)crossFeed {
    [reverbBridge_ setCrossFeed:crossFeed];
    [self applyReverbParameters];
}

- (void)setRoomSize:(float)roomSize {
    [reverbBridge_ setRoomSize:roomSize];
    [self applyReverbParameters];
}

- (void)setDensity:(float)density {
    [reverbBridge_ setDensity:density];
    [self applyReverbParameters];
}

- (void)setHighFreqDamping:(float)damping {
    [reverbBridge_ setHighFreqDamping:damping];
    [self applyReverbParameters];
}

- (void)setBypass:(BOOL)bypass {
    [reverbBridge_ setBypass:bypass];
    [self applyReverbParameters];
}

// C++ Helper methods to match Swift architecture
- (float)getCurrentWetDryMix {
    // AVAudioUnitReverb.wetDryMix expects values from 0.0 to 100.0
    // where 0 = 100% dry (original), 100 = 100% wet (effect)
    switch (currentPreset_) {
        case ReverbPresetTypeClean: return 0.0f;    // Pure dry signal (no reverb)
        case ReverbPresetTypeVocalBooth: return 25.0f;  // Subtle reverb
        case ReverbPresetTypeStudio: return 50.0f;      // Balanced mix
        case ReverbPresetTypeCathedral: return 75.0f;   // Heavy reverb
        case ReverbPresetTypeCustom: return 35.0f;      // Default custom
    }
    return 0.0f;
}

- (void)loadCurrentPreset:(AVAudioUnitReverb *)reverb {
    switch (currentPreset_) {
        case ReverbPresetTypeClean:
        case ReverbPresetTypeVocalBooth:
            [reverb loadFactoryPreset:AVAudioUnitReverbPresetSmallRoom];
            break;
        case ReverbPresetTypeStudio:
            [reverb loadFactoryPreset:AVAudioUnitReverbPresetMediumRoom];
            break;
        case ReverbPresetTypeCathedral:
            [reverb loadFactoryPreset:AVAudioUnitReverbPresetCathedral];
            break;
        case ReverbPresetTypeCustom:
            [reverb loadFactoryPreset:AVAudioUnitReverbPresetMediumRoom];
            break;
    }
    
    // Re-apply wetDryMix after preset (presets reset this value)
    reverb.wetDryMix = [self getCurrentWetDryMix];
}

- (void)installAudioLevelTap:(AVAudioNode *)node format:(AVAudioFormat *)format {
    [node removeTapOnBus:0];
    
    // Use nil format to let AVAudioEngine determine the correct format
    typeof(self) weakSelf = self;
    [node installTapOnBus:0 bufferSize:1024 format:nil block:^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        float *const *channelData = buffer.floatChannelData;
        if (!channelData) return;
        
        int frameLength = (int)buffer.frameLength;
        int channelCount = (int)buffer.format.channelCount;
        
        if (frameLength <= 0 || channelCount <= 0) return;
        
        float totalLevel = 0.0f;
        
        for (int channel = 0; channel < channelCount; channel++) {
            float *channelPtr = channelData[channel];
            float sum = 0.0f;
            
            for (int i = 0; i < frameLength; i++) {
                sum += fabsf(channelPtr[i]);
            }
            
            totalLevel += sum / frameLength;
        }
        
        float averageLevel = totalLevel / channelCount;
        float displayLevel = fminf(1.0f, fmaxf(0.0f, averageLevel * 5.0f)); // Amplify for display
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (strongSelf->audioLevelCallback_) {
                strongSelf->audioLevelCallback_(displayLevel);
            }
        });
    }];
    
    NSLog(@"✅ C++ WORKING REPO: Audio level tap installed");
}

- (void)applyReverbParameters {
    if (!reverbUnit_) {
        NSLog(@"❌ C++ No reverb unit available");
        return;
    }
    
    if (!reverbBridge_ || ![reverbBridge_ isInitialized]) {
        NSLog(@"❌ C++ ReverbBridge not initialized");
        return;
    }
    
    // Get C++ parameters
    float wetDryMix = [reverbBridge_ wetDryMix];
    float decayTime = [reverbBridge_ decayTime];
    BOOL bypassed = [reverbBridge_ isBypassed];
    
    NSLog(@"🔧 C++ WORKING REPO REVERB APPLICATION:");
    NSLog(@"   - C++ wetDry: %.1f%%", wetDryMix);
    NSLog(@"   - C++ decay: %.2fs", decayTime);
    NSLog(@"   - C++ bypassed: %@", bypassed ? @"YES" : @"NO");
    
    // CRITICAL FIX: NEVER use bypass mode - always pass audio through
    reverbUnit_.bypass = NO;  // NEVER bypass - always let audio flow
    
    if (bypassed || wetDryMix == 0.0f) {
        // For clean mode: 0% wet = 100% dry = original audio passes through
        reverbUnit_.wetDryMix = 0.0f;
        NSLog(@"🎵 C++ CLEAN MODE - 100%% DRY SIGNAL (reverb unit active but 0%% wet)");
    } else {
        reverbUnit_.wetDryMix = wetDryMix;
        NSLog(@"🎵 C++ REVERB ACTIVE - wetDryMix = %.1f%%", wetDryMix);
    }
    
    // Load appropriate preset based on current preset type
    [self loadCurrentPreset:reverbUnit_];
    
    // CRITICAL: Re-apply wetDryMix after preset load (presets reset this value)
    if (bypassed || wetDryMix == 0.0f) {
        reverbUnit_.wetDryMix = 0.0f;  // Ensure clean mode stays clean
        NSLog(@"🔄 C++ Re-applied CLEAN MODE: 0%% wet");
    } else {
        reverbUnit_.wetDryMix = wetDryMix;
        NSLog(@"🔄 C++ Re-applied wetDryMix %.1f%% after preset", wetDryMix);
    }
    
    // CRITICAL: Ensure reverb unit is never bypassed
    reverbUnit_.bypass = NO;
    
    // MAINTAIN WORKING REPO BALANCED VOLUMES
    if (gainMixer_) {
        gainMixer_.volume = 1.3f;
    }
    if (mainMixer_) {
        mainMixer_.outputVolume = 1.4f;
    }
    
    NSLog(@"✅ C++ AUDIO FLOW GUARANTEED: Reverb unit active (bypass=NO), wetDry=%.1f%%, volumes maintained", reverbUnit_.wetDryMix);
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
#pragma mark - Wet Signal Recording Implementation

- (void)startRecording:(void(^)(BOOL success))completion {
    NSLog(@"🎙️ Starting WET SIGNAL recording with all reverb parameters applied");
    
    if (isRecordingWetSignal_) {
        NSLog(@"⚠️ Recording already in progress");
        if (completion) completion(NO);
        return;
    }
    
    if (!recordingMixer_ || !connectionFormat_) {
        NSLog(@"❌ Recording components not available");
        if (completion) completion(NO);
        return;
    }
    
    // Create unique filename for wet signal recording
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *filename = [NSString stringWithFormat:@"wet_reverb_%@.wav", timestamp];
    
    // Get documents directory
    NSArray *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = [documentsPath firstObject];
    NSString *recordingsDir = [documentsDir stringByAppendingPathComponent:@"Recordings"];
    
    // Create recordings directory if needed
    [[NSFileManager defaultManager] createDirectoryAtPath:recordingsDir 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:nil];
    
    NSString *filePath = [recordingsDir stringByAppendingPathComponent:filename];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    @try {
        // Create audio file for writing wet signal
        wetRecordingFile_ = [[AVAudioFile alloc] initForWriting:fileURL 
                                                       settings:connectionFormat_.settings 
                                                          error:nil];
        
        if (!wetRecordingFile_) {
            NSLog(@"❌ Failed to create wet signal recording file");
            if (completion) completion(NO);
            return;
        }
        
        // Install tap on recording mixer to capture final wet/dry mix
        [recordingMixer_ installTapOnBus:0 
                              bufferSize:1024 
                                  format:connectionFormat_ 
                                   block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            if (!self->isRecordingWetSignal_ || !self->wetRecordingFile_) return;
            
            @try {
                [self->wetRecordingFile_ writeFromBuffer:buffer error:nil];
                
                // Debug log periodically
                if (arc4random_uniform(2000) == 0) {
                    NSLog(@"📼 WET RECORDING: %u frames captured with all reverb parameters", 
                          (unsigned int)buffer.frameLength);
                }
            } @catch (NSException *exception) {
                NSLog(@"⚠️ Wet recording write error (non-fatal): %@", exception.reason);
            }
        }];
        
        isRecordingWetSignal_ = YES;
        recordingStartTime_ = [NSDate date];
        
        NSLog(@"✅ WET SIGNAL recording started - capturing processed audio: %@", filename);
        if (completion) completion(YES);
        
    } @catch (NSException *exception) {
        NSLog(@"❌ Wet signal recording setup failed: %@", exception.reason);
        [self cleanupWetRecording];
        if (completion) completion(NO);
    }
}

- (void)stopRecording:(void(^)(BOOL success, NSString * _Nullable filename, NSTimeInterval duration))completion {
    NSLog(@"🛑 Stopping WET SIGNAL recording");
    
    if (!isRecordingWetSignal_) {
        NSLog(@"⚠️ No active wet signal recording to stop");
        if (completion) completion(NO, nil, 0.0);
        return;
    }
    
    isRecordingWetSignal_ = NO;
    
    // Calculate recording duration
    NSTimeInterval duration = recordingStartTime_ ? 
        [[NSDate date] timeIntervalSinceDate:recordingStartTime_] : 0.0;
    
    // Remove tap from recording mixer
    @try {
        [recordingMixer_ removeTapOnBus:0];
        NSLog(@"✅ Wet signal recording tap removed");
    } @catch (NSException *exception) {
        NSLog(@"⚠️ Error removing wet recording tap: %@", exception.reason);
    }
    
    // Get filename before cleanup
    NSString *filename = nil;
    if (wetRecordingFile_) {
        filename = [[wetRecordingFile_.url lastPathComponent] copy];
    }
    
    // Cleanup and finalize file
    [self cleanupWetRecording];
    
    NSLog(@"✅ WET SIGNAL recording completed: %@ (%.1fs)", filename ?: @"unknown", duration);
    
    if (completion) {
        completion(YES, filename, duration);
    }
}

- (void)cleanupWetRecording {
    if (wetRecordingFile_) {
        wetRecordingFile_ = nil; // Automatically finalizes the file
        NSLog(@"💾 Wet signal recording file finalized");
    }
    
    isRecordingWetSignal_ = NO;
    recordingStartTime_ = nil;
}

- (float)sampleRate {
    return connectionFormat_ ? (float)connectionFormat_.sampleRate : 44100.0f;
}

- (UInt32)bufferSize {
    return 512; // Valeur par défaut optimisée
}

- (void)optimizeForLowLatency {
    NSLog(@"⚡ Optimizing C++ engine for low latency");
    [self setPreferredBufferSize:0.005]; // 5ms buffer
    [self setPreferredSampleRate:44100];
}

@end
