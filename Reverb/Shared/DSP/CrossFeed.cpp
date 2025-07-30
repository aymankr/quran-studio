#include "CrossFeed.hpp"
#include <algorithm>
#include <cstring>
#include <functional>

namespace VoiceMonitor {

// CrossFeedProcessor Implementation
CrossFeedProcessor::CrossFeedProcessor()
    : crossFeedAmount_(0.0f, 0.02f)
    , stereoWidth_(1.0f, 0.02f)
    , highFreqRolloff_(8000.0f, 0.1f)
    , interChannelDelay_(0.0f, 0.02f)
    , enabled_(true)
    , phaseInvertLeft_(false)
    , phaseInvertRight_(false)
    , sampleRate_(44100.0)
    , delayBufferSize_(0)
    , delayIndexLeft_(0)
    , delayIndexRight_(0) {
}

void CrossFeedProcessor::initialize(double sampleRate) {
    sampleRate_ = sampleRate;
    
    crossFeedAmount_.setSampleRate(sampleRate);
    stereoWidth_.setSampleRate(sampleRate);
    highFreqRolloff_.setSampleRate(sampleRate);
    interChannelDelay_.setSampleRate(sampleRate);
    
    // Initialize delay buffers for maximum 10ms delay
    delayBufferSize_ = static_cast<int>(sampleRate * 0.01) + 1;
    delayBufferLeft_.resize(delayBufferSize_, 0.0f);
    delayBufferRight_.resize(delayBufferSize_, 0.0f);
    
    updateFilters();
    reset();
}

void CrossFeedProcessor::processBlock(float* leftChannel, float* rightChannel, int numSamples) {
    if (!enabled_) {
        return;
    }
    
    updateFilters();
    
    for (int i = 0; i < numSamples; ++i) {
        float left = leftChannel[i];
        float right = rightChannel[i];
        
        // Apply phase inversion if enabled
        if (phaseInvertLeft_) left = -left;
        if (phaseInvertRight_) right = -right;
        
        // Process inter-channel delay
        float delayMs = interChannelDelay_.getNextValue();
        if (delayMs > 0.001f) {
            float delaySamples = delayMs * 0.001f * sampleRate_;
            left = processDelayLine(left, delayBufferLeft_, delayIndexLeft_, delaySamples);
            right = processDelayLine(right, delayBufferRight_, delayIndexRight_, delaySamples);
        }
        
        // Apply high-frequency filtering for cross-feed
        float filteredLeft = highFreqFilterLeft_.process(left);
        float filteredRight = highFreqFilterRight_.process(right);
        
        // Cross-feed processing
        float crossFeed = crossFeedAmount_.getNextValue();
        if (crossFeed > 0.001f) {
            float crossFeedGain = crossFeed * 0.7f; // Reduce to avoid energy increase
            float newLeft = left + crossFeedGain * filteredRight;
            float newRight = right + crossFeedGain * filteredLeft;
            left = newLeft;
            right = newRight;
        }
        
        // Stereo width processing
        float width = stereoWidth_.getNextValue();
        if (std::abs(width - 1.0f) > 0.001f) {
            // Convert to mid/side
            float mid = (left + right) * 0.5f;
            float side = (left - right) * 0.5f;
            
            // Apply width scaling
            side *= width;
            
            // Convert back to L/R
            left = mid + side;
            right = mid - side;
        }
        
        leftChannel[i] = left;
        rightChannel[i] = right;
    }
}

void CrossFeedProcessor::setCrossFeedAmount(float amount) {
    crossFeedAmount_.setValue(std::max(0.0f, std::min(amount, 1.0f)));
}

void CrossFeedProcessor::setStereoWidth(float width) {
    stereoWidth_.setValue(std::max(0.0f, std::min(width, 2.0f)));
}

void CrossFeedProcessor::setPhaseInvert(bool invertLeft, bool invertRight) {
    phaseInvertLeft_ = invertLeft;
    phaseInvertRight_ = invertRight;
}

void CrossFeedProcessor::setHighFreqRolloff(float frequency) {
    highFreqRolloff_.setValue(std::max(1000.0f, std::min(frequency, 20000.0f)));
}

void CrossFeedProcessor::setInterChannelDelay(float delayMs) {
    interChannelDelay_.setValue(std::max(0.0f, std::min(delayMs, 10.0f)));
}

void CrossFeedProcessor::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void CrossFeedProcessor::reset() {
    std::fill(delayBufferLeft_.begin(), delayBufferLeft_.end(), 0.0f);
    std::fill(delayBufferRight_.begin(), delayBufferRight_.end(), 0.0f);
    delayIndexLeft_ = 0;
    delayIndexRight_ = 0;
    highFreqFilterLeft_.reset();
    highFreqFilterRight_.reset();
}

void CrossFeedProcessor::updateFilters() {
    float cutoff = highFreqRolloff_.getCurrentValue();
    auto coeffs = AudioMath::createLowpass(sampleRate_, cutoff, 0.707f);
    highFreqFilterLeft_.setCoeffs(coeffs);
    highFreqFilterRight_.setCoeffs(coeffs);
}

float CrossFeedProcessor::processDelayLine(float input, std::vector<float>& buffer, int& index, float delaySamples) {
    // Write input
    buffer[index] = input;
    
    // Calculate read position
    float readPos = index - delaySamples;
    if (readPos < 0) readPos += delayBufferSize_;
    
    // Linear interpolation
    int readIndex1 = static_cast<int>(readPos) % delayBufferSize_;
    int readIndex2 = (readIndex1 + 1) % delayBufferSize_;
    float fraction = readPos - std::floor(readPos);
    
    float sample1 = buffer[readIndex1];
    float sample2 = buffer[readIndex2];
    float output = sample1 + fraction * (sample2 - sample1);
    
    index = (index + 1) % delayBufferSize_;
    return output;
}

// MidSideProcessor Implementation
void MidSideProcessor::encodeToMidSide(float left, float right, float& mid, float& side) {
    mid = (left + right) * 0.5f;
    side = (left - right) * 0.5f;
}

void MidSideProcessor::decodeFromMidSide(float mid, float side, float& left, float& right) {
    left = mid + side;
    right = mid - side;
}

void MidSideProcessor::processBlock(float* leftChannel, float* rightChannel, int numSamples,
                                   std::function<float(float)> midProcessor,
                                   std::function<float(float)> sideProcessor) {
    for (int i = 0; i < numSamples; ++i) {
        float left = leftChannel[i];
        float right = rightChannel[i];
        
        // Encode to M/S
        float mid, side;
        encodeToMidSide(left, right, mid, side);
        
        // Apply processing
        if (midProcessor) {
            mid = midProcessor(mid);
        }
        if (sideProcessor) {
            side = sideProcessor(side);
        }
        
        // Apply gains and balance
        mid *= midGain_;
        side *= sideGain_;
        
        // Apply balance
        if (midSideBalance_ > 0) {
            mid *= (1.0f - midSideBalance_);
        } else {
            side *= (1.0f + midSideBalance_);
        }
        
        // Decode back to L/R
        decodeFromMidSide(mid, side, left, right);
        
        leftChannel[i] = left;
        rightChannel[i] = right;
    }
}

void MidSideProcessor::setMidSideBalance(float balance) {
    midSideBalance_ = std::max(-1.0f, std::min(balance, 1.0f));
}

void MidSideProcessor::setSideGain(float gain) {
    sideGain_ = std::max(0.0f, std::min(gain, 2.0f));
}

void MidSideProcessor::setMidGain(float gain) {
    midGain_ = std::max(0.0f, std::min(gain, 2.0f));
}

// StereoChorus Implementation
StereoChorus::StereoChorus()
    : sampleRate_(44100.0)
    , delayBufferSize_(0)
    , writeIndexLeft_(0)
    , writeIndexRight_(0)
    , lfoPhaseLeft_(0.0f)
    , lfoPhaseRight_(0.0f)
    , lfoRate_(0.5f)
    , lfoDepth_(0.3f)
    , stereoOffset_(90.0f)
    , feedback_(0.2f)
    , wetDryMix_(0.3f)
    , baseDelayMs_(15.0f) {
}

void StereoChorus::initialize(double sampleRate, int maxDelayMs) {
    sampleRate_ = sampleRate;
    delayBufferSize_ = static_cast<int>(sampleRate * maxDelayMs * 0.001) + 1;
    
    delayBufferLeft_.resize(delayBufferSize_, 0.0f);
    delayBufferRight_.resize(delayBufferSize_, 0.0f);
    
    reset();
}

void StereoChorus::processBlock(float* leftChannel, float* rightChannel, int numSamples) {
    const float pi = 3.14159265359f;
    
    for (int i = 0; i < numSamples; ++i) {
        float left = leftChannel[i];
        float right = rightChannel[i];
        
        // Generate LFO values
        float lfoLeft = generateLFO(lfoPhaseLeft_, lfoRate_);
        float lfoRight = generateLFO(lfoPhaseRight_, lfoRate_);
        
        // Calculate modulated delay times
        float delayLeft = baseDelayMs_ + lfoLeft * lfoDepth_ * 10.0f; // Up to 10ms modulation
        float delayRight = baseDelayMs_ + lfoRight * lfoDepth_ * 10.0f;
        
        // Process delays
        float chorused = processDelay(left, delayBufferLeft_, writeIndexLeft_, delayLeft);
        float chorusedRight = processDelay(right, delayBufferRight_, writeIndexRight_, delayRight);
        
        // Apply wet/dry mix
        leftChannel[i] = left * (1.0f - wetDryMix_) + chorused * wetDryMix_;
        rightChannel[i] = right * (1.0f - wetDryMix_) + chorusedRight * wetDryMix_;
    }
}

void StereoChorus::setRate(float rateHz) {
    lfoRate_ = std::max(0.01f, std::min(rateHz, 10.0f));
}

void StereoChorus::setDepth(float depth) {
    lfoDepth_ = std::max(0.0f, std::min(depth, 1.0f));
}

void StereoChorus::setStereoOffset(float offsetDegrees) {
    stereoOffset_ = offsetDegrees;
    // Reset right LFO with offset
    lfoPhaseRight_ = lfoPhaseLeft_ + (offsetDegrees / 180.0f) * 3.14159265359f;
}

void StereoChorus::setFeedback(float feedback) {
    feedback_ = std::max(0.0f, std::min(feedback, 0.95f));
}

void StereoChorus::setWetDryMix(float wetDryMix) {
    wetDryMix_ = std::max(0.0f, std::min(wetDryMix, 1.0f));
}

void StereoChorus::reset() {
    std::fill(delayBufferLeft_.begin(), delayBufferLeft_.end(), 0.0f);
    std::fill(delayBufferRight_.begin(), delayBufferRight_.end(), 0.0f);
    writeIndexLeft_ = 0;
    writeIndexRight_ = 0;
    lfoPhaseLeft_ = 0.0f;
    lfoPhaseRight_ = stereoOffset_ / 180.0f * 3.14159265359f;
}

float StereoChorus::processDelay(float input, std::vector<float>& buffer, int& writeIndex, float delayMs) {
    float delaySamples = delayMs * 0.001f * sampleRate_;
    
    // Add feedback
    float readPos = writeIndex - delaySamples;
    if (readPos < 0) readPos += delayBufferSize_;
    
    int readIndex1 = static_cast<int>(readPos) % delayBufferSize_;
    int readIndex2 = (readIndex1 + 1) % delayBufferSize_;
    float fraction = readPos - std::floor(readPos);
    
    float delayedSample = buffer[readIndex1] + fraction * (buffer[readIndex2] - buffer[readIndex1]);
    
    // Write input with feedback
    buffer[writeIndex] = input + delayedSample * feedback_;
    writeIndex = (writeIndex + 1) % delayBufferSize_;
    
    return delayedSample;
}

float StereoChorus::generateLFO(float& phase, float rate) {
    float lfo = std::sin(phase);
    phase += 2.0f * 3.14159265359f * rate / sampleRate_;
    if (phase > 2.0f * 3.14159265359f) {
        phase -= 2.0f * 3.14159265359f;
    }
    return lfo;
}

// HaasProcessor Implementation
HaasProcessor::HaasProcessor()
    : sampleRate_(44100.0)
    , delayBufferSize_(0)
    , writeIndex_(0)
    , delayTimeMs_(10.0f)
    , delayRight_(true)
    , delayedChannelLevel_(0.7f)
    , wetDryMix_(1.0f) {
}

void HaasProcessor::initialize(double sampleRate) {
    sampleRate_ = sampleRate;
    delayBufferSize_ = static_cast<int>(sampleRate * 0.05) + 1; // 50ms max delay
    delayBuffer_.resize(delayBufferSize_, 0.0f);
    writeIndex_ = 0;
}

void HaasProcessor::processBlock(float* leftChannel, float* rightChannel, int numSamples) {
    for (int i = 0; i < numSamples; ++i) {
        float left = leftChannel[i];
        float right = rightChannel[i];
        
        float delayedSample = processDelay(delayRight_ ? right : left, delayTimeMs_);
        delayedSample *= delayedChannelLevel_;
        
        if (delayRight_) {
            right = left * (1.0f - wetDryMix_) + delayedSample * wetDryMix_;
        } else {
            left = right * (1.0f - wetDryMix_) + delayedSample * wetDryMix_;
        }
        
        leftChannel[i] = left;
        rightChannel[i] = right;
    }
}

void HaasProcessor::setDelayTime(float delayMs) {
    delayTimeMs_ = std::max(1.0f, std::min(delayMs, 40.0f));
}

void HaasProcessor::setDelayRight(bool delayRight) {
    delayRight_ = delayRight;
}

void HaasProcessor::setDelayedChannelLevel(float level) {
    delayedChannelLevel_ = std::max(0.0f, std::min(level, 1.0f));
}

void HaasProcessor::setWetDryMix(float wetDryMix) {
    wetDryMix_ = std::max(0.0f, std::min(wetDryMix, 1.0f));
}

float HaasProcessor::processDelay(float input, float delayMs) {
    delayBuffer_[writeIndex_] = input;
    
    float delaySamples = delayMs * 0.001f * sampleRate_;
    float readPos = writeIndex_ - delaySamples;
    if (readPos < 0) readPos += delayBufferSize_;
    
    int readIndex1 = static_cast<int>(readPos) % delayBufferSize_;
    int readIndex2 = (readIndex1 + 1) % delayBufferSize_;
    float fraction = readPos - std::floor(readPos);
    
    float output = delayBuffer_[readIndex1] + fraction * (delayBuffer_[readIndex2] - delayBuffer_[readIndex1]);
    
    writeIndex_ = (writeIndex_ + 1) % delayBufferSize_;
    return output;
}

// StereoEnhancer Implementation
StereoEnhancer::StereoEnhancer()
    : enabled_(true)
    , chorusEnabled_(false)
    , haasEnabled_(false)
    , midSideEnabled_(false) {
}

void StereoEnhancer::initialize(double sampleRate) {
    crossFeed_.initialize(sampleRate);
    chorus_.initialize(sampleRate);
    haas_.initialize(sampleRate);
    
    // Initialize temp buffers
    int maxBlockSize = 512;
    tempBufferLeft_.resize(maxBlockSize);
    tempBufferRight_.resize(maxBlockSize);
}

void StereoEnhancer::processBlock(float* leftChannel, float* rightChannel, int numSamples) {
    if (!enabled_) {
        return;
    }
    
    // Copy to temp buffers
    std::copy(leftChannel, leftChannel + numSamples, tempBufferLeft_.data());
    std::copy(rightChannel, rightChannel + numSamples, tempBufferRight_.data());
    
    // Process cross-feed
    crossFeed_.processBlock(tempBufferLeft_.data(), tempBufferRight_.data(), numSamples);
    
    // Process chorus if enabled
    if (chorusEnabled_) {
        chorus_.processBlock(tempBufferLeft_.data(), tempBufferRight_.data(), numSamples);
    }
    
    // Process Haas effect if enabled
    if (haasEnabled_) {
        haas_.processBlock(tempBufferLeft_.data(), tempBufferRight_.data(), numSamples);
    }
    
    // Process mid/side if enabled
    if (midSideEnabled_) {
        midSide_.processBlock(tempBufferLeft_.data(), tempBufferRight_.data(), numSamples);
    }
    
    // Copy back to output
    std::copy(tempBufferLeft_.data(), tempBufferLeft_.data() + numSamples, leftChannel);
    std::copy(tempBufferRight_.data(), tempBufferRight_.data() + numSamples, rightChannel);
}

void StereoEnhancer::setCrossFeedAmount(float amount) {
    crossFeed_.setCrossFeedAmount(amount);
}

void StereoEnhancer::setStereoWidth(float width) {
    crossFeed_.setStereoWidth(width);
}

void StereoEnhancer::setChorusEnabled(bool enabled) {
    chorusEnabled_ = enabled;
}

void StereoEnhancer::setChorusRate(float rate) {
    chorus_.setRate(rate);
}

void StereoEnhancer::setChorusDepth(float depth) {
    chorus_.setDepth(depth);
}

void StereoEnhancer::setChorusMix(float mix) {
    chorus_.setWetDryMix(mix);
}

void StereoEnhancer::setHaasEnabled(bool enabled) {
    haasEnabled_ = enabled;
}

void StereoEnhancer::setHaasDelay(float delayMs) {
    haas_.setDelayTime(delayMs);
}

void StereoEnhancer::setHaasMix(float mix) {
    haas_.setWetDryMix(mix);
}

void StereoEnhancer::setMidSideEnabled(bool enabled) {
    midSideEnabled_ = enabled;
}

void StereoEnhancer::setMidGain(float gain) {
    midSide_.setMidGain(gain);
}

void StereoEnhancer::setSideGain(float gain) {
    midSide_.setSideGain(gain);
}

void StereoEnhancer::setEnabled(bool enabled) {
    enabled_ = enabled;
}

void StereoEnhancer::reset() {
    crossFeed_.reset();
    chorus_.reset();
    std::fill(tempBufferLeft_.begin(), tempBufferLeft_.end(), 0.0f);
    std::fill(tempBufferRight_.begin(), tempBufferRight_.end(), 0.0f);
}

} // namespace VoiceMonitor