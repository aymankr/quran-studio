#pragma once

#include <cstdint>
#include <cmath>

#ifdef __ARM_NEON__
#include <arm_neon.h>
#endif

#ifdef __APPLE__
#include <Accelerate/Accelerate.h>
#endif

namespace Reverb {
namespace ARM64 {

/**
 * @brief ARM64/NEON optimized audio processing functions
 * 
 * These functions are specifically optimized for iOS devices using ARM64 architecture
 * with NEON SIMD instructions. Fallback implementations are provided for other platforms.
 * 
 * Key optimizations:
 * - NEON intrinsics for vectorized operations
 * - vDSP integration for hardware acceleration
 * - Memory-aligned processing
 * - Denormal prevention for battery efficiency
 */

// Compile-time feature detection
constexpr bool hasNEON() {
#ifdef __ARM_NEON__
    return true;
#else
    return false;
#endif
}

constexpr bool hasvDSP() {
#ifdef __APPLE__
    return true;
#else
    return false;
#endif
}

// Memory alignment for optimal NEON performance
constexpr size_t NEON_ALIGNMENT = 16;
constexpr size_t VDSP_ALIGNMENT = 16;

/**
 * @brief NEON-optimized vector mix operation
 * 
 * Performs: output[i] = input1[i] * gain1 + input2[i] * gain2
 * Processes 4 floats at once using NEON SIMD
 * 
 * @param input1 First input buffer (must be 16-byte aligned)
 * @param input2 Second input buffer (must be 16-byte aligned)  
 * @param output Output buffer (must be 16-byte aligned)
 * @param gain1 Gain for first input
 * @param gain2 Gain for second input
 * @param numSamples Number of samples (must be multiple of 4)
 */
inline void vectorMix_NEON(const float* __restrict input1,
                          const float* __restrict input2,
                          float* __restrict output,
                          float gain1,
                          float gain2,
                          size_t numSamples) {
#ifdef __ARM_NEON__
    // Load gains into NEON registers
    const float32x4_t gain1_vec = vdupq_n_f32(gain1);
    const float32x4_t gain2_vec = vdupq_n_f32(gain2);
    
    const size_t numChunks = numSamples / 4;
    const size_t remainder = numSamples % 4;
    
    // Process 4 samples at once
    for (size_t i = 0; i < numChunks; ++i) {
        const size_t idx = i * 4;
        
        // Load 4 samples from each input
        const float32x4_t in1 = vld1q_f32(&input1[idx]);
        const float32x4_t in2 = vld1q_f32(&input2[idx]);
        
        // Multiply by gains
        const float32x4_t scaled1 = vmulq_f32(in1, gain1_vec);
        const float32x4_t scaled2 = vmulq_f32(in2, gain2_vec);
        
        // Add and store
        const float32x4_t result = vaddq_f32(scaled1, scaled2);
        vst1q_f32(&output[idx], result);
    }
    
    // Handle remaining samples
    for (size_t i = numChunks * 4; i < numSamples; ++i) {
        output[i] = input1[i] * gain1 + input2[i] * gain2;
    }
#else
    // Fallback implementation
    for (size_t i = 0; i < numSamples; ++i) {
        output[i] = input1[i] * gain1 + input2[i] * gain2;
    }
#endif
}

/**
 * @brief NEON-optimized delay line processing with interpolation
 * 
 * Performs fractional delay with linear interpolation using NEON SIMD
 * Critical for reverb delay lines with modulation
 * 
 * @param delayBuffer Circular delay buffer
 * @param readIndex Fractional read position
 * @param bufferSize Size of delay buffer (power of 2)
 * @param numSamples Number of samples to process
 * @param output Output buffer
 */
inline void fractionalDelay_NEON(const float* __restrict delayBuffer,
                                float readIndex,
                                size_t bufferSize,
                                size_t numSamples,
                                float* __restrict output) {
#ifdef __ARM_NEON__
    const uint32_t bufferMask = static_cast<uint32_t>(bufferSize - 1);
    
    for (size_t i = 0; i < numSamples; ++i) {
        const float currentIndex = readIndex + static_cast<float>(i);
        
        // Integer and fractional parts
        const int32_t idx0 = static_cast<int32_t>(currentIndex);
        const int32_t idx1 = (idx0 + 1) & bufferMask;
        const float frac = currentIndex - static_cast<float>(idx0);
        
        // Load samples for interpolation
        const float sample0 = delayBuffer[idx0 & bufferMask];
        const float sample1 = delayBuffer[idx1];
        
        // Linear interpolation using NEON
        const float32x2_t samples = {sample0, sample1};
        const float32x2_t weights = {1.0f - frac, frac};
        const float32x2_t weighted = vmul_f32(samples, weights);
        
        // Sum the weighted samples
        output[i] = vget_lane_f32(vpadd_f32(weighted, weighted), 0);
    }
#else
    // Fallback implementation
    const uint32_t bufferMask = static_cast<uint32_t>(bufferSize - 1);
    
    for (size_t i = 0; i < numSamples; ++i) {
        const float currentIndex = readIndex + static_cast<float>(i);
        const int32_t idx0 = static_cast<int32_t>(currentIndex);
        const int32_t idx1 = (idx0 + 1) & bufferMask;
        const float frac = currentIndex - static_cast<float>(idx0);
        
        const float sample0 = delayBuffer[idx0 & bufferMask];
        const float sample1 = delayBuffer[idx1];
        
        output[i] = sample0 * (1.0f - frac) + sample1 * frac;
    }
#endif
}

/**
 * @brief NEON-optimized all-pass filter processing
 * 
 * Processes all-pass filter chain for reverb diffusion
 * Uses NEON for vectorized multiply-accumulate operations
 * 
 * @param input Input samples
 * @param output Output samples  
 * @param delayBuffer Internal delay buffer
 * @param delayIndex Current delay index
 * @param feedback Feedback coefficient
 * @param numSamples Number of samples to process
 */
inline void allPassFilter_NEON(const float* __restrict input,
                              float* __restrict output,
                              float* __restrict delayBuffer,
                              size_t& delayIndex,
                              float feedback,
                              size_t delayLength,
                              size_t numSamples) {
#ifdef __ARM_NEON__
    const float32x4_t feedback_vec = vdupq_n_f32(feedback);
    const float32x4_t neg_feedback_vec = vdupq_n_f32(-feedback);
    
    const size_t numChunks = numSamples / 4;
    const size_t remainder = numSamples % 4;
    
    // Process 4 samples at once when possible
    for (size_t i = 0; i < numChunks; ++i) {
        const size_t idx = i * 4;
        
        // Load input samples
        const float32x4_t in = vld1q_f32(&input[idx]);
        
        // For each sample in the chunk
        for (size_t j = 0; j < 4; ++j) {
            const float inputSample = vgetq_lane_f32(in, j);
            const float delaySample = delayBuffer[delayIndex];
            
            // All-pass calculation: output = -feedback * input + delayed
            // Store: input + feedback * delayed  
            const float outputSample = delaySample + (-feedback) * inputSample;
            delayBuffer[delayIndex] = inputSample + feedback * delaySample;
            
            output[idx + j] = outputSample;
            
            delayIndex = (delayIndex + 1) % delayLength;
        }
    }
    
    // Handle remaining samples
    for (size_t i = numChunks * 4; i < numSamples; ++i) {
        const float inputSample = input[i];
        const float delaySample = delayBuffer[delayIndex];
        
        output[i] = delaySample + (-feedback) * inputSample;
        delayBuffer[delayIndex] = inputSample + feedback * delaySample;
        
        delayIndex = (delayIndex + 1) % delayLength;
    }
#else
    // Fallback implementation
    for (size_t i = 0; i < numSamples; ++i) {
        const float inputSample = input[i];
        const float delaySample = delayBuffer[delayIndex];
        
        output[i] = delaySample + (-feedback) * inputSample;
        delayBuffer[delayIndex] = inputSample + feedback * delaySample;
        
        delayIndex = (delayIndex + 1) % delayLength;
    }
#endif
}

/**
 * @brief Denormal prevention using NEON
 * 
 * Adds tiny DC offset to prevent denormals that can cause CPU spikes
 * Particularly important on iOS for battery efficiency
 * 
 * @param buffer Audio buffer to process
 * @param numSamples Number of samples
 */
inline void preventDenormals_NEON(float* __restrict buffer, size_t numSamples) {
#ifdef __ARM_NEON__
    // Very small DC offset to prevent denormals
    constexpr float DC_OFFSET = 1.0e-25f;
    const float32x4_t dc_vec = vdupq_n_f32(DC_OFFSET);
    
    const size_t numChunks = numSamples / 4;
    const size_t remainder = numSamples % 4;
    
    for (size_t i = 0; i < numChunks; ++i) {
        const size_t idx = i * 4;
        
        float32x4_t samples = vld1q_f32(&buffer[idx]);
        samples = vaddq_f32(samples, dc_vec);
        vst1q_f32(&buffer[idx], samples);
    }
    
    // Handle remaining samples
    for (size_t i = numChunks * 4; i < numSamples; ++i) {
        buffer[i] += DC_OFFSET;
    }
#else
    // Fallback implementation
    constexpr float DC_OFFSET = 1.0e-25f;
    for (size_t i = 0; i < numSamples; ++i) {
        buffer[i] += DC_OFFSET;
    }
#endif
}

/**
 * @brief NEON-optimized stereo width processing
 * 
 * Applies stereo width effect using NEON SIMD
 * Used in reverb output stage for spatial enhancement
 * 
 * @param left Left channel buffer
 * @param right Right channel buffer
 * @param width Width coefficient (0.0 = mono, 1.0 = normal, >1.0 = wider)
 * @param numSamples Number of samples to process
 */
inline void stereoWidth_NEON(float* __restrict left,
                            float* __restrict right,
                            float width,
                            size_t numSamples) {
#ifdef __ARM_NEON__
    const float32x4_t width_vec = vdupq_n_f32(width);
    const float32x4_t half_vec = vdupq_n_f32(0.5f);
    
    const size_t numChunks = numSamples / 4;
    
    for (size_t i = 0; i < numChunks; ++i) {
        const size_t idx = i * 4;
        
        // Load stereo samples
        const float32x4_t L = vld1q_f32(&left[idx]);
        const float32x4_t R = vld1q_f32(&right[idx]);
        
        // Calculate mid and side
        const float32x4_t mid = vmulq_f32(vaddq_f32(L, R), half_vec);
        const float32x4_t side = vmulq_f32(vsubq_f32(L, R), half_vec);
        
        // Apply width to side signal
        const float32x4_t wideSide = vmulq_f32(side, width_vec);
        
        // Reconstruct stereo
        const float32x4_t newL = vaddq_f32(mid, wideSide);
        const float32x4_t newR = vsubq_f32(mid, wideSide);
        
        // Store results
        vst1q_f32(&left[idx], newL);
        vst1q_f32(&right[idx], newR);
    }
    
    // Handle remaining samples
    for (size_t i = numChunks * 4; i < numSamples; ++i) {
        const float L = left[i];
        const float R = right[i];
        
        const float mid = 0.5f * (L + R);
        const float side = 0.5f * (L - R) * width;
        
        left[i] = mid + side;
        right[i] = mid - side;
    }
#else
    // Fallback implementation
    for (size_t i = 0; i < numSamples; ++i) {
        const float L = left[i];
        const float R = right[i];
        
        const float mid = 0.5f * (L + R);
        const float side = 0.5f * (L - R) * width;
        
        left[i] = mid + side;
        right[i] = mid - side;
    }
#endif
}

/**
 * @brief Memory-aligned buffer allocation for NEON
 * 
 * Allocates memory aligned to NEON requirements (16-byte boundary)
 * Essential for optimal SIMD performance
 * 
 * @param numElements Number of float elements
 * @return Aligned pointer or nullptr on failure
 */
inline float* allocateAlignedBuffer(size_t numElements) {
    const size_t sizeBytes = numElements * sizeof(float);
    const size_t alignedSize = (sizeBytes + NEON_ALIGNMENT - 1) & ~(NEON_ALIGNMENT - 1);
    
#ifdef __APPLE__
    return static_cast<float*>(aligned_alloc(NEON_ALIGNMENT, alignedSize));
#else
    return static_cast<float*>(std::aligned_alloc(NEON_ALIGNMENT, alignedSize));
#endif
}

/**
 * @brief Free aligned buffer
 * 
 * @param buffer Pointer to aligned buffer
 */
inline void freeAlignedBuffer(float* buffer) {
    if (buffer) {
        free(buffer);
    }
}

/**
 * @brief Check if pointer is properly aligned for NEON
 * 
 * @param ptr Pointer to check
 * @return true if aligned to 16-byte boundary
 */
inline bool isAligned(const void* ptr) {
    return (reinterpret_cast<uintptr_t>(ptr) & (NEON_ALIGNMENT - 1)) == 0;
}

/**
 * @brief ARM64 CPU detection and capability reporting
 * 
 * @return String describing ARM64 capabilities
 */
inline const char* getARM64Capabilities() {
#ifdef __ARM_NEON__
    return "ARM64 with NEON SIMD support";
#elif defined(__ARM_ARCH)
    return "ARM64 without NEON";
#else
    return "Not ARM64 architecture";
#endif
}

/**
 * @brief Performance counter for profiling critical sections
 * 
 * High-resolution timing for Instruments integration
 */
class PerformanceCounter {
private:
    uint64_t startTime_;
    uint64_t endTime_;
    
public:
    inline void start() {
#ifdef __APPLE__
        startTime_ = mach_absolute_time();
#else
        startTime_ = 0; // Fallback
#endif
    }
    
    inline void stop() {
#ifdef __APPLE__
        endTime_ = mach_absolute_time();
#else
        endTime_ = 0; // Fallback
#endif
    }
    
    inline double getElapsedNanoseconds() const {
#ifdef __APPLE__
        static mach_timebase_info_data_t timebaseInfo;
        if (timebaseInfo.denom == 0) {
            mach_timebase_info(&timebaseInfo);
        }
        
        const uint64_t elapsed = endTime_ - startTime_;
        return static_cast<double>(elapsed * timebaseInfo.numer) / timebaseInfo.denom;
#else
        return 0.0; // Fallback
#endif
    }
    
    inline double getElapsedMicroseconds() const {
        return getElapsedNanoseconds() / 1000.0;
    }
};

} // namespace ARM64
} // namespace Reverb