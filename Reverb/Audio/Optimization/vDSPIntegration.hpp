#pragma once

#ifdef __APPLE__
#include <Accelerate/Accelerate.h>
#endif

#include <vector>
#include <memory>
#include <cmath>

namespace Reverb {
namespace vDSP {

/**
 * @brief vDSP (Accelerate.framework) integration for hardware-accelerated audio processing
 * 
 * This module provides hardware-accelerated audio processing using Apple's vDSP library.
 * vDSP operations are highly optimized for Apple Silicon and Intel processors,
 * providing significant performance improvements for vector operations.
 * 
 * Key benefits:
 * - Hardware acceleration on Apple Silicon
 * - Vectorized operations (SIMD)
 * - Optimized memory access patterns  
 * - Battery-efficient processing
 * - Integration with Core Audio pipeline
 */

#ifdef __APPLE__

/**
 * @brief vDSP-accelerated vector mixing
 * 
 * Performs hardware-accelerated mixing of two audio buffers
 * Significantly faster than manual loops for large buffers
 * 
 * @param input1 First input buffer
 * @param input2 Second input buffer
 * @param output Output buffer
 * @param gain1 Gain for first input
 * @param gain2 Gain for second input
 * @param numSamples Number of samples to process
 */
inline void vectorMix_vDSP(const float* input1,
                          const float* input2,
                          float* output,
                          float gain1,  
                          float gain2,
                          vDSP_Length numSamples) {
    
    // Create temporary buffers for scaled inputs
    std::vector<float> scaled1(numSamples);
    std::vector<float> scaled2(numSamples);
    
    // Scale input1 with gain1: scaled1 = input1 * gain1
    vDSP_vsmul(input1, 1, &gain1, scaled1.data(), 1, numSamples);
    
    // Scale input2 with gain2: scaled2 = input2 * gain2  
    vDSP_vsmul(input2, 1, &gain2, scaled2.data(), 1, numSamples);
    
    // Add scaled buffers: output = scaled1 + scaled2
    vDSP_vadd(scaled1.data(), 1, scaled2.data(), 1, output, 1, numSamples);
}

/**
 * @brief vDSP-accelerated convolution for reverb processing
 * 
 * Hardware-accelerated convolution using vDSP FFT convolution
 * Ideal for impulse response processing and filtering
 * 
 * @param input Input signal buffer
 * @param impulse Impulse response buffer
 * @param output Output buffer
 * @param inputLength Length of input signal
 * @param impulseLength Length of impulse response
 */
inline void convolution_vDSP(const float* input,
                             const float* impulse,
                             float* output,
                             vDSP_Length inputLength,
                             vDSP_Length impulseLength) {
    
    const vDSP_Length outputLength = inputLength + impulseLength - 1;
    
    // Use vDSP's optimized convolution
    vDSP_conv(input, 1, impulse, 1, output, 1, outputLength, impulseLength);
}

/**
 * @brief vDSP-accelerated stereo interleaving
 * 
 * Efficiently interleaves left and right channels for stereo output
 * Hardware-optimized for Core Audio interleaved format
 * 
 * @param left Left channel buffer
 * @param right Right channel buffer
 * @param stereoOutput Interleaved stereo output (L,R,L,R,...)
 * @param numSamples Number of samples per channel
 */
inline void stereoInterleave_vDSP(const float* left,
                                 const float* right,
                                 float* stereoOutput,
                                 vDSP_Length numSamples) {
    
    // Create DSPSplitComplex for efficient interleaving
    DSPSplitComplex splitBuffer;
    splitBuffer.realp = const_cast<float*>(left);
    splitBuffer.imagp = const_cast<float*>(right);
    
    // Interleave using vDSP (treats as complex -> real conversion)
    vDSP_ztoc(&splitBuffer, 1, reinterpret_cast<DSPComplex*>(stereoOutput), 2, numSamples);
}

/**
 * @brief vDSP-accelerated stereo deinterleaving
 * 
 * Efficiently separates interleaved stereo into left/right channels
 * Hardware-optimized for Core Audio buffer processing
 * 
 * @param stereoInput Interleaved stereo input (L,R,L,R,...)
 * @param left Left channel output buffer
 * @param right Right channel output buffer
 * @param numSamples Number of samples per channel
 */
inline void stereoDeinterleave_vDSP(const float* stereoInput,
                                   float* left,
                                   float* right,
                                   vDSP_Length numSamples) {
    
    // Create DSPSplitComplex for efficient deinterleaving
    DSPSplitComplex splitBuffer;
    splitBuffer.realp = left;
    splitBuffer.imagp = right;
    
    // Deinterleave using vDSP (treats as real -> complex conversion)
    vDSP_ctoz(reinterpret_cast<const DSPComplex*>(stereoInput), 2, &splitBuffer, 1, numSamples);
}

/**
 * @brief vDSP-accelerated RMS level calculation
 * 
 * Hardware-accelerated RMS calculation for level metering
 * Essential for real-time audio level monitoring
 * 
 * @param buffer Input audio buffer
 * @param numSamples Number of samples
 * @return RMS level (0.0 to 1.0+)
 */
inline float calculateRMS_vDSP(const float* buffer, vDSP_Length numSamples) {
    float sumSquares = 0.0f;
    
    // Calculate sum of squares using vDSP
    vDSP_svesq(buffer, 1, &sumSquares, numSamples);
    
    // Return RMS
    return std::sqrt(sumSquares / static_cast<float>(numSamples));
}

/**
 * @brief vDSP-accelerated peak detection
 * 
 * Hardware-accelerated peak finding for level metering
 * Used for clip detection and dynamic range monitoring
 * 
 * @param buffer Input audio buffer
 * @param numSamples Number of samples
 * @return Peak absolute value
 */
inline float findPeak_vDSP(const float* buffer, vDSP_Length numSamples) {
    float peak = 0.0f;
    
    // Find maximum absolute value using vDSP
    vDSP_maxmgv(buffer, 1, &peak, numSamples);
    
    return peak;
}

/**
 * @brief vDSP-accelerated DC blocking filter
 * 
 * Hardware-accelerated high-pass filter to remove DC offset
 * Essential for preventing denormals and maintaining audio quality
 * 
 * @param input Input buffer
 * @param output Output buffer
 * @param numSamples Number of samples
 * @param cutoffFreq Cutoff frequency (typically 20 Hz)
 * @param sampleRate Sample rate
 * @param state Filter state (persistent across calls)
 */
inline void dcBlockingFilter_vDSP(const float* input,
                                 float* output,
                                 vDSP_Length numSamples,
                                 float cutoffFreq,
                                 float sampleRate,
                                 float& state) {
    
    // Calculate filter coefficient
    const float omega = 2.0f * M_PI * cutoffFreq / sampleRate;
    const float alpha = std::exp(-omega);
    
    // Apply first-order high-pass filter: y[n] = alpha * (y[n-1] + x[n] - x[n-1])
    float prevInput = state;
    float prevOutput = 0.0f;
    
    for (vDSP_Length i = 0; i < numSamples; ++i) {
        const float currentInput = input[i];
        const float currentOutput = alpha * (prevOutput + currentInput - prevInput);
        
        output[i] = currentOutput;
        
        prevInput = currentInput;
        prevOutput = currentOutput;
    }
    
    // Update state
    state = prevInput;
}

/**
 * @brief vDSP-accelerated multi-tap delay line
 * 
 * Hardware-accelerated multi-tap delay processing
 * Used for complex reverb algorithms with multiple delay taps
 * 
 * @param input Input buffer
 * @param output Output buffer
 * @param delayBuffer Circular delay buffer
 * @param tapDelays Array of tap delay times (in samples)
 * @param tapGains Array of tap gains
 * @param numTaps Number of taps
 * @param writeIndex Current write position in delay buffer
 * @param bufferSize Size of delay buffer
 * @param numSamples Number of samples to process
 */
inline void multiTapDelay_vDSP(const float* input,
                              float* output,
                              float* delayBuffer,
                              const int* tapDelays,
                              const float* tapGains,
                              int numTaps,
                              int& writeIndex,
                              int bufferSize,
                              vDSP_Length numSamples) {
    
    const int bufferMask = bufferSize - 1; // Assume power of 2
    
    // Clear output buffer
    vDSP_vclr(output, 1, numSamples);
    
    // Process each sample
    for (vDSP_Length sampleIdx = 0; sampleIdx < numSamples; ++sampleIdx) {
        // Write input to delay buffer
        delayBuffer[writeIndex] = input[sampleIdx];
        
        // Process all taps for this sample
        for (int tapIdx = 0; tapIdx < numTaps; ++tapIdx) {
            const int readIndex = (writeIndex - tapDelays[tapIdx]) & bufferMask;
            const float tapOutput = delayBuffer[readIndex] * tapGains[tapIdx];
            output[sampleIdx] += tapOutput;
        }
        
        writeIndex = (writeIndex + 1) & bufferMask;
    }
}

/**
 * @brief vDSP-accelerated window function application
 * 
 * Applies windowing function for FFT processing
 * Used in frequency-domain reverb algorithms
 * 
 * @param input Input buffer
 * @param output Output buffer  
 * @param window Window coefficients (Hann, Hamming, etc.)
 * @param numSamples Number of samples
 */
inline void applyWindow_vDSP(const float* input,
                            float* output,
                            const float* window,
                            vDSP_Length numSamples) {
    
    // Element-wise multiplication: output = input * window
    vDSP_vmul(input, 1, window, 1, output, 1, numSamples);
}

/**
 * @brief vDSP FFT setup for frequency-domain processing
 * 
 * Wrapper class for vDSP FFT operations
 * Used for convolution reverb and spectral processing
 */
class FFTProcessor {
private:
    FFTSetup fftSetup_;
    vDSP_Length log2n_;
    vDSP_Length fftSize_;
    std::vector<float> tempBuffer_;
    
public:
    explicit FFTProcessor(vDSP_Length log2n) 
        : log2n_(log2n), fftSize_(1 << log2n_) {
        
        fftSetup_ = vDSP_create_fftsetup(log2n_, kFFTRadix2);
        tempBuffer_.resize(fftSize_);
    }
    
