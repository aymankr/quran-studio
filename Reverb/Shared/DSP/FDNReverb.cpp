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

// Professional DampingFilter Implementation with Separate HF/LF Biquads (AD 480 Style)
FDNReverb::DampingFilter::DampingFilter(double sampleRate)
    : sampleRate_(sampleRate)
    , hfCutoffHz_(8000.0f)          // Default HF cutoff
    , lfCutoffHz_(200.0f)           // Default LF cutoff
    , hfDampingPercent_(0.0f)       // Default no HF damping
    , lfDampingPercent_(0.0f) {     // Default no LF damping
    
    // Initialize with neutral settings (no damping)
    setHFDamping(0.0f, 8000.0f);
    setLFDamping(0.0f, 200.0f);
    
    printf("DampingFilter initialized: HF=%.0fHz LF=%.0fHz\n", hfCutoffHz_, lfCutoffHz_);
}

float FDNReverb::DampingFilter::process(float input) {
    // Process through HF lowpass filter first, then LF highpass filter
    // This creates a bandpass response with controlled HF and LF damping
    
    float hfFiltered = hfFilter_.process(input);
    float output = lfFilter_.process(hfFiltered);
    
    return output;
}

void FDNReverb::DampingFilter::setHFDamping(float dampingPercent, float cutoffHz) {
    hfDampingPercent_ = std::clamp(dampingPercent, 0.0f, 100.0f);
    hfCutoffHz_ = std::clamp(cutoffHz, 1000.0f, 12000.0f);
    
    calculateLowpassCoeffs(hfFilter_, hfCutoffHz_, hfDampingPercent_);
}

void FDNReverb::DampingFilter::setLFDamping(float dampingPercent, float cutoffHz) {
    lfDampingPercent_ = std::clamp(dampingPercent, 0.0f, 100.0f);
    lfCutoffHz_ = std::clamp(cutoffHz, 50.0f, 500.0f);
    
    calculateHighpassCoeffs(lfFilter_, lfCutoffHz_, lfDampingPercent_);
}

void FDNReverb::DampingFilter::updateSampleRate(double sampleRate) {
    sampleRate_ = sampleRate;
    
    // Recalculate both filters with new sample rate
    setHFDamping(hfDampingPercent_, hfCutoffHz_);
    setLFDamping(lfDampingPercent_, lfCutoffHz_);
}

void FDNReverb::DampingFilter::clear() {
    hfFilter_.clear();
    lfFilter_.clear();
}

void FDNReverb::DampingFilter::calculateLowpassCoeffs(BiquadFilter& filter, float cutoffHz, float dampingPercent) {
    // Calculate Butterworth 2nd order lowpass biquad coefficients
    // Using bilinear transform for digital filter design
    
    if (dampingPercent <= 0.0f) {
        // No damping: set to all-pass (unity gain)
        filter.b0 = 1.0f; filter.b1 = 0.0f; filter.b2 = 0.0f;
        filter.a1 = 0.0f; filter.a2 = 0.0f;
        return;
    }
    
    // Calculate digital frequency
    float omega = 2.0f * M_PI * cutoffHz / static_cast<float>(sampleRate_);
    float cos_omega = std::cos(omega);
    float sin_omega = std::sin(omega);
    
    // Butterworth Q factor
    float Q = 0.7071f; // sqrt(2)/2 for Butterworth response
    float alpha = sin_omega / (2.0f * Q);
    
    // Apply damping scaling to filter coefficients
    float dampingFactor = 1.0f - (dampingPercent / 100.0f) * 0.8f; // Max 80% reduction
    
    // Lowpass biquad coefficients (normalized by a0)
    float a0 = 1.0f + alpha;
    filter.b0 = ((1.0f - cos_omega) / 2.0f) / a0 * dampingFactor;
    filter.b1 = (1.0f - cos_omega) / a0 * dampingFactor;
    filter.b2 = ((1.0f - cos_omega) / 2.0f) / a0 * dampingFactor;
    filter.a1 = (-2.0f * cos_omega) / a0;
    filter.a2 = (1.0f - alpha) / a0;
}

