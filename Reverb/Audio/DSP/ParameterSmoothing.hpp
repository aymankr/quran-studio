#pragma once

#include <atomic>
#include <cmath>
#include <algorithm>

#ifdef __ARM_NEON__
#include <arm_neon.h>
#endif

namespace Reverb {
namespace DSP {

/**
 * @brief High-performance parameter smoothing for iOS audio thread
 * 
 * Implements temporal interpolation in DSP to prevent zipper noise and audio thread overload.
 * Optimized for ARM64 with NEON SIMD when available. Critical for real-time parameter changes
 * from iOS UI sliders without causing audible artifacts or thread contention.
 * 
 * Key features:
 * - Exponential smoothing with configurable time constants
 * - NEON-optimized block processing  
 * - Thread-safe atomic parameter updates
 * - Multiple smoothing algorithms (linear, exponential, S-curve)
 * - Zipper noise prevention for critical parameters like wetMix
 */

/**
 * @brief Smoothing algorithm types
 */
enum class SmoothingType {
    Linear,         // Linear interpolation - fastest, acceptable for most parameters
    Exponential,    // Exponential smoothing - best for audio parameters
    SCurve,         // S-curve smoothing - most natural for user-controlled parameters
    Logarithmic     // Logarithmic smoothing - good for gain parameters
};

/**
 * @brief Single parameter smoother with configurable algorithm
 */
class ParameterSmoother {
private:
    float currentValue_;
    std::atomic<float> targetValue_;
    float smoothingCoefficient_;
    SmoothingType smoothingType_;
    float sampleRate_;
    bool isSmoothing_;
    
    // For linear smoothing
    float linearStep_;
    int remainingSteps_;
    
    // For S-curve smoothing
    float sCurvePhase_;
    float sCurveDelta_;
    
public:
    /**
     * @brief Initialize parameter smoother
     * 
     * @param initialValue Starting parameter value
     * @param smoothingTimeMs Smoothing time in milliseconds
     * @param sampleRate Audio sample rate
     * @param type Smoothing algorithm type
     */
    ParameterSmoother(float initialValue = 0.0f,
                     float smoothingTimeMs = 50.0f,
                     float sampleRate = 48000.0f,
                     SmoothingType type = SmoothingType::Exponential)
        : currentValue_(initialValue)
        , targetValue_(initialValue)
        , smoothingType_(type)
        , sampleRate_(sampleRate)
        , isSmoothing_(false)
        , linearStep_(0.0f)
        , remainingSteps_(0)
        , sCurvePhase_(0.0f)
        , sCurveDelta_(0.0f) {
        
        setSmoothingTime(smoothingTimeMs);
    }
    
    /**
     * @brief Set smoothing time constant
     * 
     * @param timeMs Smoothing time in milliseconds
     */
    void setSmoothingTime(float timeMs) {
        const float timeSamples = (timeMs / 1000.0f) * sampleRate_;
        
        switch (smoothingType_) {
        case SmoothingType::Exponential:
            // Exponential smoothing coefficient: exp(-1 / (time * sampleRate))
            smoothingCoefficient_ = std::exp(-1.0f / timeSamples);
            break;
            
        case SmoothingType::Linear:
            // Linear step size for given time
            linearStep_ = 1.0f / timeSamples;
            break;
            
        case SmoothingType::SCurve:
        case SmoothingType::Logarithmic:
            // S-curve uses exponential coefficient as base
            smoothingCoefficient_ = std::exp(-1.0f / timeSamples);
            break;
        }
    }
    
    /**
     * @brief Set target value (thread-safe, called from UI thread)
     * 
     * @param value New target value
     */
    void setTarget(float value) {
        const float previousTarget = targetValue_.exchange(value);
        
        // Start smoothing if value actually changed
        if (std::abs(value - previousTarget) > 1e-6f) {
            isSmoothing_ = true;
            
            // Initialize algorithm-specific state
            switch (smoothingType_) {
            case SmoothingType::Linear:
                remainingSteps_ = static_cast<int>(1.0f / linearStep_);
                break;
                
            case SmoothingType::SCurve:
                sCurvePhase_ = 0.0f;
                sCurveDelta_ = 1.0f / (sampleRate_ * 0.050f); // 50ms S-curve
                break;
                
            default:
                break;
            }
        }
    }
    
