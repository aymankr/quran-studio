#include "FDNReverb.hpp"
#include "AudioMath.hpp"
#include <algorithm>
#include <random>
#include <cstring>

namespace VoiceMonitor {

// Prime numbers for delay lengths to avoid flutter echoes
const std::vector<int> FDNReverb::PRIME_DELAYS = {
    347, 383, 431, 479, 523, 587, 647, 719, 787, 859, 937, 1009
};

// DelayLine Implementation
FDNReverb::DelayLine::DelayLine(int maxLength) 
    : buffer_(maxLength, 0.0f)
    , writeIndex_(0)
    , delay_(0.0f)
    , maxLength_(maxLength) {
}

void FDNReverb::DelayLine::setDelay(float delaySamples) {
    delay_ = std::max(1.0f, std::min(delaySamples, static_cast<float>(maxLength_ - 1)));
}

float FDNReverb::DelayLine::process(float input) {
    // Write input
    buffer_[writeIndex_] = input;
    
    // Calculate read position with fractional delay
    float readPos = writeIndex_ - delay_;
    if (readPos < 0) {
        readPos += maxLength_;
    }
    
    // Linear interpolation for smooth delay
    int readIndex = static_cast<int>(readPos);
    float fraction = readPos - readIndex;
    
    int readIndex1 = readIndex;
    int readIndex2 = (readIndex + 1) % maxLength_;
    
    float sample1 = buffer_[readIndex1];
    float sample2 = buffer_[readIndex2];
    
    float output = sample1 + fraction * (sample2 - sample1);
    
    // Advance write pointer
    writeIndex_ = (writeIndex_ + 1) % maxLength_;
    
    return output;
}

void FDNReverb::DelayLine::clear() {
    std::fill(buffer_.begin(), buffer_.end(), 0.0f);
    writeIndex_ = 0;
}

// AllPassFilter Implementation
FDNReverb::AllPassFilter::AllPassFilter(int delayLength, float gain)
    : delay_(delayLength)
    , gain_(gain) {
}

float FDNReverb::AllPassFilter::process(float input) {
    float delayedSignal = delay_.process(input + gain_ * delay_.process(0));
    return -gain_ * input + delayedSignal;
}

void FDNReverb::AllPassFilter::clear() {
    delay_.clear();
}

// DampingFilter Implementation
FDNReverb::DampingFilter::DampingFilter() 
    : hfState1_(0.0f), hfState2_(0.0f)
    , lfState1_(0.0f), lfState2_(0.0f)
    , hfCoeff1_(0.8f), hfCoeff2_(0.2f)
    , lfCoeff1_(0.8f), lfCoeff2_(0.2f)
    , hfGain_(1.0f), lfGain_(1.0f) {
}

void FDNReverb::DampingFilter::setDamping(float hfDamping, float lfDamping, float sampleRate) {
    // Calculate Butterworth 2nd order coefficients for HF damping
    float hfCutoff = 8000.0f * (1.0f - hfDamping); // 8kHz to 100Hz range
    float hfOmega = 2.0f * M_PI * hfCutoff / sampleRate;
    float hfCos = std::cos(hfOmega);
    float hfSin = std::sin(hfOmega);
    float hfAlpha = hfSin / 1.414f; // Q = sqrt(2)/2 for Butterworth
    
    float hfB0 = (1.0f - hfCos) / 2.0f;
    float hfB1 = 1.0f - hfCos;
    float hfB2 = (1.0f - hfCos) / 2.0f;
    float hfA0 = 1.0f + hfAlpha;
    float hfA1 = -2.0f * hfCos;
    float hfA2 = 1.0f - hfAlpha;
    
    hfCoeff1_ = hfA1 / hfA0;
    hfCoeff2_ = hfA2 / hfA0;
    hfGain_ = hfB0 / hfA0;
    
    // Calculate Butterworth 2nd order coefficients for LF damping  
    float lfCutoff = 200.0f * (1.0f - lfDamping) + 50.0f; // 200Hz to 50Hz range
    float lfOmega = 2.0f * M_PI * lfCutoff / sampleRate;
    float lfCos = std::cos(lfOmega);
    float lfSin = std::sin(lfOmega);
    float lfAlpha = lfSin / 1.414f;
    
    float lfB0 = (1.0f + lfCos) / 2.0f;
    float lfB1 = -(1.0f + lfCos);
    float lfB2 = (1.0f + lfCos) / 2.0f;
    float lfA0 = 1.0f + lfAlpha;
    float lfA1 = -2.0f * lfCos;
    float lfA2 = 1.0f - lfAlpha;
    
    lfCoeff1_ = lfA1 / lfA0;
    lfCoeff2_ = lfA2 / lfA0;
    lfGain_ = lfB0 / lfA0;
}

float FDNReverb::DampingFilter::process(float input) {
    // Process through HF lowpass filter (2nd order Butterworth)
    float hfOutput = hfGain_ * (input + 2.0f * hfState1_ + hfState2_) 
                   - hfCoeff1_ * hfState1_ - hfCoeff2_ * hfState2_;
    hfState2_ = hfState1_;
    hfState1_ = input;
    
    // Process through LF highpass filter (2nd order Butterworth)
    float lfOutput = lfGain_ * (hfOutput - 2.0f * lfState1_ + lfState2_) 
                   - lfCoeff1_ * lfState1_ - lfCoeff2_ * lfState2_;
    lfState2_ = lfState1_;
    lfState1_ = hfOutput;
    
    return lfOutput;
}

void FDNReverb::DampingFilter::clear() {
    hfState1_ = hfState2_ = 0.0f;
    lfState1_ = lfState2_ = 0.0f;
}

// ModulatedDelay Implementation
FDNReverb::ModulatedDelay::ModulatedDelay(int maxLength)
    : delay_(maxLength)
    , baseDelay_(0.0f)
    , modDepth_(0.0f)
    , modRate_(0.0f)
    , modPhase_(0.0f)
    , sampleRate_(44100.0) {
}

void FDNReverb::ModulatedDelay::setBaseDelay(float delaySamples) {
    baseDelay_ = delaySamples;
}

void FDNReverb::ModulatedDelay::setModulation(float depth, float rate) {
    modDepth_ = depth;
    modRate_ = rate;
}

float FDNReverb::ModulatedDelay::process(float input) {
    // Calculate modulated delay
    float modulation = modDepth_ * std::sin(modPhase_);
    float currentDelay = baseDelay_ + modulation;
    delay_.setDelay(currentDelay);
    
    // Update modulation phase
    modPhase_ += 2.0f * M_PI * modRate_ / sampleRate_;
    if (modPhase_ > 2.0f * M_PI) {
        modPhase_ -= 2.0f * M_PI;
    }
    
    return delay_.process(input);
}

void FDNReverb::ModulatedDelay::clear() {
    delay_.clear();
    modPhase_ = 0.0f;
}

void FDNReverb::ModulatedDelay::updateSampleRate(double sampleRate) {
    sampleRate_ = sampleRate;
}

// FDNReverb Implementation
FDNReverb::FDNReverb(double sampleRate, int numDelayLines)
    : sampleRate_(sampleRate)
    , numDelayLines_(std::max(4, std::min(numDelayLines, 12)))
    , useInterpolation_(true)
    , decayTime_(2.0f)
    , preDelay_(0.0f)
    , roomSize_(0.5f)
    , density_(0.7f)
    , highFreqDamping_(0.3f)
    , lowFreqDamping_(0.2f) {
    
    // Initialize delay lines
    delayLines_.reserve(numDelayLines_);
    for (int i = 0; i < numDelayLines_; ++i) {
        delayLines_.emplace_back(std::make_unique<DelayLine>(MAX_DELAY_LENGTH));
    }
    
    // Initialize diffusion filters (2 stages per delay line)
    for (int i = 0; i < numDelayLines_ * 2; ++i) {
        int diffusionLength = 50 + i * 20; // Varying lengths for smooth diffusion
        diffusionFilters_.emplace_back(std::make_unique<AllPassFilter>(diffusionLength));
    }
    
    // Initialize damping filters
    for (int i = 0; i < numDelayLines_; ++i) {
        dampingFilters_.emplace_back(std::make_unique<DampingFilter>());
    }
    
    // Initialize modulated delays for chorus effect
    for (int i = 0; i < numDelayLines_; ++i) {
        modulatedDelays_.emplace_back(std::make_unique<ModulatedDelay>(MAX_DELAY_LENGTH / 4));
    }
    
    // Initialize pre-delay
    preDelayLine_ = std::make_unique<DelayLine>(static_cast<int>(sampleRate * 0.2)); // 200ms max
    
    // Initialize cross-feed processor for professional stereo processing
    crossFeedProcessor_ = std::make_unique<CrossFeedProcessor>();
    
    // Initialize state vectors
    delayOutputs_.resize(numDelayLines_);
    matrixOutputs_.resize(numDelayLines_);
    tempBuffer_.resize(1024); // Temp buffer for processing
    
    // Setup delay lengths and feedback matrix
    setupDelayLengths();
    setupFeedbackMatrix();
}

FDNReverb::~FDNReverb() = default;

void FDNReverb::processMono(const float* input, float* output, int numSamples) {
    for (int i = 0; i < numSamples; ++i) {
        // Apply pre-delay
        float preDelayedInput = preDelayLine_->process(input[i]);
        
        // Process through diffusion filters
        float diffusedInput = preDelayedInput;
        for (int stage = 0; stage < 2; ++stage) {
            diffusedInput = diffusionFilters_[stage]->process(diffusedInput);
        }
        
        // Read from delay lines
        for (int j = 0; j < numDelayLines_; ++j) {
            delayOutputs_[j] = delayLines_[j]->process(0); // Just read, don't write yet
        }
        
        // Apply feedback matrix
        processMatrix();
        
        // Process through damping filters and write back to delays
        float mixedOutput = 0.0f;
        for (int j = 0; j < numDelayLines_; ++j) {
            float dampedSignal = dampingFilters_[j]->process(matrixOutputs_[j]);
            
            // Add input with some diffusion
            float delayInput = diffusedInput * 0.3f + dampedSignal;
            
            // Store in delay line (this will be read next sample)
            delayLines_[j]->process(delayInput);
            
            // Mix to output
            mixedOutput += dampedSignal;
        }
        
        output[i] = mixedOutput * 0.3f; // Scale down to prevent clipping
    }
}

void FDNReverb::processStereo(const float* inputL, const float* inputR, 
                             float* outputL, float* outputR, int numSamples) {
    for (int i = 0; i < numSamples; ++i) {
        // Mix input to mono for processing
        float monoInput = (inputL[i] + inputR[i]) * 0.5f;
        
        // Apply pre-delay
        float preDelayedInput = preDelayLine_->process(monoInput);
        
        // Process through diffusion filters
        float diffusedInput = preDelayedInput;
        for (int stage = 0; stage < 4; ++stage) {
            if (stage < diffusionFilters_.size()) {
                diffusedInput = diffusionFilters_[stage]->process(diffusedInput);
            }
        }
        
        // Read from delay lines
        for (int j = 0; j < numDelayLines_; ++j) {
            delayOutputs_[j] = delayLines_[j]->process(0);
        }
        
        // Apply feedback matrix
        processMatrix();
        
        // Process and mix outputs
        float leftMix = 0.0f;
        float rightMix = 0.0f;
        
        for (int j = 0; j < numDelayLines_; ++j) {
            float dampedSignal = dampingFilters_[j]->process(matrixOutputs_[j]);
            
            // Add input with diffusion
            float delayInput = diffusedInput * 0.25f + dampedSignal;
            delayLines_[j]->process(delayInput);
            
            // Pan odd delays to left, even to right for stereo width
            if (j % 2 == 0) {
                leftMix += dampedSignal;
            } else {
                rightMix += dampedSignal;
            }
        }
        
        outputL[i] = leftMix * 0.25f;
        outputR[i] = rightMix * 0.25f;
    }
    
    // Apply professional cross-feed processing for enhanced stereo image
    if (crossFeedProcessor_) {
        crossFeedProcessor_->processStereo(outputL, outputR, numSamples);
    }
}

void FDNReverb::processMatrix() {
    // Apply Householder feedback matrix for natural reverb decay
    for (int i = 0; i < numDelayLines_; ++i) {
        matrixOutputs_[i] = 0.0f;
        for (int j = 0; j < numDelayLines_; ++j) {
            matrixOutputs_[i] += feedbackMatrix_[i][j] * delayOutputs_[j];
        }
    }
}

void FDNReverb::setupDelayLengths() {
    std::vector<int> lengths(numDelayLines_);
    calculateDelayLengths(lengths, roomSize_);
    
    for (int i = 0; i < numDelayLines_; ++i) {
        delayLines_[i]->setDelay(static_cast<float>(lengths[i]));
    }
}

void FDNReverb::calculateDelayLengths(std::vector<int>& lengths, float baseSize) {
    // Use prime-based delays scaled by room size
    const float minDelay = 100.0f; // Minimum delay in samples
    const float maxDelay = sampleRate_ * 0.08f * baseSize; // Max 80ms scaled by room size
    
    for (int i = 0; i < numDelayLines_; ++i) {
        if (i < PRIME_DELAYS.size()) {
            float scaledDelay = minDelay + (PRIME_DELAYS[i] * baseSize);
            lengths[i] = static_cast<int>(std::max(minDelay, std::min(scaledDelay, maxDelay)));
        } else {
            // Fallback for more delay lines than primes
            lengths[i] = static_cast<int>(minDelay + (i * 100 * baseSize));
        }
    }
}

void FDNReverb::setupFeedbackMatrix() {
    // Initialize feedback matrix
    feedbackMatrix_.resize(numDelayLines_, std::vector<float>(numDelayLines_));
    
    if (numDelayLines_ == 8) {
        // Optimized 8x8 Householder matrix
        generateHouseholderMatrix();
    } else {
        // Simple matrix for other sizes
        for (int i = 0; i < numDelayLines_; ++i) {
            for (int j = 0; j < numDelayLines_; ++j) {
                if (i == j) {
                    feedbackMatrix_[i][j] = 0.0f; // No self-feedback
                } else {
                    feedbackMatrix_[i][j] = (i + j) % 2 == 0 ? 0.7f : -0.7f;
                }
            }
        }
    }
    
    // Scale matrix by decay time
    float decayGain = std::pow(0.001f, 1.0f / (decayTime_ * sampleRate_ * 0.001f));
    for (auto& row : feedbackMatrix_) {
        for (auto& element : row) {
            element *= decayGain;
        }
    }
}

void FDNReverb::generateHouseholderMatrix() {
    // Generate normalized Householder matrix for natural reverb decay
    const float scale = 2.0f / numDelayLines_;
    
    for (int i = 0; i < numDelayLines_; ++i) {
        for (int j = 0; j < numDelayLines_; ++j) {
            if (i == j) {
                feedbackMatrix_[i][j] = -1.0f + scale;
            } else {
                feedbackMatrix_[i][j] = scale;
            }
        }
    }
}

// Parameter setters
void FDNReverb::setDecayTime(float decayTimeSeconds) {
    decayTime_ = std::max(0.1f, std::min(decayTimeSeconds, 10.0f));
    setupFeedbackMatrix(); // Recalculate matrix with new decay
}

void FDNReverb::setPreDelay(float preDelaySamples) {
    preDelay_ = std::max(0.0f, std::min(preDelaySamples, float(sampleRate_ * 0.2f)));
    preDelayLine_->setDelay(preDelay_);
}

void FDNReverb::setRoomSize(float size) {
    roomSize_ = std::max(0.0f, std::min(size, 1.0f));
    setupDelayLengths();
}

void FDNReverb::setDensity(float density) {
    density_ = std::max(0.0f, std::min(density, 1.0f));
    
    // Adjust diffusion filter gains based on density
    for (auto& filter : diffusionFilters_) {
        filter->setGain(0.5f + density_ * 0.3f);
    }
}

void FDNReverb::setHighFreqDamping(float damping) {
    highFreqDamping_ = std::max(0.0f, std::min(damping, 1.0f));
    
    // Update all damping filters with both HF and LF settings
    for (auto& filter : dampingFilters_) {
        filter->setDamping(highFreqDamping_, lowFreqDamping_, sampleRate_);
    }
}

void FDNReverb::setLowFreqDamping(float damping) {
    lowFreqDamping_ = std::max(0.0f, std::min(damping, 1.0f));
    
    // Update all damping filters with both HF and LF settings
    for (auto& filter : dampingFilters_) {
        filter->setDamping(highFreqDamping_, lowFreqDamping_, sampleRate_);
    }
}

// Advanced stereo control methods
void FDNReverb::setCrossFeedAmount(float amount) {
    if (crossFeedProcessor_) {
        crossFeedProcessor_->setCrossFeedAmount(amount);
    }
}

void FDNReverb::setPhaseInversion(bool invert) {
    if (crossFeedProcessor_) {
        crossFeedProcessor_->setPhaseInversion(invert);
    }
}

void FDNReverb::setStereoWidth(float width) {
    if (crossFeedProcessor_) {
        crossFeedProcessor_->setStereoWidth(width);
    }
}

void FDNReverb::setModulation(float depth, float rate) {
    for (int i = 0; i < modulatedDelays_.size(); ++i) {
        // Vary modulation parameters slightly for each delay line
        float depthVariation = depth * (0.8f + 0.4f * i / numDelayLines_);
        float rateVariation = rate * (0.9f + 0.2f * i / numDelayLines_);
        modulatedDelays_[i]->setModulation(depthVariation, rateVariation);
    }
}

void FDNReverb::reset() {
    clear();
    setupDelayLengths();
    setupFeedbackMatrix();
}

void FDNReverb::clear() {
    for (auto& delay : delayLines_) {
        delay->clear();
    }
    
    for (auto& filter : diffusionFilters_) {
        filter->clear();
    }
    
    for (auto& filter : dampingFilters_) {
        filter->clear();
    }
    
    for (auto& delay : modulatedDelays_) {
        delay->clear();
    }
    
    preDelayLine_->clear();
    
    std::fill(delayOutputs_.begin(), delayOutputs_.end(), 0.0f);
    std::fill(matrixOutputs_.begin(), matrixOutputs_.end(), 0.0f);
}

void FDNReverb::updateSampleRate(double sampleRate) {
    sampleRate_ = sampleRate;
    
    for (auto& delay : modulatedDelays_) {
        delay->updateSampleRate(sampleRate);
    }
    
    reset(); // Recalculate everything for new sample rate
}

// CrossFeedProcessor Implementation
FDNReverb::CrossFeedProcessor::CrossFeedProcessor()
    : crossFeedAmount_(0.5f)
    , stereoWidth_(1.0f)
    , phaseInvert_(false)
    , delayStateL_(0.0f)
    , delayStateR_(0.0f) {
}

void FDNReverb::CrossFeedProcessor::processStereo(float* left, float* right, int numSamples) {
    for (int i = 0; i < numSamples; ++i) {
        float l = left[i];
        float r = right[i];
        
        // Apply stereo width control
        float mid = (l + r) * 0.5f;
        float side = (l - r) * 0.5f * stereoWidth_;
        
        // Calculate cross-feed
        float crossFeedL = r * crossFeedAmount_;
        float crossFeedR = l * crossFeedAmount_;
        
        // Apply phase inversion if enabled
        if (phaseInvert_) {
            crossFeedR = -crossFeedR;
        }
        
        // Mix with cross-feed and apply 1-sample delay for phase shift
        float outputL = mid + side + crossFeedL + delayStateL_;
        float outputR = mid - side + crossFeedR + delayStateR_;
        
        // Update delay states
        delayStateL_ = l * 0.1f;  // Subtle delay for natural phase shift
        delayStateR_ = r * 0.1f;
        
        left[i] = outputL;
        right[i] = outputR;
    }
}

void FDNReverb::CrossFeedProcessor::setCrossFeedAmount(float amount) {
    crossFeedAmount_ = std::max(0.0f, std::min(amount, 1.0f));
}

void FDNReverb::CrossFeedProcessor::setPhaseInversion(bool invert) {
    phaseInvert_ = invert;
}

void FDNReverb::CrossFeedProcessor::setStereoWidth(float width) {
    stereoWidth_ = std::max(0.0f, std::min(width, 2.0f));
}

void FDNReverb::CrossFeedProcessor::clear() {
    delayStateL_ = delayStateR_ = 0.0f;
}

} // namespace VoiceMonitor