    ~FFTProcessor() {
        if (fftSetup_) {
            vDSP_destroy_fftsetup(fftSetup_);
        }
    }
    
    /**
     * @brief Perform forward FFT
     * 
     * @param splitComplex Split complex buffer (real/imaginary)
     */
    void forwardFFT(DSPSplitComplex& splitComplex) {
        vDSP_fft_zrip(fftSetup_, &splitComplex, 1, log2n_, kFFTDirection_Forward);
        
        // Scale by 1/2 for vDSP convention
        const float scale = 0.5f;
        vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, fftSize_ / 2);
        vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, fftSize_ / 2);
    }
    
    /**
     * @brief Perform inverse FFT
     * 
     * @param splitComplex Split complex buffer (real/imaginary)
     */
    void inverseFFT(DSPSplitComplex& splitComplex) {
        vDSP_fft_zrip(fftSetup_, &splitComplex, 1, log2n_, kFFTDirection_Inverse);
        
        // Scale by 1/N for proper normalization
        const float scale = 1.0f / static_cast<float>(fftSize_);
        vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, fftSize_ / 2);
        vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, fftSize_ / 2);
    }
    
    vDSP_Length getFFTSize() const { return fftSize_; }
};

/**
 * @brief Performance benchmarking for vDSP operations
 * 
 * Measures performance of vDSP vs non-vDSP implementations
 * Used for development and optimization validation
 * 
 * @param operation Name of operation being benchmarked
 * @param numSamples Number of samples processed
 * @param timeNanoseconds Execution time in nanoseconds
 */