    /**
     * @brief Get current smoothed value (called from audio thread)
     * 
     * @return Current smoothed value
     */
    float getCurrentValue() {
        if (!isSmoothing_) {
            return currentValue_;
        }
        
        const float target = targetValue_.load();
        
        switch (smoothingType_) {
        case SmoothingType::Exponential:
            currentValue_ = currentValue_ * smoothingCoefficient_ + target * (1.0f - smoothingCoefficient_);
            break;
            
        case SmoothingType::Linear:
            if (remainingSteps_ > 0) {
                const float diff = target - currentValue_;
                currentValue_ += diff * linearStep_;
                remainingSteps_--;
            } else {
                currentValue_ = target;
            }
            break;
            
        case SmoothingType::SCurve:
            if (sCurvePhase_ < 1.0f) {
                // S-curve using smoothstep function: 3t² - 2t³
                const float t = sCurvePhase_;
                const float smoothStep = t * t * (3.0f - 2.0f * t);
                currentValue_ = currentValue_ + (target - currentValue_) * smoothStep * sCurveDelta_;
                sCurvePhase_ += sCurveDelta_;
            } else {
                currentValue_ = target;
            }
            break;
            
        case SmoothingType::Logarithmic:
            // Logarithmic smoothing for gain parameters
            if (target > 0.0f && currentValue_ > 0.0f) {
                const float logCurrent = std::log(currentValue_);
                const float logTarget = std::log(target);
                const float logSmoothed = logCurrent * smoothingCoefficient_ + logTarget * (1.0f - smoothingCoefficient_);
                currentValue_ = std::exp(logSmoothed);
            } else {
                // Fallback to exponential for zero/negative values
                currentValue_ = currentValue_ * smoothingCoefficient_ + target * (1.0f - smoothingCoefficient_);
            }
            break;
        }
        
        // Check if we're close enough to stop smoothing
        if (std::abs(currentValue_ - target) < 1e-5f) {
            currentValue_ = target;
            isSmoothing_ = false;
        }
        
        return currentValue_;
    }
    
    /**
     * @brief Process a block of samples with smoothing (NEON optimized)
     * 
     * @param outputBuffer Buffer to write smoothed values
     * @param numSamples Number of samples to process
     */
    void processBlock(float* outputBuffer, int numSamples) {
#ifdef __ARM_NEON__
        processBlockNEON(outputBuffer, numSamples);
#else
        processBlockScalar(outputBuffer, numSamples);
#endif
    }
    
    /**
     * @brief Check if parameter is currently smoothing
     */
    bool isActive() const {
        return isSmoothing_;
    }
    
    /**
     * @brief Get target value
     */
    float getTarget() const {
        return targetValue_.load();
    }
    
    /**
     * @brief Set immediate value without smoothing
     */
    void setImmediate(float value) {
        currentValue_ = value;
        targetValue_.store(value);
        isSmoothing_ = false;
    }

private:
    
#ifdef __ARM_NEON__
    void processBlockNEON(float* outputBuffer, int numSamples) {
        if (!isSmoothing_) {
            // Fill buffer with constant value using NEON
            const float32x4_t value_vec = vdupq_n_f32(currentValue_);
            const int numChunks = numSamples / 4;
            
            for (int i = 0; i < numChunks; ++i) {
                vst1q_f32(&outputBuffer[i * 4], value_vec);
            }
            
            // Handle remaining samples
            for (int i = numChunks * 4; i < numSamples; ++i) {
                outputBuffer[i] = currentValue_;
            }
            return;
        }
        
        // Process smoothing sample by sample (could be further optimized with vectorized smoothing)
        for (int i = 0; i < numSamples; ++i) {
            outputBuffer[i] = getCurrentValue();
        }
    }
#endif
    
