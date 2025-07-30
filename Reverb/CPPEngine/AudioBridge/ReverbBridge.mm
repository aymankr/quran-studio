#import "ReverbBridge.h"
#import "ReverbEngine.hpp"
#import <memory>

using namespace VoiceMonitor;

@interface ReverbBridge() {
    std::unique_ptr<ReverbEngine> reverbEngine_;
    dispatch_queue_t parameterQueue_;
}
@end

@implementation ReverbBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        reverbEngine_ = std::make_unique<ReverbEngine>();
        
        // Create serial queue for parameter updates to ensure thread safety
        parameterQueue_ = dispatch_queue_create("com.voicemonitor.reverb.parameters", 
                                               DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}

- (void)cleanup {
    if (reverbEngine_) {
        reverbEngine_->reset();
        reverbEngine_.reset();
    }
}

- (BOOL)initializeWithSampleRate:(double)sampleRate maxBlockSize:(int)maxBlockSize {
    if (!reverbEngine_) {
        return NO;
    }
    
    return reverbEngine_->initialize(sampleRate, maxBlockSize);
}

- (void)reset {
    if (reverbEngine_) {
        reverbEngine_->reset();
    }
}

- (void)processAudioWithInputs:(const float * const *)inputs
                       outputs:(float * const *)outputs
                   numChannels:(int)numChannels
                    numSamples:(int)numSamples {
    if (reverbEngine_ && reverbEngine_->isInitialized()) {
        reverbEngine_->processBlock(inputs, outputs, numChannels, numSamples);
    } else {
        // Fallback: copy input to output if engine not ready
        for (int ch = 0; ch < numChannels; ++ch) {
            memcpy(outputs[ch], inputs[ch], numSamples * sizeof(float));
        }
    }
}

#pragma mark - Preset Management

- (void)setPreset:(ReverbPresetType)preset {
    if (!reverbEngine_) return;
    
    ReverbEngine::Preset cppPreset;
    switch (preset) {
        case ReverbPresetTypeClean:
            cppPreset = ReverbEngine::Preset::Clean;
            break;
        case ReverbPresetTypeVocalBooth:
            cppPreset = ReverbEngine::Preset::VocalBooth;
            break;
        case ReverbPresetTypeStudio:
            cppPreset = ReverbEngine::Preset::Studio;
            break;
        case ReverbPresetTypeCathedral:
            cppPreset = ReverbEngine::Preset::Cathedral;
            break;
        case ReverbPresetTypeCustom:
            cppPreset = ReverbEngine::Preset::Custom;
            break;
    }
    
    // Use dispatch to ensure thread safety
    dispatch_async(parameterQueue_, ^{
        self->reverbEngine_->setPreset(cppPreset);
    });
}

- (ReverbPresetType)currentPreset {
    if (!reverbEngine_) return ReverbPresetTypeClean;
    
    ReverbEngine::Preset cppPreset = reverbEngine_->getCurrentPreset();
    switch (cppPreset) {
        case ReverbEngine::Preset::Clean:
            return ReverbPresetTypeClean;
        case ReverbEngine::Preset::VocalBooth:
            return ReverbPresetTypeVocalBooth;
        case ReverbEngine::Preset::Studio:
            return ReverbPresetTypeStudio;
        case ReverbEngine::Preset::Cathedral:
            return ReverbPresetTypeCathedral;
        case ReverbEngine::Preset::Custom:
            return ReverbPresetTypeCustom;
    }
}

#pragma mark - Parameter Control (Thread-Safe)

- (void)setWetDryMix:(float)wetDryMix {
    if (reverbEngine_) {
        reverbEngine_->setWetDryMix(wetDryMix);
    }
}

- (void)setDecayTime:(float)decayTime {
    if (reverbEngine_) {
        reverbEngine_->setDecayTime(decayTime);
    }
}

- (void)setPreDelay:(float)preDelay {
    if (reverbEngine_) {
        reverbEngine_->setPreDelay(preDelay);
    }
}

