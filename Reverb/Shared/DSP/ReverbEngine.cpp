#include "ReverbEngine.hpp"
#include "FDNReverb.hpp"
#include "AudioMath.hpp"
#include <algorithm>
#include <chrono>
#include <functional>
#include <memory>

namespace VoiceMonitor {

// Parameter smoothing class for glitch-free parameter changes
class ReverbEngine::ParameterSmoother {
public:
    ParameterSmoother(double sampleRate) : sampleRate_(sampleRate) {
        setSmoothingTime(0.05); // 50ms smoothing time
    }
    
    void setSmoothingTime(double timeInSeconds) {
        smoothingCoeff_ = 1.0 - std::exp(-1.0 / (timeInSeconds * sampleRate_));
    }
    
    float process(float target, float& current) {
        current += smoothingCoeff_ * (target - current);
        return current;
    }
    
private:
    double sampleRate_;
    double smoothingCoeff_;
};

// Cross-feed processor for stereo width control (now replaced by StereoEnhancer)
class ReverbEngine::InternalCrossFeedProcessor {
public:
    void processBlock(float* left, float* right, int numSamples, float crossFeedAmount) {
        const float amount = std::max(0.0f, std::min(crossFeedAmount, 1.0f));
        const float gain = 1.0f - amount * 0.5f; // Compensate for energy increase
        
        for (int i = 0; i < numSamples; ++i) {
            const float originalLeft = left[i];
            const float originalRight = right[i];
            
            left[i] = gain * (originalLeft + amount * originalRight);
            right[i] = gain * (originalRight + amount * originalLeft);
        }
    }
};

ReverbEngine::ReverbEngine() 
    : currentPreset_(Preset::Clean)
    , sampleRate_(44100.0)
    , maxBlockSize_(512)
    , initialized_(false) {
}

ReverbEngine::~ReverbEngine() = default;

bool ReverbEngine::initialize(double sampleRate, int maxBlockSize) {
    if (sampleRate < MIN_SAMPLE_RATE || sampleRate > MAX_SAMPLE_RATE) {
        return false;
    }
    
    sampleRate_ = sampleRate;
    maxBlockSize_ = maxBlockSize;
    
    // Initialize components
    fdnReverb_ = std::make_unique<FDNReverb>(sampleRate_, MAX_DELAY_LINES);
    crossFeed_ = std::make_unique<StereoEnhancer>();
    smoother_ = std::make_unique<ParameterSmoother>(sampleRate_);
    
    // Allocate processing buffers
    tempBuffers_.resize(MAX_CHANNELS);
    for (auto& buffer : tempBuffers_) {
        buffer.resize(maxBlockSize_);
    }
    
    wetBuffer_.resize(maxBlockSize_);
    dryBuffer_.resize(maxBlockSize_);
    
    // Apply default preset
    setPreset(Preset::VocalBooth);
    
    initialized_ = true;
    return true;
}

void ReverbEngine::processBlock(const float* const* inputs, float* const* outputs, 
                               int numChannels, int numSamples) {
    if (!initialized_ || numSamples > maxBlockSize_ || numChannels > MAX_CHANNELS) {
        // Copy input to output if not initialized
        for (int ch = 0; ch < numChannels; ++ch) {
            std::copy(inputs[ch], inputs[ch] + numSamples, outputs[ch]);
        }
        return;
    }
    
    // Measure CPU usage
    auto startTime = std::chrono::high_resolution_clock::now();
    
    // Handle bypass
    if (params_.bypass.load()) {
        for (int ch = 0; ch < numChannels; ++ch) {
            std::copy(inputs[ch], inputs[ch] + numSamples, outputs[ch]);
        }
        cpuUsage_.store(0.0);
        return;
    }
    
    // Get current parameter values with smoothing
    const float wetDryMix = params_.wetDryMix.load() * 0.01f; // Convert to 0-1
    const float decayTime = params_.decayTime.load();
    const float preDelay = params_.preDelay.load();
    const float crossFeedAmount = params_.crossFeed.load();
    const float roomSize = params_.roomSize.load();
    const float density = params_.density.load() * 0.01f;
    const float hfDamping = params_.highFreqDamping.load() * 0.01f;
    
    // Update FDN parameters
    fdnReverb_->setDecayTime(decayTime);
    fdnReverb_->setPreDelay(preDelay * 0.001 * sampleRate_); // Convert ms to samples
    fdnReverb_->setRoomSize(roomSize);
    fdnReverb_->setDensity(density);
    fdnReverb_->setHighFreqDamping(hfDamping);
    
    // Process mono to stereo if needed
    if (numChannels == 1) {
        // Mono input -> stereo reverb
        std::copy(inputs[0], inputs[0] + numSamples, dryBuffer_.data());
        
        // Process reverb
        fdnReverb_->processMono(inputs[0], wetBuffer_.data(), numSamples);
        
        // Apply wet/dry mix
        for (int i = 0; i < numSamples; ++i) {
            const float dry = dryBuffer_[i];
            const float wet = wetBuffer_[i];
            const float mixed = dry * (1.0f - wetDryMix) + wet * wetDryMix;
            outputs[0][i] = mixed;
        }
        
        // Copy to second channel if stereo output
        if (numChannels == 2) {
            std::copy(outputs[0], outputs[0] + numSamples, outputs[1]);
        }
        
    } else if (numChannels == 2) {
        // Stereo processing
        
        // Copy input to temp buffers
        std::copy(inputs[0], inputs[0] + numSamples, tempBuffers_[0].data());
        std::copy(inputs[1], inputs[1] + numSamples, tempBuffers_[1].data());
        
        // Process reverb
        fdnReverb_->processStereo(inputs[0], inputs[1], 
                                 tempBuffers_[0].data(), tempBuffers_[1].data(), 
                                 numSamples);
        
        // Apply cross-feed
        if (crossFeedAmount > 0.001f) {
            crossFeed_->setCrossFeedAmount(crossFeedAmount);
            crossFeed_->processBlock(tempBuffers_[0].data(), tempBuffers_[1].data(), numSamples);
        }
        
        // Apply wet/dry mix
        for (int i = 0; i < numSamples; ++i) {
            outputs[0][i] = inputs[0][i] * (1.0f - wetDryMix) + tempBuffers_[0][i] * wetDryMix;
            outputs[1][i] = inputs[1][i] * (1.0f - wetDryMix) + tempBuffers_[1][i] * wetDryMix;
        }
    }
    
    // Calculate CPU usage
    auto endTime = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(endTime - startTime);
    double processingTime = duration.count() / 1000.0; // Convert to ms
    double blockTime = (numSamples / sampleRate_) * 1000.0; // Block duration in ms
    cpuUsage_.store((processingTime / blockTime) * 100.0);
}

void ReverbEngine::reset() {
    if (fdnReverb_) {
        fdnReverb_->reset();
    }
    
    // Clear all buffers
    for (auto& buffer : tempBuffers_) {
        std::fill(buffer.begin(), buffer.end(), 0.0f);
    }
    std::fill(wetBuffer_.begin(), wetBuffer_.end(), 0.0f);
    std::fill(dryBuffer_.begin(), dryBuffer_.end(), 0.0f);
}

void ReverbEngine::setPreset(Preset preset) {
    currentPreset_ = preset;
    applyPresetParameters(preset);
}

void ReverbEngine::applyPresetParameters(Preset preset) {
    switch (preset) {
        case Preset::Clean:
            params_.wetDryMix.store(0.0f);
            params_.decayTime.store(0.1f);
            params_.preDelay.store(0.0f);
            params_.crossFeed.store(0.0f);
            params_.roomSize.store(0.0f);
            params_.density.store(0.0f);
            params_.highFreqDamping.store(0.0f);
            params_.bypass.store(true);
            break;
            
        case Preset::VocalBooth:
            params_.wetDryMix.store(18.0f);
            params_.decayTime.store(0.9f);
            params_.preDelay.store(8.0f);
            params_.crossFeed.store(0.3f);
            params_.roomSize.store(0.35f);
            params_.density.store(70.0f);
            params_.highFreqDamping.store(30.0f);
            params_.bypass.store(false);
            break;
            
        case Preset::Studio:
            params_.wetDryMix.store(40.0f);
            params_.decayTime.store(1.7f);
            params_.preDelay.store(15.0f);
            params_.crossFeed.store(0.5f);
            params_.roomSize.store(0.6f);
            params_.density.store(85.0f);
            params_.highFreqDamping.store(45.0f);
            params_.bypass.store(false);
            break;
            
        case Preset::Cathedral:
            params_.wetDryMix.store(65.0f);
            params_.decayTime.store(2.8f);
            params_.preDelay.store(25.0f);
            params_.crossFeed.store(0.7f);
            params_.roomSize.store(0.85f);
            params_.density.store(60.0f);
            params_.highFreqDamping.store(60.0f);
            params_.bypass.store(false);
            break;
            
        case Preset::Custom:
            // Keep current parameter values
            params_.bypass.store(false);
            break;
    }
}

// Parameter setters with validation
void ReverbEngine::setWetDryMix(float value) {
    params_.wetDryMix.store(clamp(value, 0.0f, 100.0f));
}

void ReverbEngine::setDecayTime(float value) {
    params_.decayTime.store(clamp(value, 0.1f, 8.0f));
}

void ReverbEngine::setPreDelay(float value) {
    params_.preDelay.store(clamp(value, 0.0f, 200.0f));
}

void ReverbEngine::setCrossFeed(float value) {
    params_.crossFeed.store(clamp(value, 0.0f, 1.0f));
}

void ReverbEngine::setRoomSize(float value) {
    params_.roomSize.store(clamp(value, 0.0f, 1.0f));
}

void ReverbEngine::setDensity(float value) {
    params_.density.store(clamp(value, 0.0f, 100.0f));
}

void ReverbEngine::setHighFreqDamping(float value) {
    params_.highFreqDamping.store(clamp(value, 0.0f, 100.0f));
}

void ReverbEngine::setBypass(bool bypass) {
    params_.bypass.store(bypass);
}

void ReverbEngine::setLowFreqDamping(float value) {
    params_.lowFreqDamping.store(clamp(value, 0.0f, 100.0f));
}

void ReverbEngine::setStereoWidth(float value) {
    params_.stereoWidth.store(clamp(value, 0.0f, 2.0f));
}

void ReverbEngine::setPhaseInvert(bool invert) {
    params_.phaseInvert.store(invert);
}

float ReverbEngine::clamp(float value, float min, float max) const {
    return std::max(min, std::min(max, value));
}

} // namespace VoiceMonitor