    void processBlockScalar(float* outputBuffer, int numSamples) {
        if (!isSmoothing_) {
            // Fill buffer with constant value
            std::fill(outputBuffer, outputBuffer + numSamples, currentValue_);
            return;
        }
        
        // Process smoothing sample by sample
        for (int i = 0; i < numSamples; ++i) {
            outputBuffer[i] = getCurrentValue();
        }
    }
};

/**
 * @brief Multi-parameter smoother for complete reverb parameter set
 * 
 * Manages all reverb parameters with optimized smoothing configurations
 * for each parameter type to prevent zipper noise and optimize CPU usage.
 */
class ReverbParameterSmoother {
public:
    // Parameter indices for fast access
    enum ParameterIndex {
        WetDryMix = 0,      // Most critical - needs fastest, smoothest interpolation
        InputGain = 1,      // Gain parameters - logarithmic smoothing
        OutputGain = 2,     // Gain parameters - logarithmic smoothing  
        ReverbDecay = 3,    // Slower changes acceptable
        ReverbSize = 4,     // Very slow changes
        DampingHF = 5,      // Moderate smoothing
        DampingLF = 6,      // Moderate smoothing
        NUM_PARAMETERS = 7
    };
    
private:
    ParameterSmoother smoothers_[NUM_PARAMETERS];
    float smoothedValues_[NUM_PARAMETERS];
    
public:
    /**
     * @brief Initialize all parameter smoothers with optimized settings
     * 
     * @param sampleRate Audio sample rate
     */
    ReverbParameterSmoother(float sampleRate = 48000.0f) {
        // Configure each parameter with optimal smoothing settings
        
        // WetDryMix - most critical for zipper prevention
        smoothers_[WetDryMix] = ParameterSmoother(0.5f, 30.0f, sampleRate, SmoothingType::SCurve);
        
        // Gain parameters - logarithmic smoothing for natural feel
        smoothers_[InputGain] = ParameterSmoother(1.0f, 40.0f, sampleRate, SmoothingType::Logarithmic);
        smoothers_[OutputGain] = ParameterSmoother(1.0f, 40.0f, sampleRate, SmoothingType::Logarithmic);
        
        // Reverb parameters - can be slower as they're less sensitive to zipper
        smoothers_[ReverbDecay] = ParameterSmoother(0.7f, 200.0f, sampleRate, SmoothingType::Exponential);
        smoothers_[ReverbSize] = ParameterSmoother(0.5f, 300.0f, sampleRate, SmoothingType::Exponential);
        
        // Damping parameters - moderate smoothing
        smoothers_[DampingHF] = ParameterSmoother(0.3f, 100.0f, sampleRate, SmoothingType::Exponential);
        smoothers_[DampingLF] = ParameterSmoother(0.1f, 100.0f, sampleRate, SmoothingType::Exponential);
        
        // Initialize smoothed values array
        for (int i = 0; i < NUM_PARAMETERS; ++i) {
            smoothedValues_[i] = smoothers_[i].getCurrentValue();
        }
    }
    
    /**
     * @brief Set parameter target value (thread-safe)
     * 
     * @param paramIndex Parameter index
     * @param value New target value
     */
    void setParameter(ParameterIndex paramIndex, float value) {
        if (paramIndex >= 0 && paramIndex < NUM_PARAMETERS) {
            smoothers_[paramIndex].setTarget(value);
        }
    }
    
    /**
     * @brief Update all smoothed parameter values (called once per audio buffer)
     * 
     * Call this once per audio buffer to update all smoothed values efficiently.
     */
    void updateSmoothedValues() {
        for (int i = 0; i < NUM_PARAMETERS; ++i) {
            smoothedValues_[i] = smoothers_[i].getCurrentValue();
        }
    }
    
    /**
     * @brief Get smoothed parameter value (fast array access)
     * 
     * @param paramIndex Parameter index
     * @return Current smoothed value
     */
    float getSmoothedValue(ParameterIndex paramIndex) const {
        if (paramIndex >= 0 && paramIndex < NUM_PARAMETERS) {
            return smoothedValues_[paramIndex];
        }
        return 0.0f;
    }
    