- (void)setCrossFeed:(float)crossFeed {
    if (reverbEngine_) {
        reverbEngine_->setCrossFeed(crossFeed);
    }
}

- (void)setRoomSize:(float)roomSize {
    if (reverbEngine_) {
        reverbEngine_->setRoomSize(roomSize);
    }
}

- (void)setDensity:(float)density {
    if (reverbEngine_) {
        reverbEngine_->setDensity(density);
    }
}

- (void)setHighFreqDamping:(float)damping {
    if (reverbEngine_) {
        reverbEngine_->setHighFreqDamping(damping);
    }
}

- (void)setBypass:(BOOL)bypass {
    if (reverbEngine_) {
        reverbEngine_->setBypass(bypass);
    }
}

- (void)setLowFreqDamping:(float)damping {
    if (reverbEngine_) {
        reverbEngine_->setLowFreqDamping(damping);
    }
}

- (void)setStereoWidth:(float)width {
    if (reverbEngine_) {
        reverbEngine_->setStereoWidth(width);
    }
}

- (void)setPhaseInvert:(BOOL)invert {
    if (reverbEngine_) {
        reverbEngine_->setPhaseInvert(invert);
    }
}

#pragma mark - Parameter Getters

- (float)wetDryMix {
    return reverbEngine_ ? reverbEngine_->getWetDryMix() : 0.0f;
}

- (float)decayTime {
    return reverbEngine_ ? reverbEngine_->getDecayTime() : 0.0f;
}

- (float)preDelay {
    return reverbEngine_ ? reverbEngine_->getPreDelay() : 0.0f;
}

- (float)crossFeed {
    return reverbEngine_ ? reverbEngine_->getCrossFeed() : 0.0f;
}

- (float)roomSize {
    return reverbEngine_ ? reverbEngine_->getRoomSize() : 0.0f;
}

- (float)density {
    return reverbEngine_ ? reverbEngine_->getDensity() : 0.0f;
}

- (float)highFreqDamping {
    return reverbEngine_ ? reverbEngine_->getHighFreqDamping() : 0.0f;
}

- (BOOL)isBypassed {
    return reverbEngine_ ? reverbEngine_->isBypassed() : YES;
}

- (float)lowFreqDamping {
    return reverbEngine_ ? reverbEngine_->getLowFreqDamping() : 0.0f;
}

- (float)stereoWidth {
    return reverbEngine_ ? reverbEngine_->getStereoWidth() : 1.0f;
}

- (BOOL)phaseInvert {
    return reverbEngine_ ? reverbEngine_->getPhaseInvert() : NO;
}

#pragma mark - Performance Monitoring

- (double)cpuUsage {
    return reverbEngine_ ? reverbEngine_->getCpuUsage() : 0.0;
}

- (BOOL)isInitialized {
    return reverbEngine_ ? reverbEngine_->isInitialized() : NO;
}

#pragma mark - Preset Application Methods

- (void)applyCleanPreset {
    [self setPreset:ReverbPresetTypeClean];
}

- (void)applyVocalBoothPreset {
    [self setPreset:ReverbPresetTypeVocalBooth];
}

- (void)applyStudioPreset {
    [self setPreset:ReverbPresetTypeStudio];
}

- (void)applyCathedralPreset {
    [self setPreset:ReverbPresetTypeCathedral];
}

- (void)applyCustomPresetWithWetDryMix:(float)wetDryMix
                             decayTime:(float)decayTime
                              preDelay:(float)preDelay
                             crossFeed:(float)crossFeed
                              roomSize:(float)roomSize
                               density:(float)density
                         highFreqDamping:(float)highFreqDamping {
    
    // Apply custom preset
    [self setPreset:ReverbPresetTypeCustom];
    
    // Set all parameters
    dispatch_async(parameterQueue_, ^{
        [self setWetDryMix:wetDryMix];
        [self setDecayTime:decayTime];
        [self setPreDelay:preDelay];
        [self setCrossFeed:crossFeed];
        [self setRoomSize:roomSize];
        [self setDensity:density];
        [self setHighFreqDamping:highFreqDamping];
    });
}

@end