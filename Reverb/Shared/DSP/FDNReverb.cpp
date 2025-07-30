#include "FDNReverb.hpp"
#include "AudioMath.hpp"
#include <algorithm>
#include <random>
#include <cstring>

namespace VoiceMonitor {

// Optimized prime numbers for FDN delay lengths (30ms to 100ms at 48kHz)
// These are carefully selected to minimize periodicities and flutter echoes
// Based on Freeverb and professional reverb research
const std::vector<int> FDNReverb::PRIME_DELAYS = {
    1447,  // ~30.1ms at 48kHz - Concert hall early reflections
    1549,  // ~32.3ms - Small hall size
    1693,  // ~35.3ms - Medium hall size  
    1789,  // ~37.3ms - Large room reflections
    1907,  // ~39.7ms - Cathedral early reflections
    2063,  // ~43.0ms - Large hall reflections
    2179,  // ~45.4ms - Stadium-like reflections
    2311,  // ~48.1ms - Very large space early
    2467,  // ~51.4ms - Cathedral main body
    2633,  // ~54.9ms - Large cathedral reflections
    2801,  // ~58.4ms - Massive space early
    2969,  // ~61.9ms - Very large hall main
    3137,  // ~65.4ms - Cathedral nave reflections
    3307,  // ~68.9ms - Huge space main body
    3491,  // ~72.7ms - Massive cathedral reflections
    3677,  // ~76.6ms - Arena-size reflections
    3863,  // ~80.5ms - Stadium main body
    4051,  // ~84.4ms - Very large cathedral
    4241,  // ~88.4ms - Massive space main
    4801   // ~100.0ms - Maximum hall size
};

// Prime numbers for early reflection all-pass filters (5ms to 20ms at 48kHz)
// These create the initial dense cloud of early reflections before FDN processing
const std::vector<int> FDNReverb::EARLY_REFLECTION_DELAYS = {
    241,   // ~5.0ms at 48kHz - First wall reflection
    317,   // ~6.6ms - Floor/ceiling reflection
    431,   // ~9.0ms - Back wall reflection
    563,   // ~11.7ms - Corner reflections
    701,   // ~14.6ms - Complex room geometry
    857,   // ~17.9ms - Large room early reflections
    997,   // ~20.8ms - Maximum early reflection time
    1151   // ~24.0ms - Extended early reflections
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
    , gain_(gain)
    , lastOutput_(0.0f) {
}

float FDNReverb::AllPassFilter::process(float input) {
    // High-quality all-pass filter implementation for professional diffusion
    // Based on Schroeder all-pass: y[n] = -g*x[n] + x[n-d] + g*y[n-d]
    
    // Get the delayed signal (what was written d samples ago)
    float delayedSignal = delay_.process(0.0f);
    
    // Calculate all-pass output
    float output = -gain_ * input + delayedSignal + gain_ * lastOutput_;
    
    // Feed the input + g*output back into the delay line for next iteration
    float feedbackSignal = input + gain_ * output;
    delay_.process(feedbackSignal);
    
    // Store output for next sample's feedback
    lastOutput_ = output;
    
    return output;
}

void FDNReverb::AllPassFilter::clear() {
    delay_.clear();
    lastOutput_ = 0.0f;
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
    , numEarlyReflections_(4) // Default: 4 early reflection stages
    , lastRoomSize_(0.5f)
    , needsBufferFlush_(false)
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
    
    // Initialize high-density diffusion filters (4 stages for professional quality)
    // Use prime-based lengths to avoid periodicities in diffusion
    const std::vector<int> diffusionPrimes = {89, 109, 127, 149, 167, 191, 211, 233};
    int diffusionStages = std::min(8, static_cast<int>(diffusionPrimes.size()));
    
    for (int i = 0; i < diffusionStages; ++i) {
        float gain = 0.7f - (i * 0.03f); // Gradually decreasing gains for stability
        diffusionFilters_.emplace_back(std::make_unique<AllPassFilter>(diffusionPrimes[i], gain));
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
    setupEarlyReflections();
}

FDNReverb::~FDNReverb() = default;

void FDNReverb::processMono(const float* input, float* output, int numSamples) {
    // Check for room size changes and flush buffers if needed
    checkAndFlushBuffers();
    
    for (int i = 0; i < numSamples; ++i) {
        // Apply pre-delay
        float preDelayedInput = preDelayLine_->process(input[i]);
        
        // Process through early reflections (creates initial dense cloud)
        float earlyReflected = processEarlyReflections(preDelayedInput);
        
        // Process through high-density diffusion filters (all stages)
        float diffusedInput = earlyReflected;
        for (auto& filter : diffusionFilters_) {
            diffusedInput = filter->process(diffusedInput);
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
    // Check for room size changes and flush buffers if needed
    checkAndFlushBuffers();
    
    for (int i = 0; i < numSamples; ++i) {
        // Mix input to mono for processing
        float monoInput = (inputL[i] + inputR[i]) * 0.5f;
        
        // Apply pre-delay
        float preDelayedInput = preDelayLine_->process(monoInput);
        
        // Process through early reflections (creates initial dense cloud)
        float earlyReflected = processEarlyReflections(preDelayedInput);
        
        // Process through high-density diffusion filters (all stages for stereo)
        float diffusedInput = earlyReflected;
        for (auto& filter : diffusionFilters_) {
            diffusedInput = filter->process(diffusedInput);
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
    // Use optimized prime delays scaled by room size and sample rate
    float sampleRateScale = static_cast<float>(sampleRate_) / 48000.0f;
    float roomScale = 0.5f + baseSize * 1.5f; // 0.5x to 2.0x scaling for room size
    
    for (int i = 0; i < numDelayLines_; ++i) {
        // Use prime delays with room size and sample rate compensation
        int primeIndex = std::min(i, static_cast<int>(PRIME_DELAYS.size() - 1));
        float scaledDelay = PRIME_DELAYS[primeIndex] * sampleRateScale * roomScale;
        
        // Ensure minimum and maximum bounds
        lengths[i] = static_cast<int>(std::clamp(scaledDelay, 200.0f, 
                                               static_cast<float>(MAX_DELAY_LENGTH - 1)));
        
        // Add slight variation to prevent perfect alignment (reduces metallic artifacts)
        if (i > 0) {
            lengths[i] += (i % 3) - 1; // Add -1, 0, or 1 samples variation
        }
    }
}

void FDNReverb::setupFeedbackMatrix() {
    // Initialize feedback matrix
    feedbackMatrix_.resize(numDelayLines_, std::vector<float>(numDelayLines_));
    
    // Always use Householder matrix for professional quality
    generateHouseholderMatrix();
    
    // Calculate decay gain for stable reverb tail
    // RT60 formula: gain = 10^(-3 * block_time / RT60)
    float blockTimeSeconds = 64.0f / static_cast<float>(sampleRate_); // Assuming 64-sample blocks
    float rt60 = decayTime_; // RT60 is our decay time parameter
    float decayGainLinear = std::pow(10.0f, -3.0f * blockTimeSeconds / rt60);
    
    // Apply additional scaling for stability and frequency-dependent decay
    float stabilityScale = 0.98f; // Slightly under unity for guaranteed stability
    float hfDecayScale = 1.0f - highFreqDamping_ * 0.15f; // HF decay faster
    float finalGain = decayGainLinear * stabilityScale * hfDecayScale;
    
    // Ensure matrix gain is always less than 1.0 for stability
    finalGain = std::min(finalGain, 0.95f);
    
    // Scale the entire matrix
    for (auto& row : feedbackMatrix_) {
        for (auto& element : row) {
            element *= finalGain;
        }
    }
}

void FDNReverb::generateHouseholderMatrix() {
    // Generate proper orthogonal Householder matrix for uniform energy distribution
    // This ensures no energy loss or gain in the feedback network
    
    // Use fixed seed for reproducible results
    std::mt19937 gen(42);
    std::normal_distribution<float> dist(0.0f, 1.0f);
    
    // Generate random vector for Householder reflection
    std::vector<float> v(numDelayLines_);
    for (int i = 0; i < numDelayLines_; ++i) {
        v[i] = dist(gen);
    }
    
    // Normalize the vector
    float norm = 0.0f;
    for (float val : v) {
        norm += val * val;
    }
    norm = std::sqrt(norm);
    
    for (float& val : v) {
        val /= norm;
    }
    
    // Create Householder matrix H = I - 2*v*v^T
    // This creates an orthogonal matrix with determinant -1
    for (int i = 0; i < numDelayLines_; ++i) {
        for (int j = 0; j < numDelayLines_; ++j) {
            float identity = (i == j) ? 1.0f : 0.0f;
            feedbackMatrix_[i][j] = identity - 2.0f * v[i] * v[j];
        }
    }
    
    // Verify orthogonality in debug builds
    #ifdef DEBUG
    // Calculate H * H^T to verify it equals identity matrix
    float maxError = 0.0f;
    for (int i = 0; i < numDelayLines_; ++i) {
        for (int j = 0; j < numDelayLines_; ++j) {
            float dot = 0.0f;
            for (int k = 0; k < numDelayLines_; ++k) {
                dot += feedbackMatrix_[i][k] * feedbackMatrix_[j][k];
            }
            float expected = (i == j) ? 1.0f : 0.0f;
            maxError = std::max(maxError, std::abs(dot - expected));
        }
    }
    // Matrix should be orthogonal within floating point precision
    assert(maxError < 1e-6f);
    #endif
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
    float newSize = std::clamp(size, 0.0f, 1.0f);
    
    // Check if this is a significant change that requires buffer flush
    if (std::abs(newSize - roomSize_) > ROOM_SIZE_CHANGE_THRESHOLD) {
        printf("Significant room size change: %.3f -> %.3f\n", roomSize_, newSize);
        needsBufferFlush_ = true;
    }
    
    roomSize_ = newSize;
    
    // Reconfigure delay lengths and early reflections
    setupDelayLengths();
    setupEarlyReflections();
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
    
    // Clear early reflection filters
    for (auto& filter : earlyReflectionFilters_) {
        filter->clear();
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

// Diagnostic and optimization methods for FDNReverb
void FDNReverb::printFDNConfiguration() const {
    printf("\n=== FDN Reverb Configuration ===\n");
    printf("Delay Lines: %d\n", numDelayLines_);
    printf("Sample Rate: %.1f Hz\n", sampleRate_);
    printf("Diffusion Stages: %zu\n", diffusionFilters_.size());
    printf("Early Reflections: %zu stages\n", earlyReflectionFilters_.size());
    printf("Room Size: %.2f (last: %.2f)\n", roomSize_, lastRoomSize_);
    printf("Decay Time: %.2f s\n", decayTime_);
    printf("HF Damping: %.2f\n", highFreqDamping_);
    printf("LF Damping: %.2f\n", lowFreqDamping_);
    
    printf("\nEarly Reflection Delays (samples @ %.0fHz):\n", sampleRate_);
    for (size_t i = 0; i < earlyReflectionFilters_.size() && i < EARLY_REFLECTION_DELAYS.size(); ++i) {
        float sampleRateScale = static_cast<float>(sampleRate_) / 48000.0f;
        float roomScale = 0.3f + roomSize_ * 0.7f;
        int scaledDelay = static_cast<int>(EARLY_REFLECTION_DELAYS[i] * sampleRateScale * roomScale);
        float timeMs = (scaledDelay / static_cast<float>(sampleRate_)) * 1000.0f;
        printf("  ER %zu: ~%d samples (%.1f ms)\n", i, scaledDelay, timeMs);
    }
    
    printf("\nFDN Delay Lengths (samples @ %.0fHz):\n", sampleRate_);
    for (int i = 0; i < numDelayLines_ && i < delayLines_.size(); ++i) {
        // We can't access private delay_ directly, so estimate from PRIME_DELAYS
        float sampleRateScale = static_cast<float>(sampleRate_) / 48000.0f;
        float roomScale = 0.5f + roomSize_ * 1.5f;
        int primeIndex = std::min(i, static_cast<int>(PRIME_DELAYS.size() - 1));
        int estimatedLength = static_cast<int>(PRIME_DELAYS[primeIndex] * sampleRateScale * roomScale);
        float timeMs = (estimatedLength / static_cast<float>(sampleRate_)) * 1000.0f;
        printf("  Line %d: ~%d samples (%.1f ms)\n", i, estimatedLength, timeMs);
    }
    
    printf("\nFeedback Matrix Properties:\n");
    printf("  Matrix Size: %dx%d\n", static_cast<int>(feedbackMatrix_.size()), 
           feedbackMatrix_.empty() ? 0 : static_cast<int>(feedbackMatrix_[0].size()));
    
    // Calculate matrix energy
    float matrixEnergy = 0.0f;
    for (const auto& row : feedbackMatrix_) {
        for (float element : row) {
            matrixEnergy += element * element;
        }
    }
    printf("  Matrix Energy: %.6f (should be ≈ %d for orthogonal)\n", matrixEnergy, numDelayLines_);
    printf("  Orthogonal: %s\n", verifyMatrixOrthogonality() ? "Yes" : "No");
    printf("===============================\n\n");
}

bool FDNReverb::verifyMatrixOrthogonality() const {
    if (feedbackMatrix_.empty() || feedbackMatrix_.size() != feedbackMatrix_[0].size()) {
        return false;
    }
    
    const float tolerance = 1e-4f;
    int n = static_cast<int>(feedbackMatrix_.size());
    
    // Check if H * H^T = I (within tolerance)
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            float dot = 0.0f;
            for (int k = 0; k < n; ++k) {
                dot += feedbackMatrix_[i][k] * feedbackMatrix_[j][k];
            }
            
            float expected = (i == j) ? 1.0f : 0.0f;
            if (std::abs(dot - expected) > tolerance) {
                return false;
            }
        }
    }
    
    return true;
}

std::vector<int> FDNReverb::getCurrentDelayLengths() const {
    std::vector<int> lengths(numDelayLines_);
    
    // Reconstruct the delay lengths using the same calculation as setupDelayLengths
    float sampleRateScale = static_cast<float>(sampleRate_) / 48000.0f;
    float roomScale = 0.5f + roomSize_ * 1.5f;
    
    for (int i = 0; i < numDelayLines_; ++i) {
        int primeIndex = std::min(i, static_cast<int>(PRIME_DELAYS.size() - 1));
        float scaledDelay = PRIME_DELAYS[primeIndex] * sampleRateScale * roomScale;
        lengths[i] = static_cast<int>(std::clamp(scaledDelay, 200.0f, 
                                               static_cast<float>(MAX_DELAY_LENGTH - 1)));
        if (i > 0) {
            lengths[i] += (i % 3) - 1; // Same variation as in calculateDelayLengths
        }
    }
    
    return lengths;
}

// Early Reflections Implementation
void FDNReverb::setupEarlyReflections() {
    // Clear existing early reflection filters
    earlyReflectionFilters_.clear();
    
    // Create early reflection all-pass filters
    for (int i = 0; i < numEarlyReflections_ && i < EARLY_REFLECTION_DELAYS.size(); ++i) {
        // Scale delay lengths by room size and sample rate
        float sampleRateScale = static_cast<float>(sampleRate_) / 48000.0f;
        float roomScale = 0.3f + roomSize_ * 0.7f; // 0.3x to 1.0x scaling for early reflections
        
        int scaledDelay = static_cast<int>(EARLY_REFLECTION_DELAYS[i] * sampleRateScale * roomScale);
        scaledDelay = std::clamp(scaledDelay, 10, 2400); // 10 samples to 50ms max
        
        // Decreasing gain for stability: 0.7, 0.65, 0.6, 0.55
        float gain = 0.75f - (i * 0.05f);
        
        earlyReflectionFilters_.emplace_back(std::make_unique<AllPassFilter>(scaledDelay, gain));
    }
    
    printf("Early Reflections: %d stages configured\n", static_cast<int>(earlyReflectionFilters_.size()));
}

float FDNReverb::processEarlyReflections(float input) {
    // Process input through early reflection all-pass filters in series
    float processed = input;
    for (auto& filter : earlyReflectionFilters_) {
        processed = filter->process(processed);
    }
    return processed;
}

// Buffer Management for Size Changes
void FDNReverb::checkAndFlushBuffers() {
    // Check if room size has changed significantly
    float sizeDelta = std::abs(roomSize_ - lastRoomSize_);
    
    if (sizeDelta > ROOM_SIZE_CHANGE_THRESHOLD) {
        printf("Room size change detected: %.3f -> %.3f (delta: %.3f)\n", 
               lastRoomSize_, roomSize_, sizeDelta);
        printf("Flushing all buffers to prevent artifacts...\n");
        
        needsBufferFlush_ = true;
        lastRoomSize_ = roomSize_;
    }
    
    if (needsBufferFlush_) {
        flushAllBuffers();
        needsBufferFlush_ = false;
    }
}

void FDNReverb::flushAllBuffers() {
    // Flush all delay line buffers to prevent artifacts from size changes
    // This is critical for professional quality as noted in AD 480 manual
    
    // Clear main FDN delay lines
    for (auto& delay : delayLines_) {
        delay->clear();
    }
    
    // Clear diffusion filters
    for (auto& filter : diffusionFilters_) {
        filter->clear();
    }
    
    // Clear early reflection filters
    for (auto& filter : earlyReflectionFilters_) {
        filter->clear();
    }
    
    // Clear damping filters
    for (auto& filter : dampingFilters_) {
        filter->clear();
    }
    
    // Clear modulated delays
    for (auto& delay : modulatedDelays_) {
        delay->clear();
    }
    
    // Clear pre-delay
    if (preDelayLine_) {
        preDelayLine_->clear();
    }
    
    // Clear cross-feed processor
    if (crossFeedProcessor_) {
        crossFeedProcessor_->clear();
    }
    
    // Clear processing buffers
    std::fill(delayOutputs_.begin(), delayOutputs_.end(), 0.0f);
    std::fill(matrixOutputs_.begin(), matrixOutputs_.end(), 0.0f);
    
    printf("All buffers flushed successfully\n");
}

} // namespace VoiceMonitor