    /**
     * @brief Check if any parameters are currently smoothing
     */
    bool isAnyParameterSmoothing() const {
        for (int i = 0; i < NUM_PARAMETERS; ++i) {
            if (smoothers_[i].isActive()) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @brief Get smoothing activity mask (for debugging/optimization)
     * 
     * @return Bitmask indicating which parameters are currently smoothing
     */
    uint32_t getSmoothingActivityMask() const {
        uint32_t mask = 0;
        for (int i = 0; i < NUM_PARAMETERS; ++i) {
            if (smoothers_[i].isActive()) {
                mask |= (1u << i);
            }
        }
        return mask;
    }
    
    /**
     * @brief Load preset values with smooth transition
     * 
     * @param preset Preset to load
     */
    void loadPreset(ReverbPreset preset) {
        switch (preset) {
        case ReverbPreset::Clean:
            setParameter(WetDryMix, 0.2f);
            setParameter(ReverbDecay, 0.3f);
            setParameter(ReverbSize, 0.2f);
            setParameter(DampingHF, 0.7f);
            setParameter(DampingLF, 0.1f);
            break;
            
        case ReverbPreset::VocalBooth:
            setParameter(WetDryMix, 0.3f);
            setParameter(ReverbDecay, 0.4f);
            setParameter(ReverbSize, 0.3f);
            setParameter(DampingHF, 0.6f);
            setParameter(DampingLF, 0.2f);
            break;
            
        case ReverbPreset::Studio:
            setParameter(WetDryMix, 0.4f);
            setParameter(ReverbDecay, 0.6f);
            setParameter(ReverbSize, 0.5f);
            setParameter(DampingHF, 0.4f);
            setParameter(DampingLF, 0.1f);
            break;
            
        case ReverbPreset::Cathedral:
            setParameter(WetDryMix, 0.6f);
            setParameter(ReverbDecay, 0.9f);
            setParameter(ReverbSize, 0.8f);
            setParameter(DampingHF, 0.2f);
            setParameter(DampingLF, 0.0f);
            break;
            
        case ReverbPreset::Custom:
            // Don't change values for custom preset
            break;
        }
    }
    
    // Convenience accessors for specific parameters
    float getWetDryMix() const { return getSmoothedValue(WetDryMix); }
    float getInputGain() const { return getSmoothedValue(InputGain); }
    float getOutputGain() const { return getSmoothedValue(OutputGain); }
    float getReverbDecay() const { return getSmoothedValue(ReverbDecay); }
    float getReverbSize() const { return getSmoothedValue(ReverbSize); }
    float getDampingHF() const { return getSmoothedValue(DampingHF); }
    float getDampingLF() const { return getSmoothedValue(DampingLF); }
};

/**
 * @brief Utility functions for parameter smoothing
 */
namespace SmoothingUtils {
    
    /**
     * @brief Calculate optimal smoothing time based on parameter type and user interaction
     * 
     * @param paramType Type of parameter
     * @param isUserControlled Whether parameter is being actively controlled by user
     * @return Optimal smoothing time in milliseconds
     */
    inline float getOptimalSmoothingTime(ReverbParameterSmoother::ParameterIndex paramType, 
                                        bool isUserControlled) {
        // Base smoothing times
        const float baseTimes[] = {
            30.0f,   // WetDryMix - critical for zipper prevention
            40.0f,   // InputGain - gain changes need care
            40.0f,   // OutputGain - gain changes need care
            200.0f,  // ReverbDecay - slower acceptable
            300.0f,  // ReverbSize - very slow acceptable
            100.0f,  // DampingHF - moderate
            100.0f   // DampingLF - moderate
        };
        
        float smoothingTime = baseTimes[paramType];
        
        // Reduce smoothing time when user is actively controlling parameter
        if (isUserControlled) {
            smoothingTime *= 0.5f; // More responsive during user interaction
        }
        
        return smoothingTime;
    }
    
    /**
     * @brief Check if parameter change would cause audible zipper noise
     * 
     * @param oldValue Previous parameter value
     * @param newValue New parameter value
     * @param paramType Type of parameter
     * @return True if smoothing is recommended
     */
    inline bool needsSmoothing(float oldValue, float newValue, 
                              ReverbParameterSmoother::ParameterIndex paramType) {
        const float diff = std::abs(newValue - oldValue);
        
        // Thresholds for different parameter types
        const float thresholds[] = {
            0.01f,   // WetDryMix - very sensitive
            0.05f,   // InputGain - moderately sensitive
            0.05f,   // OutputGain - moderately sensitive  
            0.1f,    // ReverbDecay - less sensitive
            0.1f,    // ReverbSize - less sensitive
            0.05f,   // DampingHF - moderately sensitive
            0.05f    // DampingLF - moderately sensitive
        };
        
        return diff > thresholds[paramType];
    }
}

} // namespace DSP
} // namespace Reverb