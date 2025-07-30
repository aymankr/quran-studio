#pragma once

#include <cmath>
#include <algorithm>

namespace VoiceMonitor {

/// Audio mathematics utilities for DSP processing
namespace AudioMath {

    // Mathematical constants
    constexpr float PI = 3.14159265359f;
    constexpr float TWO_PI = 2.0f * PI;
    constexpr float PI_OVER_2 = PI * 0.5f;
    constexpr float SQRT_2 = 1.41421356237f;
    constexpr float SQRT_2_OVER_2 = 0.70710678118f;

    // Audio constants
    constexpr float DB_MIN = -96.0f;
    constexpr float DB_MAX = 96.0f;
    constexpr float EPSILON = 1e-9f;

    /// Convert linear gain to decibels
    inline float linearToDb(float linear) {
        return (linear > EPSILON) ? 20.0f * std::log10(linear) : DB_MIN;
    }

    /// Convert decibels to linear gain
    inline float dbToLinear(float db) {
        return std::pow(10.0f, db * 0.05f);
    }

    /// Fast approximate sine using Taylor series (good for modulation)
    inline float fastSin(float x) {
        // Normalize to [-PI, PI]
        while (x > PI) x -= TWO_PI;
        while (x < -PI) x += TWO_PI;
        
        // Taylor series approximation
        const float x2 = x * x;
        return x * (1.0f - x2 * (1.0f/6.0f - x2 * (1.0f/120.0f)));
    }

    /// Fast approximate cosine
    inline float fastCos(float x) {
        return fastSin(x + PI_OVER_2);
    }

    /// Linear interpolation
    template<typename T>
    inline T lerp(T a, T b, float t) {
        return a + t * (b - a);
    }

    /// Cubic interpolation (smoother than linear)
    inline float cubicInterpolate(float y0, float y1, float y2, float y3, float mu) {
        const float mu2 = mu * mu;
        const float a0 = y3 - y2 - y0 + y1;
        const float a1 = y0 - y1 - a0;
        const float a2 = y2 - y0;
        const float a3 = y1;
        
        return a0 * mu * mu2 + a1 * mu2 + a2 * mu + a3;
    }

    /// Clamp value between min and max
    template<typename T>
    inline T clamp(T value, T min, T max) {
        return std::max(min, std::min(max, value));
    }

    /// Soft clipping/saturation
    inline float softClip(float x) {
        if (x > 1.0f) return 0.666f;
        if (x < -1.0f) return -0.666f;
        return x - (x * x * x) / 3.0f;
    }

    /// DC blocking filter coefficient calculation
    inline float dcBlockingCoeff(float sampleRate, float cutoffHz = 20.0f) {
        return 1.0f - (TWO_PI * cutoffHz / sampleRate);
    }

    /// One-pole lowpass filter coefficient
    inline float onePoleCoeff(float sampleRate, float cutoffHz) {
        return 1.0f - std::exp(-TWO_PI * cutoffHz / sampleRate);
    }

    /// Convert milliseconds to samples
    inline int msToSamples(float ms, double sampleRate) {
        return static_cast<int>(ms * 0.001 * sampleRate);
    }

    /// Convert samples to milliseconds
    inline float samplesToMs(int samples, double sampleRate) {
        return static_cast<float>(samples) * 1000.0f / static_cast<float>(sampleRate);
    }

    /// RMS calculation for audio level metering
    inline float calculateRMS(const float* buffer, int numSamples) {
        if (numSamples <= 0) return 0.0f;
        
        float sum = 0.0f;
        for (int i = 0; i < numSamples; ++i) {
            sum += buffer[i] * buffer[i];
        }
        return std::sqrt(sum / numSamples);
    }

    /// Peak calculation for audio level metering
    inline float calculatePeak(const float* buffer, int numSamples) {
        if (numSamples <= 0) return 0.0f;
        
        float peak = 0.0f;
        for (int i = 0; i < numSamples; ++i) {
            peak = std::max(peak, std::abs(buffer[i]));
        }
        return peak;
    }

    /// Simple windowing functions
    namespace Window {
        inline float hann(int n, int N) {
            return 0.5f * (1.0f - std::cos(TWO_PI * n / (N - 1)));
        }
        
        inline float hamming(int n, int N) {
            return 0.54f - 0.46f * std::cos(TWO_PI * n / (N - 1));
        }
        
        inline float blackman(int n, int N) {
            const float a0 = 0.42659f;
            const float a1 = 0.49656f;
            const float a2 = 0.07685f;
            const float factor = TWO_PI * n / (N - 1);
            return a0 - a1 * std::cos(factor) + a2 * std::cos(2.0f * factor);
        }
    }

    /// Biquad filter coefficients and processor
    struct BiquadCoeffs {
        float b0, b1, b2;  // Numerator coefficients
        float a1, a2;      // Denominator coefficients (a0 is normalized to 1)
        
        BiquadCoeffs() : b0(1), b1(0), b2(0), a1(0), a2(0) {}
    };

    /// Create lowpass biquad coefficients
    inline BiquadCoeffs createLowpass(float sampleRate, float frequency, float Q = SQRT_2_OVER_2) {
        const float omega = TWO_PI * frequency / sampleRate;
        const float sin_omega = std::sin(omega);
        const float cos_omega = std::cos(omega);
        const float alpha = sin_omega / (2.0f * Q);
        
        const float a0 = 1.0f + alpha;
        
        BiquadCoeffs coeffs;
        coeffs.b0 = (1.0f - cos_omega) / (2.0f * a0);
        coeffs.b1 = (1.0f - cos_omega) / a0;
        coeffs.b2 = coeffs.b0;
        coeffs.a1 = (-2.0f * cos_omega) / a0;
        coeffs.a2 = (1.0f - alpha) / a0;
        
        return coeffs;
    }

    /// Create highpass biquad coefficients
    inline BiquadCoeffs createHighpass(float sampleRate, float frequency, float Q = SQRT_2_OVER_2) {
        const float omega = TWO_PI * frequency / sampleRate;
        const float sin_omega = std::sin(omega);
        const float cos_omega = std::cos(omega);
        const float alpha = sin_omega / (2.0f * Q);
        
        const float a0 = 1.0f + alpha;
        
        BiquadCoeffs coeffs;
        coeffs.b0 = (1.0f + cos_omega) / (2.0f * a0);
        coeffs.b1 = -(1.0f + cos_omega) / a0;
        coeffs.b2 = coeffs.b0;
        coeffs.a1 = (-2.0f * cos_omega) / a0;
        coeffs.a2 = (1.0f - alpha) / a0;
        
        return coeffs;
    }

    /// Simple biquad filter processor
    class BiquadFilter {
    public:
        BiquadFilter() : x1_(0), x2_(0), y1_(0), y2_(0) {}
        
        void setCoeffs(const BiquadCoeffs& coeffs) {
            coeffs_ = coeffs;
        }
        
        float process(float input) {
            const float output = coeffs_.b0 * input + coeffs_.b1 * x1_ + coeffs_.b2 * x2_
                               - coeffs_.a1 * y1_ - coeffs_.a2 * y2_;
            
            // Update delay lines
            x2_ = x1_;
            x1_ = input;
            y2_ = y1_;
            y1_ = output;
            
            return output;
        }
        
        void reset() {
            x1_ = x2_ = y1_ = y2_ = 0.0f;
        }
        
    private:
        BiquadCoeffs coeffs_;
        float x1_, x2_;  // Input delay line
        float y1_, y2_;  // Output delay line
    };

} // namespace AudioMath
} // namespace VoiceMonitor