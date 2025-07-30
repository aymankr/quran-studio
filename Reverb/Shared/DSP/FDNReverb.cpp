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
    crossFeedProcessor_ = std::make_unique<CrossFeedProcessor>(sampleRate_);
    
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
    
    // Create temporary buffers for cross-feed processing
    std::vector<float> crossFeedL(numSamples);
    std::vector<float> crossFeedR(numSamples);
    
    // Copy input to temporary buffers
    std::copy(inputL, inputL + numSamples, crossFeedL.data());
    std::copy(inputR, inputR + numSamples, crossFeedR.data());
    
    // STEP 1: Apply cross-feed BEFORE reverb processing (AD 480 style)
    // This creates the L+R mixing for coherent stereo reverb
    if (crossFeedProcessor_) {
        crossFeedProcessor_->processStereo(crossFeedL.data(), crossFeedR.data(), numSamples);
    }
    
    // STEP 2: Process both channels through separate FDN paths
    for (int i = 0; i < numSamples; ++i) {
        // Use cross-fed signals for reverb input
        float inputLeftChan = crossFeedL[i];
        float inputRightChan = crossFeedR[i];
        
        // Process LEFT channel through FDN
        // Apply pre-delay
        float preDelayedL = preDelayLine_->process(inputLeftChan);
        
        // Process through early reflections
        float earlyReflectedL = processEarlyReflections(preDelayedL);
        
        // Process through diffusion filters
        float diffusedL = earlyReflectedL;
        for (auto& filter : diffusionFilters_) {
            diffusedL = filter->process(diffusedL);
        }
        
        // Read from delay lines (left channel processing)
        for (int j = 0; j < numDelayLines_; ++j) {
            delayOutputs_[j] = delayLines_[j]->process(0);
        }
        
        // Apply feedback matrix
        processMatrix();
        
        // Process through damping and create output mix
        float leftOutput = 0.0f;
        float rightOutput = 0.0f;
        
        for (int j = 0; j < numDelayLines_; ++j) {
            float dampedSignal = dampingFilters_[j]->process(matrixOutputs_[j]);
            
            // Add diffused input to delay lines
            float delayInput = diffusedL * 0.2f + dampedSignal;
            delayLines_[j]->process(delayInput);
            
            // Create stereo image: 
            // Even delays (0,2,4,6) -> Left channel emphasis
            // Odd delays (1,3,5,7) -> Right channel emphasis
            // But both channels get some of each for natural reverb
            float leftGain = (j % 2 == 0) ? 0.7f : 0.3f;
            float rightGain = (j % 2 == 0) ? 0.3f : 0.7f;
            
            leftOutput += dampedSignal * leftGain;
            rightOutput += dampedSignal * rightGain;
        }
        
        // Scale output and mix with original cross-fed dry signal for natural blend
        float reverbGain = 0.3f;
        outputL[i] = leftOutput * reverbGain;
        outputR[i] = rightOutput * reverbGain;
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
    
    // AD 480 calibrated decay time calculation
    // Calculate average delay time for the FDN network
    float averageDelayTime = calculateAverageDelayTime();
    
    // Apply Size-dependent decay limitation (AD 480 behavior)
    float maxDecayForSize = calculateMaxDecayForSize(roomSize_);
    float limitedDecayTime = std::min(decayTime_, maxDecayForSize);
    
    // Classic RT60 formula: gain = 10^(-3 * Δt / RT60)
    // where Δt is the average delay time in the network
    float deltaT = averageDelayTime / static_cast<float>(sampleRate_); // Convert to seconds
    float rt60 = limitedDecayTime; // Our calibrated RT60 target
    
    // Prevent division by zero and ensure minimum decay
    rt60 = std::max(rt60, 0.05f); // Minimum 50ms decay
    
    // Calculate theoretical decay gain
    float theoreticalGain = std::pow(10.0f, -3.0f * deltaT / rt60);
    
    // AD 480 style frequency-dependent scaling
    // High frequencies decay faster, low frequencies sustain longer
    float hfDecayFactor = 1.0f - (highFreqDamping_ * 0.25f); // 0-25% HF reduction
    float lfDecayFactor = 1.0f - (lowFreqDamping_ * 0.15f);  // 0-15% LF reduction
    float freqWeightedGain = theoreticalGain * hfDecayFactor * lfDecayFactor;
    
    // Stability enforcement (critical for professional quality)
    // AD 480 uses approximately 0.97 max gain for guaranteed stability
    float stabilityLimit = 0.97f;
    
    // Additional safety margin based on room size (larger rooms need more stability)
    float sizeStabilityFactor = 0.98f - (roomSize_ * 0.03f); // 0.98 to 0.95 range
    stabilityLimit = std::min(stabilityLimit, sizeStabilityFactor);
    
    float finalGain = std::min(freqWeightedGain, stabilityLimit);
    
    // Diagnostic output for calibration verification
    printf("=== AD 480 Decay Calibration ===\n");
    printf("Target RT60: %.2f s (limited from %.2f s)\n", rt60, decayTime_);
    printf("Average delay: %.1f samples (%.2f ms)\n", averageDelayTime, deltaT * 1000.0f);
    printf("Theoretical gain: %.6f\n", theoreticalGain);
    printf("Freq-weighted gain: %.6f\n", freqWeightedGain);
    printf("Final gain: %.6f (stability limit: %.6f)\n", finalGain, stabilityLimit);
    printf("Room size factor: %.3f\n", roomSize_);
    printf("================================\n");
    
    // Scale the entire orthogonal matrix
    for (auto& row : feedbackMatrix_) {
        for (auto& element : row) {
            element *= finalGain;
        }
    }
    
    // Verify final matrix energy for debugging
    float matrixEnergy = 0.0f;
    for (const auto& row : feedbackMatrix_) {
        for (float element : row) {
            matrixEnergy += element * element;
        }
    }
    printf("Matrix energy after scaling: %.6f (should be < %.1f for stability)\n", 
           matrixEnergy, static_cast<float>(numDelayLines_) * finalGain * finalGain);
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

// Advanced stereo control methods (AD 480 style)
void FDNReverb::setCrossFeedAmount(float amount) {
    if (crossFeedProcessor_) {
        crossFeedProcessor_->setCrossFeedAmount(amount);
    }
}

void FDNReverb::setCrossDelayMs(float delayMs) {
    if (crossFeedProcessor_) {
        crossFeedProcessor_->setCrossDelayMs(delayMs);
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

void FDNReverb::setCrossFeedBypass(bool bypass) {
    if (crossFeedProcessor_) {
        crossFeedProcessor_->setBypass(bypass);
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
    
    // Update cross-feed processor with new sample rate
    if (crossFeedProcessor_) {
        crossFeedProcessor_->updateSampleRate(sampleRate);
    }
    
    reset(); // Recalculate everything for new sample rate
}

// Professional CrossFeedProcessor Implementation (AD 480 Style)
FDNReverb::CrossFeedProcessor::CrossFeedProcessor(double sampleRate)
    : crossFeedAmount_(0.5f)          // Default 50% cross-feed (AD 480 default)
    , crossDelayMs_(10.0f)            // Default 10ms cross-delay
    , stereoWidth_(1.0f)              // Default normal stereo width
    , phaseInvert_(false)             // Default no phase inversion
    , bypass_(false)                  // Default cross-feed enabled
    , sampleRate_(sampleRate) {
    
    // Initialize cross-feed delay lines (50ms max = 2400 samples at 48kHz)
    int maxDelaySamples = static_cast<int>(sampleRate * 0.05); // 50ms max
    crossDelayL_ = std::make_unique<DelayLine>(maxDelaySamples);
    crossDelayR_ = std::make_unique<DelayLine>(maxDelaySamples);
    
    // Set initial delay lengths
    updateDelayLengths();
    
    printf("CrossFeedProcessor initialized: %.1fms delay, %.1f%% amount\n", 
           crossDelayMs_, crossFeedAmount_ * 100.0f);
}

void FDNReverb::CrossFeedProcessor::processStereo(float* left, float* right, int numSamples) {
    if (bypass_) {
        // Bypass: only apply stereo width control, no cross-feed
        for (int i = 0; i < numSamples; ++i) {
            float l = left[i];
            float r = right[i];
            
            // Apply stereo width control only
            float mid = (l + r) * 0.5f;
            float side = (l - r) * 0.5f * stereoWidth_;
            
            left[i] = mid + side;
            right[i] = mid - side;
        }
        return;
    }
    
    // Professional AD 480 style cross-feed processing
    for (int i = 0; i < numSamples; ++i) {
        float inputL = left[i];
        float inputR = right[i];
        
        // Read delayed cross-feed signals
        float delayedL = crossDelayL_->process(0.0f); // Read without writing
        float delayedR = crossDelayR_->process(0.0f); // Read without writing
        
        // Calculate cross-feed amounts
        // L->R: Take left signal, attenuate it, delay it, mix to right
        // R->L: Take right signal, attenuate it, delay it, mix to left
        float crossFeedL_to_R = delayedL * crossFeedAmount_;
        float crossFeedR_to_L = delayedR * crossFeedAmount_;
        
        // Apply phase inversion on cross-feed if enabled (AD 480 feature)
        if (phaseInvert_) {
            crossFeedR_to_L = -crossFeedR_to_L; // Invert phase on R->L cross-feed
        }
        
        // Mix input signals with cross-feed
        // At crossFeedAmount_ = 0.0: pure stereo (L+0, R+0)
        // At crossFeedAmount_ = 1.0: full mono (L+R, R+L) -> identical signals
        float mixedL = inputL + crossFeedR_to_L;
        float mixedR = inputR + crossFeedL_to_R;
        
        // Apply stereo width control (AD 480 style Mid/Side processing)
        float mid = (mixedL + mixedR) * 0.5f;
        float side = (mixedL - mixedR) * 0.5f * stereoWidth_;
        
        // Write current inputs to delay lines for next samples
        crossDelayL_->process(inputL);
        crossDelayR_->process(inputR);
        
        // Final output
        left[i] = mid + side;
        right[i] = mid - side;
    }
}

void FDNReverb::CrossFeedProcessor::setCrossFeedAmount(float amount) {
    crossFeedAmount_ = std::clamp(amount, 0.0f, 1.0f);
    printf("Cross-feed amount: %.1f%%\n", crossFeedAmount_ * 100.0f);
}

void FDNReverb::CrossFeedProcessor::setCrossDelayMs(float delayMs) {
    crossDelayMs_ = std::clamp(delayMs, 0.0f, 50.0f); // 0-50ms range
    updateDelayLengths();
    printf("Cross-feed delay: %.2f ms\n", crossDelayMs_);
}

void FDNReverb::CrossFeedProcessor::setPhaseInversion(bool invert) {
    phaseInvert_ = invert;
    printf("Cross-feed phase invert: %s\n", invert ? "ON" : "OFF");
}

void FDNReverb::CrossFeedProcessor::setStereoWidth(float width) {
    stereoWidth_ = std::clamp(width, 0.0f, 2.0f);
    printf("Stereo width: %.1f%%\n", stereoWidth_ * 100.0f);
}

void FDNReverb::CrossFeedProcessor::setBypass(bool bypass) {
    bypass_ = bypass;
    printf("Cross-feed bypass: %s\n", bypass ? "ON" : "OFF");
}

void FDNReverb::CrossFeedProcessor::updateSampleRate(double sampleRate) {
    sampleRate_ = sampleRate;
    
    // Recreate delay lines with new sample rate
    int maxDelaySamples = static_cast<int>(sampleRate * 0.05); // 50ms max
    crossDelayL_ = std::make_unique<DelayLine>(maxDelaySamples);
    crossDelayR_ = std::make_unique<DelayLine>(maxDelaySamples);
    
    updateDelayLengths();
}

void FDNReverb::CrossFeedProcessor::clear() {
    if (crossDelayL_) crossDelayL_->clear();
    if (crossDelayR_) crossDelayR_->clear();
}

void FDNReverb::CrossFeedProcessor::updateDelayLengths() {
    // Convert milliseconds to samples
    float delaySamples = (crossDelayMs_ / 1000.0f) * static_cast<float>(sampleRate_);
    
    if (crossDelayL_) crossDelayL_->setDelay(delaySamples);
    if (crossDelayR_) crossDelayR_->setDelay(delaySamples);
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

// AD 480 Calibration Helper Methods
float FDNReverb::calculateAverageDelayTime() {
    // Calculate the average delay time across all FDN delay lines
    // This is critical for accurate RT60 calibration
    
    float sampleRateScale = static_cast<float>(sampleRate_) / 48000.0f;
    float roomScale = 0.5f + roomSize_ * 1.5f; // Same scaling as in calculateDelayLengths
    
    float totalDelay = 0.0f;
    for (int i = 0; i < numDelayLines_; ++i) {
        int primeIndex = std::min(i, static_cast<int>(PRIME_DELAYS.size() - 1));
        float scaledDelay = PRIME_DELAYS[primeIndex] * sampleRateScale * roomScale;
        
        // Apply the same bounds and variations as in calculateDelayLengths
        scaledDelay = std::clamp(scaledDelay, 200.0f, static_cast<float>(MAX_DELAY_LENGTH - 1));
        if (i > 0) {
            scaledDelay += (i % 3) - 1; // Same variation pattern
        }
        
        totalDelay += scaledDelay;
    }
    
    return totalDelay / static_cast<float>(numDelayLines_);
}

float FDNReverb::calculateMaxDecayForSize(float roomSize) {
    // AD 480 style Size-dependent decay limitation
    // Prevents infinite sustain at maximum room size by limiting decay time
    // This is critical for stability in large virtual spaces
    
    // AD 480 approximate behavior:
    // - Small rooms (size 0.0-0.3): Up to 8.0s decay
    // - Medium rooms (size 0.3-0.7): Up to 6.0s decay  
    // - Large rooms (size 0.7-1.0): Up to 3.0s decay
    // This prevents standing wave buildup in large spaces
    
    if (roomSize <= 0.3f) {
        // Small rooms: full decay range available
        return 8.0f;
    } else if (roomSize <= 0.7f) {
        // Medium rooms: interpolate from 8.0s to 6.0s
        float factor = (roomSize - 0.3f) / 0.4f; // 0.0 to 1.0 over 0.3-0.7 range
        return 8.0f - (factor * 2.0f); // 8.0s to 6.0s
    } else {
        // Large rooms: interpolate from 6.0s to 3.0s
        float factor = (roomSize - 0.7f) / 0.3f; // 0.0 to 1.0 over 0.7-1.0 range
        return 6.0f - (factor * 3.0f); // 6.0s to 3.0s
    }
}

// RT60 Validation Methods for Professional Calibration
std::vector<float> FDNReverb::generateImpulseResponse(int lengthSamples) {
    // Generate impulse response for RT60 measurement and validation
    // This allows us to verify that our decay calibration is accurate
    
    printf("=== Generating Impulse Response for RT60 Validation ===\n");
    printf("Length: %d samples (%.2f seconds at %.0f Hz)\n", 
           lengthSamples, lengthSamples / sampleRate_, sampleRate_);
    
    std::vector<float> impulseResponse(lengthSamples, 0.0f);
    
    // Create a temporary copy of the current state for restoration
    // We need to preserve the current state during measurement
    auto tempDelayOutputs = delayOutputs_;
    auto tempMatrixOutputs = matrixOutputs_;
    
    // Clear all buffers to start with clean slate
    const_cast<FDNReverb*>(this)->clear();
    
    // Generate impulse (single sample at maximum amplitude)
    float impulse = 1.0f;
    
    // Process the impulse and subsequent silence
    for (int i = 0; i < lengthSamples; ++i) {
        float input = (i == 0) ? impulse : 0.0f; // Impulse only on first sample
        
        // Process single sample (same logic as processMono but inline)
        
        // Apply pre-delay
        float preDelayedInput = preDelayLine_->process(input);
        
        // Process through early reflections
        float earlyReflected = const_cast<FDNReverb*>(this)->processEarlyReflections(preDelayedInput);
        
        // Process through diffusion filters
        float diffusedInput = earlyReflected;
        for (auto& filter : diffusionFilters_) {
            diffusedInput = filter->process(diffusedInput);
        }
        
        // Read from delay lines
        for (int j = 0; j < numDelayLines_; ++j) {
            delayOutputs_[j] = delayLines_[j]->process(0); // Just read
        }
        
        // Apply feedback matrix
        const_cast<FDNReverb*>(this)->processMatrix();
        
        // Process through damping and write back
        float mixedOutput = 0.0f;
        for (int j = 0; j < numDelayLines_; ++j) {
            float dampedSignal = dampingFilters_[j]->process(matrixOutputs_[j]);
            
            // Add input with diffusion
            float delayInput = diffusedInput * 0.3f + dampedSignal;
            delayLines_[j]->process(delayInput);
            
            // Mix to output
            mixedOutput += dampedSignal;
        }
        
        impulseResponse[i] = mixedOutput * 0.3f; // Same scaling as processMono
    }
    
    // Restore previous state
    delayOutputs_ = tempDelayOutputs;
    matrixOutputs_ = tempMatrixOutputs;
    
    printf("Impulse response generated successfully\n");
    printf("Peak amplitude: %.6f\n", *std::max_element(impulseResponse.begin(), impulseResponse.end()));
    printf("=================================================\n");
    
    return impulseResponse;
}

float FDNReverb::measureRT60FromImpulseResponse(const std::vector<float>& impulseResponse) const {
    // Measure RT60 from impulse response using energy decay analysis
    // RT60 is the time for reverb to decay by 60dB (-60dB = 0.001 linear amplitude)
    
    if (impulseResponse.empty()) {
        return 0.0f;
    }
    
    printf("=== RT60 Measurement from Impulse Response ===\n");
    
    // Calculate energy envelope (running RMS with smoothing)
    std::vector<float> energyEnvelope;
    energyEnvelope.reserve(impulseResponse.size());
    
    const int windowSize = 512; // 512 samples ≈ 10.7ms at 48kHz
    float runningSum = 0.0f;
    
    for (size_t i = 0; i < impulseResponse.size(); ++i) {
        float sample = impulseResponse[i];
        runningSum += sample * sample;
        
        // Remove old samples from window
        if (i >= windowSize) {
            float oldSample = impulseResponse[i - windowSize];
            runningSum -= oldSample * oldSample;
        }
        
        float rms = std::sqrt(runningSum / std::min(static_cast<float>(windowSize), static_cast<float>(i + 1)));
        energyEnvelope.push_back(rms);
    }
    
    // Find peak energy
    float peakEnergy = *std::max_element(energyEnvelope.begin(), energyEnvelope.end());
    printf("Peak energy: %.6f\n", peakEnergy);
    
    if (peakEnergy < 1e-8f) {
        printf("ERROR: Peak energy too low for measurement\n");
        return 0.0f;
    }
    
    // Calculate target levels
    float target60dB = peakEnergy * 0.001f; // -60dB = 10^(-60/20) = 0.001
    float target20dB = peakEnergy * 0.1f;   // -20dB = 10^(-20/20) = 0.1
    
    printf("Target -20dB level: %.6f\n", target20dB);
    printf("Target -60dB level: %.6f\n", target60dB);
    
    // Find -20dB and -60dB crossing points
    int crossingPoint20dB = -1;
    int crossingPoint60dB = -1;
    
    // Look for crossings after peak
    size_t peakIndex = std::max_element(energyEnvelope.begin(), energyEnvelope.end()) - energyEnvelope.begin();
    
    for (size_t i = peakIndex; i < energyEnvelope.size(); ++i) {
        if (crossingPoint20dB == -1 && energyEnvelope[i] <= target20dB) {
            crossingPoint20dB = static_cast<int>(i);
        }
        if (crossingPoint60dB == -1 && energyEnvelope[i] <= target60dB) {
            crossingPoint60dB = static_cast<int>(i);
            break;
        }
    }
    
    printf("Peak at sample: %zu (%.2f ms)\n", peakIndex, (peakIndex / sampleRate_) * 1000.0f);
    
    if (crossingPoint20dB != -1) {
        printf("-20dB crossing at sample: %d (%.2f ms)\n", 
               crossingPoint20dB, (crossingPoint20dB / sampleRate_) * 1000.0f);
    } else {
        printf("WARNING: -20dB level never reached\n");
    }
    
    if (crossingPoint60dB != -1) {
        printf("-60dB crossing at sample: %d (%.2f ms)\n", 
               crossingPoint60dB, (crossingPoint60dB / sampleRate_) * 1000.0f);
        
        float rt60 = (crossingPoint60dB - static_cast<int>(peakIndex)) / sampleRate_;
        printf("Measured RT60: %.3f seconds\n", rt60);
        return rt60;
    } else {
        // Extrapolate RT60 from RT20 if -60dB not reached
        if (crossingPoint20dB != -1) {
            float rt20 = (crossingPoint20dB - static_cast<int>(peakIndex)) / sampleRate_;
            float extrapolatedRT60 = rt20 * 3.0f; // RT60 = 3 * RT20
            printf("Extrapolated RT60 from RT20: %.3f seconds (RT20 = %.3f s)\n", 
                   extrapolatedRT60, rt20);
            return extrapolatedRT60;
        } else {
            printf("ERROR: Cannot measure RT60 - insufficient decay\n");
            return 0.0f;
        }
    }
    
    printf("==============================================\n");
}

} // namespace VoiceMonitor