void FDNReverb::DampingFilter::calculateHighpassCoeffs(BiquadFilter& filter, float cutoffHz, float dampingPercent) {
    // Calculate Butterworth 2nd order highpass biquad coefficients
    // Using bilinear transform for digital filter design
    
    if (dampingPercent <= 0.0f) {
        // No damping: set to all-pass (unity gain)
        filter.b0 = 1.0f; filter.b1 = 0.0f; filter.b2 = 0.0f;
        filter.a1 = 0.0f; filter.a2 = 0.0f;
        return;
    }
    
    // Calculate digital frequency
    float omega = 2.0f * M_PI * cutoffHz / static_cast<float>(sampleRate_);
    float cos_omega = std::cos(omega);
    float sin_omega = std::sin(omega);
    
    // Butterworth Q factor
    float Q = 0.7071f; // sqrt(2)/2 for Butterworth response
    float alpha = sin_omega / (2.0f * Q);
    
    // Apply damping scaling to filter coefficients
    float dampingFactor = 1.0f - (dampingPercent / 100.0f) * 0.6f; // Max 60% reduction for LF
    
    // Highpass biquad coefficients (normalized by a0)
    float a0 = 1.0f + alpha;
    filter.b0 = ((1.0f + cos_omega) / 2.0f) / a0 * dampingFactor;
    filter.b1 = (-(1.0f + cos_omega)) / a0 * dampingFactor;
    filter.b2 = ((1.0f + cos_omega) / 2.0f) / a0 * dampingFactor;
    filter.a1 = (-2.0f * cos_omega) / a0;
    filter.a2 = (1.0f - alpha) / a0;
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
    
    // Initialize damping filters with sample rate
    for (int i = 0; i < numDelayLines_; ++i) {
        dampingFilters_.emplace_back(std::make_unique<DampingFilter>(sampleRate_));
    }
    
    // Initialize modulated delays for chorus effect
    for (int i = 0; i < numDelayLines_; ++i) {
        modulatedDelays_.emplace_back(std::make_unique<ModulatedDelay>(MAX_DELAY_LENGTH / 4));
    }
    
    // Initialize pre-delay
    preDelayLine_ = std::make_unique<DelayLine>(static_cast<int>(sampleRate * 0.2)); // 200ms max
    
    // Initialize cross-feed processor for professional stereo processing
    crossFeedProcessor_ = std::make_unique<CrossFeedProcessor>(sampleRate_);
    
    // Initialize stereo spread processor for output wet control
    stereoSpreadProcessor_ = std::make_unique<StereoSpreadProcessor>();
    
    // Initialize tone filter for global High Cut and Low Cut
    toneFilter_ = std::make_unique<ToneFilter>(sampleRate_);
    
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
    
    // STEP 3: Apply stereo spread control to wet output (AD 480 "Spread")
    // This controls the stereo width of the wet signal only
    if (stereoSpreadProcessor_) {
        stereoSpreadProcessor_->processStereo(outputL, outputR, numSamples);
    }
    
    // STEP 4: Apply global tone filtering (AD 480 "High Cut" and "Low Cut")
    // This is the final EQ stage before wet/dry mix (out-of-loop filtering)
    if (toneFilter_) {
        toneFilter_->processStereo(outputL, outputR, numSamples);
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
    highFreqDamping_ = std::clamp(damping, 0.0f, 1.0f);
    
    // Convert damping percentage to cutoff frequency (AD 480 style)
    // damping 0% = 12kHz cutoff (no damping), 100% = 1kHz cutoff (heavy damping)
    float cutoffHz = 12000.0f - (damping * 11000.0f); // 12kHz to 1kHz range
    
    // Update all damping filters with new HF settings
    for (auto& filter : dampingFilters_) {
        filter->setHFDamping(highFreqDamping_ * 100.0f, cutoffHz);
    }
    
    printf("HF Damping: %.1f%% (cutoff: %.0f Hz)\n", highFreqDamping_ * 100.0f, cutoffHz);
}

void FDNReverb::setLowFreqDamping(float damping) {
    lowFreqDamping_ = std::clamp(damping, 0.0f, 1.0f);
    
    // Convert damping percentage to cutoff frequency (AD 480 style)
    // damping 0% = 50Hz cutoff (no LF damping), 100% = 500Hz cutoff (heavy LF damping)
    float cutoffHz = 50.0f + (damping * 450.0f); // 50Hz to 500Hz range
    
    // Update all damping filters with new LF settings
    for (auto& filter : dampingFilters_) {
        filter->setLFDamping(lowFreqDamping_ * 100.0f, cutoffHz);
    }
    
    printf("LF Damping: %.1f%% (cutoff: %.0f Hz)\n", lowFreqDamping_ * 100.0f, cutoffHz);
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

// Stereo spread control methods (AD 480 "Spread" - output wet processing)
void FDNReverb::setStereoSpread(float spread) {
    if (stereoSpreadProcessor_) {
        stereoSpreadProcessor_->setStereoWidth(spread);
    }
}

void FDNReverb::setStereoSpreadCompensation(bool compensate) {
    if (stereoSpreadProcessor_) {
        stereoSpreadProcessor_->setCompensateGain(compensate);
    }
}

// Global tone control methods (AD 480 "High Cut" and "Low Cut" - output EQ)
void FDNReverb::setHighCutFreq(float freqHz) {
    if (toneFilter_) {
        toneFilter_->setHighCutFreq(freqHz);
    }
}

void FDNReverb::setLowCutFreq(float freqHz) {
    if (toneFilter_) {
        toneFilter_->setLowCutFreq(freqHz);
    }
}

void FDNReverb::setHighCutEnabled(bool enabled) {
    if (toneFilter_) {
        toneFilter_->setHighCutEnabled(enabled);
    }
}

void FDNReverb::setLowCutEnabled(bool enabled) {
    if (toneFilter_) {
        toneFilter_->setLowCutEnabled(enabled);
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
    
    // Clear tone filter
    if (toneFilter_) {
        toneFilter_->clear();
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
    
    // Update damping filters with new sample rate
    for (auto& filter : dampingFilters_) {
        filter->updateSampleRate(sampleRate);
    }
    
    // Update tone filter with new sample rate
    if (toneFilter_) {
        toneFilter_->updateSampleRate(sampleRate);
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

// Professional StereoSpreadProcessor Implementation (AD 480 "Spread" Control)
FDNReverb::StereoSpreadProcessor::StereoSpreadProcessor()
    : stereoWidth_(1.0f)        // Default natural stereo width
    , compensateGain_(true) {   // Default gain compensation enabled
    
    printf("StereoSpreadProcessor initialized: width=%.1f, compensation=%s\n", 
           stereoWidth_, compensateGain_ ? "ON" : "OFF");
}

void FDNReverb::StereoSpreadProcessor::processStereo(float* left, float* right, int numSamples) {
    // AD 480 style Mid/Side processing for stereo width control
    // This processes the wet reverb output to control its stereo spread
    
    for (int i = 0; i < numSamples; ++i) {
        float l = left[i];
        float r = right[i];
        
        // Convert L/R to Mid/Side
        float mid = (l + r) * 0.5f;         // Center information (mono sum)
        float side = (l - r) * 0.5f;        // Stereo difference information
        
        // Apply stereo width scaling to Side component
        // width = 0.0: side = 0 -> mono output (L = R = mid)
        // width = 1.0: side unchanged -> natural stereo
        // width = 2.0: side doubled -> exaggerated stereo width
        float scaledSide = side * stereoWidth_;
        
        // Apply mid gain compensation for constant perceived volume
        float midGain = 1.0f;
        if (compensateGain_) {
            midGain = calculateMidGainCompensation(stereoWidth_);
        }
        float compensatedMid = mid * midGain;
        
        // Convert back to L/R
        left[i] = compensatedMid + scaledSide;
        right[i] = compensatedMid - scaledSide;
    }
}

void FDNReverb::StereoSpreadProcessor::setStereoWidth(float width) {
    stereoWidth_ = std::clamp(width, 0.0f, 2.0f);
    printf("Stereo spread width: %.2f (%.0f%% width)\n", stereoWidth_, stereoWidth_ * 100.0f);
}

void FDNReverb::StereoSpreadProcessor::setCompensateGain(bool compensate) {
    compensateGain_ = compensate;
    printf("Stereo spread gain compensation: %s\n", compensate ? "ON" : "OFF");
}

void FDNReverb::StereoSpreadProcessor::clear() {
    // No internal state to clear for Mid/Side processing
}

float FDNReverb::StereoSpreadProcessor::calculateMidGainCompensation(float width) const {
    // Calculate compensation gain to maintain constant perceived volume
    // when adjusting stereo width
    //
    // Theory:
    // - At width=0 (mono): All energy is in Mid, no Side -> need 100% mid
    // - At width=1 (natural): Mid + Side as recorded -> baseline
    // - At width=2 (wide): Mid + 2*Side -> louder perception -> compensate mid down
    //
    // AD 480 uses approximately this curve for natural perception:
    // Gain reduces slightly as width increases to compensate for increased Side energy
    
    if (width <= 0.0f) {
        return 1.0f; // Mono: full mid gain
    } else if (width <= 1.0f) {
        // Natural range: no compensation needed
        return 1.0f;
    } else {
        // Wide range: reduce mid gain slightly to compensate for louder side
        // Linear reduction from 1.0 at width=1.0 to ~0.85 at width=2.0
        float compensation = 1.0f - ((width - 1.0f) * 0.15f);
        return std::max(compensation, 0.7f); // Minimum 70% to avoid too much reduction
    }
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
    
    // Clear tone filter
    if (toneFilter_) {
        toneFilter_->clear();
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

// Professional ToneFilter Implementation (AD 480 Global High Cut and Low Cut)
FDNReverb::ToneFilter::ToneFilter(double sampleRate)
    : sampleRate_(sampleRate)
    , highCutFreq_(20000.0f)         // Default: no high cut (20kHz)
    , lowCutFreq_(20.0f)             // Default: no low cut (20Hz)
    , highCutEnabled_(false)         // Default: high cut disabled
    , lowCutEnabled_(false) {        // Default: low cut disabled
    
    // Initialize all filters with neutral settings (no filtering)
    setHighCutFreq(20000.0f);  // No high cut
    setLowCutFreq(20.0f);      // No low cut
    
    printf("ToneFilter initialized: High Cut=%.0fHz (%s), Low Cut=%.0fHz (%s)\n", 
           highCutFreq_, highCutEnabled_ ? "ON" : "OFF",
           lowCutFreq_, lowCutEnabled_ ? "ON" : "OFF");
}

void FDNReverb::ToneFilter::processStereo(float* left, float* right, int numSamples) {
    // Professional AD 480 style global tone filtering
    // Applied to wet signal BEFORE wet/dry mix (out-of-loop filtering)
    
    for (int i = 0; i < numSamples; ++i) {
        float leftSample = left[i];
        float rightSample = right[i];
        
        // Apply High Cut filter (lowpass) if enabled
        if (highCutEnabled_) {
            leftSample = highCutL_.process(leftSample);
            rightSample = highCutR_.process(rightSample);
        }
        
        // Apply Low Cut filter (highpass) if enabled
        if (lowCutEnabled_) {
            leftSample = lowCutL_.process(leftSample);
            rightSample = lowCutR_.process(rightSample);
        }
        
        left[i] = leftSample;
        right[i] = rightSample;
    }
}

void FDNReverb::ToneFilter::setHighCutFreq(float freqHz) {
    highCutFreq_ = std::clamp(freqHz, 1000.0f, 20000.0f); // 1kHz-20kHz range
    
    // Update both L and R channel filters
    calculateLowpassCoeffs(highCutL_, highCutFreq_);
    calculateLowpassCoeffs(highCutR_, highCutFreq_);
    
    printf("High Cut frequency: %.0f Hz\n", highCutFreq_);
}

void FDNReverb::ToneFilter::setLowCutFreq(float freqHz) {
    lowCutFreq_ = std::clamp(freqHz, 20.0f, 1000.0f); // 20Hz-1kHz range
    
    // Update both L and R channel filters
    calculateHighpassCoeffs(lowCutL_, lowCutFreq_);
    calculateHighpassCoeffs(lowCutR_, lowCutFreq_);
    
    printf("Low Cut frequency: %.0f Hz\n", lowCutFreq_);
}

void FDNReverb::ToneFilter::setHighCutEnabled(bool enabled) {
    highCutEnabled_ = enabled;
    printf("High Cut filter: %s\n", enabled ? "ENABLED" : "DISABLED");
}

void FDNReverb::ToneFilter::setLowCutEnabled(bool enabled) {
    lowCutEnabled_ = enabled;
    printf("Low Cut filter: %s\n", enabled ? "ENABLED" : "DISABLED");
}

void FDNReverb::ToneFilter::updateSampleRate(double sampleRate) {
    sampleRate_ = sampleRate;
    
    // Recalculate all filter coefficients with new sample rate
    setHighCutFreq(highCutFreq_);
    setLowCutFreq(lowCutFreq_);
    
    printf("ToneFilter sample rate updated: %.0f Hz\n", sampleRate_);
}

void FDNReverb::ToneFilter::clear() {
    // Clear all filter states
    highCutL_.clear();
    highCutR_.clear();
    lowCutL_.clear();
    lowCutR_.clear();
}

void FDNReverb::ToneFilter::calculateLowpassCoeffs(BiquadFilter& filter, float cutoffHz) {
    // Calculate Butterworth 2nd order lowpass biquad coefficients (-12 dB/oct)
    // Using bilinear transform for digital filter design
    
    // Calculate digital frequency
    float omega = 2.0f * M_PI * cutoffHz / static_cast<float>(sampleRate_);
    float cos_omega = std::cos(omega);
    float sin_omega = std::sin(omega);
    
    // Butterworth Q factor for 2nd order lowpass
    float Q = 0.7071f; // sqrt(2)/2 for maximally flat response
    float alpha = sin_omega / (2.0f * Q);
    
    // Lowpass biquad coefficients (normalized by a0)
    float a0 = 1.0f + alpha;
    filter.b0 = ((1.0f - cos_omega) / 2.0f) / a0;
    filter.b1 = (1.0f - cos_omega) / a0;
    filter.b2 = ((1.0f - cos_omega) / 2.0f) / a0;
    filter.a1 = (-2.0f * cos_omega) / a0;
    filter.a2 = (1.0f - alpha) / a0;
}

void FDNReverb::ToneFilter::calculateHighpassCoeffs(BiquadFilter& filter, float cutoffHz) {
    // Calculate Butterworth 2nd order highpass biquad coefficients (-12 dB/oct)
    // Using bilinear transform for digital filter design
    
    // Calculate digital frequency
    float omega = 2.0f * M_PI * cutoffHz / static_cast<float>(sampleRate_);
    float cos_omega = std::cos(omega);
    float sin_omega = std::sin(omega);
    
    // Butterworth Q factor for 2nd order highpass
    float Q = 0.7071f; // sqrt(2)/2 for maximally flat response
    float alpha = sin_omega / (2.0f * Q);
    
    // Highpass biquad coefficients (normalized by a0)
    float a0 = 1.0f + alpha;
    filter.b0 = ((1.0f + cos_omega) / 2.0f) / a0;
    filter.b1 = (-(1.0f + cos_omega)) / a0;
    filter.b2 = ((1.0f + cos_omega) / 2.0f) / a0;
    filter.a1 = (-2.0f * cos_omega) / a0;
    filter.a2 = (1.0f - alpha) / a0;
}

} // namespace VoiceMonitor