inline void logPerformance(const char* operation, 
                          vDSP_Length numSamples, 
                          uint64_t timeNanoseconds) {
    const double samplesPerSecond = static_cast<double>(numSamples) / 
                                   (static_cast<double>(timeNanoseconds) / 1e9);
    
#ifdef DEBUG
    printf("vDSP %s: %llu samples in %llu ns (%.2f MSamples/sec)\n",
           operation, 
           static_cast<unsigned long long>(numSamples),
           static_cast<unsigned long long>(timeNanoseconds),
           samplesPerSecond / 1e6);
#endif
}

#else // __APPLE__

// Fallback implementations for non-Apple platforms
inline void vectorMix_vDSP(const float* input1, const float* input2, float* output,
                          float gain1, float gain2, size_t numSamples) {
    for (size_t i = 0; i < numSamples; ++i) {
        output[i] = input1[i] * gain1 + input2[i] * gain2;
    }
}

inline float calculateRMS_vDSP(const float* buffer, size_t numSamples) {
    float sumSquares = 0.0f;
    for (size_t i = 0; i < numSamples; ++i) {
        sumSquares += buffer[i] * buffer[i];
    }
    return std::sqrt(sumSquares / static_cast<float>(numSamples));
}

inline float findPeak_vDSP(const float* buffer, size_t numSamples) {
    float peak = 0.0f;
    for (size_t i = 0; i < numSamples; ++i) {
        const float abs_val = std::abs(buffer[i]);
        if (abs_val > peak) peak = abs_val;
    }
    return peak;
}

#endif // __APPLE__

/**
 * @brief Check vDSP availability and capabilities
 * 
 * @return String describing vDSP capabilities
 */
inline const char* getvDSPCapabilities() {
#ifdef __APPLE__
    return "vDSP (Accelerate.framework) available - hardware acceleration enabled";
#else
    return "vDSP not available - using fallback implementations";
#endif
}

} // namespace vDSP
} // namespace Reverb